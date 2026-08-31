import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'phone_number_normalizer.dart';
import '../../services/core_entity_payload_builder.dart';

/// Converts technical persistence errors into messages safe for end users.
class CoreEntityErrorMessage {
  CoreEntityErrorMessage._();

  static String save(Object error, String entity, {required bool isUpdate}) {
    if (error is PhoneValidationException) {
      return 'Please enter a valid phone number.';
    }
    if (error is CoreEntityValidationException) {
      return error.message;
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
