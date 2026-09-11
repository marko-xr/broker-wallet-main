import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/email_addition_dialog.dart';
import 'package:broker_wallet/src/Views/Widgets/email_verification_dialog.dart';
import 'package:broker_wallet/src/Views/Widgets/phone_addition_dialog.dart';
import 'package:broker_wallet/src/Views/Widgets/current_user_avatar.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/clean_media_service.dart';
import 'package:broker_wallet/src/services/fast_profile_upload_service.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/Views/Widgets/profile_text_field.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/edit_profile_viewmodel.dart';
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
  StreamSubscription<ProfileUploadCompletedEvent>?
      _uploadCompletionSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _initializeUserData();
      _setupUploadCompletionListener();
      _isInitialized = true;
    }
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
      String phoneNumber = user.phoneNumber ?? '';
      _originalPhone = phoneNumber; // Store original phone

      try {
        // User model already has the correct data from repository
        if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
          phoneNumber = user.phoneNumber!;

          // Format phone number for display
          if (phoneNumber.startsWith('+971')) {
            // Remove country code
            phoneNumber = phoneNumber.substring(4);
            // Add leading 0 if not present for UAE numbers
            if (phoneNumber.length == 9 && !phoneNumber.startsWith('0')) {
              phoneNumber = '0$phoneNumber';
            }
          }
        }
      } catch (e) {
        // Debug log suppressed: Error processing phone number: $e
      }

      _phoneController.text = phoneNumber;

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
                        padding: const EdgeInsets.all(26),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Profile Card with Image Picker
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: colors.surface,
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
                                            color: colors.primary
                                                .withValues(alpha: 0.3),
                                            width: 3,
                                          ),
                                        ),
                                        child: ClipOval(
                                          child: SizedBox(
                                            width: 100,
                                            height: 100,
                                            // The unsaved pick previews here
                                            // directly. Everything else — the
                                            // confirmed image, or a saved image
                                            // still uploading — comes from the
                                            // same current-user source every
                                            // other screen uses.
                                            child: _selectedImage != null
                                                ? Image.file(
                                                    _selectedImage!,
                                                    fit: BoxFit.cover,
                                                    width: 100,
                                                    height: 100,
                                                  )
                                                : const CurrentUserAvatar(
                                                    size: 100,
                                                  ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 4,
                                        right: 4,
                                        child: GestureDetector(
                                          onTap: _pickImage,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  colors.primary,
                                                  colors.primary
                                                      .withValues(alpha: 0.8),
                                                ],
                                              ),
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: colors.primary
                                                      .withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            padding: const EdgeInsets.all(8),
                                            child: const Icon(
                                              Icons.camera_alt_rounded,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                      _nameController.text.isNotEmpty
                                          ? _nameController.text
                                          : 'User Name',
                                      style: texts.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      )),
                                  const SizedBox(height: 4),
                                  Text(
                                      _emailController.text.isNotEmpty
                                          ? _emailController.text
                                          : 'user@example.com',
                                      style: texts.bodyMedium?.copyWith(
                                        color: colors.onSurface
                                            .withValues(alpha: 0.7),
                                      )),
                                  const SizedBox(height: 8),

                                  // Image selection hint
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color:
                                          colors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          size: 16,
                                          color: colors.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          loc.translate('tapToChangePhoto'),
                                          style: texts.bodySmall?.copyWith(
                                            color: colors.primary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Form Fields
                            Text(loc.translate('name'),
                                style: texts.titleMedium),
                            const SizedBox(height: 8),
                            ProfileTextField(
                              controller: _nameController,
                              hintText: loc.translate('enterName'),
                              iconAsset: 'assets/icons/profile.svg',
                              isSvg: true,
                            ),
                            const SizedBox(height: 16),
                            Text(loc.translate('email'),
                                style: texts.titleMedium),
                            const SizedBox(height: 8),
                            _buildEmailSection(context, vm, colors, texts, loc),
                            const SizedBox(height: 16),
                            Text(loc.translate('phoneNumber'),
                                style: texts.titleMedium),
                            const SizedBox(height: 8),
                            _buildPhoneSection(context, vm, colors, texts, loc),
                            const SizedBox(height: 80),

                            // Save Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSaving
                                    ? null
                                    : () async {
                                        // Only save name and image changes
                                        await _saveProfileChanges(vm);
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colors.primary,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  elevation: 2,
                                ),
                                child: Text(
                                  loc.translate('saveChanges'),
                                  style: texts.labelLarge
                                      ?.copyWith(color: Colors.white),
                                ),
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

  /// Show phone addition dialog (for email-only accounts)
  Future<void> _showPhoneAdditionDialog(EditProfileViewModel vm) async {
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

    // If user has email, show read-only display
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
        color: colors.surface,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.email_outlined,
              color: colors.onSurfaceVariant,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.translate('email'),
                  style: texts.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _originalEmail,
                  style: texts.bodyLarge?.copyWith(
                    color: colors.onSurface,
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

  /// Build phone section with Add Phone button or text field
  Widget _buildPhoneSection(
    BuildContext context,
    EditProfileViewModel vm,
    ColorScheme colors,
    TextTheme texts,
    AppLocalizations loc,
  ) {
    // If user has no phone originally, show Add Phone button
    if (_originalPhone.isEmpty) {
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
              await _showPhoneAdditionDialog(vm);
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
                      Icons.phone_outlined,
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
                          loc.translate('addPhoneNumber'),
                          style: texts.titleSmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          loc.translate('tapToAddPhoneNumber'),
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

    // If user has phone, show read-only display
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
        color: colors.surface,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.phone_outlined,
              color: colors.onSurfaceVariant,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.translate('phoneNumber'),
                  style: texts.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _originalPhone,
                  style: texts.bodyLarge?.copyWith(
                    color: colors.onSurface,
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

  @override
  void dispose() {
    _uploadCompletionSubscription?.cancel();
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
