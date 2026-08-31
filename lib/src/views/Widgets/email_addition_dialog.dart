import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Bottom-sheet email addition UI that avoids keyboard push issues.
/// Use with showModalBottomSheet(isScrollControlled: true).
class EmailAdditionDialog extends StatefulWidget {
  final Function(String email, String password, String confirmPassword)
      onSubmit;

  const EmailAdditionDialog({super.key, required this.onSubmit});

  @override
  State<EmailAdditionDialog> createState() => _EmailAdditionDialogState();
}

class _EmailAdditionDialogState extends State<EmailAdditionDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    return GestureDetector(
      // tap outside fields to dismiss keyboard (keeps sheet in place)
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              // Max height ~85% of screen for small devices
              final maxH = MediaQuery.sizeOf(ctx).height * 0.85;
              final bottomInset =
                  MediaQuery.viewInsetsOf(ctx).bottom; // keyboard height

              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle + Title Row
                    const SizedBox(height: 8),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.outline.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.email_outlined, color: colors.primary),
                          const SizedBox(width: 10),
                          Text(
                            loc.translate('addEmail'),
                            style: texts.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            child: Text(loc.translate('cancel')),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable content with keyboard-aware padding
                    Expanded(
                      child: SingleChildScrollView(
                        padding:
                            EdgeInsets.fromLTRB(20, 8, 20, 12 + bottomInset),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Notice
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.orange.withValues(alpha: 0.25)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.security,
                                            color: Colors.orange[700],
                                            size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          loc.translate('importantNotice'),
                                          style: texts.labelLarge?.copyWith(
                                            color: Colors.orange[800],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      loc.translate(
                                          'emailNotAddedUntilVerified'),
                                      style: texts.bodySmall
                                          ?.copyWith(color: Colors.orange[800]),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '• ${loc.translate('checkYourEmail')}\n'
                                      '• ${loc.translate('clickVerificationLink')}\n'
                                      '• ${loc.translate('emailWillBeAdded')}',
                                      style: texts.bodySmall
                                          ?.copyWith(color: Colors.orange[800]),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Email
                              Text(loc.translate('email'),
                                  style: texts.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              _buildEmailField(),

                              const SizedBox(height: 16),

                              // Password
                              Text(loc.translate('password'),
                                  style: texts.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              _buildPasswordField(),

                              const SizedBox(height: 16),

                              // Confirm password
                              Text(loc.translate('confirmPassword'),
                                  style: texts.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              _buildConfirmPasswordField(),

                              const SizedBox(height: 16),

                              // Info box
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: colors.primary.withValues(alpha: 0.25)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.mark_email_read_outlined,
                                        color: colors.primary, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        loc.translate(
                                            'verificationEmailWillBeSent'),
                                        style: texts.bodySmall
                                            ?.copyWith(color: colors.primary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Sticky action bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(loc.translate('verifyYourEmail')),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);

    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(
        hintText: loc.translate('enterEmail'),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: SvgPicture.asset(
            SvgIcon.email,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        filled: true,
        fillColor: colors.surface,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return loc.translate('emailRequired');
        }
        if (!_isValidEmail(value.trim())) {
          return loc.translate('invalidEmail');
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);

    return TextFormField(
      controller: _passwordController,
      obscureText: !_showPassword,
      decoration: InputDecoration(
        hintText: loc.translate('enterPassword'),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: SvgPicture.asset(
            SvgIcon.lockPassword,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
          ),
        ),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _showPassword = !_showPassword),
          icon: SvgPicture.asset(
            _showPassword ? SvgIcon.unHidePassword : SvgIcon.hidePassword,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        filled: true,
        fillColor: colors.surface,
      ),
      validator: (value) {
        if (value == null || value.isEmpty)
          return loc.translate('passwordRequired');
        if (value.length < 6) return loc.translate('passwordTooShort');
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);

    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: !_showConfirmPassword,
      decoration: InputDecoration(
        hintText: loc.translate('confirmPassword'),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: SvgPicture.asset(
            SvgIcon.lockPassword,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
          ),
        ),
        suffixIcon: IconButton(
          onPressed: () =>
              setState(() => _showConfirmPassword = !_showConfirmPassword),
          icon: SvgPicture.asset(
            _showConfirmPassword
                ? SvgIcon.unHidePassword
                : SvgIcon.hidePassword,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        filled: true,
        fillColor: colors.surface,
      ),
      validator: (value) {
        if (value == null || value.isEmpty)
          return loc.translate('confirmPasswordRequired');
        if (value != _passwordController.text)
          return loc.translate('passwordsDoNotMatch');
        return null;
      },
    );
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);

  void _handleSubmit() {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isLoading = true);
      widget.onSubmit(
        _emailController.text.trim(),
        _passwordController.text,
        _confirmPasswordController.text,
      );
    }
  }
}
