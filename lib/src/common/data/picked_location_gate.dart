import 'package:broker_wallet/src/common/data/uae_coordinate_sanity.dart';

/// Where a position the person picked on the map is accepted into a form.
///
/// Every form that has a pickup location (Offer, Owner, Office, Watchman) gets
/// its pin through one widget, and that widget hands the picked position to
/// [admit] before the form sees it. So all four forms share one rule: a position
/// that could not be in the UAE ([UaeCoordinateSanity]) is turned away, and the
/// form keeps the pickup location it already had.
///
/// This is for a NEW choice only. It is not applied when a record is saved, so a
/// record whose stored position is out of range for the UAE can still be edited
/// and saved like any other until the person chooses another position.
///
/// Plain Dart: the form and the message are passed in.
abstract final class PickedLocationGate {
  /// Gives the form the position through [accept] when it could be in the UAE,
  /// and returns true. Otherwise [accept] is never called, so the form is left
  /// exactly as it was; [reject] is called once instead, and this returns false.
  static Future<bool> admit({
    required double latitude,
    required double longitude,
    required Future<void> Function() accept,
    required void Function() reject,
  }) async {
    if (!UaeCoordinateSanity.couldBeInUae(latitude, longitude)) {
      reject();
      return false;
    }
    await accept();
    return true;
  }
}
