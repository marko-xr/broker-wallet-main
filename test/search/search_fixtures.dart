// Shared fixtures for the Search tests: the real English and Arabic strings, read
// straight from the ARB files, and builders for the six record types with only
// the fields a test cares about filled in.

import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/views/Screens/home/search/search_engine.dart';

final Map<String, dynamic> enArb = json.decode(
  File('lib/src/common/localization/app_en.arb').readAsStringSync(),
) as Map<String, dynamic>;

final Map<String, dynamic> arArb = json.decode(
  File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
) as Map<String, dynamic>;

/// The text of [key] in [language], from the ARB files on disk.
String? arbLookup(String language, String key) {
  final table = language == 'en'
      ? enArb
      : language == 'ar'
          ? arArb
          : const <String, dynamic>{};
  return table[key] as String?;
}

/// An engine that reads names from the real ARB files.
SearchEngine newEngine() => SearchEngine(lookup: arbLookup);

final DateTime _then = DateTime(2026, 9, 1);

RequestModel request({
  String? id,
  String type = 'rent',
  String city = 'Dubai',
  List<String> areas = const <String>[],
  String location = '',
  String phone = '',
  String code = '+971',
  String minPrice = '',
  String maxPrice = '',
  String squareFootage = '',
  String notes = '',
  String? propertyType,
  String specific = '',
}) =>
    RequestModel(
      id: id,
      userId: 'u1',
      requestType: type,
      selectedCity: city,
      selectedAreas: areas,
      location: location,
      phoneNumber: phone,
      countryCode: code,
      minPrice: minPrice,
      maxPrice: maxPrice,
      squareFootage: squareFootage,
      notes: notes,
      propertyType: propertyType,
      specificPropertyType: specific,
      rooms: 0,
      bathrooms: 0,
      createdAt: _then,
      updatedAt: _then,
    );

OfferModel offer({
  String? id,
  String type = 'sell',
  String city = 'Dubai',
  List<String> areas = const <String>[],
  String location = '',
  String phone = '',
  String code = '+971',
  String minPrice = '',
  String maxPrice = '',
  String squareFootage = '',
  String notes = '',
  String? propertyType,
  String specific = '',
  String pickUpAddress = '',
}) =>
    OfferModel(
      id: id,
      userId: 'u1',
      offerType: type,
      selectedCity: city,
      selectedAreas: areas,
      location: location,
      phoneNumber: phone,
      countryCode: code,
      minPrice: minPrice,
      maxPrice: maxPrice,
      squareFootage: squareFootage,
      notes: notes,
      propertyType: propertyType,
      specificPropertyType: specific,
      rooms: 0,
      bathrooms: 0,
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: pickUpAddress,
      uploadedFileName: '',
      createdAt: _then,
      updatedAt: _then,
      mediaUrls: const <String>[],
    );

OwnerModel owner({
  String? id,
  String name = '',
  String phone = '',
  String code = '+971',
  String typeOfProperties = '',
  String propertyLocation = '',
  String notes = '',
}) =>
    OwnerModel(
      id: id,
      userId: 'u1',
      name: name,
      phoneNumber: phone,
      countryCode: code,
      typeOfProperties: typeOfProperties,
      propertyLocation: propertyLocation,
      notes: notes,
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      mediaUrls: const <String>[],
      createdAt: _then,
      updatedAt: _then,
    );

OfficeModel office({
  String? id,
  String name = '',
  String location = '',
  String phone = '',
  String code = '+971',
  String notes = '',
}) =>
    OfficeModel(
      id: id,
      officeName: name,
      managerName: '',
      countryCode: code,
      phoneNumber: phone,
      officeLocation: location,
      notes: notes,
      pickUpLocation: '',
      pickUpAddress: '',
    );

BrokerModel broker({
  String? id,
  String name = '',
  String phone = '',
  String code = '+971',
  String notes = '',
}) =>
    BrokerModel(
      id: id,
      name: name,
      countryCode: code,
      phoneNumber: phone,
      notes: notes,
    );

WatchmenModel watchman({
  String? id,
  String name = '',
  String building = '',
  String buildingLocation = '',
  String phone = '',
  String code = '+971',
  String notes = '',
}) =>
    WatchmenModel(
      id: id,
      name: name,
      countryCode: code,
      phoneNumber: phone,
      buildingName: building,
      notes: notes,
      buildingLocation: buildingLocation,
      pickUpLocation: '',
      pickUpAddress: '',
    );
