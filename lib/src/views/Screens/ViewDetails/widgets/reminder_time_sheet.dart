import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Asks for the follow-up reminder's time with two scroll wheels (hours and
/// minutes, one-minute steps) instead of the clock dial, where hitting one
/// minute on the circle is hard. Returns null on Cancel or dismiss.
Future<TimeOfDay?> showReminderTimeSheet(
  BuildContext context, {
  required TimeOfDay initial,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    showDragHandle: true,
    builder: (_) => ReminderTimeSheet(initial: initial),
  );
}

class ReminderTimeSheet extends StatefulWidget {
  const ReminderTimeSheet({super.key, required this.initial});

  final TimeOfDay initial;

  /// Height of the wheels: five rows visible, the chosen one in the middle.
  static const double wheelHeight = 216;

  @override
  State<ReminderTimeSheet> createState() => _ReminderTimeSheetState();
}

class _ReminderTimeSheetState extends State<ReminderTimeSheet> {
  late TimeOfDay _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.translate('followUpPickTime'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: ReminderTimeSheet.wheelHeight,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: theme.brightness,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      fontSize: 22,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  key: const ValueKey('follow-up-time-wheels'),
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: DateTime(
                    2000,
                    1,
                    1,
                    widget.initial.hour,
                    widget.initial.minute,
                  ),
                  use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
                  onDateTimeChanged: (time) =>
                      _value = TimeOfDay(hour: time.hour, minute: time.minute),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('follow-up-time-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(loc.translate('cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('follow-up-time-save'),
                    onPressed: () => Navigator.of(context).pop(_value),
                    child: Text(loc.translate('save')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
