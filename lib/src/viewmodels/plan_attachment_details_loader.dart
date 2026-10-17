// Loads a record's land / plot plan for its Details screen.
//
// A separate, non-blocking read, like the record's private media: the Details
// screen is usable first, and the plan card appears when the server answers. A
// record with no plan answers `null` and nothing is drawn. A failed read keeps
// whatever was last known and draws nothing new; it never shows an error over a
// screen that otherwise works.

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';

class PlanAttachmentDetailsLoader {
  PlanAttachmentDetailsLoader({
    required this.parent,
    required this.parentId,
    required PlanAttachmentTransport transport,
    required VoidCallback onChanged,
  })  : _transport = transport,
        _onChanged = onChanged;

  final PlanParent parent;
  final String parentId;
  final PlanAttachmentTransport _transport;
  final VoidCallback _onChanged;

  PlanAttachmentRef? _plan;
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;
  bool _disposed = false;

  /// The record's plan, with the read link of the last answer; null when it
  /// has none (or none was read yet).
  PlanAttachmentRef? get plan => _plan;
  bool get isLoading => _loading;
  bool get loadFailed => _failed;

  /// Reads the plan. Only the most recent read is applied.
  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_generation;
    _loading = true;
    _failed = false;
    try {
      final current =
          await _transport.fetchCurrent(parent: parent, parentId: parentId);
      if (_disposed || generation != _generation) return;
      _plan = current;
      _loading = false;
      _onChanged();
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _loading = false;
      _failed = true;
      _onChanged();
    }
  }

  void dispose() {
    _disposed = true;
  }
}
