import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Marks one list item while its delete is in flight: the item stays where it
/// is, dimmed and not interactive, with a progress indicator over it. Nothing
/// else on the screen changes, and a second delete of the item cannot start.
class EntityDeleteProgress extends StatelessWidget {
  const EntityDeleteProgress({
    super.key,
    required this.deleting,
    required this.child,
  });

  final bool deleting;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      // The item is laid out exactly as it would be without this wrapper.
      fit: StackFit.passthrough,
      children: [
        IgnorePointer(
          ignoring: deleting,
          child: AnimatedOpacity(
            opacity: deleting ? 0.45 : 1,
            duration: const Duration(milliseconds: 150),
            child: child,
          ),
        ),
        if (deleting)
          Positioned.fill(
            child: Center(
              child: SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Theme.of(context).colorScheme.primary,
                  semanticsLabel:
                      AppLocalizations.of(context).translate('processing'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
