import 'package:flutter/widgets.dart';

extension RtlX on BuildContext {
  bool get isRTL {
    final dir = Directionality.maybeOf(this);
    if (dir != null) return dir == TextDirection.rtl;
    // Fallback to locale if Directionality not found
    final locale = Localizations.maybeLocaleOf(this);
    return (locale?.languageCode ?? 'en') == 'ar';
  }
}

/// Force a subtree’s text direction (useful for phone/email fields in Arabic).
class ForceDirectionality extends StatelessWidget {
  final TextDirection direction;
  final Widget child;
  const ForceDirectionality(
      {super.key, required this.direction, required this.child});
  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: direction, child: child);
}
