// P3.4 (tracker §7AH): a Favorites read that started under one session of an
// account must not publish or cache once that session has ended, even when
// the same account signs straight back in. The real AuthViewModel turns the
// sign-out (a null identity) into the Favorites account-generation step.
import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
// The app (and AuthViewModel) reach Favorites through `src/Views/…`; another
// spelling would be a second copy of the library with its own generation.
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_item_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

UserModel _user() => UserModel(
      uid: _uid,
      name: 'Test User',
      email: 'favorites@example.test',
      createdAt: DateTime(2026, 1, 1),
      subscription:
          UserSubscription(plan: 'free', isActive: false, features: const []),
    );

class _Auth implements AuthRepository {
  UserModel? user;
  final _changes = StreamController<UserModel?>.broadcast();

  void emit(UserModel? next) {
    user = next;
    _changes.add(next);
  }

  @override
  UserModel? get currentUser => user;

  @override
  String? get currentUserId => user?.uid;

  @override
  Stream<UserModel?> get authStateChanges => _changes.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Users implements UserRepository {
  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  // The account's profile exists, as it does for a signed-in account.
  @override
  Future<UserModel?> getUserById(String uid) async => _user();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Favorites extends FavoriteService {
  _Favorites(this.answer);

  final Future<Map<String, List<FavoriteMetadata>>> answer;
  int loads = 0;
  final List<List<FavoriteItem>> cacheWrites = [];

  @override
  Future<void> waitForAuthReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {}

  @override
  Future<void> initializeCache({String? uidOverride}) async {}

  @override
  List<FavoriteItem> getCachedFavoritesSync() => const [];

  @override
  Future<Map<String, List<FavoriteMetadata>>> getAllFavoritesWithMetadata() {
    loads++;
    return answer;
  }

  @override
  Future<void> cacheFavorites(
    List<FavoriteItem> favorites, {
    required int expectedGeneration,
  }) async {
    if (expectedGeneration != FavoriteService.currentAccountGeneration) return;
    cacheWrites.add(favorites);
  }
}

class _Offers extends OfferService {
  _Offers(this.offer);

  final OfferModel offer;

  @override
  Future<List<OfferModel>> getOffersByIds(
    List<String> offerIds, {
    bool Function()? stop,
  }) async =>
      [
        if (offerIds.contains(offer.id)) offer,
      ];
}

OfferModel _offer(String id) => OfferModel(
      id: id,
      userId: _uid,
      offerType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const [],
      location: '',
      phoneNumber: '500000000',
      countryCode: '+971',
      minPrice: '',
      maxPrice: '',
      notes: '',
      specificPropertyType: 'Offer $id',
      rooms: 1,
      bathrooms: 1,
      pickUpLocation: '',
      pickUpLatitude: 0,
      pickUpLongitude: 0,
      pickUpAddress: '',
      uploadedFileName: '',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      mediaUrls: const [],
    );

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await sb.Supabase.initialize(
      url: 'https://unit-test.invalid',
      publishableKey: 'unit-test-publishable-key',
    );
  });

  test(
      'a read from an ended session of the same account neither publishes '
      'nor caches after that account signs back in', () async {
    final auth = _Auth();
    final authVM =
        AuthViewModel(authRepository: auth, userRepository: _Users());
    auth.emit(_user());
    await _flush();

    final metadata = {
      'offers': [
        FavoriteMetadata(
            itemId: 'o1', type: 'offers', addedAt: DateTime(2026, 11, 1)),
      ],
    };
    final oldAnswer = Completer<Map<String, List<FavoriteMetadata>>>();
    final oldFavorites = _Favorites(oldAnswer.future);
    final oldScreen = FavoritesViewModel(
        favoriteService: oldFavorites, offerService: _Offers(_offer('o1')));
    var oldNotices = 0;
    oldScreen.addListener(() => oldNotices++);
    await _flush();
    expect(oldFavorites.loads, 1);

    // The session ends and the same account signs straight back in.
    final before = FavoriteService.currentAccountGeneration;
    auth.emit(null);
    await _flush();
    auth.emit(_user());
    await _flush();
    expect(FavoriteService.currentAccountGeneration, greaterThan(before));

    oldNotices = 0;
    oldAnswer.complete(metadata);
    await _flush();
    expect(oldScreen.favorites, isEmpty);
    expect(oldFavorites.cacheWrites, isEmpty);
    expect(oldNotices, 0);

    // A screen opened in the new session loads normally.
    final newFavorites = _Favorites(Future.value(metadata));
    final newScreen = FavoritesViewModel(
        favoriteService: newFavorites, offerService: _Offers(_offer('o1')));
    await _flush();
    expect(newScreen.favorites.map((c) => c.id), ['o1']);
    expect(newFavorites.cacheWrites, hasLength(1));

    oldScreen.dispose();
    newScreen.dispose();
    authVM.dispose();
  });
}
