import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// "Did you mean name@gmail.com?" under an email field: a hint, never an
/// error. Tapping it puts [suggestion] in the field.
class EmailSuggestionHint extends StatelessWidget {
  const EmailSuggestionHint({
    super.key,
    required this.suggestion,
    required this.onAccept,
  });

  final String suggestion;
  final VoidCallback onAccept;

  // The address is kept left-to-right inside an Arabic sentence.
  static final String _ltrStart = String.fromCharCode(0x2066);
  static final String _isolateEnd = String.fromCharCode(0x2069);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final sentence = AppLocalizations.of(context).translate('emailDidYouMean');
    final parts = sentence.split('{email}');
    final before = parts.first;
    final after = parts.length > 1 ? parts.sublist(1).join('{email}') : '';
    final style = texts.bodySmall?.copyWith(color: colors.onSurfaceVariant);

    return Semantics(
      button: true,
      child: InkWell(
        onTap: onAccept,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(text: before),
                TextSpan(
                  text: '$_ltrStart$suggestion$_isolateEnd',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.primary,
                  ),
                ),
                TextSpan(text: after),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
