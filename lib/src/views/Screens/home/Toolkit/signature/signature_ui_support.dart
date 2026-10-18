import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';

/// The Document Signature tool's accent colours (the same reds the screens have
/// always used).
class SignatureColors {
  const SignatureColors._();

  static const Color redLight = Color(0xFFF44336);
  static const Color redDark = Color(0xFFC62828);
  static const Color redDarker = Color(0xFFB71C1C);
}

/// The pen colours offered for a drawn or typed item.
final List<Color> kSignaturePenColors = <Color>[
  Colors.black,
  Colors.blue.shade900,
  Colors.blue,
  Colors.red,
  Colors.green,
];

/// A short message at the bottom of the screen. A phone without the toast
/// plugin (or a test) just shows nothing: a message is never worth a crash.
Future<void> showSignatureToast(String message, Color background) async {
  try {
    await Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: background,
      textColor: Colors.white,
    );
  } catch (_) {}
}

/// The message key of every failure. Every [SignatureFailure] has an entry; a
/// test pins that and that both languages have each message.
const Map<SignatureFailure, String> kSignatureFailureKeys =
    <SignatureFailure, String>{
  SignatureFailure.signedOut: 'sigErrSignedOut',
  SignatureFailure.busy: 'sigErrBusy',
  SignatureFailure.cancelled: 'sigErrCancelled',
  SignatureFailure.accountChanged: 'sigErrAccountChanged',
  SignatureFailure.missingSource: 'sigErrMissing',
  SignatureFailure.emptySource: 'sigErrEmpty',
  SignatureFailure.corruptSource: 'sigErrCorrupt',
  SignatureFailure.encryptedSource: 'sigErrEncrypted',
  SignatureFailure.signedSource: 'sigErrSigned',
  SignatureFailure.tooLargeSource: 'sigErrTooLarge',
  SignatureFailure.tooManyPages: 'sigErrTooManyPages',
  SignatureFailure.geometryUnsupported: 'sigErrGeometry',
  SignatureFailure.sourceChanged: 'sigErrChanged',
  SignatureFailure.noPlacements: 'sigNothingToSave',
  SignatureFailure.invalidPlacement: 'sigErrPlacement',
  SignatureFailure.stampFailed: 'sigErrStamp',
  SignatureFailure.tooManyItems: 'sigErrTooManyItems',
  SignatureFailure.outputInvalid: 'sigErrOutputInvalid',
  SignatureFailure.writeFailed: 'sigErrWrite',
  SignatureFailure.storageFull: 'sigErrStorageFull',
  SignatureFailure.notFound: 'sigErrNotFound',
  SignatureFailure.invalidName: 'sigErrInvalidName',
  SignatureFailure.nameInUse: 'sigErrNameInUse',
  SignatureFailure.fileMissing: 'documentFileNotFound',
  SignatureFailure.quotaBlocked: 'sigErrBusy',
  SignatureFailure.permissionDenied: 'sigErrPermission',
  SignatureFailure.exportFailed: 'sigErrExport',
  SignatureFailure.unexpected: 'sigErrUnexpected',
};

/// The localized text for a failure.
String signatureFailureMessage(
    AppLocalizations localization, SignatureFailure failure) {
  return localization
      .translate(kSignatureFailureKeys[failure] ?? 'sigErrWrite');
}

/// Failures a second attempt can fix (as opposed to a file that must change).
const Set<SignatureFailure> kSignatureRetryable = <SignatureFailure>{
  SignatureFailure.writeFailed,
  SignatureFailure.outputInvalid,
  SignatureFailure.storageFull,
};
