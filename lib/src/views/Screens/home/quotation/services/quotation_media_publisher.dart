import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/services/list_refresh_signals.dart';

import 'package:broker_wallet/src/views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/views/Screens/home/quotation/services/pdf_generation_service.dart';
import 'package:broker_wallet/src/views/Screens/home/quotation/services/quotation_pdf_files.dart';
import 'package:broker_wallet/src/views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/views/Screens/home/quotation/services/r2_quotation_media_service.dart';
import 'package:broker_wallet/src/views/Screens/home/quotation/services/supabase_quotation_service.dart';

/// Renders a Quotation to a local PDF file and returns its path.
typedef QuotationPublishPdfGenerator = Future<String>
    Function(QuotationModel quotation, {Locale? locale});

/// What is left to do for one saved Quotation: its logo change (if any) and
/// its PDF. Kept on the device until it is done.
@immutable
class QuotationPublishJob {
  const QuotationPublishJob({
    required this.account,
    required this.quotationId,
    this.languageCode,
    this.logoPath,
    this.logoMediaId,
    this.logoFileName,
    this.removeLogo = false,
    this.revision = 0,
  });

  final String account;
  final String quotationId;

  /// The language the PDF is written in.
  final String? languageCode;

  /// The device's copy of a newly picked logo, uploaded under [logoMediaId]
  /// (the same id on every attempt, so a lost confirm resolves on retry).
  final String? logoPath;
  final String? logoMediaId;
  final String? logoFileName;

  /// The user cleared the bound logo.
  final bool removeLogo;

  /// Grows when a newer save replaces this job, so a finishing attempt for an
  /// older revision never removes the newer one.
  final int revision;

  bool get hasLogoUpload => logoPath != null && logoMediaId != null;

  QuotationPublishJob copyWith({int? revision}) => QuotationPublishJob(
        account: account,
        quotationId: quotationId,
        languageCode: languageCode,
        logoPath: logoPath,
        logoMediaId: logoMediaId,
        logoFileName: logoFileName,
        removeLogo: removeLogo,
        revision: revision ?? this.revision,
      );

  Map<String, Object?> toJson() => {
        'account': account,
        'quotationId': quotationId,
        'languageCode': languageCode,
        'logoPath': logoPath,
        'logoMediaId': logoMediaId,
        'logoFileName': logoFileName,
        'removeLogo': removeLogo,
        'revision': revision,
      };

  static QuotationPublishJob? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final account = raw['account'];
    final id = raw['quotationId'];
    if (account is! String || account.isEmpty || id is! String || id.isEmpty) {
      return null;
    }
    String? text(String key) => raw[key] is String ? raw[key] as String : null;
    return QuotationPublishJob(
      account: account,
      quotationId: id,
      languageCode: text('languageCode'),
      logoPath: text('logoPath'),
      logoMediaId: text('logoMediaId'),
      logoFileName: text('logoFileName'),
      removeLogo: raw['removeLogo'] == true,
      revision: raw['revision'] is int ? raw['revision'] as int : 0,
    );
  }
}

/// Finishes a saved Quotation's logo and PDF after the editor has closed.
///
/// The editor saves the Quotation itself (one quick request) and hands the
/// rest here, so Save does not wait for the uploads. Each job is kept on the
/// device until its PDF is published: an app that is closed, or a network
/// that drops, resumes it on the next open, rebuilding the PDF from the
/// Quotation as the server holds it. A Quotation is never left without a PDF.
///
/// Every run starts from the server's current state, so a resumed job never
/// repeats a step that already happened (a bound logo is not uploaded again)
/// and always draws the newest saved data.
class QuotationMediaPublisher extends ChangeNotifier {
  QuotationMediaPublisher({
    QuotationService Function()? service,
    QuotationPublishPdfGenerator? generatePdf,
    String? Function()? currentUserId,
    Future<Directory> Function()? documents,
    Future<SharedPreferences> Function()? preferences,
    Stream<void>? retryHints,
    List<Duration>? backoff,
  })  : _newService = service ?? QuotationService.new,
        _generatePdf = generatePdf ?? PdfGenerationService.generateQuotationPdf,
        _currentUserId = currentUserId ?? _signedInUserId,
        _documents = documents ?? getApplicationDocumentsDirectory,
        _preferences = preferences ?? SharedPreferences.getInstance,
        _retryHints = retryHints,
        _backoff = backoff ?? _defaultBackoff;

  /// The app's one publisher.
  static final QuotationMediaPublisher shared = QuotationMediaPublisher();

  static const String journalKey = 'quotation_publish_jobs_v1';
  static const List<Duration> _defaultBackoff = [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  final QuotationService Function() _newService;
  final QuotationPublishPdfGenerator _generatePdf;
  final String? Function() _currentUserId;
  final Future<Directory> Function() _documents;
  final Future<SharedPreferences> Function() _preferences;
  final Stream<void>? _retryHints;
  final List<Duration> _backoff;

  /// Pending jobs by `<account>/<quotationId>`.
  final Map<String, QuotationPublishJob> _jobs = {};

  /// The service and renderer an editor passed with its job, used while this
  /// process lives (a resumed job uses the defaults).
  final Map<String, QuotationService> _services = {};
  final Map<String, QuotationPublishPdfGenerator> _generators = {};

  final Map<String, int> _failures = {};
  final Map<String, DateTime> _notBefore = {};
  final Map<String, int> _publishedVersions = {};

  bool _loaded = false;
  Future<void>? _loading;
  Future<void>? _draining;
  String? _runningKey;
  Future<void>? _runningAttempt;
  Timer? _retryTimer;
  StreamSubscription<void>? _hintSubscription;

  static String? _signedInUserId() {
    try {
      return RepositoryProvider.instance.authRepository.currentUserId;
    } catch (_) {
      return null;
    }
  }

  static String _key(String account, String quotationId) =>
      '$account/$quotationId';

  /// Whether [quotationId] of the signed-in account still has a logo or PDF
  /// on its way. Its PDF is not ready (or not current) until this is false.
  bool isPending(String? quotationId) {
    final account = _currentUserId();
    if (quotationId == null || account == null) return false;
    return _jobs.containsKey(_key(account, quotationId));
  }

  /// The Quotation version the last publish of [quotationId] left, so an
  /// editor still holding an older one does not see its own media as a
  /// conflict.
  int? publishedVersion(String quotationId) => _publishedVersions[quotationId];

  /// Completes when no attempt for [quotationId] is running. It does not wait
  /// for a later retry.
  Future<void> whenSettled(String quotationId) async {
    final account = _currentUserId();
    if (account == null || _runningKey != _key(account, quotationId)) return;
    try {
      await _runningAttempt;
    } catch (_) {}
  }

  /// Picks up the jobs an earlier run of the app left, for the signed-in
  /// account, and starts them. Safe to call at any time and more than once.
  Future<void> resume() async {
    await _load();
    _listenForHints();
    _schedule();
  }

  /// Hands over a saved Quotation's logo change and PDF. [logo] is copied to
  /// a private folder first, so the editor may delete its own files. Never
  /// throws: a job that cannot be written down still runs in this process.
  Future<void> enqueue({
    required String account,
    required String quotationId,
    Locale? locale,
    File? logo,
    String? logoMediaId,
    String? logoFileName,
    bool removeLogo = false,
    QuotationService? service,
    QuotationPublishPdfGenerator? generatePdf,
  }) async {
    await _load();
    final key = _key(account, quotationId);
    final previous = _jobs[key];

    String? logoPath;
    if (logo != null && logoMediaId != null) {
      logoPath = await _keepLogo(account, quotationId, logoMediaId, logo);
    }

    var job = QuotationPublishJob(
      account: account,
      quotationId: quotationId,
      languageCode: locale?.languageCode,
      logoPath: logoPath,
      logoMediaId: logoPath == null ? null : logoMediaId,
      logoFileName: logoPath == null ? null : logoFileName,
      removeLogo: logoPath == null && removeLogo,
      revision: (previous?.revision ?? -1) + 1,
    );
    if (previous != null) {
      final changesLogo = job.hasLogoUpload || job.removeLogo;
      if (!changesLogo) {
        // A later save that left the logo alone keeps the earlier one's.
        job = QuotationPublishJob(
          account: account,
          quotationId: quotationId,
          languageCode: job.languageCode ?? previous.languageCode,
          logoPath: previous.logoPath,
          logoMediaId: previous.logoMediaId,
          logoFileName: previous.logoFileName,
          removeLogo: previous.removeLogo,
          revision: job.revision,
        );
      } else if (previous.logoPath != null &&
          previous.logoPath != job.logoPath) {
        unawaited(_deleteQuietly(previous.logoPath));
      }
    }

    _jobs[key] = job;
    if (service != null) _services[key] = service;
    if (generatePdf != null) _generators[key] = generatePdf;
    _failures.remove(key);
    _notBefore.remove(key);
    await _save();
    notifyListeners();
    _listenForHints();
    _schedule();
  }

  /// Drops every job of [account] and its logo copies (Delete Account).
  Future<void> forgetAccount(String account) async {
    await _load();
    final keys = [
      for (final entry in _jobs.entries)
        if (entry.value.account == account) entry.key,
    ];
    for (final key in keys) {
      await _deleteQuietly(_jobs.remove(key)?.logoPath);
      _services.remove(key);
      _generators.remove(key);
    }
    await _save();
    notifyListeners();
  }

  // -------------------------------------------------------------- running

  void _schedule() {
    if (_draining != null) return;
    _draining = _drain().whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    while (true) {
      final account = _currentUserId();
      if (account == null) return;
      final now = DateTime.now();
      final due = [
        for (final entry in _jobs.entries)
          if (entry.value.account == account &&
              !(_notBefore[entry.key]?.isAfter(now) ?? false))
            entry.key,
      ];
      if (due.isEmpty) break;
      for (final key in due) {
        final job = _jobs[key];
        if (job == null || _currentUserId() != job.account) continue;
        _runningKey = key;
        final attempt = _attempt(key, job);
        _runningAttempt = attempt;
        try {
          await attempt;
        } finally {
          _runningKey = null;
          _runningAttempt = null;
        }
      }
    }
    _armRetryTimer();
  }

  void _armRetryTimer() {
    final account = _currentUserId();
    DateTime? next;
    for (final entry in _jobs.entries) {
      if (entry.value.account != account) continue;
      final at = _notBefore[entry.key];
      if (at != null && (next == null || at.isBefore(next))) next = at;
    }
    if (next == null) return;
    var wait = next.difference(DateTime.now());
    if (wait.isNegative) wait = Duration.zero;
    _retryTimer = Timer(wait, _schedule);
  }

  Future<void> _attempt(String key, QuotationPublishJob job) async {
    final service = _services[key] ?? _newService();
    final generatePdf = _generators[key] ?? _generatePdf;
    try {
      await service.batchMutations(() => _publish(job, service, generatePdf));
      _finish(key, job);
    } on _JobDropped {
      _finish(key, job);
    } on _StopForNow {
      // Signed out or the session was refused: kept for the next resume.
    } catch (_) {
      final failures = (_failures[key] ?? 0) + 1;
      _failures[key] = failures;
      _notBefore[key] = DateTime.now()
          .add(_backoff[(failures - 1).clamp(0, _backoff.length - 1)]);
    }
  }

  /// The job is done (or can never be): it goes, unless a newer save replaced
  /// it while it ran, which then runs on its own.
  void _finish(String key, QuotationPublishJob job) {
    final current = _jobs[key];
    _failures.remove(key);
    _notBefore.remove(key);
    if (current == null || current.revision != job.revision) return;
    _jobs.remove(key);
    _services.remove(key);
    _generators.remove(key);
    unawaited(_deleteQuietly(job.logoPath));
    unawaited(_save());
    notifyListeners();
  }

  Future<void> _publish(
    QuotationPublishJob job,
    QuotationService service,
    QuotationPublishPdfGenerator generatePdf,
  ) async {
    final id = job.quotationId;
    var state =
        await _read<QuotationMediaState?>(job, () => service.getMediaState(id));
    if (state == null) throw const _JobDropped();

    // 1. The logo, against the logo the server holds now.
    File? logoFile = job.logoPath == null ? null : File(job.logoPath!);
    if (logoFile != null && !await logoFile.exists()) logoFile = null;
    if (job.hasLogoUpload &&
        logoFile != null &&
        state.officeLogoMediaId != job.logoMediaId) {
      try {
        final binding = await _media(
            job,
            () => service.uploadOfficeLogo(
                  quotationId: id,
                  file: logoFile!,
                  expectedMediaId: state!.officeLogoMediaId,
                  mediaObjectId: job.logoMediaId!,
                  originalFileName: job.logoFileName,
                ));
        _remember(id, binding.resultingVersion);
      } on _LogoRefused {
        logoFile = null; // the PDF is still published, with the bound logo
      }
    } else if (job.removeLogo && state.officeLogoMediaId != null) {
      final removal = await _media(
          job,
          () => service.removeOfficeLogo(
                quotationId: id,
                expectedMediaId: state!.officeLogoMediaId,
              ));
      _remember(id, removal.resultingVersion);
    }

    // 2. The PDF, drawn from the Quotation as the server holds it now.
    final quotation = await _read(job, () => service.getQuotationById(id));
    if (quotation == null) throw const _JobDropped();
    state =
        await _read<QuotationMediaState?>(job, () => service.getMediaState(id));
    if (state == null) throw const _JobDropped();

    String? logoSource;
    if (logoFile != null && state.officeLogoMediaId == job.logoMediaId) {
      logoSource = Uri.file(logoFile.path).toString();
    } else if (state.officeLogoMediaId != null) {
      try {
        logoSource = (await service.signedOfficeLogo(id))?.url;
      } catch (_) {
        logoSource = null; // the PDF is still useful without the logo
      }
    }

    final code = job.languageCode;
    final path = await generatePdf(
      quotation.copyWith(id: id, officeLogoUrl: logoSource),
      locale: code == null ? null : Locale(code),
    );
    _checkAccount(job);
    final pdf = File(path);
    try {
      final binding = await _media(
          job,
          () => service.publishPdf(
                quotationId: id,
                pdf: pdf,
                expectedMediaId: state!.pdfMediaId,
              ));
      _remember(id, binding.resultingVersion);
    } finally {
      await _deleteQuietly(pdf.path);
    }
  }

  void _remember(String quotationId, int? version) {
    if (version != null) _publishedVersions[quotationId] = version;
  }

  void _checkAccount(QuotationPublishJob job) {
    if (_currentUserId() != job.account) throw const _StopForNow();
  }

  /// A server read for [job]: a deleted Quotation ends the job, a refused
  /// session waits for the next resume, anything else is retried later.
  Future<T> _read<T>(QuotationPublishJob job, Future<T> Function() read) async {
    _checkAccount(job);
    try {
      return await read();
    } on QuotationException catch (error) {
      switch (error.failure) {
        case QuotationFailure.notFound:
        case QuotationFailure.deleted:
          throw const _JobDropped();
        case QuotationFailure.notSignedIn:
        case QuotationFailure.permissionDenied:
          throw const _StopForNow();
        default:
          rethrow;
      }
    }
  }

  /// A media step for [job], classified the same way; a logo the media
  /// service will never accept is skipped rather than retried for ever.
  Future<T> _media<T>(
      QuotationPublishJob job, Future<T> Function() step) async {
    _checkAccount(job);
    try {
      return await step();
    } on QuotationMediaException catch (error) {
      switch (error.failure) {
        case QuotationMediaFailure.quotationNotFound:
          throw const _JobDropped();
        case QuotationMediaFailure.notSignedIn:
        case QuotationMediaFailure.unauthorized:
          throw const _StopForNow();
        case QuotationMediaFailure.unsupportedType:
        case QuotationMediaFailure.typeMismatch:
        case QuotationMediaFailure.tooLarge:
          throw const _LogoRefused();
        default:
          rethrow;
      }
    }
  }

  // -------------------------------------------------------------- storage

  Future<void> _load() {
    if (_loaded) return Future.value();
    return _loading ??= () async {
      try {
        final prefs = await _preferences();
        final raw = prefs.getString(journalKey);
        if (raw != null) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final entry in decoded) {
              final job = QuotationPublishJob.fromJson(entry);
              if (job == null) continue;
              _jobs.putIfAbsent(_key(job.account, job.quotationId), () => job);
            }
          }
        }
      } catch (_) {
        // Nothing saved can be read: start with what this process has.
      }
      _loaded = true;
    }();
  }

  Future<void> _save() async {
    try {
      final prefs = await _preferences();
      if (_jobs.isEmpty) {
        await prefs.remove(journalKey);
      } else {
        await prefs.setString(
          journalKey,
          jsonEncode([for (final job in _jobs.values) job.toJson()]),
        );
      }
    } catch (_) {
      // The jobs still run in this process; only a restart would lose them.
    }
  }

  /// A private, backup-excluded copy of [logo] that survives the editor.
  /// Falls back to the editor's own file when no copy can be made.
  Future<String> _keepLogo(
    String account,
    String quotationId,
    String mediaId,
    File logo,
  ) async {
    try {
      final folder = Directory(p.join(
        QuotationPdfFiles.workDirectory(await _documents(), account).path,
        'publish',
      ));
      await folder.create(recursive: true);
      final target = p.join(
        folder.path,
        '${quotationId}_$mediaId${p.extension(logo.path)}',
      );
      if (p.equals(target, logo.path)) return target;
      await logo.copy(target);
      return target;
    } catch (_) {
      return logo.path;
    }
  }

  static Future<void> _deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _listenForHints() {
    if (_hintSubscription != null) return;
    try {
      _hintSubscription =
          (_retryHints ?? ListRefreshSignals.instance.hints).listen((_) {
        // The app is back, or the network is: waiting jobs may run now.
        _notBefore.clear();
        _schedule();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    unawaited(_hintSubscription?.cancel());
    super.dispose();
  }
}

class _JobDropped implements Exception {
  const _JobDropped();
}

class _StopForNow implements Exception {
  const _StopForNow();
}

class _LogoRefused implements Exception {
  const _LogoRefused();
}
