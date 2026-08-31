// lib/src/views/feedback/feedback_view.dart
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:flutter/material.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/feedback_viewmodel.dart';
import 'package:broker_wallet/src/Views/Widgets/feedback_success_bottom_sheet.dart';
import '../../../widgets/rating_bar.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';

class FeedbackView extends StatelessWidget {
  const FeedbackView({super.key});

  void _showSuccessBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FeedbackSuccessBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final authVM = Provider.of<AuthViewModel>(context);
    final resolvedName = authVM.displayName.trim();
    final userName = resolvedName.isNotEmpty
        ? resolvedName
        : loc.translate('favoritesGuestUser');

    return ChangeNotifierProvider(
      create: (_) => FeedbackViewModel(),
      child: Consumer<FeedbackViewModel>(
        builder: (context, vm, _) => Scaffold(
          appBar: AppBar(
            leading: const BackArrowButton(),
            title:
                Text(loc.translate('feedBackScreen'), style: texts.titleLarge),
            centerTitle: true,
            elevation: 0,
            backgroundColor: colors.surface,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 25),

                  // Avatar & name
                  Center(
                    child: Column(
                      children: [
                        ClipOval(
                          child: SizedBox(
                            width: 70,
                            height: 70,
                            child: authVM.currentUser?.profileImageUrl !=
                                        null &&
                                    authVM.currentUser!.profileImageUrl!
                                        .isNotEmpty
                                ? OfflineMediaService.instance
                                    .buildOfflineAwareImage(
                                    imageUrl:
                                        authVM.currentUser!.profileImageUrl!,
                                    fit: BoxFit.cover,
                                    width: 48,
                                    height: 48,
                                  )
                                : Image.asset(
                                    'assets/images/avatar-placeholder.jpg',
                                    fit: BoxFit.cover,
                                    width: 48,
                                    height: 48,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(userName, style: texts.titleLarge),
                        const SizedBox(height: 4),
                        Text(loc.translate('feedbackSubtitle'),
                            style: texts.bodyMedium),
                      ],
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Rating stars
                  RatingBar(rating: vm.rating, onRatingChanged: vm.setRating),

                  const SizedBox(height: 50),

                  // Comment label
                  Text(loc.translate('comment'), style: texts.titleMedium),
                  const SizedBox(height: 8),

                  // Comment input
                  Container(
                    height: 120,
                    child: TextField(
                      controller: vm.commentController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: loc.translate('writeFeedbackHint'),
                        filled: true,
                        fillColor: colors.surface,
                        contentPadding: const EdgeInsets.all(16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 140), // Reduced from 120

                  // Error message if any
                  if (vm.errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: colors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: colors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: colors.error, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              vm.errorMessage!,
                              style: texts.bodySmall
                                  ?.copyWith(color: colors.error),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Submit button
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: vm.canSubmit
                            ? colors.primary
                            : colors.primary.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onPressed: vm.isSubmitting
                          ? null
                          : () async {
                              if (authVM.currentUser != null) {
                                await vm.submitFeedback(authVM.currentUser!);
                                if (vm.isSubmitted && context.mounted) {
                                  _showSuccessBottomSheet(context);
                                }
                              }
                            },
                      child: vm.isSubmitting
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colors.onPrimary,
                                ),
                              ),
                            )
                          : Text(
                              loc.translate('submit'),
                              style: texts.labelLarge?.copyWith(
                                color: colors.onPrimary,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Add extra padding for keyboard space
                  SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
