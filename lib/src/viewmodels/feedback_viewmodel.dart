// lib/src/viewmodels/feedback_viewmodel.dart
import 'package:flutter/material.dart';
import '../services/feedback_service.dart';
import '../data/models/user_model.dart';

class FeedbackViewModel extends ChangeNotifier {
  final FeedbackService _feedbackService = FeedbackService();

  int rating = 0;
  final TextEditingController commentController = TextEditingController();

  // Loading and error states
  bool _isSubmitting = false;
  String? _errorKey;
  bool _isSubmitted = false;

  // Getters
  bool get isSubmitting => _isSubmitting;
  String? get errorKey => _errorKey;
  bool get isSubmitted => _isSubmitted;
  bool get canSubmit => rating > 0 && commentController.text.trim().isNotEmpty;

  void setRating(int newRating) {
    rating = newRating;
    _clearError();
    notifyListeners();
  }

  /// Submit feedback to Firebase for admin review
  Future<void> submitFeedback(UserModel user) async {
    if (!canSubmit) {
      _setError('feedbackRatingCommentRequired');
      return;
    }

    try {
      _isSubmitting = true;
      _clearError();
      notifyListeners();

      await _feedbackService.submitFeedback(
        rating: rating,
        comment: commentController.text.trim(),
        user: user,
      );

      _isSubmitted = true;
    } catch (e) {
      _setError('feedbackSubmitFailed');
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void _setError(String key) {
    _errorKey = key;
    notifyListeners();
  }

  void _clearError() {
    if (_errorKey != null) {
      _errorKey = null;
      notifyListeners();
    }
  }

  /// Reset the form
  void reset() {
    rating = 0;
    commentController.clear();
    _isSubmitting = false;
    _errorKey = null;
    _isSubmitted = false;
    notifyListeners();
  }

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }
}
