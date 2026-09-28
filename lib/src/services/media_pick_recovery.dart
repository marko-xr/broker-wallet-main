import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:broker_wallet/src/services/media_parent.dart';

/// The form a photo/video picker was opened from: the signed-in account, the
/// kind of record (Offer or Owner), and the record itself — or, while the
/// record does not exist yet, the form's own session.
@immutable
class MediaPickOrigin {
  const MediaPickOrigin._(
    this.accountId,
    this.parent,
    this.recordId,
    this.formSessionId,
  );

  /// The origin of a picker opened on a [parent] form of [accountId]: the
  /// record [recordId] once the form has one (Edit, or a new record after its
  /// first Save), otherwise the form's [formSessionId]. Null when nobody is
  /// signed in: then nothing is recorded, and nothing recovered.
  static MediaPickOrigin? of({
    required String? accountId,
    required MediaParent parent,
    required String? recordId,
    required String formSessionId,
  }) {
    final account = accountId?.trim() ?? '';
    if (account.isEmpty) return null;
    final record = recordId?.trim() ?? '';
    return record.isEmpty
        ? MediaPickOrigin._(account, parent, null, formSessionId)
        : MediaPickOrigin._(account, parent, record, null);
  }

  final String accountId;
  final MediaParent parent;

  /// The record the picked media is for, when it exists.
  final String? recordId;

  /// The form, while its record does not exist yet. A form lives only as long
  /// as the app process, so a pick lost with the process can never return to
  /// it.
  final String? formSessionId;

  Map<String, Object> toJson() => {
        'account': accountId,
        'parent': parent.name,
        if (recordId != null) 'record': recordId!,
        if (formSessionId != null) 'session': formSessionId!,
      };

  /// Reads a persisted origin; null for anything malformed.
  static MediaPickOrigin? fromJson(Object? json) {
    if (json is! Map) return null;
    final account = json['account'];
    final parent = json['parent'];
    final record = json['record'];
    final session = json['session'];
    if (account is! String || account.isEmpty || parent is! String) {
      return null;
    }
    final kind = MediaParent.byName(parent);
    if (kind == null) return null;
    if (record is String && record.isNotEmpty && session == null) {
      return MediaPickOrigin._(account, kind, record, null);
    }
    if (session is String && session.isNotEmpty && record == null) {
      return MediaPickOrigin._(account, kind, null, session);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is MediaPickOrigin &&
      other.accountId == accountId &&
      other.parent == parent &&
      other.recordId == recordId &&
      other.formSessionId == formSessionId;

  @override
  int get hashCode => Object.hash(accountId, parent, recordId, formSessionId);
}

/// Keeps what Android hands back after it stopped the app while a picker was
/// open with the form that picker was opened from — and only that form.
///
/// Android returns such a result once, after the restart, with nothing saying
/// which screen asked for it, and image_picker's `retrieveLostData` gives it
/// to whoever asks first. Taken as it came, a photo started on one Owner could
/// land in whichever Offer or Owner form opened next — another record, another
/// kind of record, or another account signed in on the same device.
///
/// So the result is routed by origin, never by timing:
///
/// 1. Before an Offer/Owner picker opens, [beginPick] persists the form's
///    [MediaPickOrigin]; when the picker returns in the same process — a pick,
///    a cancel or an error — [endPick] clears it.
/// 2. Once per process, at start-up and before any picker can open again,
///    [reconcile] takes Android's result and keeps it under the origin that
///    was pending when the app stopped. A result with no pending origin came
///    from another picker in the app and is not adopted; one picked on a form
///    for a record not yet saved is not adopted either, since that form did
///    not survive the restart.
/// 3. A form asks with [take] for exactly its own origin — the same account,
///    kind of record and record. Anything else stays kept for its own form;
///    what is taken is handed out once.
///
/// Only one result is kept, as Android itself keeps only one. Nothing here
/// deletes a file: a result that is not adopted is simply left alone.
class MediaPickRecovery {
  MediaPickRecovery({
    ImagePicker? picker,
    Future<SharedPreferences> Function()? preferences,
  })  : _picker = picker ?? ImagePicker(),
        _preferences = preferences ?? SharedPreferences.getInstance;

  /// The app's instance: the pending origin and the kept result are
  /// process-wide, like Android's own result.
  static final MediaPickRecovery instance = MediaPickRecovery();

  static const pendingOriginKey = 'media_pick_recovery.pending_origin';
  static const keptResultKey = 'media_pick_recovery.kept_result';

  /// How long opening a picker waits for [reconcile] before it goes ahead.
  /// Routing stays correct either way (see [_reconcile]); this only keeps a
  /// slow read from holding the picker back.
  static const reconcileWait = Duration(seconds: 2);

  final ImagePicker _picker;
  final Future<SharedPreferences> Function() _preferences;
  Future<void>? _reconciled;

  /// Start-up: routes Android's result on Android; nothing elsewhere.
  static void reconcileAtStartup() {
    if (kIsWeb || !Platform.isAndroid) return;
    unawaited(instance.reconcile());
  }

  /// Routes Android's result for this process; runs once.
  Future<void> reconcile() => _reconciled ??= _reconcile();

  Future<void> _reconcile() async {
    final SharedPreferences prefs;
    try {
      prefs = await _preferences();
    } catch (_) {
      return;
    }
    // Read before anything else runs, so a picker opened meanwhile can only
    // record its origin after this one was read.
    final pendingRaw = prefs.getString(pendingOriginKey);
    List<String> paths;
    try {
      paths = await _retrieveLostPaths();
    } catch (_) {
      paths = const <String>[];
    }
    try {
      // The launch that origin described is over, whatever it returned —
      // unless a picker of this process has recorded its own origin since.
      if (prefs.getString(pendingOriginKey) == pendingRaw) {
        await prefs.remove(pendingOriginKey);
      }
      if (paths.isEmpty) return;
      final pending = _decodeOrigin(pendingRaw);
      if (pending == null || pending.recordId == null) return;
      await prefs.setString(
        keptResultKey,
        jsonEncode({'origin': pending.toJson(), 'files': paths}),
      );
    } catch (_) {
      // Nothing is adopted when routing cannot be completed.
    }
  }

  Future<List<String>> _retrieveLostPaths() async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return const <String>[];
    final files = response.files ?? [if (response.file != null) response.file!];
    return [for (final file in files) file.path];
  }

  /// A picker is about to open for [origin] (null: a form with no account,
  /// whose pick is then never adopted after a restart).
  Future<void> beginPick(MediaPickOrigin? origin) async {
    try {
      await reconcile().timeout(reconcileWait);
    } catch (_) {
      // Opening the picker must not depend on it.
    }
    try {
      final prefs = await _preferences();
      if (origin == null) {
        await prefs.remove(pendingOriginKey);
      } else {
        await prefs.setString(pendingOriginKey, jsonEncode(origin.toJson()));
      }
    } catch (_) {
      // Unrecorded, a lost pick is not adopted: the safe side.
    }
  }

  /// The picker returned in this process: nothing is pending any more.
  Future<void> endPick() async {
    try {
      await (await _preferences()).remove(pendingOriginKey);
    } catch (_) {}
  }

  /// The files Android handed back for exactly [origin], once. Empty for any
  /// other origin, which keeps them for its own form.
  Future<List<File>> take(MediaPickOrigin? origin) async {
    if (origin == null) return const <File>[];
    await reconcile();
    try {
      final prefs = await _preferences();
      final kept = _decodeKept(prefs.getString(keptResultKey));
      if (kept == null || kept.origin != origin) return const <File>[];
      await prefs.remove(keptResultKey);
      return [for (final path in kept.paths) File(path)];
    } catch (_) {
      return const <File>[];
    }
  }

  static MediaPickOrigin? _decodeOrigin(String? raw) {
    if (raw == null) return null;
    try {
      return MediaPickOrigin.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static ({MediaPickOrigin origin, List<String> paths})? _decodeKept(
    String? raw,
  ) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final origin = MediaPickOrigin.fromJson(json['origin']);
      final files = json['files'];
      if (origin == null || files is! List) return null;
      final paths = <String>[
        for (final file in files)
          if (file is String && file.isNotEmpty) file,
      ];
      return paths.isEmpty ? null : (origin: origin, paths: paths);
    } catch (_) {
      return null;
    }
  }
}
