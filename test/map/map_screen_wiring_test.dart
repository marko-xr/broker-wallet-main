// The map screen reads the user's places from Supabase, narrows them with one
// compact filter row over what is already loaded, says everything in the app's
// language, never shows a technical message, asks for location only when
// Nearby is turned on, and uses the same phone and media handling as the rest
// of the app. Source and string guards: they read the files.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

Map<String, dynamic> _arb(String code) => json.decode(
      File('lib/src/common/localization/app_$code.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

/// How many times [needle] occurs in [text].
int _count(String text, String needle) =>
    needle.isEmpty ? 0 : text.split(needle).length - 1;

void main() {
  const view = 'lib/src/views/Screens/home/map/map_view.dart';
  const bar = 'lib/src/views/Screens/home/map/map_filter_bar.dart';
  const viewModel = 'lib/src/views/Screens/home/map/map_viewmodel.dart';
  const cache = 'lib/src/services/map_data_cache_service.dart';
  const source = 'lib/src/services/map_location_source.dart';
  const data = 'lib/src/services/map_location_data.dart';
  const loader = 'lib/src/services/map_places_loader.dart';
  const filter = 'lib/src/services/map_filter.dart';
  const controller = 'lib/src/services/map_filter_controller.dart';
  const locator = 'lib/src/services/map_nearby_locator.dart';
  const policy = 'lib/src/services/map_camera_policy.dart';

  // Every file the active map path is made of.
  const mapFiles = [
    view,
    bar,
    viewModel,
    cache,
    source,
    data,
    loader,
    filter,
    controller,
    locator,
    'lib/src/services/device_location_platform.dart',
    'lib/src/services/map_camera.dart',
    policy,
    'lib/src/services/map_city_geography.dart',
    'lib/src/services/geo_distance.dart',
    'lib/src/services/map_price.dart',
    'lib/src/common/data/uae_city_matcher.dart',
    'lib/src/common/data/uae_coordinate_sanity.dart',
    'lib/src/common/utils/coalesced_runner.dart',
    'lib/src/constants/location_filter.dart',
    'lib/src/views/Screens/home/map/map_filter_status_line.dart',
    'lib/src/services/map_result_count.dart',
    'lib/src/services/map_layer_controls.dart',
  ];

  group('where the places come from', () {
    test('the view model reads through the loader, not Firestore', () {
      final text = _read(viewModel);
      for (final gone in [
        'cloud_firestore',
        'FirebaseFirestore',
        ".collection('users')",
        'snapshots()',
      ]) {
        expect(text.contains(gone), isFalse, reason: gone);
      }
      final squashed = _squash(text);
      expect(squashed.contains('_loader = MapPlacesLoader( '), isTrue);
      expect(
        squashed.contains('source: source ?? DefaultMapLocationSource(),'),
        isTrue,
      );
      expect(
        squashed.contains('onPlaces: _onPlaces, onFailed: _failLoad,'),
        isTrue,
      );
      expect(text.contains('unawaited(_loader.start());'), isTrue);
      expect(text.contains('_loader.dispose();'), isTrue);
    });

    test('Supabase is read through the same four list reads Search uses', () {
      final text = _squash(_read(source));
      for (final read in [
        'service.getOffers().first,',
        'service.getOwners().first,',
        'service.getOffices().first,',
        'service.getWatchmen().first,',
      ]) {
        expect(text.contains(read), isTrue, reason: read);
      }
      // One path: there is no second backend to fall back to.
      expect(text.contains('_loadFirestore'), isFalse);
      expect(text.contains('useSupabaseAuth'), isFalse);
      // A change anywhere in the app refreshes the map while it is open.
      expect(
        text.contains(
          'Stream<void> get changes => CoreEntityMutationNotifier.changes;',
        ),
        isTrue,
      );
    });

    test('nothing the map is made of names Firebase or Firestore', () {
      for (final path in mapFiles) {
        final text = _read(path);
        expect(text.contains('FirebaseFirestore'), isFalse, reason: path);
        expect(text.contains('cloud_firestore'), isFalse, reason: path);
        expect(
          RegExp('firebase', caseSensitive: false).hasMatch(text),
          isFalse,
          reason: '$path mentions Firebase',
        );
        expect(
          RegExp('firestore', caseSensitive: false).hasMatch(text),
          isFalse,
          reason: '$path mentions Firestore',
        );
      }
    });

    test(
      'the cache forgets on every Supabase change, and has nothing to preload',
      () {
        final text = _squash(_read(cache));
        expect(
          text.contains('CoreEntityMutationNotifier.changes.listen('),
          isTrue,
          reason: 'the Supabase save paths do not invalidate it themselves',
        );
        expect(text.contains('(_) => invalidateCache(),'), isTrue);
        expect(
          text.contains('if (generation != _generation) return;'),
          isTrue,
          reason: 'a read that raced a change is not kept',
        );
        expect(text.contains('Future<void> preloadMapData() async {}'), isTrue);
        expect(text.contains('implements MapPlacesCache'), isTrue);
      },
    );

    test('the pure files stay plain Dart', () {
      for (final path in [
        data,
        loader,
        filter,
        controller,
        locator,
        'lib/src/services/map_camera.dart',
        policy,
        'lib/src/services/map_city_geography.dart',
        'lib/src/services/geo_distance.dart',
        'lib/src/services/map_price.dart',
        'lib/src/common/data/uae_city_matcher.dart',
        'lib/src/common/data/uae_coordinate_sanity.dart',
        'lib/src/common/utils/coalesced_runner.dart',
        'lib/src/constants/location_filter.dart',
        'lib/src/services/map_result_count.dart',
      ]) {
        final text = _read(path);
        expect(text.contains('package:flutter'), isFalse, reason: path);
        expect(text.contains('google_maps_flutter'), isFalse, reason: path);
        expect(text.contains('geolocator'), isFalse, reason: path);
        expect(text.contains('permission_handler'), isFalse, reason: path);
      }
      // The plugins are touched in one thin file.
      final adapter = _read('lib/src/services/device_location_platform.dart');
      expect(adapter.contains("import 'package:geolocator/geolocator.dart';"),
          isTrue);
      expect(
        adapter.contains(
          "import 'package:permission_handler/permission_handler.dart';",
        ),
        isTrue,
      );
      expect(adapter.contains('package:flutter'), isFalse);
      final colors = _read('lib/src/constants/location_colors.dart');
      expect(
        colors.contains(
          "export 'package:broker_wallet/src/constants/location_filter.dart';",
        ),
        isTrue,
        reason: 'existing imports of LocationFilter keep working',
      );
      expect(colors.contains('enum LocationFilter'), isFalse);
    });
  });

  group('the screen keeps what is on the map', () {
    test(
      'markers: a newer build wins, and a rebuilt group is not overwritten',
      () {
        final text = _squash(_read(viewModel));
        // A draw stops as soon as a newer one has started...
        expect(text.contains('if (_disposed || !isCurrent()) return null;'),
            isTrue);
        expect(
          text.contains(
            'if (_disposed || !identical(_locationClusters[key], cluster)) return;',
          ),
          isTrue,
        );
        // ...and only the newest draw publishes, then moves the camera, in one
        // synchronous step: the pipeline (plain Dart, tested) owns the order.
        final pipeline = _squash(_read(policy));
        expect(pipeline.contains('final build = ++_build;'), isTrue);
        expect(
          pipeline
              .contains('if (drawn == null || build != _build) return false;'),
          isTrue,
        );
        expect(
          pipeline
              .contains('_publish(snapshot, drawn); _moveCameraFor(snapshot);'),
          isTrue,
          reason: 'the camera is planned from the snapshot just published',
        );
      },
    );

    test(
      'an open card is the filter\'s selected place, and closes with it',
      () {
        final text = _squash(_read(viewModel));
        // One source of truth: the controller's selected key.
        expect(
          text.contains('_filters.select(cluster.activeItem.key);'),
          isTrue,
        );
        expect(text.contains('final key = _filters.selectedKey;'), isTrue);
        expect(text.contains('_syncSelection();'), isTrue);
        expect(text.contains('_filters.select(null);'), isTrue);
        expect(
          text.contains(
            'if (_filters.selectedKey == null && _selectedCluster != null) { _selectedCluster = null; _selectedLocationInfo = null; }',
          ),
          isTrue,
          reason: 'a card whose place the filter removed closes at once',
        );
      },
    );

    test('a failed read never empties a map that has places', () {
      final text = _squash(_read(viewModel));
      expect(
        text.contains(
          'void _failLoad() { if (_allLocations.isEmpty) { _hasLoadError = true;',
        ),
        isTrue,
      );
    });

    test('places appearing or refreshing never move the camera', () {
      final text = _read(viewModel);
      final shown = text.substring(
        text.indexOf('Future<void> _show('),
        text.indexOf('LocationInfo _toLocationInfo('),
      );
      for (final move in [
        'animateCamera',
        '_animateCamera',
        'moveCamera',
        '_moveCamera',
        'requestCamera',
        '_afterFilterChange',
        'initialCameraFor',
        'Future.delayed',
      ]) {
        expect(shown.contains(move), isFalse, reason: '_show must not `$move`');
      }
      // It draws what it has, and asks for no camera move.
      expect(shown.contains('_pipeline.show(_filters.snapshot)'), isTrue);
      // The first appearance of markers no longer frames them either.
      expect(text.contains('_scheduleCameraFit'), isFalse);
      expect(text.contains('hadMarkers'), isFalse);
      expect(text.contains('Future.delayed'), isFalse, reason: 'no timer');
      expect(text.contains('Timer('), isFalse, reason: 'no timer');
    });
  });

  group('one compact filter row', () {
    test('the screen has the bar and no per-kind chips any more', () {
      final text = _read(view);
      expect(text.contains('MapFilterBar('), isTrue);
      expect(text.contains('MapNoMatchesBanner('), isTrue);
      for (final gone in [
        '_FloatingFilterChips',
        '_FilterChip',
        'setFilter(',
        'isFilterSelected',
        'selectedFilters',
        'offersCount',
        'filterByType',
      ]) {
        expect(text.contains(gone), isFalse, reason: gone);
      }
      for (final path in [bar, viewModel]) {
        final other = _read(path);
        expect(other.contains('setFilter('), isFalse, reason: path);
        expect(other.contains('selectedFilters'), isFalse, reason: path);
      }
    });

    test(
      'the chips come in the order: Layers, Location, Near Me, Rent / Sale, '
      'Property Type, Sort, and Reset is not one of them',
      () {
        final text = _squash(_read(bar));
        final order = [
          'onTap: () => _chooseEntity(context),',
          'onTap: () => _chooseLocation(context),',
          'onTap: () => _tapNearby(context),',
          'onTap: () => _chooseTransaction(context),',
          'onTap: () => _choosePropertyType(context),',
          'onTap: () => _choosePrice(context),',
          'onTap: () => _chooseSort(context),',
        ];
        var from = 0;
        for (final step in order) {
          final at = text.indexOf(step, from);
          expect(at, greaterThanOrEqualTo(0), reason: step);
          from = at + step.length;
        }
        // Each is named for what it is, in the same order.
        final names = [
          "loc.translate('mapFilterLayers')",
          "loc.translate('mapFilterLocation')",
          "loc.translate('mapFilterNearby')",
          "loc.translate('mapFilterTransaction')",
          "loc.translate('propertyType')",
          '_priceLabel(state.priceRange)',
          "loc.translate('mapFilterSort')",
        ];
        from = 0;
        for (final name in names) {
          final at = text.indexOf(name, from);
          expect(at, greaterThanOrEqualTo(0), reason: name);
          from = at + name.length;
        }
        // Five chips open an option list; Near Me and Price use their own
        // controls (a radius list and a compact range sheet).
        expect(_count(text, 'dropdown: true,'), 5);
        expect(_count(text, 'onTap: () => _tapNearby(context),'), 1);
        // Reset is not a chip: at the end of a row that scrolls it could be out
        // of sight exactly when a filter is on. The status line shows it.
        expect(text.contains('vm.filtersActive'), isFalse);
        expect(text.contains('onTap: vm.clearFilters,'), isFalse);
        expect(text.contains("loc.translate('clear')"), isFalse);
      },
    );

    test('the row scrolls sideways, so a small phone never overflows', () {
      final text = _squash(_read(bar));
      expect(text.contains('scrollDirection: Axis.horizontal,'), isTrue);
    });

    test(
        'in a list, the check sits beside the count on the label\'s side, '
        'so the counts stay in one column', () {
      final text = _read(bar);
      final start = text.indexOf('trailing: Row(');
      final end = text.indexOf('onTap: () => Navigator.of(sheetContext)');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final trailing = text.substring(start, end);
      final check = trailing.indexOf('Icon(Icons.check_rounded');
      final count = trailing.indexOf('option.trailing!');
      expect(check, greaterThanOrEqualTo(0));
      expect(count, greaterThanOrEqualTo(0));
      // Written first, so it is the label's side in both directions: right of
      // the count in Arabic, left of it in English. The count is last, at the
      // edge, where every row's count is.
      expect(check, lessThan(count));
      expect(_count(trailing, 'Icons.check_rounded'), 1);
      // A list with no counts still shows its check, with no stray gap.
      expect(
        _squash(trailing).contains(
          'if (option.trailing != null) const SizedBox(width: 8),',
        ),
        isTrue,
      );
    });

    test(
      'the Layers selector lists All and exactly the kinds the map shows',
      () {
        final text = _squash(_read(bar));
        expect(text.contains('for (final type in MapEntityTypes.all)'), isTrue);
        expect(text.contains('value: LocationFilter.all,'), isTrue);
        // The chip is called Layers until a kind is chosen, then it says which
        // kind; the list is titled Layers and its first choice is "All".
        expect(
          text.contains(
            "label: entity == LocationFilter.all ? loc.translate('mapFilterLayers') : loc.translate(_entityKey(entity)),",
          ),
          isTrue,
        );
        expect(
          text.contains("title: localization.translate('mapFilterLayers'),"),
          isTrue,
        );
        expect(text.contains("label: localization.translate('all'),"), isTrue);
        expect(text.contains('mapFilterCategory'), isFalse);
      },
    );

    test('the lists come from the app\'s canonical sources', () {
      final bartext = _squash(_read(bar));
      expect(
        bartext.contains('UaeAreaCatalog.cityKey('),
        isTrue,
        reason: 'cities are labelled by the catalog\'s own keys',
      );
      expect(bartext.contains('vm.cityOptions'), isTrue);
      expect(bartext.contains('vm.propertyTypeOptions'), isTrue);
      expect(
        bartext.contains('for (final transaction in MapTransaction.values)'),
        isTrue,
      );

      final model = _squash(_read(viewModel));
      expect(
        model.contains('_filters.propertyTypeOptions'),
        isTrue,
        reason: 'the active layer supplies its own canonical options',
      );
      final options = _squash(_read('lib/src/services/map_property_type_options.dart'));
      expect(
        options.contains('OfferPropertyTypes.keys'),
        isTrue,
      );
      expect(
        options.contains(
          'for (final option in OwnerPropertyTypes.options) option.key,',
        ),
        isTrue,
      );

      final vocabulary = _squash(_read(source));
      expect(
        vocabulary.contains(
          'MapPropertyTypes.canonicalKey(stored, ShareFormat.propertySubTypeKeys)',
        ),
        isTrue,
      );
      expect(vocabulary.contains('OwnerPropertyTypes.match(stored,'), isTrue);
      expect(vocabulary.contains('OwnerLocationCodec('), isTrue);
      // A city named in Arabic is read as well as one named in English: the
      // labels are the app's own, in both languages, taken from its ARB tables.
      expect(
        vocabulary.contains(
          'cityLabels: (city) => namesOfKey(UaeAreaCatalog.cityKey(city)),',
        ),
        isTrue,
      );
      expect(
        vocabulary.contains(
          "for (final language in const <String>['en', 'ar'])",
        ),
        isTrue,
      );
    });

    test('the property-type reading is the share messages\' own', () {
      // `MapPropertyTypes.canonicalKey` reads a stored type exactly the way
      // `ShareFormat.propertyType` does; if one changes, this says so.
      const normalization =
          ".toLowerCase().replaceAll(' ', '').replaceAll('&', 'and')";
      final share = _squash(_read('lib/src/services/share/share_format.dart'));
      final mine = _squash(_read(data));
      expect(share.contains(normalization), isTrue);
      expect(mine.contains(normalization), isTrue);
      expect(share.contains("wanted == 'hotelhotelapartment'"), isTrue);
      expect(mine.contains("wanted == 'hotelhotelapartment'"), isTrue);
      expect(share.contains("wanted = 'hotelandhotelapartment'"), isTrue);
      expect(mine.contains("wanted = 'hotelandhotelapartment'"), isTrue);
    });

    test('choosing a filter reads nothing: it only recomputes and redraws', () {
      final text = _read(viewModel);
      final start = text.indexOf('// ---- filter changes');
      final end = text.indexOf('// UI methods');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final changes = text.substring(start, end);
      for (final read in ['_loader', '_cache', 'refresh', 'retry', 'load(']) {
        expect(
          changes.contains(read),
          isFalse,
          reason: 'the filter code must not touch `$read`',
        );
      }
      // The only reads: the first one, a retry, and a manual refresh.
      expect(_count(text, '_loader.start()'), 1);
      expect(_count(text, '_loader.refresh()'), 2);
      expect(
        _squash(text).contains(
          'void clearFilters() => _afterFilterChange( _filters.clear(), MapCameraCause.filterChanged, );',
        ),
        isTrue,
      );
    });

    test('filters that match nothing say so, and are not a failed load', () {
      final screen = _squash(_read(view));
      expect(screen.contains('if (vm.hasNoFilterMatches) Positioned('), isTrue);
      expect(
        screen.contains("localization.translate('mapNoFilterMatches')"),
        isTrue,
      );
      expect(
        screen.contains("localization.translate('mapResetFilters')"),
        isTrue,
      );
      expect(screen.contains('onClear: vm.clearFilters,'), isTrue);
      // The map stays visible: the load-error branch is a different state.
      expect(screen.contains('vm.hasLoadError ? Center('), isTrue);
      expect(
        _squash(_read(viewModel))
            .contains('bool get hasNoFilterMatches => _filters.hasNoMatches;'),
        isTrue,
      );
    });
  });

  group('location is asked for only after a tap, with no dialog of the app\'s',
      () {
    // Every file the location path is made of, the plugin adapter included.
    const platform = 'lib/src/services/device_location_platform.dart';
    const locationFiles = [view, bar, viewModel, controller, locator, platform];

    String between(String text, String from, String to) {
      final start = text.indexOf(from);
      expect(start, greaterThanOrEqualTo(0), reason: from);
      final end = text.indexOf(to, start + from.length);
      expect(end, greaterThan(start), reason: to);
      return text.substring(start, end);
    }

    test('opening the map only reads the permission, it never asks', () {
      final screen = _read(view);
      final model = _read(viewModel);
      expect(
        screen.contains('unawaited(vm.checkLocationPermission());'),
        isTrue,
      );
      final check = between(
        model,
        'Future<void> checkLocationPermission()',
        '// Move camera to specific location',
      );
      expect(check.contains('_device.permission()'), isTrue);
      for (final ask in ['requestPermission', 'position(', 'locate()']) {
        expect(check.contains(ask), isFalse, reason: 'check must not `$ask`');
      }
      // Nothing about the view model's construction touches the device.
      final constructor = between(
        model,
        'MapViewViewModel({',
        'final MapDataCacheService _cache;',
      );
      for (final ask in ['_device.', 'locate(', 'permission', 'Geolocator']) {
        expect(
          constructor.contains(ask),
          isFalse,
          reason: 'the constructor must not `$ask`',
        );
      }
      // Nor does building the screen: the only calls are the two taps.
      expect(_count(screen, 'moveToCurrentLocation('), 1);
      expect(_count(screen, 'enableNearby('), 0);
      expect(_count(screen, 'locate('), 0);
    });

    test('the system\'s prompt and the position are reached from one place',
        () {
      for (final path in [...mapFiles, platform]) {
        final text = _read(path);
        final asks = _count(text, '.request()');
        final positions = _count(text, 'getCurrentPosition(');
        expect(asks, path == platform ? 1 : 0, reason: '$path asks');
        expect(positions, path == platform ? 1 : 0, reason: '$path positions');
        // The flow is the only caller of the platform's two asking methods.
        expect(
          _count(text, '.requestPermission('),
          path == locator ? 1 : 0,
          reason: '$path requestPermission',
        );
        expect(
          _count(text, '.position('),
          path == locator ? 1 : 0,
          reason: '$path position',
        );
      }
      // The system's prompt comes only after the permission was read and found
      // neither granted nor refused for good.
      final flow = _squash(_read(locator));
      expect(
        flow.contains(
          'var permission = await _device.permission(); if (permission == DevicePermission.permanentlyDenied) { return const NearbyPermanentlyDenied(); } if (permission != DevicePermission.granted) { permission = await _device.requestPermission();',
        ),
        isTrue,
      );
    });

    test('the map shows no permission or location dialog of its own', () {
      for (final path in locationFiles) {
        final text = _read(path);
        for (final dialog in [
          'showDialog',
          'AlertDialog',
          'showCupertinoDialog',
          'CleanPermissionService',
          'CleanLocationService',
          'locationAccessNeeded',
          'locationPermissionExplanation',
          'locationPermissionRequired',
          'openAppSettings',
          'openLocationSettings',
          'openSettings',
        ]) {
          expect(text.contains(dialog), isFalse, reason: '$path: $dialog');
        }
      }
      // The boundary has no screen to show anything on.
      final flow = _read(locator);
      expect(flow.contains('BuildContext'), isFalse);
      expect(flow.contains('package:flutter'), isFalse);
      expect(
          _read(viewModel).contains('moveToCurrentLocation(context'), isFalse);
      expect(_read(viewModel).contains('enableNearby(context'), isFalse);
    });

    test('"my location" and Nearby go through the same boundary', () {
      final model = _squash(_read(viewModel));
      expect(
        model.contains(
          'late final NearbyLocator _nearbyLocator = DeviceNearbyLocator(_device);',
        ),
        isTrue,
      );
      expect(
        model.contains(
          'late final NearbyLocator _myLocationLocator = DeviceNearbyLocator(_device, precise: true);',
        ),
        isTrue,
      );
      expect(_count(model, 'DeviceNearbyLocator('), 2);
      expect(
        model.contains(
            '_filters.enableNearby(_nearbyLocator, radiusKm: radiusKm)'),
        isTrue,
      );
      expect(model.contains('_myLocationLocator.locate()'), isTrue);
      // Neither entry point starts a request while the other is running, so
      // two taps never mean two competing permission requests.
      expect(
        model.contains(
          'Future<NearbyFix?> enableNearby({ int radiusKm = NearbyFilter.defaultRadiusKm, }) async { if (_disposed || _filters.isLocatingNearby || _locatingMe) return null;',
        ),
        isTrue,
      );
      expect(
        model.contains(
          'Future<NearbyFix?> moveToCurrentLocation() async { if (_disposed || _filters.isLocatingNearby || _locatingMe) return null;',
        ),
        isTrue,
      );
    });

    test('"my location" moves the camera and nothing else', () {
      final model = _read(viewModel);
      final body = between(
        model,
        'Future<NearbyFix?> moveToCurrentLocation()',
        'Future<void> checkLocationPermission()',
      );
      // It may only READ whether Nearby is being awaited (so two location
      // requests never run at once); it changes no filter.
      final code = body.replaceAll('_filters.isLocatingNearby', '');
      for (final filter in [
        '_filters',
        'enableNearby',
        'NearbyFilter',
        'setCity',
        'clearFilters',
        '_afterFilterChange',
      ]) {
        expect(
          code.contains(filter),
          isFalse,
          reason: 'it must not touch `$filter`: Locate Me is not Nearby',
        );
      }
      expect(body.contains('animateCamera('), isTrue);
    });

    test('Nearby shows it is working from the tap, and hides nothing meanwhile',
        () {
      final model = _squash(_read(viewModel));
      // The chip's loading state is the controller's, and the view model
      // refreshes right after the request starts, so the chip changes at the tap.
      expect(
        model.contains(
            'bool get isLocatingNearby => _filters.isLocatingNearby;'),
        isTrue,
      );
      expect(
        model.contains(
          'final pending = _filters.enableNearby(_nearbyLocator, radiusKm: radiusKm); _safeNotifyListeners(); final request = _filters.nearbyRequest; final fix = await pending;',
        ),
        isTrue,
      );
      // Nothing is drawn, filtered or moved before the position is back.
      final body = between(
        _read(viewModel),
        'Future<NearbyFix?> enableNearby({',
        'void _afterFilterChange(',
      );
      final beforeAnswer = body.substring(0, body.indexOf('await pending'));
      for (final early in ['_afterFilterChange', '_pipeline', '_moveCamera']) {
        expect(beforeAnswer.contains(early), isFalse, reason: early);
      }
      // A second tap starts nothing.
      expect(
        _squash(body).contains(
          'if (_disposed || _filters.isLocatingNearby || _locatingMe) return null;',
        ),
        isTrue,
      );

      // The Near Me chip shows a compact busy state and cannot be tapped
      // meanwhile. It is the only chip that does: Location is a chip of its
      // own, so a city or All UAE can still be chosen, and supersedes the wait.
      final chip = _squash(_read(bar));
      expect(chip.contains('loading: vm.isLocatingNearby,'), isTrue);
      expect(_count(chip, 'loading: vm.isLocatingNearby,'), 1);
      expect(chip.contains('onTap: loading ? null : onTap,'), isTrue);
      expect(chip.contains('if (vm.isLocatingNearby) return;'), isTrue);
      expect(chip.contains('CircularProgressIndicator('), isTrue);
      final location = between(
        _read(bar),
        'Future<void> _chooseLocation(',
        'Future<void> _choosePropertyType(',
      );
      expect(location.contains('isLocatingNearby'), isFalse);
    });

    test(
        'Nearby takes the position the system holds, once, and only for Nearby',
        () {
      final flow = _squash(_read(locator));
      expect(_count(flow, '_device.lastKnownPosition()'), 1);
      expect(
          flow.contains(
              'if (!precise) { final recent = await _recentPosition();'),
          isTrue,
          reason: '"my location" is precise and never takes a held position');
      expect(
        flow.contains(
            'static const Duration maxRecentAge = Duration(seconds: 60);'),
        isTrue,
      );
      expect(
        flow.contains('static const double maxRecentAccuracyMeters = 500;'),
        isTrue,
      );
      // Taps share one running request.
      expect(
        flow.contains(
          'Future<NearbyFix> locate() => _running ??= _locate().whenComplete(() { _running = null; });',
        ),
        isTrue,
      );
      // The adapter asks the system for its cached position, never a new fix.
      final adapter =
          _squash(_read('lib/src/services/device_location_platform.dart'));
      expect(_count(adapter, 'Geolocator.getLastKnownPosition()'), 1);
      expect(_count(adapter, 'Geolocator.getCurrentPosition('), 1);
    });

    test('Near Me is switched on from its own chip, and nowhere else', () {
      expect(_count(_read(bar), 'vm.enableNearby()'), 1);
      expect(_count(_read(view), 'enableNearby('), 0);
      final model = _read(viewModel);
      expect(_count(model, '_filters.enableNearby('), 1);
    });

    test('a failure is a result the screen words, never a raw error', () {
      final flow = _squash(_read(locator));
      for (final outcome in [
        'return const NearbyServicesOff();',
        'return const NearbyPermanentlyDenied();',
        'return const NearbyDenied();',
        '} catch (_) { return const NearbyUnavailable(); }',
      ]) {
        expect(flow.contains(outcome), isTrue, reason: outcome);
      }
      // The screen asks one function which sentence goes with an outcome.
      final barText = _squash(_read(bar));
      expect(
        barText.contains(
          'final key = fix == null ? null : nearbyFixMessageKey(fix); if (key != null) onMessage(localization.translate(key));',
        ),
        isTrue,
      );
      final screen = _squash(_read(view));
      expect(
        screen.contains(
          'final key = nearbyFixMessageKey(fix); if (key != null) _showToast(localization.translate(key), Colors.orange);',
        ),
        isTrue,
      );
      // No raw error or platform text reaches the person from the location
      // path (the screen's card has a `toString()` of its own, unrelated).
      final nearbyTap = between(
        _read(bar),
        'Future<void> _tapNearby(',
        'class _PriceRangeSheet',
      );
      for (final path in locationFiles.where((path) => path != view)) {
        // The Price sheet also lives in the bar and formats its numeric input
        // with toString(); it is outside the location failure path.
        final text = path == bar ? nearbyTap : _read(path);
        expect(text.contains('toString()'), isFalse, reason: path);
      }
      final locateMe = between(
        _read(view),
        'Future<void> _locateMe(',
        'Future<void> _searchLocation(',
      );
      expect(locateMe.contains('toString()'), isFalse);
      expect(locateMe.contains('catch'), isFalse);
    });

    test('the position is never logged, stored or sent', () {
      // Logging: print, debugPrint, developer.log or a bare log(. (`math.log(`
      // is the natural logarithm of the camera's maths, not a log line.)
      final outward = RegExp(
        r'\b(debugPrint|print)\(|\bdeveloper\.log\(|(?<![\w.])log\(',
      );
      final storage = RegExp(
        r"import '[^']*(shared_preferences|hive|supabase|flutter_secure_storage|package:http)",
      );
      for (final path in [
        view,
        bar,
        controller,
        filter,
        locator,
        viewModel,
        'lib/src/services/device_location_platform.dart',
        'lib/src/services/map_camera.dart',
        policy,
        'lib/src/services/map_city_geography.dart',
        'lib/src/services/geo_distance.dart',
        'lib/src/common/data/uae_coordinate_sanity.dart',
        'lib/src/common/data/picked_location_gate.dart',
      ]) {
        final text = _read(path);
        expect(outward.hasMatch(text), isFalse, reason: '$path logs');
        expect(
          storage.hasMatch(text),
          isFalse,
          reason: '$path stores or sends',
        );
        expect(
          RegExp(r'\b(SharedPreferences|jsonEncode|writeAsString)\b')
              .hasMatch(text),
          isFalse,
          reason: '$path persists',
        );
      }
      // The position lives in the filter state only: the view model keeps no
      // copy of it, and builds no position of its own.
      final model = _read(viewModel);
      expect(model.contains('nearby.latitude'), isFalse);
      expect(model.contains('NearbyLocated('), isFalse);
      for (final copy in [
        '_userLocation',
        '_lastLocation',
        '_currentPosition',
        '_lastPosition',
        'package:geolocator',
      ]) {
        expect(model.contains(copy), isFalse, reason: 'it keeps `$copy`');
      }
      // The only words said about a failed fix are fixed ones from the app's
      // own table: no coordinate can reach a message.
      final screen = _read(view);
      final bartext = _read(bar);
      for (final text in [screen, bartext]) {
        expect(text.contains(r'${fix'), isFalse);
        expect(text.contains(r'$fix'), isFalse);
        expect(text.contains('fix.latitude'), isFalse);
        expect(text.contains('fix.longitude'), isFalse);
      }
    });

    test('the distance is a haversine, and the radii are 5, 10 and 25 km', () {
      final text = _squash(_read(filter));
      expect(
        text.contains(
          'static const List<int> radiusOptionsKm = <int>[5, 10, 25];',
        ),
        isTrue,
      );
      expect(text.contains('static const int defaultRadiusKm = 10;'), isTrue);
      // The maths lives in its own plain file, which the filter re-exports.
      final geo = _squash(_read('lib/src/services/geo_distance.dart'));
      expect(
        geo.contains('static const double earthRadiusMeters = 6371008.8;'),
        isTrue,
      );
      expect(geo.contains('math.asin(math.sqrt(clamped))'), isTrue);
      expect(
        text.contains(
          "export 'package:broker_wallet/src/services/geo_distance.dart';",
        ),
        isTrue,
      );
      expect(text.contains('GeoDistance.meters('), isTrue);
    });
  });

  group('in the app\'s language, with no technical message', () {
    test('no English placeholder or message is written in the map code', () {
      for (final path in mapFiles) {
        final text = _read(path);
        for (final english in [
          'Property Offer',
          'Property Owner',
          'Real Estate Office',
          'Building Watchman',
          'No address',
          'Location found',
          'Owner not found',
          'Office not found',
          'Watchman not found',
          'Error loading details',
          'Please select a specific',
          'items at this location',
          'Failed to initialize map',
          'User not authenticated',
          'No locations match',
          'Clear filters',
          'All property types',
          "'Nearby'",
          "'Category'",
          "'All cities'",
          "'Rent / Sale'",
          "'Hello'",
          'All prices',
          'Lowest price',
          'Highest price',
          "'Price'",
          'Location access is blocked',
          'Location permission denied',
          // the Phase 1 names, in the app's language only
          "'Layers'",
          "'Near Me'",
          "'Sort'",
          "'Default'",
          "'Reset'",
          'Reset filters',
          'Price: Low to High',
          'Price: High to Low',
          'Search location...',
          "'All UAE'",
        ]) {
          expect(text.contains(english), isFalse, reason: '$path: $english');
        }
      }
    });

    test(
      'a toast is always a translated string, never a literal or an error',
      () {
        final text = _read(view);
        expect(RegExp(r"_showToast\(\s*'").hasMatch(text), isFalse);
        expect(RegExp(r'_showToast\(\s*"').hasMatch(text), isFalse);
        expect(
          text.contains(r'${e.toString()}'),
          isFalse,
          reason: 'the exception text is not for the person',
        );
        for (final key in [
          'mapLocationFound',
          'mapLocationNotFound',
          'ownerNotFound',
          'officeNotFound',
          'watchmanNotFound',
          'mapDetailsLoadFailed',
          'unableToMakePhoneCall',
          'couldNotOpenWhatsApp',
        ]) {
          expect(text.contains("loc.translate('$key')"), isTrue, reason: key);
        }
      },
    );

    test('a failed load shows a translated message and a working Retry', () {
      final text = _squash(_read(view));
      expect(text.contains('vm.hasLoadError ? Center('), isTrue);
      expect(text.contains("localization.translate('mapLoadFailed'),"), isTrue);
      expect(text.contains('onPressed: vm.retry,'), isTrue);
      expect(text.contains('vm.error'), isFalse);
      expect(text.contains('vm.loadLocations'), isFalse);
    });

    test('the view model gets the language, and words empty titles with it',
        () {
      expect(
        _read(view).contains('vm.updateLocalization(localization);'),
        isTrue,
      );
      final text = _squash(_read(viewModel));
      for (final key in ['offer', 'propertyOwner', 'office', 'watchman']) {
        expect(text.contains("loc.translate('$key')"), isTrue, reason: key);
      }
      // An Offer's property type is shown in the app's language, as elsewhere.
      expect(text.contains('ShareFormat.propertyType('), isTrue);
      expect(text.contains(".translate('mapItemsAtLocation')"), isTrue);
      expect(
        _squash(_read(view)).contains('titleOf: vm.displayTitle,'),
        isTrue,
      );
    });

    for (final code in ['en', 'ar']) {
      test('$code: every string the map uses exists', () {
        final table = _arb(code);
        for (final key in [
          // the map's own
          'mapLocationFound',
          'mapLocationNotFound',
          'mapLoadFailed',
          'mapItemsAtLocation',
          'ownerNotFound',
          'officeNotFound',
          'watchmanNotFound',
          'mapDetailsLoadFailed',
          // the filter row
          'mapSearchHint',
          'mapFilterLayers',
          'mapFilterNearby',
          'mapNearbyActive',
          'mapNearbyRadius',
          'mapNearbyTurnOff',
          'mapKmValue',
          'mapNearbyUnavailable',
          'mapFilterLocation',
          'mapAllUae',
          'mapAllPropertyTypes',
          'mapFilterTransaction',
          'mapFilterPrice',
          'mapPriceMinimum',
          'mapPriceMaximum',
          'mapPriceInvalid',
          'mapPriceOrder',
          'mapPriceApply',
          'mapPriceClear',
          'mapPriceFrom',
          'mapPriceUpTo',
          'mapPriceBetween',
          'mapFilterSort',
          'mapSortDefault',
          'mapSortPriceLowToHigh',
          'mapSortPriceHighToLow',
          'mapReset',
          'mapResetFilters',
          'mapNoFilterMatches',
          'mapResultsNone',
          'mapResultsOne',
          'mapResultsTwo',
          'mapResultsFew',
          'mapResultsOther',
          'mapLocationBlocked',
          // the app's own words, reused
          'all',
          'propertyType',
          'rent',
          'sale',
          'locationServiceDisabledMessage',
          'locationPermissionDenied',
          'offer',
          'propertyOwner',
          'office',
          'watchman',
          'unableToMakePhoneCall',
          'couldNotOpenWhatsApp',
          'whatsAppBusinessMessage',
          'propertyManager',
          'retry',
          'offers',
          'owners',
          'offices',
          'watchmen',
          'whatsapp',
          'call',
        ]) {
          expect(
            (table[key] as String?)?.trim(),
            isNotEmpty,
            reason: '$code $key',
          );
        }
        for (final entry in {
          'mapItemsAtLocation': '{count}',
          'mapNearbyActive': '{km}',
          'mapKmValue': '{km}',
          'whatsAppBusinessMessage': '{managerName}',
        }.entries) {
          expect(
            (table[entry.key] as String).contains(entry.value),
            isTrue,
            reason: '$code ${entry.key} keeps its placeholder',
          );
        }
      });

      test(
          '$code: every city and property type a selector can show is '
          'translated', () {
        final table = _arb(code);

        final catalog = _read('lib/src/common/data/uae_area_catalog.dart');
        final cityStart = catalog.indexOf(
          'static const Map<String, String> _cityKeys = {',
        );
        final cityBlock = catalog.substring(
          cityStart,
          catalog.indexOf('};', cityStart),
        );
        final cityKeys = RegExp(r"'[A-Za-z ]+': '([a-zA-Z]+)',")
            .allMatches(cityBlock)
            .map((m) => m.group(1)!)
            .toList();
        expect(cityKeys, hasLength(9));

        final share = _read('lib/src/services/share/share_format.dart');
        expect(
          share.contains(
            'static const List<String> propertySubTypeKeys = OfferPropertyTypes.keys;',
          ),
          isTrue,
        );
        final offerTypes =
            _read('lib/src/common/data/offer_property_types.dart');
        final from = offerTypes.indexOf(
          'static const List<String> keys = <String>[',
        );
        expect(from, greaterThanOrEqualTo(0));
        final end = offerTypes.indexOf('];', from);
        expect(end, greaterThan(from));
        final formKeys = RegExp(r"'([A-Za-z]+)'")
            .allMatches(offerTypes.substring(from, end))
            .map((m) => m.group(1)!)
            .toList();
        expect(formKeys, isNotEmpty);

        final owner = _read('lib/src/common/data/owner_property_types.dart');
        final ownerKeys = RegExp(r"OwnerPropertyType\(\s*'([A-Za-z]+)'")
            .allMatches(owner)
            .map((m) => m.group(1)!)
            .toList();
        expect(ownerKeys, isNotEmpty);

        for (final key in {...cityKeys, ...formKeys, ...ownerKeys}) {
          expect(
            (table[key] as String?)?.trim(),
            isNotEmpty,
            reason: '$code $key',
          );
        }
      });
    }
  });

  group('the map opens on the whole UAE, and nothing re-frames it', () {
    String between(String text, String from, String to) {
      final start = text.indexOf(from);
      expect(start, greaterThanOrEqualTo(0), reason: from);
      final end = text.indexOf(to, start + from.length);
      expect(end, greaterThan(start), reason: to);
      return text.substring(start, end);
    }

    test('the map is created on a UAE frame worked out from its real size', () {
      final screen = _squash(_read(view));
      expect(screen.contains('LayoutBuilder('), isTrue);
      expect(
        screen.contains(
            'initialCameraPosition: vm.initialCameraFor( MapViewport('),
        isTrue,
      );
      expect(screen.contains('width: constraints.maxWidth,'), isTrue);
      expect(screen.contains('height: constraints.maxHeight,'), isTrue);
      expect(_count(screen, 'initialCameraFor('), 1);
      expect(screen.contains('vm.initialCameraPosition'), isFalse);

      final model = _squash(_read(viewModel));
      expect(
        model
            .contains('final MapCameraDirector _camera = MapCameraDirector();'),
        isTrue,
      );
      expect(model.contains('_camera.initial(viewport)'), isTrue);
      expect(_count(model, '_camera.initial('), 1);
      // The frame itself is the pure file's: neither screen nor model fits it.
      for (final path in [view, viewModel, bar]) {
        expect(_read(path).contains('UaeMapFraming.fit('), isFalse,
            reason: path);
      }
      expect(
        _read('lib/src/services/map_camera.dart')
            .contains('_initial ??= UaeMapFraming.fit(viewport);'),
        isTrue,
        reason: 'the one-time guard: decided once, then kept',
      );
    });

    test('the old Dubai camera, and the timer that framed markers, are gone',
        () {
      final model = _read(viewModel);
      expect(model.contains('25.2048'), isFalse);
      expect(model.contains('zoom: 11'), isFalse);
      expect(model.contains('Dubai coordinates'), isFalse);
      expect(model.contains('_scheduleCameraFit'), isFalse);
      expect(model.contains('Future.delayed'), isFalse);
      expect(_read(view).contains('Future.delayed'), isFalse);
      expect(_read(view).contains('Timer'), isFalse);
    });

    test('creating the map moves nothing', () {
      final model = _read(viewModel);
      final created = between(
        model,
        'void onMapCreated(',
        'void onMapTap(',
      );
      for (final move in [
        'animateCamera',
        'moveCamera',
        'newLatLngBounds',
        'newLatLngZoom',
        '_moveCamera',
        '_animateCamera',
        '_pipeline',
        '_markers',
      ]) {
        expect(created.contains(move), isFalse, reason: 'onMapCreated: $move');
      }
      expect(created.contains('_mapController = controller;'), isTrue);
    });

    test(
        'only an explicit choice moves the camera, and only All UAE goes to '
        'the UAE', () {
      final model = _squash(_read(viewModel));
      // Every filter choice goes through one door, which asks the pipeline for
      // a camera move for that choice and draws the same snapshot. A choice
      // that is its own request to see something (All UAE) can force it.
      expect(
        model.contains(
          'void _afterFilterChange( bool changed, MapCameraCause cause, { bool force = false, }) { if (_disposed || (!changed && !force)) return;',
        ),
        isTrue,
      );
      expect(_count(model, 'force: true'), 1, reason: 'only All UAE forces');
      expect(
        model.contains(
          'final snapshot = _filters.snapshot; _pipeline.requestCamera(cause, snapshot); unawaited(_pipeline.show(snapshot));',
        ),
        isTrue,
      );
      expect(_count(model, '_pipeline.requestCamera('), 1);
      // The only camera animations: the person's own moves (my location, a
      // searched place) and the one mover the pipeline calls.
      expect(_count(model, 'controller.animateCamera('), 1);
      expect(_count(model, '_animateCamera('), 4); // 3 callers + definition
      // Loading, refreshing and retrying go through none of that.
      final text = _read(viewModel);
      final loadPath = [
        // _onPlaces, _failLoad and _show
        between(
            text, 'Future<void> _onPlaces(', 'LocationInfo _toLocationInfo('),
        // retry and refreshLocations
        between(
          text,
          'Future<void> retry()',
          '// Helper method to get icon asset for type',
        ),
      ];
      for (final code in loadPath) {
        for (final move in [
          '_afterFilterChange',
          'requestCamera',
          '_moveCamera',
          '_animateCamera',
          'animateCamera',
          'initialCameraFor',
        ]) {
          expect(code.contains(move), isFalse, reason: 'load path: $move');
        }
      }
      // Nothing in the view model frames the country: not Clear, not a
      // filter. Only the planner does, for the one cause All UAE, with the
      // opening camera's own function.
      expect(model.contains('UaeMapFraming'), isFalse);
      final planner = _squash(_read(policy));
      expect(_count(planner, 'UaeMapFraming.fit('), 1);
      expect(
        planner.contains(
          'return MapCameraPlan( cause: cause, subject: MapCameraSubject.uaeOverview, target: UaeMapFraming.fit(viewport), );',
        ),
        isTrue,
      );
      expect(
        model.contains(
          'void clearFilters() => _afterFilterChange( _filters.clear(), MapCameraCause.filterChanged, );',
        ),
        isTrue,
      );
    });

    test(
        'the markers are drawn from the snapshot, never from live filter state',
        () {
      final draw = between(
        _read(viewModel),
        'Future<_Drawn?> _drawMarkers(',
        'void _publishDrawn(',
      );
      expect(draw.contains('_filters'), isFalse,
          reason: 'a slow draw must not mix an old filter with a new one');
      expect(draw.contains('snapshot.visible'), isTrue);
      expect(draw.contains('snapshot.selectedKey'), isTrue);
      // And the camera is planned from the published snapshot in the pipeline.
      final pipeline = _squash(_read(policy));
      expect(
        pipeline.contains(
          'final plan = MapCameraPlanner.plan( cause: intent.cause, snapshot: published, viewport: _viewport(), );',
        ),
        isTrue,
      );
    });

    test('each choice names the cause that says what the camera shows', () {
      final model = _squash(_read(viewModel));
      for (final pair in {
        'setEntityType': 'filterChanged',
        'setCity': 'cityChanged',
        'setAllUae': 'allUae',
        'setPropertyType': 'filterChanged',
        'setTransaction': 'filterChanged',
        'setPriceMode': 'filterChanged',
        'setNearbyRadius': 'nearbyRadiusChanged',
        'disableNearby': 'filterChanged',
        'clearFilters': 'filterChanged',
      }.entries) {
        final start = model.indexOf('void ${pair.key}(');
        expect(start, greaterThanOrEqualTo(0), reason: pair.key);
        final end = model.indexOf(');', start);
        expect(
          model.substring(start, end).contains('MapCameraCause.${pair.value}'),
          isTrue,
          reason: '${pair.key} -> ${pair.value}',
        );
      }
      expect(
        model.contains(
          '_afterFilterChange( fix is NearbyLocated && _filters.state.nearbyEnabled, MapCameraCause.nearbyEnabled, );',
        ),
        isTrue,
      );
    });

    test('the camera moves as one planned position, with nothing after it', () {
      final model = _read(viewModel);
      expect(model.contains('_moveCameraToShowAllMarkers'), isFalse);
      expect(model.contains('_applyFilterAndFit'), isFalse);
      expect(model.contains('newLatLngBounds'), isFalse,
          reason: 'no native bounds call that can fail and fall back late');
      // One animation helper, not awaited, whose failure is swallowed.
      final helper = between(
        model,
        'void _animateCamera(CameraUpdate update)',
        '@override\n  void dispose()',
      );
      expect(
        _squash(helper).contains(
          'controller.animateCamera(update).then<void>((_) {}, onError: (_) {})',
        ),
        isTrue,
      );
      expect(RegExp(r'\bawait\b').hasMatch(helper), isFalse);
      // The planned move is a camera position, not a list of steps.
      expect(
        _squash(model)
            .contains('CameraUpdate.newCameraPosition( CameraPosition('),
        isTrue,
      );
    });

    test(
        '"my location" never overrides a newer choice, and cancels older '
        'requests', () {
      final model = _squash(_read(viewModel));
      expect(model.contains('final epoch = _pipeline.cameraEpoch;'), isTrue);
      expect(model.contains('if (epoch == _pipeline.cameraEpoch) {'), isTrue);
      expect(
          model.contains('_pipeline.cancelCamera(); _animateCamera('), isTrue);
      // A searched place is a choice too.
      final searched = between(
        _read(viewModel),
        'Future<void> animateToLocation(',
        'void _moveCamera(',
      );
      expect(searched.contains('_pipeline.cancelCamera();'), isTrue);
    });

    test('the frame leaves room for the controls that cover the map', () {
      final screen = _squash(_read(view));
      for (final inset in [
        'top: MediaQuery.of(context).padding.top + _controlsBelowTop,',
        'bottom: _controlsAboveBottom,',
        'left: _controlsSideGap,',
        'right: _controlsSideGap,',
      ]) {
        expect(screen.contains(inset), isTrue, reason: inset);
      }
      // The numbers are the layout's own: the filter row sits at 76 and is 48
      // high; the my-location button is 40 high at 16 from the bottom.
      expect(
        screen.contains('static const double _controlsBelowTop = 76 + 48 + 8;'),
        isTrue,
      );
      expect(
        screen.contains(
            'static const double _controlsAboveBottom = 16 + 40 + 16;'),
        isTrue,
      );
      expect(
        screen.contains(
          'top: MediaQuery.of(context).padding.top + 76, // Below search bar left: 0,',
        ),
        isTrue,
        reason: 'the filter row is where the frame assumes',
      );
    });
  });

  group('a record\'s city and its pin are told apart', () {
    test('every kind of record is judged once, when it is mapped', () {
      final mapper = _squash(_read(data));
      expect(
        _count(mapper,
            'cityConflict: MapCityGeography.conflicts(city, lat, lng),'),
        4,
        reason: 'Offers, Owners, Offices and Watchmen',
      );
      expect(mapper.contains('final bool cityConflict;'), isTrue);
      expect(mapper.contains('this.cityConflict = false,'), isTrue);
    });

    test('the City filter shows a place under a city only if its pin agrees',
        () {
      final engine = _squash(_read(filter));
      expect(
        engine.contains(
          'if (state.city != null && (place.city != state.city || place.cityConflict)) { return false; }',
        ),
        isTrue,
      );
      // Only the City filter reads it: every city still shows with all cities.
      expect(_count(engine, 'cityConflict'), 2,
          reason: 'its doc, and the one check');
    });

    test('the geography is plain Dart, and the Map does not write to it', () {
      for (final path in [
        'lib/src/services/map_city_geography.dart',
        'lib/src/services/geo_distance.dart',
      ]) {
        final text = _read(path);
        expect(text.contains('package:flutter'), isFalse, reason: path);
        expect(text.contains('geolocator'), isFalse, reason: path);
        expect(text.contains('http'), isFalse, reason: path);
        expect(RegExp(r'\b(Future|async|await)\b').hasMatch(text), isFalse,
            reason: '$path asks nothing from anywhere');
      }
    });

    test(
        'the camera table keeps the catalog\'s names, and lives with the '
        'geography', () {
      final policyText = _read(policy);
      expect(policyText.contains('class MapCityFrame'), isFalse);
      expect(policyText.contains('class MapCityCameras'), isFalse);
      expect(
        _squash(policyText).contains(
          "export 'package:broker_wallet/src/services/map_city_geography.dart' show MapCityCameras, MapCityFrame;",
        ),
        isTrue,
      );
      final geography = _read('lib/src/services/map_city_geography.dart');
      expect(geography.contains("'Abu Dhabi': MapCityFrame(24.4539, 54.3773"),
          isTrue);
    });
  });

  group('the City list is the forms\' catalog', () {
    test('every city, from the one catalog, and not from the loaded places',
        () {
      expect(
        _squash(_read(filter)).contains(
          'static List<String> cities() => UaeAreaCatalog.supportedCities;',
        ),
        isTrue,
      );
      expect(
        _squash(_read(controller)).contains(
            'List<String> get cityOptions => MapFilterOptions.cities();'),
        isTrue,
      );
      expect(
        _squash(_read(viewModel))
            .contains('List<String> get cityOptions => _filters.cityOptions;'),
        isTrue,
      );
      // It no longer looks at places at all.
      final filterText = _read(filter);
      final cityStart = filterText.indexOf('static List<String> cities()');
      expect(cityStart, greaterThanOrEqualTo(0));
      // Stop at this method's terminator; the next method's doc comment
      // legitimately talks about loaded places and is outside the city list.
      final cityEnd = filterText.indexOf(';', cityStart) + 1;
      expect(cityEnd, greaterThan(cityStart));
      final cities = filterText.substring(cityStart, cityEnd);
      for (final loaded in [
        'places',
        'place.city',
        'Iterable<CachedLocationData>'
      ]) {
        expect(cities.contains(loaded), isFalse, reason: loaded);
      }
      // The Owner form lists the very same catalog.
      expect(
        _read('lib/src/viewmodels/AddScreens/add_owners_viewmodel.dart').contains(
            'List<String> get locationCities => UaeAreaCatalog.supportedCities;'),
        isTrue,
      );
    });

    test(
        'the Location list shows All UAE, then each city labelled as the '
        'forms label it', () {
      final text = _squash(_read(bar));
      expect(
        text.contains(
          "_SheetOption( value: const _LocationChoice.allUae(), label: localization.translate('mapAllUae'), icon: Icons.public_rounded, ), for (final city in vm.cityOptions) _SheetOption( value: _LocationChoice.city(city), label: _cityLabel(city), ),",
        ),
        isTrue,
      );
      expect(
        text.contains(
            'String _cityLabel(String city) => _label(UaeAreaCatalog.cityKey(city));'),
        isTrue,
      );
      // The forms' own chips use the same key for the same label.
      expect(
        _squash(_read('lib/src/views/Widgets/uae_city_area_picker.dart'))
            .contains(
                'label: localization.translate(UaeAreaCatalog.cityKey(city)),'),
        isTrue,
      );
    });

    test('choosing a place in the Location list asks no network, no geocoder',
        () {
      final text = _read(bar);
      final start = text.indexOf('Future<void> _chooseLocation(');
      final chosen = text.substring(
        start,
        text.indexOf('Future<void> _choosePropertyType('),
      );
      for (final remote in ['http', 'geocoding', 'locationFromAddress']) {
        expect(chosen.contains(remote), isFalse, reason: remote);
      }
      // The only await is the list itself: a city or All UAE never asks the
      // device (Near Me is its own chip), and a Near Me request still waiting
      // is simply superseded by the view model.
      expect(_count(chosen, 'await '), 1);
      expect(_count(chosen, 'await _showOptions<_LocationChoice>('), 1);
      for (final device in ['enableNearby', 'locate', 'nearbyFixMessageKey']) {
        expect(chosen.contains(device), isFalse, reason: device);
      }
      expect(_read(filter).contains('locationFromAddress'), isFalse);
      expect(_read(data).contains('geocoding'), isFalse);
    });

    test('the Near Me chip asks no network, and the device only to turn on',
        () {
      final text = _read(bar);
      final start = text.indexOf('Future<void> _tapNearby(');
      final tap = text.substring(
        start,
        text.indexOf('/// One chip of the bar'),
      );
      for (final remote in ['http', 'geocoding', 'locationFromAddress']) {
        expect(tap.contains(remote), isFalse, reason: remote);
      }
      // The only awaits: the device's position through the view model (asked
      // for Near Me only, from this tap) and the radius list.
      expect(_count(tap, 'await '), 2);
      expect(_count(tap, 'await vm.enableNearby();'), 1);
      expect(_count(tap, 'await _showOptions<int>('), 1);
      // Already on: a radius only changes the radius, and the way out turns it
      // off; neither asks the device.
      expect(
        _squash(tap).contains(
          'if (choice == null) return; if (choice.value == turnOff) { vm.disableNearby(); } else if (choice.value != null) { vm.setNearbyRadius(choice.value!); }',
        ),
        isTrue,
      );
      expect(
        _squash(tap).contains(
          'for (final km in NearbyFilter.radiusOptionsKm) _SheetOption(value: km, label: _km(km)), _SheetOption( value: turnOff, label: localization.translate(\'mapNearbyTurnOff\'), icon: Icons.close_rounded, ),',
        ),
        isTrue,
      );
    });

    test('the lists are laid out start-to-end, so Arabic reads right to left',
        () {
      final text = _read(bar);
      expect(text.contains('AlignmentDirectional.centerStart'), isTrue);
      for (final physical in [
        'Alignment.centerLeft',
        'Alignment.centerRight',
        'TextAlign.left',
        'TextAlign.right',
        'EdgeInsets.only(left',
        'EdgeInsets.only(right',
        'Positioned(left',
      ]) {
        expect(text.contains(physical), isFalse, reason: physical);
      }
    });
  });

  group('the Sort chip', () {
    test('one compact chip with three choices, not three chips', () {
      final text = _squash(_read(bar));
      expect(_count(text, 'onTap: () => _chooseSort(context),'), 1);
      expect(_count(text, 'Icons.sort_rounded'), 1);
      expect(text.contains('Icons.payments_rounded'), isFalse);
      expect(text.contains("loc.translate('mapFilterSort')"), isTrue);
      expect(
        text.contains("title: localization.translate('mapFilterSort'),"),
        isTrue,
      );
      expect(text.contains('active: state.priceMode != MapPriceMode.all,'),
          isTrue);
      expect(text.contains('for (final mode in MapPriceMode.values)'), isTrue);
      for (final key in [
        'mapSortDefault',
        'mapSortPriceLowToHigh',
        'mapSortPriceHighToLow',
      ]) {
        expect(text.contains("localization.translate('$key')"), isTrue,
            reason: key);
      }
      expect(text.contains('vm.setPriceMode(choice.value ?? MapPriceMode.all)'),
          isTrue);
    });

    test('each choice is worded for the order it really gives', () {
      final text = _squash(_read(bar));
      expect(
        text.contains(
          "case MapPriceMode.all: return localization.translate('mapSortDefault'); case MapPriceMode.lowest: return localization.translate('mapSortPriceLowToHigh'); case MapPriceMode.highest: return localization.translate('mapSortPriceHighToLow');",
        ),
        isTrue,
        reason: 'lowest is Low to High, highest is High to Low',
      );
      // ...and the engine really does put the lowest price first for lowest.
      final engine = _squash(_read(filter));
      expect(
        engine.contains(
          'case MapPriceMode.lowest: return _byPrice(kept, highestFirst: false);',
        ),
        isTrue,
      );
      expect(
        engine.contains(
          'case MapPriceMode.highest: return _byPrice(kept, highestFirst: true);',
        ),
        isTrue,
      );
    });

    test('choosing a price only sorts what is loaded', () {
      final model = _read(viewModel);
      expect(
        _squash(model).contains(
          'void setPriceMode(MapPriceMode mode) => _afterFilterChange( _filters.setPriceMode(mode), MapCameraCause.filterChanged, );',
        ),
        isTrue,
      );
      // It sits in the filter section, which the existing guard keeps free of
      // any read.
      final start = model.indexOf('// ---- filter changes');
      final end = model.indexOf('// UI methods');
      expect(model.indexOf('void setPriceMode('), inExclusiveRange(start, end));
    });

    test('the price is ranked from the Offer\'s stored minimum, else maximum',
        () {
      final mapper = _squash(_read(data));
      expect(
        mapper.contains(
          'price: MapPrice.comparable( minPrice: offer.minPrice, maxPrice: offer.maxPrice, ),',
        ),
        isTrue,
      );
      expect(
        _squash(_read('lib/src/services/map_price.dart'))
            .contains('parse(minPrice) ?? parse(maxPrice);'),
        isTrue,
      );
      // No other kind is given a price.
      expect(_count(mapper, 'price: '), 1);
    });
  });

  group('the card\'s actions and picture', () {
    test('calls and WhatsApp use the number the way the detail screens do', () {
      final text = _squash(_read(view));
      expect(
        RegExp('PhoneInputService\\.formatForDial\\(').allMatches(text).length,
        2,
        reason: 'the call and WhatsApp',
      );
      expect(text.contains(r"https://wa.me/$digits?text=$message"), isTrue);
      expect(
        text.contains(r'https://wa.me/$phoneNumber'),
        isFalse,
        reason: 'the raw stored number is not a WhatsApp number',
      );
      expect(text.contains("loc.translate('whatsAppBusinessMessage')"), isTrue);
    });

    test(
      'the address line is the mapper\'s, which keeps areas with "st" in them',
      () {
        expect(_read(view).contains('MapLocationMapper.areaAndCity('), isTrue);
        expect(_read(view).contains('_extractAreaAndCity'), isFalse);
        expect(_read(data).contains(r"RegExp(r'\b(st|street)\b')"), isTrue);
        expect(_read(data).contains(".contains('st')"), isFalse);
      },
    );

    test(
      'an Offer\'s or Owner\'s picture is the one Search and Favorites draw',
      () {
        final text = _squash(_read(view));
        expect(text.contains('resolver.current(kind, id)'), isTrue);
        expect(
          text.contains('isWanted: () => mounted && request == _mediaRequest,'),
          isTrue,
        );
        expect(
          text.contains(
            'PrivateCardMedia( cacheKey: media.cacheKey, isVideo: media.isVideo, signedUrl: media.signedUrl, posterPath: media.posterPath,',
          ),
          isTrue,
        );
        // Only Offers and Owners have private media; the plain URL stays.
        expect(
          text.contains(
            'case LocationFilter.offers: return CardMediaKind.offer; case LocationFilter.owners: return CardMediaKind.owner;',
          ),
          isTrue,
        );
        expect(text.contains('CachedNetworkImage('), isTrue);
        expect(
          _squash(_read(viewModel)).contains('cardMedia.invalidate();'),
          isTrue,
        );
      },
    );

    test('the media type and resolver are named one way, so the types agree',
        () {
      // `Views` and `views` are different libraries to Dart; both files name the
      // resolver, and the screen the media type, through `Views`.
      const resolver =
          'package:broker_wallet/src/Views/Screens/home/search/search_card_media.dart';
      const lower =
          'package:broker_wallet/src/views/Screens/home/search/search_card_media.dart';
      for (final path in [view, viewModel]) {
        final text = _read(path);
        expect(text.contains(resolver), isTrue, reason: path);
        expect(text.contains(lower), isFalse, reason: path);
      }
      expect(
        _read(view).contains(
          'package:broker_wallet/src/Views/Screens/home/favorites/favorite_card_media.dart',
        ),
        isTrue,
      );
      expect(
        _read(viewModel).contains('favorite_card_media'),
        isFalse,
        reason: 'the model passes the resolver, never the media type',
      );
      // The bar and the screen name the view model the same way.
      const modelImport =
          'package:broker_wallet/src/Views/Screens/home/map/map_viewmodel.dart';
      expect(_read(view).contains(modelImport), isTrue);
      expect(_read(bar).contains(modelImport), isTrue);
      expect(
        _read(view).contains(
          'package:broker_wallet/src/Views/Screens/home/map/map_filter_bar.dart',
        ),
        isTrue,
      );
    });
  });
}
