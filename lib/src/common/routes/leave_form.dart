import 'package:go_router/go_router.dart';

/// Leaves an Add form after a save, a cancel or a discard: back to the screen
/// it was opened from (a list, or Home's quick actions), and Home only when
/// there is nothing to go back to (the form was opened by a link).
///
/// Takes the router rather than a context, so a dialog can read it before it
/// closes itself.
void leaveForm(GoRouter router) {
  if (router.canPop()) {
    router.pop();
  } else {
    router.go('/home');
  }
}
