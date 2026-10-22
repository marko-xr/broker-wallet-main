import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/login_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
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

                  // Phone / Email tabs. Restored at the product owner's
                  // request: this UI is theirs, and where phone sign-in cannot
                  // complete the screen says so on submit rather than hiding
                  // the option.
                  _LoginTabs(
                    method: vm.loginMethod,
                    onChanged: vm.setLoginMethod,
                    localization: localization,
                  ),

                  const SizedBox(height: 24),

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
                      outlined: true,
                    ),
                    const SizedBox(height: 280),
                    SizedBox(
                      width: double.infinity,
                      height: AppControlSizes.standardButtonHeight,
                      child: ElevatedButton(
                        onPressed:
                            vm.isLoading ? null : () => vm.sendOTP(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32)),
                          padding: EdgeInsets.zero,
                        ),
                        child: vm.isLoading
                            ? const _ButtonSpinner()
                            : Text(
                                localization.translate('sendOTP'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.buttonText
                                    .copyWith(color: Colors.white),
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
                      hasError: vm.emailError != null,
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
                      hasError: vm.passwordError != null,
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
                      height: AppControlSizes.standardButtonHeight,
                      child: ElevatedButton(
                        onPressed:
                            vm.isLoading ? null : () => vm.signIn(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32)),
                          padding: EdgeInsets.zero,
                        ),
                        child: vm.isLoading
                            ? const _ButtonSpinner()
                            : Text(
                                localization.translate('signIn'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.buttonText
                                    .copyWith(color: Colors.white),
                              ),
                      ),
                    ),
                  ],

                  // Then add it back wrapped in an email-only condition:
                  if (vm.loginMethod == LoginMethod.email) ...[
                    const SizedBox(height: 24),
                    // Same divider as the date headings in the Offers,
                    // Requests and Owners lists: a line that fades out toward
                    // the outer edge on each side of the label.
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  colors.onSurface.withValues(alpha: 0.2),
                                ],
                                begin: AlignmentDirectional.centerStart,
                                end: AlignmentDirectional.centerEnd,
                              ),
                            ),
                          ),
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
                        Expanded(
                          child: Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colors.onSurface.withValues(alpha: 0.2),
                                  Colors.transparent,
                                ],
                                begin: AlignmentDirectional.centerStart,
                                end: AlignmentDirectional.centerEnd,
                              ),
                            ),
                          ),
                        ),
                      ],
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
      height: AppControlSizes.standardButtonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.outline.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
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

/// The progress indicator the app's large buttons show in place of the label
/// (as the Save button does).
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8, start: 4),
      child: Text(
        text,
        style: AppTextStyles.sectionLabel.copyWith(
          color: AuthInputStyle.label(Theme.of(context).colorScheme),
        ),
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
  final bool hasError;

  const _TextFieldIcon({
    this.iconAsset,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
    this.forceLTR = false,
    this.hasError = false,
    Key? key,
  }) : super(key: key);

  @override
  State<_TextFieldIcon> createState() => _TextFieldIconState();
}

class _TextFieldIconState extends State<_TextFieldIcon> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode.addListener(_onFocusChanged);
  }

  // Only repaints the field outline; focus behaviour itself is untouched.
  void _onFocusChanged() => setState(() {});

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
    _focusNode.dispose();
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

    final focused = _focusNode.hasFocus;

    final textField = TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      textAlign: shouldForceLTR
          ? (isRTL ? TextAlign.end : TextAlign.start) // hint/caret placement
          : TextAlign.start,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: widget.hint,
        hintStyle: AppTextStyles.hintText.copyWith(
          color: AuthInputStyle.hint(colors),
          height: 1.3,
        ),
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
      // Painted over the existing box, so it is the single field boundary and
      // adds no layout size or padding.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AuthInputStyle.border(
            colors,
            focused: focused,
            hasError: widget.hasError,
          ),
          width: AuthInputStyle.borderWidth,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (widget.iconAsset != null)
            SvgPicture.asset(
              widget.iconAsset!,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                AuthInputStyle.icon(
                  colors,
                  focused: focused,
                  hasError: widget.hasError,
                ),
                BlendMode.srcIn,
              ),
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
