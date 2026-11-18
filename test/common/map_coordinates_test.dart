import 'package:broker_wallet/src/common/utils/map_coordinates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final invalid = <String, (double?, double?)>{
    'both null': (null, null),
    'latitude null': (null, 55.3),
    'longitude null': (25.2, null),
    'latitude NaN': (double.nan, 55.3),
    'longitude NaN': (25.2, double.nan),
    'latitude positive infinity': (double.infinity, 55.3),
    'latitude negative infinity': (double.negativeInfinity, 55.3),
    'longitude positive infinity': (25.2, double.infinity),
    'longitude negative infinity': (25.2, double.negativeInfinity),
    'latitude above range': (90.000001, 55.3),
    'latitude below range': (-90.000001, 55.3),
    'longitude above range': (25.2, 180.000001),
    'longitude below range': (25.2, -180.000001),
    'Null Island': (0, 0),
    'signed zero': (-0.0, 0),
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key}', () {
      expect(MapCoordinates.isValid(entry.value.$1, entry.value.$2), isFalse);
    });
  }

  final valid = <String, (double, double)>{
    'Dubai': (25.2048, 55.2708),
    'south west boundaries': (-90, -180),
    'north east boundaries': (90, 180),
    'north west boundaries': (90, -180),
    'south east boundaries': (-90, 180),
    'equator': (0, 55.3),
    'prime meridian': (25.2, 0),
    'outside UAE': (-33.8688, 151.2093),
  };
  for (final entry in valid.entries) {
    test('accepts ${entry.key}', () {
      expect(MapCoordinates.isValid(entry.value.$1, entry.value.$2), isTrue);
    });
  }
}
