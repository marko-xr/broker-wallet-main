import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/Views/Widgets/input_phone_validation.dart';

class PhoneAdditionDialog extends StatefulWidget {
  final Future<void> Function(String phoneNumber) onSubmit;

  const PhoneAdditionDialog({
    super.key,
    required this.onSubmit,
  });

  @override
  State<PhoneAdditionDialog> createState() => _PhoneAdditionDialogState();
}

class _PhoneAdditionDialogState extends State<PhoneAdditionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _focus = FocusNode();

  static const String _countryCode = '+971'; // Fixed UAE country code
  String _phoneNumber = ''; // Store clean phone number
  String? _phoneError; // Store validation error
  bool _isLoading = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final loc = AppLocalizations.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420), // keep dialog compact
        child: AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          title: Row(
            children: [
              Icon(Icons.phone_outlined, color: colors.primary),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  loc.translate('addPhoneNumber'),
                  style:
                      texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Info message (subtle, compact)
                _InfoBanner(
                  icon: Icons.info_outline,
                  text: loc.translate('phoneAdditionInfo'),
                  background: colors.primary.withValues(alpha: 0.08),
                  foreground: colors.primary,
                  borderColor: colors.primary.withValues(alpha: 0.15),
                  dense: true,
                ),
                const SizedBox(height: 14),

                // Label
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    loc.translate('phoneNumber'),
                    style:
                        texts.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 6),

                // Phone field
                PhoneInputWidget(
                  countryCode:
                      _countryCode.substring(1), // Remove '+' for widget
                  value: _phoneNumber,
                  onChanged: (value) {
                    setState(() {
                      _phoneNumber = value;
                      _phoneError = null; // Clear error on change
                    });
                  },
                  localization: loc,
                  phoneError: _phoneError,
                  showError: _phoneError != null,
                  validateInternally: false, // We'll handle validation manually
                ),

                const SizedBox(height: 12),

                // OTP note (warning tone, compact)
                _InfoBanner(
                  icon: Icons.sms_outlined,
                  title: loc.translate('phoneVerificationRequired'),
                  text: loc.translate('otpWillBeSent'),
                  background: Colors.orange.withValues(alpha: 0.08),
                  foreground: Colors.orange[800]!,
                  borderColor: Colors.orange.withValues(alpha: 0.25),
                  dense: true,
                ),
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _isLoading ? null : () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      backgroundColor: colors.surface,
                      foregroundColor: colors.onSurface,
                      elevation: 0,
                      side: BorderSide(color: colors.outline),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(loc.translate('cancel')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            loc.translate('sendOTPVerification'),
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isValidUAEPhone(String phone) {
    // Normalize: remove spaces/dashes
    final normalized = phone.replaceAll(RegExp(r'[\s\-]'), '');
    // Accept leading 0 or not; then (50|51|52|54|55|56|58) + 7 digits
    final uaePattern = RegExp(r'^0?(50|51|52|54|55|56|58)\d{7}$');
    return uaePattern.hasMatch(normalized);
  }

  Future<void> _handleSubmit() async {
    if (_isLoading) return;

    final loc = AppLocalizations.of(context);

    // Validate phone number
    if (_phoneNumber.trim().isEmpty) {
      setState(() => _phoneError = loc.translate('phoneRequired'));
      return;
    }

    if (!_isValidUAEPhone(_phoneNumber)) {
      setState(() => _phoneError = loc.translate('invalidUAEPhoneNumber'));
      return;
    }

    setState(() => _isLoading = true);
    try {
      String phoneNumber =
          _phoneNumber.trim().replaceAll(RegExp(r'[\s\-]'), '');
      if (phoneNumber.startsWith('0')) {
        phoneNumber = phoneNumber.substring(1);
      }
      final fullPhoneNumber = '$_countryCode$phoneNumber';

      // Await in case the caller performs async work (e.g., sending OTP)
      await widget.onSubmit(fullPhoneNumber);

      if (mounted) Navigator.of(context).pop(); // close only on success
    } catch (_) {
      // You can show a SnackBar or inline error handling here if needed
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

/// Compact, reusable info banner used above.
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? title;
  final Color background;
  final Color foreground;
  final Color borderColor;
  final bool dense;

  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
    required this.borderColor,
    this.title,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final texts = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: dense ? const EdgeInsets.all(10) : const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: texts.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  text,
                  style: texts.bodySmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
