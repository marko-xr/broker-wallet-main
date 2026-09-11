import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/login_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/input_phone_validation.dart';

// Enforce LTR for phone/email/ID fields in Arabic UI (safe, minimal change).

class SignInView extends StatefulWidget {
  const SignInView({super.key});

  @override
  State<SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<SignInView> {
  // Navigation after a successful sign-in is owned solely by the GoRouter
  // redirect in app.dart. This screen used to schedule its own post-frame
  // `go('/home')` as well, gated on `isLoading` — auth operation state stood in
  // for bootstrap state — which made two authorities race for the same
  // transition.

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);

    return ChangeNotifierProvider(
      create: (_) => SignInViewModel(),
      child: Consumer<SignInViewModel>(
        builder: (context, vm, _) {
          final colors = Theme.of(context).colorScheme;

          return Scaffold(
            backgroundColor: colors.surface,
            appBar: AppBar(
              leading: const BackArrowButton(),
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),

                  // Title
                  Text(
                    localization.translate('welcomeBack'),
                    style: AppTextStyles.appBarTitle.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    localization.translate('welcomeBackDescription'),
                    style: AppTextStyles.bodyText.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 34),

                  // Phone / Email tabs — only where phone sign-in exists.
                  // Otherwise the screen is the email form alone, with no
                  // dead-end phone option.
                  if (SignInViewModel.phoneSignInAvailable) ...[
                    _LoginTabs(
                      method: vm.loginMethod,
                      onChanged: vm.setLoginMethod,
                      localization: localization,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // --- conditional form ---
                  if (vm.loginMethod == LoginMethod.phone) ...[
                    _Label(localization.translate('phoneNumber')),
                    PhoneInputWidget(
                      countryCode: vm.countryCode,
                      value: vm.phoneController.text,
                      onChanged: vm.setPhone,
                      localization: localization,
                      phoneError: vm.phoneError,
                      showError: vm.phoneError != null,
                      validateInternally: false,
                    ),
                    const SizedBox(height: 280),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed:
                            vm.isLoading ? null : () => vm.sendOTP(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                          elevation: 0,
                        ),
                        child: vm.isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text(
                                localization.translate('sendOTP'),
                                style: AppTextStyles.buttonText.copyWith(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),

                    // Add the "Don't have account" section for phone method
                    const SizedBox(height: 30),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            localization.translate('dontHaveAccount'),
                            style: AppTextStyles.bodyText,
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => context.go('/sign-up'),
                            child: Text(
                              localization.translate('signUp'),
                              style: AppTextStyles.bodyText.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    _Label(localization.translate('email')),
                    _TextFieldIcon(
                      iconAsset: 'assets/icons/email.svg',
                      hint: localization.translate('enterEmail'),
                      value: vm.emailController.text,
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
                    _Label(localization.translate('password')),
                    _TextFieldIcon(
                      iconAsset: 'assets/icons/lock-password.svg',
                      hint: localization.translate('enterPassword'),
                      value: vm.passwordController.text,
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
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => vm.forgotPassword(context),
                        child: Text(
                          localization.translate('forgotPassword'),
                          style: AppTextStyles.bodyText.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed:
                            vm.isLoading ? null : () => vm.signIn(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                          elevation: 0,
                        ),
                        child: vm.isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text(
                                localization.translate('signIn'),
                                style: AppTextStyles.buttonText.copyWith(
                                    color: Colors.white, fontSize: 16),
                              ),
                      ),
                    ),
                  ],

                  // Then add it back wrapped in an email-only condition:
                  if (vm.loginMethod == LoginMethod.email) ...[
                    const SizedBox(height: 24),
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
                    SizedBox(
                      width: double.infinity,
                      child: _buildSocialButton(
                        localization.translate('google'),
                        'assets/icons/google-icon.svg',
                        () => vm.signInWithGoogle(context),
                        colors,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(localization.translate('dontHaveAccount'),
                              style: AppTextStyles.bodyText),
                          GestureDetector(
                            onTap: () => context.go('/sign-up'),
                            child: Text(
                              localization.translate('signUp'),
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
            Flexible(
              child: Text(
                text,
                style: AppTextStyles.bodyText.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Atomic Widgets (copy from SignUpView) ---

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8, start: 4),
      child: Text(text, style: AppTextStyles.sectionLabel),
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

class _LoginTabs extends StatelessWidget {
  final LoginMethod method;
  final ValueChanged<LoginMethod> onChanged;
  final AppLocalizations localization;

  const _LoginTabs({
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
              onTap: () => onChanged(LoginMethod.phone),
              child: Container(
                decoration: BoxDecoration(
                  color: method == LoginMethod.phone
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Text(
                  localization.translate('phoneNumber'),
                  style: AppTextStyles.tabText.copyWith(
                    color: method == LoginMethod.phone
                        ? Colors.white
                        : colors.onSurface,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(LoginMethod.email),
              child: Container(
                decoration: BoxDecoration(
                  color: method == LoginMethod.email
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Text(
                  localization.translate('email'),
                  style: AppTextStyles.tabText.copyWith(
                    color: method == LoginMethod.email
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
