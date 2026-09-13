import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/password_policy.dart';
import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:flutter/material.dart';

/// One password input, used by Change Password, Reset Password and nothing
/// else, so every password field in the app behaves identically.
///
/// The value is always laid out left-to-right, including in Arabic: a password
/// is an opaque sequence, and mirroring it makes a typo impossible to spot.
/// The label and everything around it stay in the reading direction.
///
/// The visibility toggle carries its own semantics label because an icon-only
/// control that changes what is on screen is otherwise unusable with a screen
/// reader.
class PasswordFormField extends StatefulWidget {
  const PasswordFormField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.autofillHints,
    this.enabled = true,
    this.autofocus = false,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  /// Purpose-specific: `password` for an existing secret, `newPassword` for one
  /// being created, so a password manager offers the right thing and can save
  /// the change.
  final List<String> autofillHints;

  final bool enabled;
  final bool autofocus;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordFormField> createState() => _PasswordFormFieldState();
}

class _PasswordFormFieldState extends State<PasswordFormField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final loc = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: texts.labelLarge),
        const SizedBox(height: 6),
        ForceDirectionality(
          direction: TextDirection.ltr,
          child: TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: widget.textInputAction,
            autofillHints: widget.enabled ? widget.autofillHints : null,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: const Icon(Icons.lock_outline),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: Semantics(
                button: true,
                label: loc.translate(
                  _obscured ? 'showPassword' : 'hidePassword',
                ),
                child: IconButton(
                  onPressed: () => setState(() => _obscured = !_obscured),
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: colors.onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The live requirement checklist for a new password.
///
/// It states the rules and whether each one is met yet - never a verdict such
/// as "Strong", which would be an estimate this application has no estimator
/// for. Once every rule is met the list collapses to a single confirmation line
/// so it stops competing with the button the user is reaching for.
class PasswordRequirementChecklist extends StatelessWidget {
  const PasswordRequirementChecklist({
    super.key,
    required this.password,
  });

  final String password;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final loc = AppLocalizations.of(context);
    final unmet = PasswordPolicy.unmetRequirements(password);

    if (password.isNotEmpty && unmet.isEmpty) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loc.translate('passwordMeetsRequirements'),
              style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final requirement in PasswordPolicy.requirements)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  unmet.contains(requirement)
                      ? Icons.circle_outlined
                      : Icons.check_circle_outline,
                  size: 14,
                  color: unmet.contains(requirement)
                      ? colors.onSurfaceVariant
                      : colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.translate(passwordRequirementKey(requirement)),
                    style: texts.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One inline error line, shaped like the one the email-change sheet uses so
/// failures read the same everywhere in the account area.
class PasswordErrorLine extends StatelessWidget {
  const PasswordErrorLine({super.key, required this.messageKey});

  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 16, color: colors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppLocalizations.of(context).translate(messageKey),
            style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
          ),
        ),
      ],
    );
  }
}
