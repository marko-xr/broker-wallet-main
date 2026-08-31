import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Enforce LTR for phone/email/ID fields in Arabic UI (safe, minimal change).

class ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String iconAsset;
  final bool isSvg;
  final TextInputType keyboardType;
  final bool isPassword;
  final VoidCallback? onTogglePassword;
  final bool showPassword;

  const ProfileTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.iconAsset,
    this.isSvg = false,
    this.keyboardType = TextInputType.text,
    this.isPassword = false,
    this.onTogglePassword,
    this.showPassword = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final shouldForceLTR = keyboardType == TextInputType.phone ||
        keyboardType == TextInputType.emailAddress ||
        keyboardType == TextInputType.url;

    final textField = TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: isPassword && !showPassword,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: Color.fromARGB((0.6 * 255).round(), colors.onSurface.red,
              colors.onSurface.green, colors.onSurface.blue),
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: isSvg
              ? SvgPicture.asset(
                  iconAsset,
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    Color.fromARGB((0.6 * 255).round(), colors.onSurface.red,
                        colors.onSurface.green, colors.onSurface.blue),
                    BlendMode.srcIn,
                  ),
                )
              : Icon(
                  IconData(
                    // ignore: non_const_argument_for_const_parameter
                    int.parse(iconAsset),
                    fontFamily: 'MaterialIcons',
                  ),
                  color: Color.fromARGB(
                      (0.6 * 255).round(),
                      colors.onSurface.red,
                      colors.onSurface.green,
                      colors.onSurface.blue),
                ),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  showPassword ? Icons.visibility_off : Icons.visibility,
                  color: Color.fromARGB(
                      (0.6 * 255).round(),
                      colors.onSurface.red,
                      colors.onSurface.green,
                      colors.onSurface.blue),
                ),
                onPressed: onTogglePassword,
              )
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      textAlign: shouldForceLTR ? TextAlign.left : TextAlign.start,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color.fromARGB((0.3 * 255).round(), colors.outline.red,
              colors.outline.green, colors.outline.blue),
        ),
      ),
      child: shouldForceLTR
          ? ForceDirectionality(
              direction: TextDirection.ltr,
              child: textField,
            )
          : textField,
    );
  }
}
