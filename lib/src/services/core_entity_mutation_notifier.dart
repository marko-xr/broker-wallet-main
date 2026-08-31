import 'dart:async';
import 'package:flutter/foundation.dart';

/// Process-local signal used to refresh dashboard counts after an RLS-backed
/// core entity mutation. It carries no data and is not an authorization layer.
class CoreEntityMutationNotifier {
  CoreEntityMutationNotifier._();

  static final StreamController<void> _controller =
      StreamController<void>.broadcast(sync: true);

  static Stream<void> get changes => _controller.stream;

  static void notify() {
    try {
      _controller.add(null);
    } catch (error, stackTrace) {
      debugPrint('Core entity refresh notification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
