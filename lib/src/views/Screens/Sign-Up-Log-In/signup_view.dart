import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/signup_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/constants.dart';

// Enforce LTR for phone/email/ID fields in Arabic UI (safe, minimal change).

import '../../../viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/input_phone_validation.dart';

class SignUpView extends StatefulWidget {
  const SignUpView({super.key});

  @override
  State<SignUpView> createState() => _SignUpViewState();
}

class _SignUpViewState extends State<SignUpView> {
  // Navigation after a successful sign-up is owned solely by the GoRouter
  // redirect in app.dart. `authVM.isLoading` is still read below, but only as
  // auth *operation* state for the submit button — never as bootstrap state.

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);

    return ChangeNotifierProvider(
      create: (_) => SignUpViewModel(),
      child: Consumer2<SignUpViewModel, AuthViewModel>(
        builder: (context, vm, authVM, _) {
          final theme = Theme.of(context);
          final colors = theme.colorScheme;

          return Scaffold(
            backgroundColor: colors.surface,
            appBar: AppBar(
              leading: const BackArrowButton(),
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    localization.translate('letsGetStarted'),
                    style: AppTextStyles.appBarTitle.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    localization.translate('welcomeSignUp'),
                    style: AppTextStyles.bodyText.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 34),

                  // Phone / Email tabs. Restored at the product owner's
                  // request: this UI is theirs, and where phone registration
                  // cannot complete the screen says so on submit rather than
                  // hiding the option.
                  _SignupTabs(
                    method: vm.signupMethod,
                    onChanged: vm.setSignupMethod,
                    localization: localization,
                  ),

                  const SizedBox(height: 24),

                  // Conditional form fields based on signup method
                  if (vm.signupMethod == SignupMethod.phone) ...[
                    // Name Field (required for phone signup)
                    _Label(localization.translate('name')),
                    _TextFieldIcon(
                      iconAsset: 'assets/icons/profile-person.svg',
                      hint: localization.translate('enterName'),
                      value: vm.name,
                      onChanged: vm.setName,
                    ),
                    if (vm.nameError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        vm.nameError!,
                        style: AppTextStyles.bodyText.copyWith(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Phone Number Field
                    _Label(localization.translate('phoneNumber')),
                    PhoneInputWidget(
                      countryCode: vm.countryCode,
                      value: vm.phone,
                      onChanged: vm.setPhone,
                      localization: localization,
                      phoneError: vm.phoneError,
                      showError: vm.phoneError != null,
                      validateInternally: false,
                    ),
                  ] else ...[
                    // Email signup fields
                    // Name Field
                    _Label(localization.translate('name')),
                    _TextFieldIcon(
                      iconAsset: 'assets/icons/profile-person.svg',
                      hint: localization.translate('enterName'),
                      value: vm.name,
                      onChanged: vm.setName,
                    ),
                    if (vm.nameError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        vm.nameError!,
                        style: AppTextStyles.bodyText.copyWith(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Email Field
                    _Label(localization.translate('email')),
                    _TextFieldIcon(
                      iconAsset: 'assets/icons/email.svg',
                      hint: localization.translate('enterEmail'),
                      value: vm.email,
                      onChanged: vm.setEmail,
                      keyboardType: TextInputType.emailAddress,
                      forceLTR: true,
                    ),
                    if (vm.emailError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        vm.emailError!,
                        style: AppTextStyles.bodyText.copyWith(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Password Field
                    _Label(localization.translate('password')),
                    _TextFieldIcon(
                      iconAsset: 'assets/icons/lock-password.svg',
                      hint: localization.translate('enterPassword'),
                      value: vm.password,
                      onChanged: vm.setPassword,
                      obscureText: !vm.showPassword,
                      suffixIcon: IconButton(
                        icon: SvgPicture.asset(
                          vm.showPassword
                              ? 'assets/icons/un-hide-password.svg'
                              : 'assets/icons/hide-password.svg',
                          width: 24,
                          height: 24,
                          colorFilter: ColorFilter.mode(
                            colors.primary,
                            BlendMode.srcIn,
                          ),
                        ),
                        onPressed: vm.togglePasswordVisibility,
                      ),
                    ),
                    if (vm.passwordError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        vm.passwordError!,
                        style: AppTextStyles.bodyText.copyWith(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Confirm Password Field
                    _Label(localization.translate('confirmPassword')),
                    _TextFieldIcon(
                      iconAsset: 'assets/icons/lock-password.svg',
                      hint: localization.translate('enterConfirmPassword'),
                      value: vm.confirmPassword,
                      onChanged: vm.setConfirmPassword,
                      obscureText: !vm.showConfirmPassword,
                      suffixIcon: IconButton(
                        icon: SvgPicture.asset(
                          vm.showConfirmPassword
                              ? 'assets/icons/un-hide-password.svg'
                              : 'assets/icons/hide-password.svg',
                          width: 24,
                          height: 24,
                          colorFilter: ColorFilter.mode(
                            colors.primary,
                            BlendMode.srcIn,
                          ),
                        ),
                        onPressed: vm.toggleConfirmPasswordVisibility,
                      ),
                    ),
                    if (vm.confirmPasswordError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        vm.confirmPasswordError!,
                        style: AppTextStyles.bodyText.copyWith(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],

                  // Conditional spacing based on signup method
                  SizedBox(
                    height: vm.signupMethod == SignupMethod.phone ? 180 : 40,
                  ),

                  // Sign Up Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (vm.isLoading || authVM.isLoading)
                          ? null
                          : () {
                              if (vm.signupMethod == SignupMethod.phone) {
                                vm.signUpWithPhone(context);
                              } else {
                                vm.signUp(context);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 0,
                      ),
                      child: (vm.isLoading || authVM.isLoading)
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              vm.signupMethod == SignupMethod.phone
                                  ? localization.translate('sendOTP')
                                  : localization.translate('signUp'),
                              style: AppTextStyles.buttonText.copyWith(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),

                  // Only show social signup for email method
                  if (vm.signupMethod == SignupMethod.email) ...[
                    const SizedBox(height: 24),

                    // Or sign in with
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 1,
                            color: colors.onSurface.withValues(alpha: 0.2),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              localization.translate('orSignInWith'),
                              style: AppTextStyles.bodyText.copyWith(
                                color: colors.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          Container(
                            width: 60,
                            height: 1,
                            color: colors.onSurface.withValues(alpha: 0.2),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Social Login Buttons
                    SizedBox(
                      width: double.infinity,
                      child: _buildSocialButton(
                        localization.translate('google'),
                        'assets/icons/google-icon.svg',
                        () => vm.signUpWithGoogle(context),
                        colors,
                      ),
                    ),
                  ],

                  const SizedBox(height: 30),

                  // Already have account
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          localization.translate('alreadyHaveAccount'),
                          style: AppTextStyles.bodyText,
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => context.go('/sign-in'),
                          child: Text(
                            localization.translate('signIn'),
                            style: AppTextStyles.bodyText.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSocialButton(
    String text,
    String iconPath,
    VoidCallback onPressed,
    ColorScheme colors,
  ) {
    return Container(
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.outline.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              iconPath,
              width: 20,
              height: 20,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: AppTextStyles.bodyText.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Atomic Widgets (reuse from AddOfficesView) ---

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8, start: 4),
      child: Text(
        text,
        style: AppTextStyles.sectionLabel,
      ),
    );
  }
}

class _TextFieldIcon extends StatefulWidget {
  final String? iconAsset;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType keyboardType;
  final bool forceLTR;

  const _TextFieldIcon({
    this.iconAsset,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
    this.forceLTR = false,
    Key? key,
  }) : super(key: key);

  @override
  State<_TextFieldIcon> createState() => _TextFieldIconState();
}

class _TextFieldIconState extends State<_TextFieldIcon> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _TextFieldIcon old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      // Preserve caret when parent updates value (validation, trims, etc.)
      final oldSel = _controller.selection;
      final newText = widget.value;
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: oldSel.baseOffset.clamp(0, newText.length),
        ),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Force LTR for email/phone/url (content flows left-to-right),
    // but align visually with the UI direction so the hint sits near the icon.
    final shouldForceLTR = widget.forceLTR ||
        widget.keyboardType == TextInputType.phone ||
        widget.keyboardType == TextInputType.emailAddress ||
        widget.keyboardType == TextInputType.url;

    final isRTL = Directionality.of(context) == TextDirection.rtl;

    final textField = TextField(
      controller: _controller,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      textAlign: shouldForceLTR
          ? (isRTL ? TextAlign.end : TextAlign.start) // hint/caret placement
          : TextAlign.start,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: widget.hint,
        hintStyle: AppTextStyles.hintText.copyWith(height: 1.3),
        isCollapsed: true, // prevents odd vertical shifts
        contentPadding: EdgeInsets.zero, // keeps hint snug near icon
      ),
      style: AppTextStyles.bodyText.copyWith(height: 1.3),
      strutStyle: const StrutStyle(height: 1.3, forceStrutHeight: true),
      onChanged: widget.onChanged,
    );

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (widget.iconAsset != null)
            SvgPicture.asset(
              widget.iconAsset!,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: shouldForceLTR
                ? ForceDirectionality(
                    direction:
                        TextDirection.ltr, // content is LTR (email/phone)
                    child: textField,
                  )
                : textField,
          ),
          if (widget.suffixIcon != null) widget.suffixIcon!,
        ],
      ),
    );
  }
}

class _SignupTabs extends StatelessWidget {
  final SignupMethod method;
  final ValueChanged<SignupMethod> onChanged;
  final AppLocalizations localization;

  const _SignupTabs({
    required this.method,
    required this.onChanged,
    required this.localization,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(SignupMethod.phone),
              child: Container(
                decoration: BoxDecoration(
                  color: method == SignupMethod.phone
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Text(
                  localization.translate('phoneNumber'),
                  style: AppTextStyles.tabText.copyWith(
                    color: method == SignupMethod.phone
                        ? Colors.white
                        : colors.onSurface,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(SignupMethod.email),
              child: Container(
                decoration: BoxDecoration(
                  color: method == SignupMethod.email
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Text(
                  localization.translate('email'),
                  style: AppTextStyles.tabText.copyWith(
                    color: method == SignupMethod.email
                        ? Colors.white
                        : colors.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
