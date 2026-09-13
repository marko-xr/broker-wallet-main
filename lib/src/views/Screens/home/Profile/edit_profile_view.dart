import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/email_addition_dialog.dart';
import 'package:broker_wallet/src/Views/Widgets/email_change_pending_sheet.dart';
import 'package:broker_wallet/src/Views/Widgets/email_change_sheet.dart';
import 'package:broker_wallet/src/Views/Widgets/change_password_sheet.dart';
import 'package:broker_wallet/src/Views/Widgets/email_verification_dialog.dart';
import 'package:broker_wallet/src/Views/Widgets/phone_addition_dialog.dart';
import 'package:broker_wallet/src/Views/Widgets/phone_otp_dialog.dart';
import 'package:broker_wallet/src/Views/Widgets/current_user_avatar.dart';
import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:broker_wallet/src/common/utils/rtl_utils.dart';
import 'package:broker_wallet/src/viewmodels/phone_verification_viewmodel.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/clean_media_service.dart';
import 'package:broker_wallet/src/services/fast_profile_upload_service.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/Views/Widgets/profile_text_field.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/edit_profile_viewmodel.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/viewmodels/change_password_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/email_change_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/theme_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'dart:async';

class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  File? _selectedImage;
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _isSaving = false; // Track save operation for overlay
  String _originalEmail = '';
  String _originalPhone = '';
  EmailChangeViewModel? _emailChangeViewModel;
  StreamSubscription<ProfileUploadCompletedEvent>?
      _uploadCompletionSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _setupEmailChangeState();
      _initializeUserData();
      _setupUploadCompletionListener();
      _isInitialized = true;
    }
  }

  void _setupEmailChangeState() {
    final authVM = context.read<AuthViewModel>();
    final flow = EmailChangeViewModel(gateway: authVM.emailChange);
    _emailChangeViewModel = flow;
    flow.addListener(_onEmailChangeStateChanged);
    _onEmailChangeStateChanged();
  }

  void _onEmailChangeStateChanged() {
    final flow = _emailChangeViewModel;
    final confirmedEmail = flow?.confirmedEmail ?? '';
    if (confirmedEmail.isNotEmpty && confirmedEmail != _originalEmail) {
      _originalEmail = confirmedEmail;
      _emailController.text = confirmedEmail;
    }
    // A change can complete while this screen is open but the pending sheet is
    // not — the user returns from their mail app straight onto Edit Profile.
    // The sheet consumes the flag when it is open, so this fires at most once.
    if (flow != null && flow.justCompleted && mounted) {
      flow.acknowledgeCompletion();
      _showToast(
        AppLocalizations.of(context).translate('emailChangeCompleted'),
        Theme.of(context).colorScheme.primary,
      );
    }
    if (mounted) setState(() {});
  }

  void _setupUploadCompletionListener() {
    _uploadCompletionSubscription =
        FastProfileUploadService.onUploadCompleted.listen((event) async {
      // Debug log suppressed: profile upload completed

      if (!mounted) return;

      // Capture AuthViewModel reference before async operations
      final authVM = context.read<AuthViewModel>();

      // Refresh the auth state to get updated user data
      await authVM
          .syncUserFromRepository(); // Sync from repository to get latest data
      await authVM.checkEmailVerificationStatus();

      if (mounted) {
        setState(() {
          // This will trigger a rebuild with the new profile image URL
        });
      }
    });
  }

  void _initializeUserData() async {
    final authVM = context.read<AuthViewModel>();

    if (authVM.currentUser != null) {
      final user = authVM.currentUser!;
      // Reopening the editor while a save is still persisting must show what
      // the user last saved, not the value that save is replacing.
      _nameController.text = authVM.pendingProfileName ?? user.name;
      _emailController.text = user.email;
      _originalEmail = user.email; // Store original email

      // Get phone number from user model
      _originalPhone = user.phoneNumber ?? ''; // Store original phone

      // Supabase Auth may hold the confirmed number as `971…` without its
      // `+`; the shared normalizer displays every form the same way.
      _phoneController.text = _localUaeDisplay(user.phoneNumber);

      // Update the UI after data is loaded
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      // No user, stop loading
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final loc = AppLocalizations.of(context);

    return ChangeNotifierProvider(
      create: (ctx) {
        return EditProfileViewModel(
          themeVM: ctx.read<ThemeViewModel>(),
          localeVM: ctx.read<LocaleViewModel>(),
          name: _nameController.text,
          email: _emailController.text,
          phone: _phoneController.text,
        );
      },
      child: Consumer<EditProfileViewModel>(
        builder: (context, vm, _) => Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                leading: const BackArrowButton(),
                title:
                    Text(loc.translate('editProfile'), style: texts.titleLarge),
                centerTitle: true,
                elevation: 0,
                backgroundColor: colors.surface,
              ),
              body: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildIdentityHeader(colors, texts, loc),
                            const SizedBox(height: 24),

                            _SectionLabel(loc.translate('personalInformation')),
                            const SizedBox(height: 8),
                            ProfileTextField(
                              controller: _nameController,
                              hintText: loc.translate('enterName'),
                              iconAsset: 'assets/icons/profile.svg',
                              isSvg: true,
                            ),
                            const SizedBox(height: 20),

                            _SectionLabel(loc.translate('email')),
                            const SizedBox(height: 8),
                            _buildEmailSection(context, vm, colors, texts, loc),
                            const SizedBox(height: 20),

                            _SectionLabel(loc.translate('phoneNumber')),
                            const SizedBox(height: 8),
                            _buildPhoneSection(context, vm, colors, texts, loc),
                            const SizedBox(height: 20),

                            _SectionLabel(loc.translate('password')),
                            const SizedBox(height: 8),
                            _buildPasswordSection(context, colors, texts, loc),
                            const SizedBox(height: 28),

                            // Save owns the name and photo only. Email and
                            // phone are their own confirmed flows and must not
                            // appear to depend on this button.
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSaving
                                    ? null
                                    : () async {
                                        await _saveProfileChanges(vm);
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colors.primary,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  loc.translate('saveChanges'),
                                  style: texts.labelLarge
                                      ?.copyWith(color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              loc.translate('editProfileSaveScope'),
                              textAlign: TextAlign.center,
                              style: texts.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // Semi-transparent loading overlay - only shown during save
            if (_isSaving)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 4,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        loc.translate('savingChanges'),
                        style: texts.bodyLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Compact identity header.
  ///
  /// Avatar, name, and the confirmed email as secondary text — enough to say
  /// whose account this is without the header owning a third of the screen.
  /// The camera badge keeps the existing tap target; the text button beside it
  /// makes the same action discoverable without a separate hint chip.
  ///
  /// Image-picking logic is untouched: this only changes presentation.
  Widget _buildIdentityHeader(
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    final name = _nameController.text.trim();
    final email = _originalEmail.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.3),
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    // The unsaved pick previews here directly. Everything
                    // else — the confirmed image, or a saved image still
                    // uploading — comes from the same current-user source
                    // every other screen uses.
                    child: _selectedImage != null
                        ? Image.file(
                            _selectedImage!,
                            fit: BoxFit.cover,
                            width: 84,
                            height: 84,
                          )
                        : const CurrentUserAvatar(size: 84),
                  ),
                ),
              ),
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 2),
                    ),
                    padding: const EdgeInsets.all(7),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name.isNotEmpty ? name : loc.translate('name'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 2),
            // An address is never Arabic text, so it stays LTR inside an RTL
            // layout while the rest of the header follows the locale.
            ForceDirectionality(
              direction: TextDirection.ltr,
              child: Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: texts.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_camera_outlined, size: 16),
            label: Text(loc.translate('changePhoto')),
            style: TextButton.styleFrom(
              foregroundColor: colors.primary,
              visualDensity: VisualDensity.compact,
              textStyle: texts.labelLarge,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final cleanMediaService = CleanMediaService();
      final loc = AppLocalizations.of(context);

      // Show source selection dialog
      final String? source = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          final theme = Theme.of(context);
          final colors = theme.colorScheme;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.photo_camera,
                    color: Colors.blue,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    loc.translate('selectImageSource'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => Navigator.pop(dialogContext, 'camera'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: colors.outline.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.blue, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                loc.translate('camera'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                loc.translate('takeNewPhoto'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => Navigator.pop(dialogContext, 'gallery'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: colors.outline.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.photo_library,
                              color: Colors.green, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                loc.translate('gallery'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                loc.translate('chooseFromGallery'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  loc.translate('cancel'),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (source == null || !mounted) return;

      // Pick image based on source
      File? selectedFile;
      if (source == 'camera') {
        selectedFile = await cleanMediaService.pickImageFromCamera(context);
      } else if (source == 'gallery') {
        selectedFile = await cleanMediaService.pickImageFromGallery(context);
      }

      if (selectedFile != null && mounted) {
        setState(() {
          _selectedImage = selectedFile;
        });
      }
    } catch (e) {
      // Debug log suppressed: Error selecting image: $e
      if (mounted) {
        _showToast('Error: ${e.toString()}', Colors.red);
      }
    }
  }

  void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  /// Save profile changes (name and image only)
  Future<void> _saveProfileChanges(EditProfileViewModel vm) async {
    if (!mounted) return;

    if (SupabaseConfig.useSupabaseAuth) {
      _saveProfileChangesOptimistically(vm);
      return;
    }

    await _saveProfileChangesLegacy(vm);
  }

  /// Supabase mode.
  ///
  /// The new name and image appear everywhere on the next frame and the editor
  /// closes at once — there is no blocking overlay. Persistence is owned by
  /// [AuthViewModel], which outlives this route; this State is disposed on
  /// pop, so nothing below may touch `context`, `setState` or `mounted` once
  /// the save has been handed off.
  void _saveProfileChangesOptimistically(EditProfileViewModel vm) {
    final authVM = context.read<AuthViewModel>();
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);

    // Resolved now, while the context is alive. The outcome may arrive after
    // this route is gone, and the toast needs no context to show.
    final feedback = _ProfileSaveFeedback.resolve(context);

    vm.name = _nameController.text;
    final pendingSave = vm.submitProfileSave(
      authVM: authVM,
      imagePath: _selectedImage?.path,
    );

    if (navigator.canPop()) {
      navigator.pop();
    } else {
      router.go('/profile');
    }

    // Observes a future owned by AuthViewModel; it is not an orphaned job.
    pendingSave?.then(feedback.show);
  }

  /// Firebase mode — the legacy blocking save, left functionally unchanged.
  Future<void> _saveProfileChangesLegacy(EditProfileViewModel vm) async {
    // Capture context references before async operations
    final authVM = context.read<AuthViewModel>();
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final saveFailedMessage =
        AppLocalizations.of(context).translate('profileSaveFailed');

    // Show overlay loading
    setState(() {
      _isSaving = true;
    });

    try {
      // Only update name - email and phone are not editable once set
      vm.name = _nameController.text;

      // Debug log suppressed: Saving profile changes
      // Debug log suppressed: Selected image path: ${_selectedImage?.path}

      await vm.saveChanges(
        profileImage:
            _selectedImage != null ? XFile(_selectedImage!.path) : null,
      );

      if (!mounted) return;

      // Clear selected image after successful save
      setState(() {
        _selectedImage = null;
      });

      // Debug log suppressed: Syncing user data from repository
      // Refresh the auth user with latest profile data
      await authVM.syncUserFromRepository();

      // Refresh the auth state to get updated user data
      await authVM.checkEmailVerificationStatus();

      // Debug log suppressed: Profile save completed

      // Hide overlay loading
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }

      // Safe navigation - minimal delay
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          router.go('/profile');
        }
      }
    } catch (e) {
      // Debug log suppressed: Error saving profile: $e

      // Hide overlay loading
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }

      if (mounted) {
        // Localized, and never the raw exception text.
        _showToast(saveFailedMessage, Colors.red);
      }
    }
  }

  /// Show email addition bottom sheet (for phone-only accounts)
  Future<void> _showEmailAdditionDialog(EditProfileViewModel vm) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // we draw our own rounded container
      isDismissible: false,
      enableDrag: false,
      builder: (BuildContext sheetContext) {
        return EmailAdditionDialog(
          onSubmit: (email, password, confirmPassword) async {
            try {
              await vm.addEmailToAccount(email: email, password: password);

              if (sheetContext.mounted) Navigator.of(sheetContext).pop();

              if (mounted) {
                final verified = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return EmailVerificationDialog(
                        email: email, password: password);
                  },
                );

                if (verified == true) {
                  _showToast('Email successfully added to your account!',
                      Colors.green);
                  await context.read<AuthViewModel>().syncUserFromRepository();
                  if (context.canPop())
                    context.pop();
                  else
                    context.go('/profile');
                } else {
                  _showToast('Email verification was cancelled or failed.',
                      Colors.orange);
                }
              }
            } catch (e) {
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (mounted) {
                _showToast('Failed to send verification email: ${e.toString()}',
                    Colors.red);
              }
            }
          },
        );
      },
    );
  }

  /// Starts Supabase's authenticated replacement-email flow.
  ///
  /// A successful request closes the form and hands the user straight to the
  /// pending sheet, which is where the two-mailbox explanation and every
  /// recovery action live.
  Future<void> _showEmailChangeSheet() async {
    final flow = _emailChangeViewModel;
    if (flow == null || !flow.isAvailable) return;
    flow.clearMessages();

    final requested = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmailChangeSheet(viewModel: flow),
    );
    if (requested != true || !mounted) return;

    if (flow.isPending) {
      await _showEmailChangePendingSheet();
      return;
    }
    final notice = flow.noticeKey;
    if (notice != null && mounted) {
      _showToast(
        AppLocalizations.of(context).translate(notice),
        Theme.of(context).colorScheme.primary,
      );
    }
  }

  /// Opens the focused pending sheet.
  ///
  /// "Use a different email" reopens the request sheet: GoTrue's own
  /// `sendEmailChange` regenerates both confirmation tokens and resets the
  /// confirmation status, so a fresh request genuinely replaces the pending
  /// one rather than stacking a second request on top of it.
  Future<void> _showEmailChangePendingSheet() async {
    final flow = _emailChangeViewModel;
    if (flow == null || !flow.isAvailable) return;
    flow.clearMessages();

    final completed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmailChangePendingSheet(
        viewModel: flow,
        onUseDifferentEmail: _showEmailChangeSheet,
      ),
    );
    if (completed == true && mounted) {
      _showToast(
        AppLocalizations.of(context).translate('emailChangeCompleted'),
        Theme.of(context).colorScheme.primary,
      );
    }
  }

  /// Supabase phone verification for the signed-in account.
  ///
  /// Two dialogs in sequence — number, then code — driven by one
  /// [PhoneVerificationViewModel] that lives exactly as long as this flow.
  /// Nothing is written to the profile here: the number is not persisted
  /// anywhere until Supabase confirms it, and the confirmed number reaches the
  /// profile through the database's own auth → profile sync.
  ///
  /// Navigation stays local to this flow: each dialog closes itself, and this
  /// screen stays where it is. General auth routing is untouched.
  Future<void> _verifyPhoneForCurrentAccount(AuthViewModel authVM) async {
    final loc = AppLocalizations.of(context);
    final flow = PhoneVerificationViewModel(authViewModel: authVM);

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PhoneAdditionDialog(
          onSubmit: (phoneNumber) async {
            final sent = await flow.sendCode(phoneNumber);
            if (!sent) {
              final key = flow.errorKey;
              if (key != null) _showToast(loc.translate(key), Colors.red);
              // Throwing keeps the number dialog open so it can be corrected;
              // the dialog closes itself only on success.
              throw StateError('Verification code was not sent.');
            }
            _showToast(loc.translate('otpSent'), Colors.green);
          },
        ),
      );

      if (!mounted || flow.phase != PhoneVerificationPhase.awaitingCode) {
        return;
      }

      final verified = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ChangeNotifierProvider<PhoneVerificationViewModel>.value(
          value: flow,
          child: const PhoneOtpDialog(),
        ),
      );
      if (verified != true || !mounted) return;

      final confirmedPhone = flow.phoneE164 ?? '';
      setState(() {
        _originalPhone = confirmedPhone;
        _phoneController.text = _localUaeDisplay(confirmedPhone);
      });
      _showToast(loc.translate('phoneVerifiedSuccessfully'), Colors.green);
    } finally {
      flow.dispose();
    }
  }

  /// `0501234567` for display. Supabase Auth may store the number without its
  /// `+`, so it is normalized first; anything else is shown as stored.
  String _localUaeDisplay(String? phone) {
    if (phone == null || phone.trim().isEmpty) return '';
    if (!PhoneNumberNormalizer.isUaeMobile(phone)) return phone;
    return '0${PhoneNumberNormalizer.normalizeUaeMobile(phone).substring(4)}';
  }

  /// Show phone addition dialog (for email-only accounts)
  Future<void> _showPhoneAdditionDialog(EditProfileViewModel vm) async {
    final authVM = context.read<AuthViewModel>();
    if (authVM.phoneVerification != null) {
      await _verifyPhoneForCurrentAccount(authVM);
      return;
    }

    // Legacy Firebase backend: its own older flow, unchanged.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PhoneAdditionDialog(
          onSubmit: (phoneNumber) async {
            try {
              // Send OTP for phone verification
              final verificationId = await vm.sendPhoneVerificationOTP(
                phoneNumber: phoneNumber,
              );

              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }

              if (mounted) {
                // Show OTP verification dialog
                await _showOTPVerificationDialog(
                    vm, verificationId, phoneNumber);
              }
            } catch (e) {
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }

              if (mounted) {
                _showToast(
                  'Failed to send OTP: ${e.toString()}',
                  Colors.red,
                );
              }
            }
          },
        );
      },
    );
  }

  /// Show OTP verification dialog
  Future<void> _showOTPVerificationDialog(
    EditProfileViewModel vm,
    String verificationId,
    String phoneNumber,
  ) async {
    final loc = AppLocalizations.of(context);
    final otpController = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.translate('verifyPhoneNumber')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${loc.translate('otpSentTo')} $phoneNumber',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: loc.translate('enterOTP'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(loc.translate('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await vm.verifyPhoneNumber(
                    verificationId: verificationId,
                    otpCode: otpController.text.trim(),
                  );

                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }

                  if (mounted) {
                    _showToast(
                      loc.translate('phoneVerifiedSuccessfully'),
                      Colors.green,
                    );

                    // Refresh user data
                    await context
                        .read<AuthViewModel>()
                        .syncUserFromRepository();

                    // Navigate back to profile
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/profile');
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    _showToast(
                      'Verification failed: ${e.toString()}',
                      Colors.red,
                    );
                  }
                }
              },
              child: Text(loc.translate('verify')),
            ),
          ],
        );
      },
    );
  }

  /// Build email section with Add Email button or text field
  Widget _buildEmailSection(
    BuildContext context,
    EditProfileViewModel vm,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    // If user has no email originally, show Add Email button
    if (_originalEmail.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
          color: colors.primary.withValues(alpha: 0.05),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await _showEmailAdditionDialog(vm);
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.email_outlined,
                      color: colors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.translate('addEmail'),
                          style: texts.titleSmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          loc.translate('tapToAddEmailAccount'),
                          style: texts.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: colors.primary,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final emailChange = _emailChangeViewModel;
    final confirmedEmail = emailChange?.confirmedEmail.isNotEmpty == true
        ? emailChange!.confirmedEmail
        : _originalEmail;
    final canChangeEmail =
        SupabaseConfig.useSupabaseAuth && emailChange?.isAvailable == true;
    final pending = emailChange?.isPending == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
          decoration: _fieldCardDecoration(colors),
          child: Row(
            children: [
              _FieldLeadingIcon(
                icon: Icons.email_outlined,
                colors: colors,
              ),
              const SizedBox(width: 12),
              // The confirmed address stays the primary identity on this row
              // for the whole pending window, so nothing here can imply the
              // new address is already in force.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.translate('currentEmail'),
                      style: texts.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 1),
                    // A long address must shrink to one tidy line rather than
                    // wrapping and pushing the row's action out of reach.
                    ForceDirectionality(
                      direction: TextDirection.ltr,
                      child: Text(
                        confirmedEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: texts.bodyMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (canChangeEmail && !pending)
                TextButton(
                  onPressed: emailChange?.isBusy == true
                      ? null
                      : _showEmailChangeSheet,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(loc.translate('change')),
                )
              else if (!canChangeEmail)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Icon(
                    Icons.lock_outline,
                    color: colors.onSurfaceVariant,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
        if (pending) ...[
          const SizedBox(height: 8),
          _buildPendingEmailIndicator(emailChange!, colors, texts, loc),
        ],
      ],
    );
  }

  /// One compact line, not a status panel.
  ///
  /// Everything explanatory and every recovery action lives in the pending
  /// sheet behind "View", so Edit Profile stays a settings screen.
  Widget _buildPendingEmailIndicator(
    EmailChangeViewModel flow,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    return Material(
      color: colors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showEmailChangePendingSheet,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
          child: Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 16,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.translate('emailChangePendingTitle'),
                      style: texts.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        flow.pendingEmail ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: texts.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                loc.translate('view'),
                style: texts.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build phone section with Add Phone button or text field
  Widget _buildPhoneSection(
    BuildContext context,
    EditProfileViewModel vm,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    // No phone yet: one actionable row that opens the existing Add Phone flow.
    if (_originalPhone.isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await _showPhoneAdditionDialog(vm);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
            decoration: _fieldCardDecoration(colors),
            child: Row(
              children: [
                _FieldLeadingIcon(
                  icon: Icons.phone_outlined,
                  colors: colors,
                  emphasized: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loc.translate('addPhoneNumber'),
                        style: texts.bodyMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        loc.translate('tapToAddPhoneNumber'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: texts.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Confirmed number. Read-only here by design: the number is owned by
    // Supabase Auth's own verification flow, not by this form's Save.
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
      decoration: _fieldCardDecoration(colors),
      child: Row(
        children: [
          _FieldLeadingIcon(icon: Icons.phone_outlined, colors: colors),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  loc.translate('phoneNumber'),
                  style: texts.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                ForceDirectionality(
                  direction: TextDirection.ltr,
                  child: Text(
                    _originalPhone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texts.bodyMedium?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.lock_outline,
            color: colors.onSurfaceVariant,
            size: 16,
          ),
        ],
      ),
    );
  }

  /// The account's password row.
  ///
  /// Deliberately the same actionable card as the "Add phone number" row, with
  /// the same decoration, leading icon and chevron, so the new section reads as
  /// part of the existing form rather than as something bolted on. The password
  /// itself is never shown, and Save does not own it: changing it is its own
  /// confirmed flow, exactly like email and phone.
  Widget _buildPasswordSection(
    BuildContext context,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openChangePasswordSheet,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
          decoration: _fieldCardDecoration(colors),
          child: Row(
            children: [
              _FieldLeadingIcon(
                icon: Icons.lock_outline,
                colors: colors,
                emphasized: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.translate('changePassword'),
                      style: texts.bodyMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      loc.translate('changePasswordRowHint'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: texts.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.primary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openChangePasswordSheet() async {
    final repository = RepositoryProvider.instance.authRepository;
    final viewModel = ChangePasswordViewModel(
      gateway: passwordCapabilityOf(repository),
      authRepository: repository,
    );
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangePasswordSheet(viewModel: viewModel),
    );
    viewModel.dispose();
    if (changed != true || !mounted) return;
    final loc = AppLocalizations.of(context);
    Fluttertoast.showToast(
      msg: loc.translate('passwordUpdated'),
      backgroundColor: Colors.green,
      textColor: Colors.white,
    );
  }

  /// One card treatment shared by the email and phone rows, so neither reads as
  /// more important than the other.
  BoxDecoration _fieldCardDecoration(ColorScheme colors) => BoxDecoration(
        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
        color: colors.surface,
      );

  @override
  void dispose() {
    _uploadCompletionSubscription?.cancel();
    _emailChangeViewModel?.removeListener(_onEmailChangeStateChanged);
    _emailChangeViewModel?.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}

/// The ARB key that describes [result] to the user.
///
/// A partial success is never reported as a full success or a full failure:
/// when one of two attempted parts persisted, the message says which one. When
/// only one part was attempted, its failure is simply a failure.
String? profileSaveFeedbackKey(ProfileSaveResult result) {
  if (!result.nameAttempted && !result.imageAttempted) return null;

  switch (result.outcome) {
    case ProfileSaveOutcome.success:
      return 'profileUpdated';
    case ProfileSaveOutcome.imageFailed:
      return result.isPartialSuccess
          ? 'profileSaveNameSavedImageFailed'
          : 'profileSaveFailed';
    case ProfileSaveOutcome.nameFailed:
      return result.isPartialSuccess
          ? 'profileSaveImageSavedNameFailed'
          : 'profileSaveFailed';
    case ProfileSaveOutcome.bothFailed:
      return 'profileSaveFailed';
  }
}

/// Save feedback resolved while the editor's context is still alive.
///
/// The editor closes as soon as a save is handed off, so the outcome usually
/// arrives after this route has been disposed. Every string and color is
/// resolved up front, and the toast itself needs no BuildContext, so showing
/// it later touches nothing that belonged to the disposed route.
class _ProfileSaveFeedback {
  const _ProfileSaveFeedback({
    required this.messages,
    required this.successBackground,
    required this.successForeground,
    required this.failureBackground,
    required this.failureForeground,
  });

  factory _ProfileSaveFeedback.resolve(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return _ProfileSaveFeedback(
      messages: {
        for (final key in const [
          'profileUpdated',
          'profileSaveNameSavedImageFailed',
          'profileSaveImageSavedNameFailed',
          'profileSaveFailed',
        ])
          key: loc.translate(key),
      },
      successBackground: colors.primary,
      successForeground: colors.onPrimary,
      failureBackground: colors.error,
      failureForeground: colors.onError,
    );
  }

  final Map<String, String> messages;
  final Color successBackground;
  final Color successForeground;
  final Color failureBackground;
  final Color failureForeground;

  void show(ProfileSaveResult result) {
    final key = profileSaveFeedbackKey(result);
    if (key == null) return;

    final succeeded = result.outcome == ProfileSaveOutcome.success;
    Fluttertoast.showToast(
      msg: messages[key] ?? '',
      toastLength: succeeded ? Toast.LENGTH_SHORT : Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: succeeded ? successBackground : failureBackground,
      textColor: succeeded ? successForeground : failureForeground,
    );
  }
}

/// A section heading for the account form.
///
/// Small, quiet and consistent, so the headings group the fields instead of
/// competing with the values inside them.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// The small square icon that opens each account row.
///
/// Kept modest on purpose: the value beside it is the content, the icon is
/// only a marker. [emphasized] tints it for a row that is an invitation to act
/// rather than a statement of fact.
class _FieldLeadingIcon extends StatelessWidget {
  const _FieldLeadingIcon({
    required this.icon,
    required this.colors,
    this.emphasized = false,
  });

  final IconData icon;
  final ColorScheme colors;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: emphasized
            ? colors.primary.withValues(alpha: 0.10)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: emphasized ? colors.primary : colors.onSurfaceVariant,
        size: 18,
      ),
    );
  }
}
