import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/follow_up_reminder.dart';
import 'package:broker_wallet/src/repositories/follow_up_reminder_repository.dart';
import 'package:broker_wallet/src/services/push/push_messaging_service.dart';
import 'package:broker_wallet/src/viewmodels/follow_up_reminder_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'details_section.dart';
import 'reminder_time_sheet.dart';

/// "Follow-up reminder" on a Request or Offer Details screen: the user picks
/// a date and time; the server creates the inbox notification (and the push)
/// when it is due. Create, change and cancel all go through the server.
class FollowUpReminderSection extends StatefulWidget {
  const FollowUpReminderSection({
    super.key,
    required this.target,
    required this.targetId,
    this.repository,
  });

  final FollowUpTarget target;
  final String targetId;

  /// Test seam; the app uses the Supabase repository.
  final FollowUpReminderRepository? repository;

  @override
  State<FollowUpReminderSection> createState() =>
      _FollowUpReminderSectionState();
}

class _FollowUpReminderSectionState extends State<FollowUpReminderSection> {
  static bool _pushDeniedNoticeShown = false;

  late final FollowUpReminderViewModel _vm = FollowUpReminderViewModel(
    repository: widget.repository ?? SupabaseFollowUpReminderRepository(),
    target: widget.target,
    targetId: widget.targetId,
  )..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => DetailsSection(
        key: const ValueKey('follow-up-reminder-section'),
        title: loc.translate('followUpReminder'),
        icon: Icons.alarm_outlined,
        child: ConstrainedBox(
          // One height for every state, so loading never makes the screen jump.
          constraints:
              const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: _content(context, loc),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AppLocalizations loc) {
    final theme = Theme.of(context);
    switch (_vm.state) {
      case FollowUpLoadState.loading:
        return const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case FollowUpLoadState.offline:
        return _line(theme, loc.translate('followUpOffline'), muted: true);
      case FollowUpLoadState.failed:
        return _row(
          _line(theme, loc.translate('followUpLoadFailed'), muted: true),
          [
            TextButton(onPressed: _vm.load, child: Text(loc.translate('retry')))
          ],
        );
      case FollowUpLoadState.ready:
        final scheduled = _vm.scheduled;
        final busy = _vm.isBusy;
        if (scheduled == null) {
          return _row(
            _line(theme, loc.translate('followUpNone'), muted: true),
            [
              FilledButton.tonal(
                key: const ValueKey('follow-up-set'),
                onPressed: busy ? null : () => _pick(null),
                child: Text(loc.translate('followUpSet')),
              ),
            ],
          );
        }
        return _row(
          _line(theme, _format(context, scheduled.remindAt)),
          [
            TextButton(
              key: const ValueKey('follow-up-change'),
              onPressed: busy ? null : () => _pick(scheduled.remindAt),
              child: Text(loc.translate('followUpChange')),
            ),
            TextButton(
              key: const ValueKey('follow-up-cancel'),
              onPressed: busy ? null : _cancel,
              child: Text(loc.translate('followUpCancel')),
            ),
          ],
        );
    }
  }

  Widget _line(ThemeData theme, String text, {bool muted = false}) => Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: muted ? theme.colorScheme.onSurfaceVariant : null,
        ),
      );

  /// Text and actions on one line when they fit, stacked when they do not
  /// (narrow phones, large text, Arabic).
  Widget _row(Widget text, List<Widget> actions) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      children: [text, Wrap(spacing: 4, children: actions)],
    );
  }

  static String _format(BuildContext context, DateTime utc) {
    final locale = AppLocalizations.of(context).locale.toString();
    final known = DateFormat.localeExists(locale) ? locale : 'en_US';
    return DateFormat.yMMMEd(known).add_jm().format(utc.toLocal());
  }

  Future<void> _pick(DateTime? current) async {
    final loc = AppLocalizations.of(context);
    final earliest = _vm.earliest;
    final initial = current != null && current.toLocal().isAfter(earliest)
        ? current.toLocal()
        : earliest.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateUtils.dateOnly(earliest),
      lastDate: _vm.latest,
      helpText: loc.translate('followUpPickDate'),
    );
    if (date == null || !mounted) return;
    final time = await showReminderTimeSheet(
      context,
      initial: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final chosen =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final failure = await _vm.schedule(chosen);
    if (!mounted) return;
    if (failure != null) {
      _message(_failureKey(failure));
      return;
    }
    await _askForNotifications();
  }

  Future<void> _cancel() async {
    final failure = await _vm.cancel();
    if (!mounted || failure == null) return;
    _message(_failureKey(failure));
  }

  /// The contextual moment to ask for the notification permission: the user
  /// has just asked to be reminded. A refusal is respected; the reminder still
  /// appears in the in-app inbox.
  Future<void> _askForNotifications() async {
    final push = PushMessagingService.current;
    if (push == null || !push.isActive) return;
    final permission = await push.requestPermissionAndRegister();
    if (!mounted || permission != PushPermission.denied) return;
    // Said once per app run, not after every reminder.
    if (_pushDeniedNoticeShown) return;
    _pushDeniedNoticeShown = true;
    _message('followUpPushDenied');
  }

  void _message(String key) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).translate(key)),
    ));
  }

  static String _failureKey(FollowUpFailureCode code) => switch (code) {
        FollowUpFailureCode.inPast => 'followUpInPast',
        FollowUpFailureCode.tooFar => 'followUpTooFar',
        FollowUpFailureCode.offline => 'followUpOffline',
        FollowUpFailureCode.notFound => 'followUpRecordGone',
        FollowUpFailureCode.tooMany => 'followUpTooMany',
        FollowUpFailureCode.sessionSuperseded ||
        FollowUpFailureCode.unavailable =>
          'followUpSaveFailed',
      };
}
