/// The private image cache (tracker §7AZ, M1b, D-M1a-1..5).
///
/// One cached copy per media item, found by its stable identity — never by
/// the signed R2 link used to fetch it. A signed link is transport: the
/// Worker mints a new one, valid for 15 minutes, on every request, so keying
/// by it would download the same bytes again and again, and keeping it would
/// put a working link to private media on disk.
///
/// How it works:
///  * Each item is addressed by an account-scoped key — the existing
///    [offerMediaCacheKey] for Offer and Owner media (and its poster key),
///    and [profileMediaKey] for profile photos. The key names the account.
///  * The cache library stores a fixed pseudo-URL made from that key
///    ([pseudoUrlFor]) as the entry's address. When it has to fetch, the
///    request reaches this file's own file service, which asks the caller's
///    `signedUrl` callback for a fresh link — the established path: the
///    Worker checks the access token and the database's application-session
///    gate before it signs — fetches the bytes into memory, and hands them
///    back only if the account and session are still the ones that asked.
///    The link lives only in memory for that one request. No R2 ETag is kept,
///    so no conditional request ever needs one.
///  * A copy that is already held is shown without asking for any link, so
///    an expired link never forces a new download. This holds because the
///    bytes behind a media id never change: every upload gets a new id, and
///    the Worker signs an upload only while the item is still pending
///    (tracker §7AZ M1b). Replacing a photo therefore means a new id and a new
///    entry. Removal is the owner's own act (only the owner can see the item)
///    and is handled by [forget]; unused copies leave after 30 days, and only
///    the 200 most recently used are kept.
///  * Every read, cached or not, needs the current application session, and
///    the key's account must be that session's account. Holding the bytes is
///    never permission on its own.
///
/// An image this device already holds in the image cache used before M1c can
/// be copied in with [PrivateMediaCache.adopt] (tracker §7AZ, M1d-1): its
/// bytes enter through the same file service, size limit and session checks
/// as a download, with the local file standing in for the link, and the copy
/// is read back and compared before it counts.
///
/// Storage (backup-excluded, tracker §7AZ M1b): the index is
/// `bwPrivateMedia.db` in the application-support folder on Android and iOS
/// (`bwPrivateMedia.json` on desktop hosts), and the bytes are in
/// `bwPrivateMedia/` in the temporary folder, which is not backed up.
/// Nothing here encrypts; the separate store, backup exclusion and the
/// session gate are the protections.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:broker_wallet/src/services/app_access_policy.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:broker_wallet/src/services/image_signature_detector.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_session.dart';

/// The account and application session a read is made for.
@immutable
class PrivateMediaScope {
  const PrivateMediaScope({required this.account, required this.session});

  final String account;

  /// The access token's `session_id`: kept by a token refresh, new for every
  /// sign-in, so a replaced or repeated sign-in is a different scope.
  final String session;

  @override
  bool operator ==(Object other) =>
      other is PrivateMediaScope &&
      other.account == account &&
      other.session == session;

  @override
  int get hashCode => Object.hash(account, session);
}

/// Why a fetch was refused. It never carries a link, a token or a provider
/// message, and it never leaves this file: callers only see a missing image.
class PrivateMediaUnavailable implements Exception {
  const PrivateMediaUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'PrivateMediaUnavailable($reason)';
}

/// How [PrivateMediaCache.adopt] ended (tracker §7AZ, M1d-1).
enum PrivateMediaAdoption {
  /// Stored, read back and found identical to the source.
  adopted,

  /// A valid copy is already held; nothing was written.
  alreadyHeld,

  /// The item is already being stored for this session; nothing was read.
  inProgress,

  /// No current session for the key's account, or no longer the session that
  /// asked. Nothing is kept.
  notAllowed,

  /// The file is missing, unreadable, empty, over [PrivateMediaCache.maxBytes]
  /// or not a JPEG, PNG or WebP image.
  unusableSource,

  /// Storing or reading back failed. Nothing is kept.
  failed,
}

class PrivateMediaCache {
  PrivateMediaCache({
    required PrivateMediaScope? Function() currentScope,
    FileService? transport,
    Duration timeout = const Duration(seconds: 30),
    // Tests only: stands in for the index the library picks for this host
    // (JSON here, SQLite on Android/iOS), e.g. to delay its writes.
    @visibleForTesting CacheInfoRepository? debugRepository,
  })  : _currentScope = currentScope,
        _debugRepository = debugRepository {
    _service = _PrivateMediaFileService(
      currentScope: currentScope,
      transport: transport ??
          HttpFileService(httpClient: AppAccessPolicy.guard(http.Client())),
      timeout: timeout,
    );
  }

  /// The app's instance, bound to the signed-in application session.
  static final PrivateMediaCache instance =
      PrivateMediaCache(currentScope: applicationScope);

  /// The cache library's store key; it names the index file and the folder.
  static const String storeKey = 'bwPrivateMedia';

  /// Kept from the image cache in use today (D-M1a-2).
  static const int maxEntries = 200;
  static const Duration unusedFor = Duration(days: 30);

  /// How long the library treats a copy as current. Nothing here decides by
  /// it — a held copy is always used, since its bytes never change — it only
  /// keeps the library from refreshing on its own.
  static const Duration freshFor = Duration(days: 365);

  /// The Worker's image limit; anything larger is not one of its images.
  static const int maxBytes = 10 * 1024 * 1024;

  static const String profileMediaKeyPrefix = 'profile-media:';
  static const String _pseudoUrlPrefix = 'bw-private-media://v1/';

  final PrivateMediaScope? Function() _currentScope;
  final CacheInfoRepository? _debugRepository;
  late final _PrivateMediaFileService _service;
  Future<_Store>? _store;
  final Map<String, Future<File?>> _inFlight = {};

  /// [adopt]s in progress, by key — whichever session started them, since a
  /// copy written for one session is visible to every session of its account
  /// until it is verified or removed. Each settles to the verified copy, or
  /// null.
  final Map<String, Future<File?>> _adopting = {};

  /// Called at each step of [adopt] — `source_read` once the source bytes
  /// passed their checks, `written` once the copy is stored and before it is
  /// read back — so tests can change the session or damage the copy there.
  @visibleForTesting
  Future<void> Function(String step, File file)? debugOnAdoptStep;

  /// The account-scoped key for a profile photo, or null without both ids.
  static String? profileMediaKey({
    required String? accountId,
    required String? mediaObjectId,
  }) {
    final account = accountId?.trim();
    final media = mediaObjectId?.trim();
    if (account == null || account.isEmpty || media == null || media.isEmpty) {
      return null;
    }
    return '$profileMediaKeyPrefix$account:$media';
  }

  /// The account a private key belongs to, or null when it is not one.
  static String? accountOf(String key) {
    for (final prefix in [offerMediaCacheKeyPrefix, profileMediaKeyPrefix]) {
      if (!key.startsWith(prefix)) continue;
      final rest = key.substring(prefix.length);
      final colon = rest.indexOf(':');
      if (colon <= 0 || colon == rest.length - 1) return null;
      return rest.substring(0, colon);
    }
    return null;
  }

  /// The address stored for [key]: the key itself, never a link.
  static String pseudoUrlFor(String key) =>
      '$_pseudoUrlPrefix${Uri.encodeComponent(key)}';

  /// The signed-in application session's scope: an application-authenticated
  /// account (not a password-recovery or deletion-quarantine session) whose
  /// session the Single Active Device check has authorized.
  static PrivateMediaScope? applicationScope() {
    final account = OfferMediaSession.applicationAccount;
    final coordinator = AppSessionCoordinator.active;
    if (account == null || coordinator == null) return null;
    final session = coordinator.client.auth.currentSession;
    if (session == null || session.user.id != account) return null;
    if (!coordinator.isAuthorized(session)) return null;
    final id = AppSessionCoordinator.sessionId(session);
    return id == null ? null : PrivateMediaScope(account: account, session: id);
  }

  /// Whether [key] may be read now: there is an application session and the
  /// key names its account. Touches no storage.
  bool canRead(String key) => _scopeFor(key) != null;

  /// The current scope when [key] names its account, else null. Touches no
  /// storage. Captured when an image is shown, so later work can tell whether
  /// it is still that session.
  PrivateMediaScope? scopeFor(String key) => _scopeFor(key);

  /// The held copy of [key], with no network; null when there is none, when
  /// it is damaged (it is then removed), or when [key] is not the current
  /// session's account's. While [adopt] is storing [key] — for this session
  /// or a replaced one — waits for it, so an unverified copy is never handed
  /// out, and a fetch for a newer session starts only after the older copy
  /// was kept or removed.
  Future<File?> cached(String key) async {
    final scope = _scopeFor(key);
    if (scope == null) return null;
    final adopting = _adopting[key];
    if (adopting != null) {
      final copy = await adopting;
      if (copy != null) return _currentScope() == scope ? copy : null;
    }
    try {
      final file = await _held(await _open(), key);
      return _currentScope() == scope ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// The copy of [key]: the held one, or else one fetched now with a link
  /// from [signedUrl]. Null when it cannot be had — offline, no access, a
  /// changed session — and nothing is stored then. Callers asking for the
  /// same item in the same session share one fetch.
  Future<File?> get(
    String key, {
    required Future<String?> Function() signedUrl,
  }) async {
    final scope = _scopeFor(key);
    if (scope == null) return null;
    final held = await cached(key);
    if (held != null) return held;
    if (_currentScope() != scope) return null;

    final flightKey = '${scope.session}\n$key';
    final running = _inFlight[flightKey];
    if (running != null) return running;
    final flight = _fetch(key, scope, signedUrl);
    _inFlight[flightKey] = flight;
    unawaited(flight.whenComplete(() {
      if (identical(_inFlight[flightKey], flight)) _inFlight.remove(flightKey);
    }));
    return flight;
  }

  /// Copies [source], an image this device already holds, into this cache
  /// under [key] with no network (tracker §7AZ, M1d-1). [origin] is the scope
  /// in which the image was shown; it must still be current, and is checked
  /// again after every wait.
  ///
  /// The bytes enter through the same file service, [maxBytes] limit and
  /// index handling as a download, with [source] standing in for the link,
  /// and must be a JPEG, PNG or WebP image (the Worker's formats). A format
  /// says nothing about whose image it is: the caller establishes that.
  /// Nothing is written over a valid copy. The stored copy is read back and
  /// compared (SHA-256 and size); a copy that differs, or whose session ended
  /// first, is removed. [source] is only read, never changed or removed.
  Future<PrivateMediaAdoption> adopt(
    String key,
    File source, {
    required PrivateMediaScope origin,
  }) async =>
      (await adoptCopy(key, source, origin: origin)).$1;

  /// [adopt], also handing back the verified copy when the outcome is
  /// [PrivateMediaAdoption.adopted] — the file M1d-2 switches the mapping to.
  Future<(PrivateMediaAdoption, File?)> adoptCopy(
    String key,
    File source, {
    required PrivateMediaScope origin,
  }) async {
    if (_scopeFor(key) != origin) {
      return (PrivateMediaAdoption.notAllowed, null);
    }
    final flightKey = '${origin.session}\n$key';
    if (_adopting.containsKey(key) || _inFlight.containsKey(flightKey)) {
      return (PrivateMediaAdoption.inProgress, null);
    }
    final copy = Completer<File?>();
    _adopting[key] = copy.future;
    var outcome = PrivateMediaAdoption.failed;
    File? file;
    try {
      (outcome, file) = await _adopt(key, source, origin);
    } finally {
      _adopting.remove(key);
      copy.complete(outcome == PrivateMediaAdoption.adopted ? file : null);
    }
    return (outcome, outcome == PrivateMediaAdoption.adopted ? file : null);
  }

  /// Removes the copy of [key], e.g. once its item was removed or access to
  /// it was refused.
  Future<void> forget(String key) async {
    try {
      await (await _open()).manager.removeFile(key);
    } catch (_) {
      // Nothing held, or storage unavailable: nothing to remove.
    }
  }

  /// Removes every copy that belongs to [accountId] — and only those: a key
  /// matches only when the account id is followed by its separator. Returns
  /// how many were removed. Needs no session: it runs for a deleted account.
  Future<int> forgetAccount(String accountId) async {
    final account = accountId.trim();
    if (account.isEmpty) return 0;
    final prefixes = [
      '$offerMediaCacheKeyPrefix$account:',
      '$profileMediaKeyPrefix$account:',
    ];
    final store = await _open();
    final repo = store.config.repo;
    await repo.open();
    final List<CacheObject> objects;
    try {
      objects = await repo.getAllObjects();
    } finally {
      await repo.close();
    }
    var removed = 0;
    for (final object in objects) {
      if (!prefixes.any(object.key.startsWith)) continue;
      await store.manager.removeFile(object.key);
      removed++;
    }
    return removed;
  }

  /// Closes the store (its index is written out); the next use opens it again.
  Future<void> dispose() async {
    final store = _store;
    _store = null;
    if (store == null) return;
    try {
      await (await store).manager.dispose();
    } catch (_) {}
  }

  @visibleForTesting
  FileService get debugFileService => _service;

  PrivateMediaScope? _scopeFor(String key) {
    final scope = _currentScope();
    if (scope == null) return null;
    final account = accountOf(key);
    return account != null && account == scope.account ? scope : null;
  }

  Future<File?> _fetch(
    String key,
    PrivateMediaScope scope,
    Future<String?> Function() signedUrl,
  ) async {
    final url = pseudoUrlFor(key);
    final ticket = _Ticket(scope, signedUrl);
    try {
      final store = await _open();
      _service.allow(url, ticket);
      // `force`: never join the library's own in-flight download for this
      // key, which may belong to an earlier session; same-session callers
      // already share this one through [_inFlight].
      final info = await store.manager.downloadFile(url, key: key, force: true);
      return _currentScope() == scope ? info.file : null;
    } catch (_) {
      return null;
    } finally {
      _service.withdraw(url, ticket);
    }
  }

  Future<(PrivateMediaAdoption, File?)> _adopt(
    String key,
    File source,
    PrivateMediaScope origin,
  ) async {
    final url = pseudoUrlFor(key);
    final ticket = _Ticket.local(origin, source, debugOnAdoptStep);
    File? written;
    try {
      final store = await _open();
      if (await _held(store, key) != null) {
        return (PrivateMediaAdoption.alreadyHeld, null);
      }
      if (_currentScope() != origin) {
        return (PrivateMediaAdoption.notAllowed, null);
      }
      // Asked again inside the file service, right before the bytes are
      // handed over: a copy that appeared meanwhile is never written over.
      ticket.destinationFree = () async => !await _holdsValid(store, key);
      _service.allow(url, ticket);
      final info = await store.manager.downloadFile(url, key: key, force: true);
      written = info.file;
      await debugOnAdoptStep?.call('written', written);
      if (!await _sameBytes(written, ticket)) {
        await _discard(store, key, written);
        return (PrivateMediaAdoption.failed, null);
      }
      if (_currentScope() != origin) {
        await _discard(store, key, written);
        return (PrivateMediaAdoption.notAllowed, null);
      }
      return (PrivateMediaAdoption.adopted, written);
    } on PrivateMediaUnavailable catch (refused) {
      return (
        switch (refused.reason) {
          'already_held' => PrivateMediaAdoption.alreadyHeld,
          'session_changed' => PrivateMediaAdoption.notAllowed,
          'unreadable' ||
          'empty' ||
          'too_large' ||
          'not_image' =>
            PrivateMediaAdoption.unusableSource,
          _ => PrivateMediaAdoption.failed,
        },
        null
      );
    } catch (_) {
      if (written != null) {
        try {
          await _discard(await _open(), key, written);
        } catch (_) {}
      }
      return (PrivateMediaAdoption.failed, null);
    } finally {
      _service.withdraw(url, ticket);
    }
  }

  /// Whether [written] holds exactly the bytes the file service handed over.
  static Future<bool> _sameBytes(File written, _Ticket ticket) async {
    final expected = ticket.copiedDigest;
    final length = ticket.copiedLength;
    if (expected == null || length == null) return false;
    if (!await written.exists() || await written.length() != length) {
      return false;
    }
    return await sha256.bind(written.openRead()).first == expected;
  }

  /// Removes a copy [adopt] wrote and does not keep. Every write is a new,
  /// uniquely named file, so deleting [written] can never touch another
  /// entry; the index row, written by the library without waiting, is
  /// removed with it when it is there, and otherwise dropped by the library
  /// the next time it finds the file missing.
  Future<void> _discard(_Store store, String key, File written) async {
    try {
      final current = await store.manager.getFileFromCache(key);
      if (current != null && current.file.path == written.path) {
        await store.manager.removeFile(key);
      }
    } catch (_) {}
    try {
      if (await written.exists()) await written.delete();
    } catch (_) {}
  }

  Future<File?> _held(_Store store, String key) async {
    final info = await store.manager.getFileFromCache(key);
    if (info == null) return null;
    final file = await _valid(store, key, info.file);
    if (file == null) await store.manager.removeFile(key);
    return file;
  }

  /// Like [_held], but changes nothing.
  Future<bool> _holdsValid(_Store store, String key) async {
    final info = await store.manager.getFileFromCache(key);
    return info != null && await _valid(store, key, info.file) != null;
  }

  Future<File?> _valid(_Store store, String key, File file) async {
    final row = await store.config.repo.get(key);
    final length = await file.exists() ? await file.length() : -1;
    if (row == null ||
        length <= 0 ||
        (row.length != null && row.length != length)) {
      return null;
    }
    return file;
  }

  /// Opens the store once. The folders are resolved first, so that a missing
  /// platform folder fails here — inside the caller's error handling — rather
  /// than inside the library's own unawaited setup.
  Future<_Store> _open() {
    return _store ??= () async {
      try {
        await getApplicationSupportDirectory();
        await getTemporaryDirectory();
        final repository = _debugRepository;
        final config = repository == null
            ? Config(
                storeKey,
                stalePeriod: unusedFor,
                maxNrOfCacheObjects: maxEntries,
                fileService: _service,
              )
            : Config(
                storeKey,
                stalePeriod: unusedFor,
                maxNrOfCacheObjects: maxEntries,
                repo: repository,
                fileService: _service,
              );
        return _Store(config, CacheManager(config));
      } catch (_) {
        _store = null;
        rethrow;
      }
    }();
  }
}

class _Store {
  _Store(this.config, this.manager);

  final Config config;
  final CacheManager manager;
}

/// One authorized fetch: who asked, and how to get its link — or, for
/// [PrivateMediaCache.adopt], the local file standing in for it.
class _Ticket {
  _Ticket(this.scope, Future<String?> Function() this.signedUrl)
      : source = null,
        onStep = null;

  _Ticket.local(this.scope, File this.source, this.onStep) : signedUrl = null;

  final PrivateMediaScope scope;
  final Future<String?> Function()? signedUrl;
  final File? source;
  final Future<void> Function(String step, File file)? onStep;

  /// For a local source: false when a valid copy is held by now.
  Future<bool> Function()? destinationFree;

  /// What a local source handed over, for the read-back comparison.
  Digest? copiedDigest;
  int? copiedLength;
}

/// The only way bytes enter the cache: a fetch that [PrivateMediaCache.get]
/// or [PrivateMediaCache.adopt] authorized for exactly this address. Any
/// other request — the library refreshing on its own, say — is refused
/// without touching the network.
class _PrivateMediaFileService extends FileService {
  _PrivateMediaFileService({
    required PrivateMediaScope? Function() currentScope,
    required FileService transport,
    required Duration timeout,
  })  : _currentScope = currentScope,
        _transport = transport,
        _timeout = timeout;

  final PrivateMediaScope? Function() _currentScope;
  final FileService _transport;
  final Duration _timeout;
  final Map<String, _Ticket> _tickets = {};

  static const _extensions = {'.jpg', '.jpeg', '.png', '.webp', '.heic'};

  void allow(String url, _Ticket ticket) => _tickets[url] = ticket;

  void withdraw(String url, _Ticket ticket) {
    if (identical(_tickets[url], ticket)) _tickets.remove(url);
  }

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    final ticket = _tickets[url];
    if (ticket == null) throw const PrivateMediaUnavailable('not_requested');
    _stillCurrent(ticket);
    final source = ticket.source;
    if (source != null) return _fromLocal(ticket, source);

    final String? link;
    try {
      link = await ticket.signedUrl!();
    } catch (_) {
      throw const PrivateMediaUnavailable('no_link');
    }
    if (link == null || link.isEmpty) {
      throw const PrivateMediaUnavailable('no_link');
    }
    _stillCurrent(ticket);

    final Uint8List bytes;
    final String extension;
    try {
      // No headers: R2 needs none, and none of ours belong there.
      final response = await _transport.get(link).timeout(_timeout);
      if (response.statusCode != 200) {
        throw PrivateMediaUnavailable('status_${response.statusCode}');
      }
      final declared = response.contentLength;
      if (declared != null && declared > PrivateMediaCache.maxBytes) {
        throw const PrivateMediaUnavailable('too_large');
      }
      bytes = await _read(response.content).timeout(_timeout);
      final named = response.fileExtension.toLowerCase();
      extension = _extensions.contains(named) ? named : '';
    } on PrivateMediaUnavailable {
      rethrow;
    } catch (_) {
      // Transport errors can quote the link; none of their text goes on.
      throw const PrivateMediaUnavailable('transport');
    }
    if (bytes.isEmpty) throw const PrivateMediaUnavailable('empty');
    // The late answer of a session that is gone is dropped here, before the
    // library writes anything.
    _stillCurrent(ticket);
    return _Bytes(bytes, extension);
  }

  /// A local file in place of a download (M1d-1): the same size limit and
  /// session checks, and it must be a supported image. No link is asked for
  /// and the network is never used.
  Future<FileServiceResponse> _fromLocal(_Ticket ticket, File source) async {
    final Uint8List bytes;
    try {
      final size = await source.length().timeout(_timeout);
      if (size <= 0) throw const PrivateMediaUnavailable('empty');
      if (size > PrivateMediaCache.maxBytes) {
        throw const PrivateMediaUnavailable('too_large');
      }
      bytes = await source.readAsBytes().timeout(_timeout);
    } on PrivateMediaUnavailable {
      rethrow;
    } catch (_) {
      // File errors quote the path; none of their text goes on.
      throw const PrivateMediaUnavailable('unreadable');
    }
    if (bytes.isEmpty) throw const PrivateMediaUnavailable('empty');
    if (bytes.length > PrivateMediaCache.maxBytes) {
      throw const PrivateMediaUnavailable('too_large');
    }
    final extension = switch (ImageSignatureDetector.detectMimeType(bytes)) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      _ => throw const PrivateMediaUnavailable('not_image'),
    };
    await ticket.onStep?.call('source_read', source);
    _stillCurrent(ticket);
    final free = ticket.destinationFree;
    if (free != null && !await free()) {
      throw const PrivateMediaUnavailable('already_held');
    }
    // A session that ended meanwhile gets nothing written.
    _stillCurrent(ticket);
    ticket
      ..copiedLength = bytes.length
      ..copiedDigest = sha256.convert(bytes);
    return _Bytes(bytes, extension);
  }

  void _stillCurrent(_Ticket ticket) {
    if (_currentScope() != ticket.scope) {
      throw const PrivateMediaUnavailable('session_changed');
    }
  }

  static Future<Uint8List> _read(Stream<List<int>> content) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in content) {
      builder.add(chunk);
      if (builder.length > PrivateMediaCache.maxBytes) {
        throw const PrivateMediaUnavailable('too_large');
      }
    }
    return builder.takeBytes();
  }
}

class _Bytes implements FileServiceResponse {
  _Bytes(this._bytes, this.fileExtension);

  final Uint8List _bytes;

  @override
  final String fileExtension;

  @override
  Stream<List<int>> get content => Stream.value(_bytes);

  @override
  int? get contentLength => _bytes.length;

  @override
  int get statusCode => 200;

  @override
  DateTime get validTill => DateTime.now().add(PrivateMediaCache.freshFor);

  @override
  String? get eTag => null;
}
