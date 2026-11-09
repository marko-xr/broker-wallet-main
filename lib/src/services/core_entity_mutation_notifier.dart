import 'dart:async';
import 'package:flutter/foundation.dart';

/// The kind of record a core-entity mutation changed.
enum CoreEntityKind {
  request,
  offer,
  owner,
  office,
  broker,
  watchman,
  quotation
}

/// Process-local signal used to refresh dashboard counts after an RLS-backed
/// core entity mutation. It carries no data and is not an authorization layer.
/// A signal may say which [CoreEntityKind] it changed; one that does not (no
/// kind) may have changed anything.
class CoreEntityMutationNotifier {
  CoreEntityMutationNotifier._();

  static final StreamController<CoreEntityKind?> _controller =
      StreamController<CoreEntityKind?>.broadcast(sync: true);

  /// Every mutation, whatever it changed.
  static Stream<void> get changes => _controller.stream;

  /// Only mutations that may have changed records of [kind]: those of that
  /// kind, and those that do not say what they changed.
  static Stream<void> changesTo(CoreEntityKind kind) =>
      _controller.stream.where((changed) => changed == null || changed == kind);

  static void notify([CoreEntityKind? kind]) {
    try {
      _controller.add(kind);
    } catch (error, stackTrace) {
      debugPrint('Core entity refresh notification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
