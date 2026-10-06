import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';

/// Presents the app-lifetime displacement notice only after Welcome is built.
/// The auth view model owns the pending notice across the protected-route
/// teardown; this route merely consumes it once the local sign-out is complete.
class SessionSupersededDialogHost extends StatefulWidget {
  const SessionSupersededDialogHost({
    required this.authViewModel,
    required this.child,
    super.key,
  });

  final AuthViewModel authViewModel;
  final Widget child;

  @override
  State<SessionSupersededDialogHost> createState() =>
      _SessionSupersededDialogHostState();
}

class _SessionSupersededDialogHostState
    extends State<SessionSupersededDialogHost> {
  bool _scheduled = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    widget.authViewModel.addListener(_scheduleNotice);
    _scheduleNotice();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recheck if this route becomes current after another auth route leaves.
    if (ModalRoute.of(context)?.isCurrent == true) _scheduleNotice();
  }

  @override
  void didUpdateWidget(SessionSupersededDialogHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authViewModel == widget.authViewModel) return;
    oldWidget.authViewModel.removeListener(_scheduleNotice);
    widget.authViewModel.addListener(_scheduleNotice);
    _scheduleNotice();
  }

  void _scheduleNotice() {
    if (_scheduled ||
        _showing ||
        !widget.authViewModel.hasSessionSupersededNotice) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted ||
          _showing ||
          !widget.authViewModel.hasSessionSupersededNotice ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      final loc = AppLocalizations.of(context);
      if (!widget.authViewModel.takeSessionSupersededNotice()) return;
      _showing = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(loc.translate('sessionSupersededDialogTitle')),
            content: Text(loc.translate('sessionSupersededDialogBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(loc.translate('sessionSupersededDialogOk')),
              ),
            ],
          ),
        ),
      ).whenComplete(() {
        _showing = false;
        if (mounted) _scheduleNotice();
      });
    });
  }

  @override
  void dispose() {
    widget.authViewModel.removeListener(_scheduleNotice);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
