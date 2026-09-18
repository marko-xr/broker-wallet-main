import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'phone_number_normalizer.dart';
import '../../services/core_entity_payload_builder.dart';

/// Converts technical persistence errors into messages safe for end users.
class CoreEntityErrorMessage {
  CoreEntityErrorMessage._();

  static String save(
    Object error,
    String entity, {
    required bool isUpdate,
    String Function(String key)? translate,
  }) {
    if (error is PhoneValidationException) {
      return 'Please enter a valid phone number.';
    }
    if (error is CoreEntityValidationException) {
      return error.message;
    }
    // Matches only the specific partial-upload StateError thrown by
    // OfferService._saveOfferWithMediaSupabase (offer_service.dart), never a
    // raw file name, path, or the failure count from that message: the $entity
    // itself is already saved by the time that error is thrown, so the
    // generic save-failure message below would falsely claim total failure.
    // Only this branch is localized; every other message in this class is
    // unchanged, pre-existing English-only technical debt.
    if (error is StateError &&
        error.message.contains('photo(s) failed to upload')) {
      if (translate != null) {
        return translate('offerSavedMediaPartialFailure');
      }
      return 'The $entity was saved, but one or more photos could not be '
          'uploaded. Edit the $entity to retry.';
    }
    if (error is StateError && error.message.contains('session')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (error is AuthException ||
        (error is PostgrestException && error.code == '42501')) {
      return 'You do not have permission to save this $entity.';
    }
    if (error is TimeoutException ||
        error.runtimeType.toString().contains('SocketException') ||
        error.runtimeType.toString().contains('ClientException')) {
      return 'Check your internet connection and try again.';
    }
    if (error is PostgrestException) {
      return 'The $entity data could not be validated. Please check the form.';
    }
    return 'Unable to ${isUpdate ? 'update' : 'save'} the $entity. Please try again.';
  }
}
