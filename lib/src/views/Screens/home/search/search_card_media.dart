import 'dart:async';
import 'dart:collection';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';

import '../favorites/favorite_card_media.dart';

/// Which kind of record a card's media belongs to. Offers and Owners are the
/// records that have private photos and videos.
enum CardMediaKind { offer, owner }

/// Where the resolver gets media from: this device, and the server.
abstract interface class SearchCardMediaSource {
  /// The signed-in account, or null when there is no session.
  String? get accountId;

  /// What this device already holds for the record, with no network at all.
  List<OfferMediaRef> cached(CardMediaKind kind, String recordId);

  /// The record's media as the server lists it now, with fresh links; null
  /// when the backend has no separate media stage (the Firebase backend, whose
  /// records carry plain URLs).
  Future<OfferMediaResolution?> resolve(
    CardMediaKind kind,
    String recordId,
    String accountId,
  );
}

/// What this device holds for a record by its saved list's media identity
/// (`listedMediaObjectIds`) — Search's own setting (tracker §7AZ, M3b-2).
///
/// Both are read only: no network, no download, no mapping or catalogue
/// write. Both follow the record's catalogue entry when the device has one
/// (even an empty one) and use the saved [ids] only when it has none; they
/// give nothing for another account or without its authorized session.
abstract interface class SearchCardHeldMedia {
  /// What is on the device now by the saved [ids], for the first frame.
  List<OfferMediaRef> listed(
    CardMediaKind kind,
    String recordId,
    String accountId,
    List<String> ids,
  );

  /// The same, also finding bytes held only in the private image cache.
  Future<List<OfferMediaRef>> discover(
    CardMediaKind kind,
    String recordId,
    String accountId,
    List<String> ids,
  );
}

/// The photo (or video frame) a Search result card shows for an Offer or an
/// Owner, chosen the way Favorites chooses it: the first photo; if the record
/// has only videos, the first video's still frame; never a video link drawn as
/// if it were a photo.
///
/// A list read carries no media links (signing them for a whole list would be
/// one request per record), so each card asks for its own, and only when it is
/// on screen:
///
///  * [current] answers at once from memory and from what this device holds, so
///    a card that was seen before draws its picture on its first frame;
///  * [resolve] asks the server when that is needed, [maxConcurrent] at a time,
///    skips a card that scrolled away before its turn, shares one request
///    between cards that ask for the same record, and remembers the answer for
///    [validFor];
///  * a record whose photo this device already holds is never asked about;
///  * a failure only means the card keeps what the device holds (or its icon),
///    and the same record is not asked again for [failedFor].
///
/// With [heldMedia] (Search only; off by default, so Smart Map's resolver is
/// unchanged — tracker §7AZ, M3b-2, D-M3-3), what "the device holds" also
/// covers the record's saved ids (`listedIds`), used only when the record has
/// no catalogue entry, and bytes held only in the private image cache, found
/// by a read-only lookup before the Worker is asked. A photo found that way is
/// shown without asking the Worker, so it says nothing new about whether the
/// server still lists it (the same as a catalogue photo today); it is never
/// remembered as a Worker answer.
class SearchCardMediaResolver {
  SearchCardMediaResolver({
    required SearchCardMediaSource source,
    SearchCardHeldMedia? heldMedia,
    this.maxConcurrent = 3,
    this.validFor = const Duration(minutes: 5),
    this.failedFor = const Duration(seconds: 30),
    DateTime Function()? clock,
  })  : assert(maxConcurrent > 0),
        _source = source,
        _heldMedia = heldMedia,
        _clock = clock ?? DateTime.now;

  final SearchCardMediaSource _source;

  /// Search's saved-ids lookup; null keeps the resolver as it was before M3b-2.
  final SearchCardHeldMedia? _heldMedia;

  /// How many records are asked about at the same time.
  final int maxConcurrent;

  /// How long an answer from the server is trusted.
  final Duration validFor;

  /// How long a failed record is left alone before it is asked about again.
  final Duration failedFor;

  final DateTime Function() _clock;

  final Map<String, _Answer> _answers = {};
  final Map<String, _Job> _jobs = {};
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();
  int _running = 0;

  /// Bumped by [invalidate]; an answer that started before it is not kept.
  int _epoch = 0;

  /// What the card can draw right now, with no network: the server's answer
  /// from earlier, otherwise what this device holds — with the Search setting,
  /// also by the record's saved [listedIds] when it has no catalogue entry.
  FavoriteCardMedia? current(
    CardMediaKind kind,
    String recordId, {
    List<String> listedIds = const <String>[],
  }) {
    final id = recordId.trim();
    if (id.isEmpty) return null;
    final answer = _freshAnswer(_key(kind, id));
    if (answer != null && !answer.failed) return answer.media;
    return _held(kind, id, listedIds);
  }

  /// The media the card should show for the record, asking the server when this
  /// device does not already hold the record's photo. Never throws; null means
  /// nothing to draw (no media, no session, a skipped request, or a failure
  /// with nothing held).
  ///
  /// [isWanted] is asked when the record's turn comes: a request whose cards
  /// are all gone (scrolled away, disposed) is dropped without any network.
  ///
  /// [listedIds] are the record's saved media ids, used only with the Search
  /// setting; empty means unknown, never "no media".
  Future<FavoriteCardMedia?> resolve(
    CardMediaKind kind,
    String recordId, {
    bool Function()? isWanted,
    List<String> listedIds = const <String>[],
  }) {
    final id = recordId.trim();
    final account = _source.accountId?.trim() ?? '';
    if (id.isEmpty || account.isEmpty) {
      return Future<FavoriteCardMedia?>.value(null);
    }
    final key = _key(kind, id);

    final answer = _freshAnswer(key);
    if (answer != null) {
      return Future<FavoriteCardMedia?>.value(
        answer.failed ? _held(kind, id, listedIds) : answer.media,
      );
    }

    // The device already holds a photo: that is the card's picture, and there
    // is nothing to ask.
    final held = _held(kind, id, listedIds);
    if (held != null && !held.isVideo) {
      return Future<FavoriteCardMedia?>.value(held);
    }

    final job = _jobs[key];
    if (job != null) {
      job.wanted.add(isWanted ?? _always);
      return job.result;
    }
    final created = _Job(isWanted ?? _always);
    _jobs[key] = created;
    created.result = _run(kind, id, account, key, created, listedIds);
    return created.result;
  }

  /// Forgets what was asked: the records changed, so the next ask is a new one.
  /// A request already running finishes but is not kept.
  void invalidate() {
    _epoch++;
    _answers.clear();
  }

  static bool _always() => true;

  static String _key(CardMediaKind kind, String id) => '${kind.name}:$id';

  _Answer? _freshAnswer(String key) {
    final answer = _answers[key];
    if (answer == null) return null;
    final age = _clock().difference(answer.at);
    final limit = answer.failed ? failedFor : validFor;
    // A clock that went back is not trusted either.
    if (age >= limit || age.isNegative) {
      _answers.remove(key);
      return null;
    }
    return answer;
  }

  FavoriteCardMedia? _held(
    CardMediaKind kind,
    String id,
    List<String> listedIds,
  ) {
    final List<OfferMediaRef> catalogued;
    try {
      catalogued = _source.cached(kind, id);
    } catch (_) {
      return null;
    }
    // What the catalogue holds is the card's picture. The saved ids are read
    // only when it holds nothing, and give nothing for a record with an entry
    // at all (even an empty one), so the two are never merged.
    if (catalogued.isNotEmpty) return FavoriteCardMedia.pick(catalogued);
    final lookup = _heldMedia;
    if (lookup == null || listedIds.isEmpty) return null;
    final account = _source.accountId?.trim() ?? '';
    if (account.isEmpty) return null;
    try {
      return FavoriteCardMedia.pick(
          lookup.listed(kind, id, account, listedIds));
    } catch (_) {
      return null;
    }
  }

  /// The first photo (or video frame) the read-only lookup finds; null when it
  /// finds nothing or fails.
  Future<FavoriteCardMedia?> _discover(
    SearchCardHeldMedia lookup,
    CardMediaKind kind,
    String id,
    String account,
    List<String> listedIds,
  ) async {
    try {
      return FavoriteCardMedia.pick(
          await lookup.discover(kind, id, account, listedIds));
    } catch (_) {
      return null;
    }
  }

  Future<FavoriteCardMedia?> _run(
    CardMediaKind kind,
    String id,
    String account,
    String key,
    _Job job,
    List<String> listedIds,
  ) async {
    final epoch = _epoch;
    await _acquire();
    try {
      // Every card that wanted this record is gone: ask nothing.
      if (!job.isWanted) return null;
      // The account changed while waiting: this answer is for nobody now.
      if ((_source.accountId?.trim() ?? '') != account) return null;

      // Search looks on the device first, in this same slot. A photo found
      // there is shown with nothing signed, and is not kept as an answer.
      final lookup = _heldMedia;
      if (lookup != null) {
        final found = await _discover(lookup, kind, id, account, listedIds);
        if ((_source.accountId?.trim() ?? '') != account) return null;
        if (found != null && !found.isVideo) return found;
        if (!job.isWanted) return null;
      }

      FavoriteCardMedia? media;
      var failed = false;
      try {
        final resolution = await _source.resolve(kind, id, account);
        // No separate media stage (the Firebase backend): the record's own URLs.
        media = resolution == null
            ? null
            : FavoriteCardMedia.pick(resolution.items);
      } catch (_) {
        failed = true;
        // Read again after the failure: a 403/404 has emptied the catalogue,
        // so nothing held before the request comes back.
        media = _held(kind, id, listedIds);
      }

      // Another account signed in meanwhile: this answer is for nobody now.
      if ((_source.accountId?.trim() ?? '') != account) return null;
      // The records were read again meanwhile: the card may draw this answer,
      // but it is not kept.
      if (epoch == _epoch) {
        _answers[key] = _Answer(media: media, failed: failed, at: _clock());
      }
      return media;
    } finally {
      _jobs.remove(key);
      _release();
    }
  }

  Future<void> _acquire() {
    if (_running < maxConcurrent) {
      _running++;
      return Future<void>.value();
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    return turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // The slot passes to the next record in line.
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }
}

class _Answer {
  const _Answer({required this.media, required this.failed, required this.at});

  final FavoriteCardMedia? media;
  final bool failed;
  final DateTime at;
}

class _Job {
  _Job(bool Function() first) : wanted = [first];

  final List<bool Function()> wanted;
  late final Future<FavoriteCardMedia?> result;

  bool get isWanted => wanted.any((stillWanted) => stillWanted());
}
