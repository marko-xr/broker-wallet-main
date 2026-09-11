import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_user_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/edit_profile_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/theme_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/edit_profile_view.dart'
    show profileSaveFeedbackKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = '550e8400-e29b-41d4-a716-446655440000';
const _otherUid = '550e8400-e29b-41d4-a716-4466554400ff';

const _oldName = 'Old Name';
const _newName = 'New Name';
const _oldMediaId = 'media-old';
const _newMediaId = 'media-new';
const _pickedPath = '/tmp/picked_profile_photo.jpg';

/// Text a backend failure might carry. It must never reach the user.
const _rawErrorText = 'PostgrestException(code: 42501, token=abc123)';

UserSubscription _subscription() => UserSubscription(
      plan: 'test',
      isActive: false,
      features: const [],
    );

UserModel _session({String uid = _uid}) => UserModel(
      uid: uid,
      name: '',
      email: 'session@example.test',
      createdAt: DateTime(2026, 1, 1),
      isEmailVerified: true,
      subscription: _subscription(),
      preferences: const {},
    );

UserModel _profile({String uid = _uid}) => UserModel(
      uid: uid,
      name: _oldName,
      email: 'profile@example.test',
      createdAt: DateTime(2026, 1, 1),
      isEmailVerified: true,
      profileMediaId: _oldMediaId,
      subscription: _subscription(),
      preferences: const {},
    );

class _AuthRepository implements AuthRepository {
  _AuthRepository({UserModel? initialUser}) : _currentUser = initialUser;

  final StreamController<UserModel?> _controller =
      StreamController<UserModel?>.broadcast();
  UserModel? _currentUser;

  /// When set, `updateUserProfile` waits on it.
  Completer<void>? pendingUpdate;
  final List<Map<String, String?>> updateCalls = [];

  @override
  Stream<UserModel?> get authStateChanges async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  @override
  UserModel? get currentUser => _currentUser;

  @override
  String? get currentUserId => _currentUser?.uid;

  @override
  Future<void> updateUserProfile({
    String? name,
    String? phoneNumber,
    String? profileImageUrl,
  }) async {
    updateCalls.add({
      'name': name,
      'phoneNumber': phoneNumber,
      'profileImageUrl': profileImageUrl,
    });
    final pending = pendingUpdate;
    if (pending != null) await pending.future;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }

  void emit(UserModel? user) {
    _currentUser = user;
    _controller.add(user);
  }

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UserRepository implements UserRepository, ProfileImageUrlResolver {
  _UserRepository(this.profile);

  UserModel? profile;

  @override
  Future<UserModel?> getUserById(String uid) async =>
      profile?.uid == uid ? profile : null;

  @override
  Future<String?> resolveProfileImageUrl(String profileMediaId) async => null;

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  Future<void> updateUser(UserModel user) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for R2 authorize → PUT → confirm.
class _Uploader {
  Completer<String>? pending;
  final List<String> calls = [];

  Future<String> call(String path) async {
    calls.add(path);
    final completer = pending ??= Completer<String>();
    return completer.future;
  }
}

class _Adopter {
  final List<(String, String)> calls = [];

  Future<void> call(String mediaId, String path) async {
    calls.add((mediaId, path));
  }
}

class _Harness {
  _Harness._(this.auth, this.users, this.uploader, this.adopter, this.vm);

  final _AuthRepository auth;
  final _UserRepository users;
  final _Uploader uploader;
  final _Adopter adopter;
  final AuthViewModel vm;

  static Future<_Harness> hydrated() async {
    final auth = _AuthRepository(initialUser: _session());
    final users = _UserRepository(_profile());
    final uploader = _Uploader();
    final adopter = _Adopter();
    final vm = AuthViewModel(
      authRepository: auth,
      userRepository: users,
      profileImageUploader: uploader.call,
      profileMediaAdopter: adopter.call,
    );
    await settle();
    expect(vm.profileHydration, ProfileHydrationStatus.resolved);
    expect(vm.displayName, _oldName);
    expect(vm.profileImage.mediaId, _oldMediaId);
    return _Harness._(auth, users, uploader, adopter, vm);
  }

  Future<void> dispose() async {
    vm.dispose();
    await auth.dispose();
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Optimistic name', () {
    test('is visible before the repository future completes', () async {
      final h = await _Harness.hydrated();
      h.auth.pendingUpdate = Completer<void>();

      final save = h.vm.saveProfile(name: _newName);

      // Synchronous — nothing awaited yet.
      expect(h.vm.displayName, _newName);
      expect(h.vm.isSavingProfile, isTrue);
      expect(h.vm.currentUser?.name, _oldName,
          reason: 'the canonical model is not mutated optimistically');

      h.auth.pendingUpdate!.complete();
      await save;
      await h.dispose();
    });

    test('success clears the override with no visual rollback', () async {
      final h = await _Harness.hydrated();
      h.auth.pendingUpdate = Completer<void>();

      final seen = <String>[];
      h.vm.addListener(() => seen.add(h.vm.displayName));

      final save = h.vm.saveProfile(name: _newName);
      await settle();
      h.auth.pendingUpdate!.complete();
      final result = await save;

      expect(result.outcome, ProfileSaveOutcome.success);
      expect(h.vm.pendingProfileName, isNull);
      expect(h.vm.currentUser?.name, _newName);
      expect(h.vm.displayName, _newName);
      expect(seen, everyElement(_newName),
          reason: 'the old name must never reappear during reconciliation');
      expect(h.vm.isSavingProfile, isFalse);

      await h.dispose();
    });

    test('failure rolls back the name only', () async {
      final h = await _Harness.hydrated();
      h.auth.pendingUpdate = Completer<void>();

      final save = h.vm.saveProfile(name: _newName);
      expect(h.vm.displayName, _newName);

      h.auth.pendingUpdate!.completeError(StateError(_rawErrorText));
      final result = await save;

      expect(result.outcome, ProfileSaveOutcome.nameFailed);
      expect(result.isPartialSuccess, isFalse);
      expect(h.vm.displayName, _oldName);
      expect(h.vm.pendingProfileName, isNull);
      expect(h.vm.profileImage.mediaId, _oldMediaId);

      await h.dispose();
    });
  });

  group('Optimistic image', () {
    test('is visible before the upload pipeline begins', () async {
      final h = await _Harness.hydrated();

      final save = h.vm.saveProfile(imagePath: _pickedPath);

      expect(h.vm.profileImage.localFilePath, _pickedPath);
      expect(h.vm.profileImage.hasLocalSource, isTrue);
      expect(h.uploader.calls, isEmpty,
          reason: '/authorize has not been reached yet');

      await settle();
      expect(h.uploader.calls, [_pickedPath]);

      h.uploader.pending!.complete(_newMediaId);
      await save;
      await h.dispose();
    });

    test('success adopts the picked bytes under the confirmed media id',
        () async {
      final h = await _Harness.hydrated();

      final save = h.vm.saveProfile(imagePath: _pickedPath);
      await settle();
      h.uploader.pending!.complete(_newMediaId);
      final result = await save;

      expect(result.outcome, ProfileSaveOutcome.success);
      expect(h.adopter.calls, [(_newMediaId, _pickedPath)]);
      expect(h.vm.profileImage.mediaId, _newMediaId);
      expect(h.vm.profileImage.localFilePath, isNull);
      expect(h.vm.profileImage.signedUrl, isNull,
          reason: 'the previous image URL must not be fetched under the new id');

      await h.dispose();
    });

    test('the new media id is presented only after its bytes are adopted',
        () async {
      final h = await _Harness.hydrated();
      final events = <String>[];
      final vm = AuthViewModel(
        authRepository: h.auth,
        userRepository: h.users,
        profileImageUploader: (_) async => _newMediaId,
        profileMediaAdopter: (mediaId, path) async {
          events.add('adopted $mediaId');
        },
      );
      await settle();

      vm.addListener(() {
        final image = vm.profileImage;
        if (image.mediaId == _newMediaId) {
          events.add(image.hasLocalSource
              ? 'presented new id with override'
              : 'presented new id');
        } else if (image.hasLocalSource) {
          events.add('presented override');
        }
      });

      await vm.saveProfile(imagePath: _pickedPath);

      // The override covers the whole upload; the adopted mapping is in place
      // before the new identity is ever drawn without it.
      expect(events.first, 'presented override');
      final adopted = events.indexOf('adopted $_newMediaId');
      final presentedNew = events.indexOf('presented new id');
      expect(adopted, isNonNegative);
      expect(presentedNew, greaterThan(adopted));

      vm.dispose();
      await h.dispose();
    });

    test('failure restores the previous confirmed image', () async {
      final h = await _Harness.hydrated();

      final save = h.vm.saveProfile(imagePath: _pickedPath);
      expect(h.vm.profileImage.localFilePath, _pickedPath);

      await settle();
      h.uploader.pending!.completeError(StateError(_rawErrorText));
      final result = await save;

      expect(result.outcome, ProfileSaveOutcome.imageFailed);
      expect(h.vm.profileImage.localFilePath, isNull);
      expect(h.vm.profileImage.mediaId, _oldMediaId);
      expect(h.adopter.calls, isEmpty);

      await h.dispose();
    });
  });

  group('Partial success', () {
    test('name persisted, image failed → imageFailed, name kept', () async {
      final h = await _Harness.hydrated();

      final save = h.vm.saveProfile(name: _newName, imagePath: _pickedPath);
      await settle();
      h.uploader.pending!.completeError(StateError(_rawErrorText));
      final result = await save;

      expect(result.outcome, ProfileSaveOutcome.imageFailed);
      expect(result.isPartialSuccess, isTrue);
      expect(result.namePersisted, isTrue);
      expect(result.imagePersisted, isFalse);
      expect(h.vm.displayName, _newName);
      expect(h.vm.currentUser?.name, _newName);
      expect(h.vm.profileImage.mediaId, _oldMediaId);
      expect(h.vm.profileImage.localFilePath, isNull);

      await h.dispose();
    });

    test('image persisted, name failed → nameFailed, image kept', () async {
      final h = await _Harness.hydrated();
      h.auth.pendingUpdate = Completer<void>();

      final save = h.vm.saveProfile(name: _newName, imagePath: _pickedPath);
      await settle();
      h.uploader.pending!.complete(_newMediaId);
      h.auth.pendingUpdate!.completeError(StateError(_rawErrorText));
      final result = await save;

      expect(result.outcome, ProfileSaveOutcome.nameFailed);
      expect(result.isPartialSuccess, isTrue);
      expect(result.namePersisted, isFalse);
      expect(result.imagePersisted, isTrue);
      expect(h.vm.displayName, _oldName);
      expect(h.vm.profileImage.mediaId, _newMediaId);

      await h.dispose();
    });

    test('both failed → both rolled back, canonical state unchanged',
        () async {
      final h = await _Harness.hydrated();
      h.auth.pendingUpdate = Completer<void>();

      final save = h.vm.saveProfile(name: _newName, imagePath: _pickedPath);
      await settle();
      h.uploader.pending!.completeError(StateError(_rawErrorText));
      h.auth.pendingUpdate!.completeError(StateError(_rawErrorText));
      final result = await save;

      expect(result.outcome, ProfileSaveOutcome.bothFailed);
      expect(result.isPartialSuccess, isFalse);
      expect(h.vm.displayName, _oldName);
      expect(h.vm.currentUser?.name, _oldName);
      expect(h.vm.profileImage.mediaId, _oldMediaId);
      expect(h.vm.profileImage.localFilePath, isNull);
      expect(h.vm.pendingProfileName, isNull);

      await h.dispose();
    });
  });

  group('Save pipeline', () {
    test('a text-only save never enters the image pipeline', () async {
      final h = await _Harness.hydrated();

      await h.vm.saveProfile(name: _newName);

      expect(h.uploader.calls, isEmpty);
      expect(h.adopter.calls, isEmpty);
      expect(h.auth.updateCalls, [
        {'name': _newName, 'phoneNumber': null, 'profileImageUrl': null},
      ]);

      await h.dispose();
    });

    test('an image-only save does not write profile text', () async {
      final h = await _Harness.hydrated();

      final save = h.vm.saveProfile(imagePath: _pickedPath);
      await settle();
      h.uploader.pending!.complete(_newMediaId);
      await save;

      expect(h.auth.updateCalls, isEmpty);

      await h.dispose();
    });

    test('name and image persist concurrently', () async {
      final h = await _Harness.hydrated();
      h.auth.pendingUpdate = Completer<void>();

      final save = h.vm.saveProfile(name: _newName, imagePath: _pickedPath);
      await settle();

      // Both started, neither finished.
      expect(h.auth.updateCalls, hasLength(1));
      expect(h.uploader.calls, hasLength(1));
      expect(h.auth.pendingUpdate!.isCompleted, isFalse);
      expect(h.uploader.pending!.isCompleted, isFalse);

      h.auth.pendingUpdate!.complete();
      h.uploader.pending!.complete(_newMediaId);
      expect((await save).outcome, ProfileSaveOutcome.success);

      await h.dispose();
    });

    test('nothing to save does no work', () async {
      final h = await _Harness.hydrated();

      final result = await h.vm.saveProfile();

      expect(identical(result, ProfileSaveResult.none), isTrue);
      expect(h.auth.updateCalls, isEmpty);
      expect(h.uploader.calls, isEmpty);
      expect(h.vm.isSavingProfile, isFalse);

      await h.dispose();
    });

    test('an overlapping save keeps the newer optimistic name', () async {
      final h = await _Harness.hydrated();
      h.auth.pendingUpdate = Completer<void>();

      final first = h.vm.saveProfile(name: 'First');
      final second = h.vm.saveProfile(name: 'Second');
      expect(h.vm.displayName, 'Second');

      h.auth.pendingUpdate!.complete();
      await first;
      expect(h.vm.displayName, 'Second',
          reason: 'the first save must not clear an override it no longer owns');

      await second;
      expect(h.vm.displayName, 'Second');
      expect(h.auth.updateCalls.map((c) => c['name']), ['First', 'Second']);

      await h.dispose();
    });
  });

  group('EditProfileViewModel hand-off', () {
    EditProfileViewModel editor(_Harness h, String name) => EditProfileViewModel(
          themeVM: ThemeViewModel(),
          localeVM: LocaleViewModel(),
          name: name,
          email: '',
          phone: '',
          userRepository: h.users,
          authRepository: h.auth,
        );

    test('an unchanged name with no image is nothing to save', () async {
      final h = await _Harness.hydrated();

      expect(editor(h, _oldName).submitProfileSave(authVM: h.vm), isNull);
      expect(h.vm.isSavingProfile, isFalse);

      await h.dispose();
    });

    test('an unchanged name with an image sends only the image', () async {
      final h = await _Harness.hydrated();

      final save = editor(h, _oldName)
          .submitProfileSave(authVM: h.vm, imagePath: _pickedPath);
      expect(save, isNotNull);
      await settle();
      h.uploader.pending!.complete(_newMediaId);
      await save;

      expect(h.auth.updateCalls, isEmpty);
      expect(h.uploader.calls, [_pickedPath]);

      await h.dispose();
    });
  });

  group('Account isolation', () {
    test('sign-out clears every optimistic override', () async {
      final h = await _Harness.hydrated();
      h.auth.pendingUpdate = Completer<void>();

      final save = h.vm.saveProfile(name: _newName, imagePath: _pickedPath);
      expect(h.vm.displayName, _newName);
      expect(h.vm.profileImage.hasLocalSource, isTrue);

      await h.vm.signOut();
      await settle();

      expect(h.vm.pendingProfileName, isNull);
      expect(h.vm.displayName, isEmpty);
      expect(h.vm.profileImage, ProfileImageSource.empty);

      h.auth.pendingUpdate!.complete();
      h.uploader.pending!.complete(_newMediaId);
      await save;

      expect(h.vm.currentUser, isNull,
          reason: 'a late result must not resurrect the signed-out user');

      await h.dispose();
    });

    test('a late result never leaks into a different account', () async {
      final h = await _Harness.hydrated();
      h.auth.pendingUpdate = Completer<void>();

      final save = h.vm.saveProfile(name: _newName, imagePath: _pickedPath);

      h.users.profile = null;
      h.auth.emit(_session(uid: _otherUid));
      await settle();

      expect(h.vm.currentUser?.uid, _otherUid);
      expect(h.vm.pendingProfileName, isNull);
      expect(h.vm.profileImage.hasLocalSource, isFalse);

      h.auth.pendingUpdate!.complete();
      h.uploader.pending!.complete(_newMediaId);
      await save;

      expect(h.vm.currentUser?.uid, _otherUid);
      expect(h.vm.currentUser?.name, isNot(_newName));
      expect(h.vm.profileImage.mediaId, isNot(_newMediaId));
      expect(h.vm.profileImage.hasLocalSource, isFalse);
      expect(h.adopter.calls, isEmpty);

      await h.dispose();
    });
  });

  group('User-facing feedback', () {
    Map<String, dynamic> arb(String language) => json.decode(
          File('lib/src/common/localization/app_$language.arb')
              .readAsStringSync(),
        ) as Map<String, dynamic>;

    ProfileSaveResult result({
      bool nameAttempted = false,
      bool namePersisted = false,
      bool imageAttempted = false,
      bool imagePersisted = false,
    }) =>
        ProfileSaveResult(
          nameAttempted: nameAttempted,
          namePersisted: namePersisted,
          imageAttempted: imageAttempted,
          imagePersisted: imagePersisted,
        );

    test('each outcome maps to the honest message', () {
      expect(
        profileSaveFeedbackKey(result(nameAttempted: true, namePersisted: true)),
        'profileUpdated',
      );
      expect(
        profileSaveFeedbackKey(result(
          nameAttempted: true,
          namePersisted: true,
          imageAttempted: true,
        )),
        'profileSaveNameSavedImageFailed',
      );
      expect(
        profileSaveFeedbackKey(result(
          nameAttempted: true,
          imageAttempted: true,
          imagePersisted: true,
        )),
        'profileSaveImageSavedNameFailed',
      );
      expect(
        profileSaveFeedbackKey(result(nameAttempted: true, imageAttempted: true)),
        'profileSaveFailed',
      );
      // A single attempted part that failed is a failure, not a partial.
      expect(profileSaveFeedbackKey(result(nameAttempted: true)),
          'profileSaveFailed');
      expect(profileSaveFeedbackKey(result(imageAttempted: true)),
          'profileSaveFailed');
      expect(profileSaveFeedbackKey(ProfileSaveResult.none), isNull);
    });

    test('every message key exists in English and Arabic', () {
      final en = arb('en');
      final ar = arb('ar');
      for (final key in const [
        'profileUpdated',
        'profileSaveNameSavedImageFailed',
        'profileSaveImageSavedNameFailed',
        'profileSaveFailed',
      ]) {
        expect(en[key], isA<String>(), reason: 'en: $key');
        expect(ar[key], isA<String>(), reason: 'ar: $key');
        expect((ar[key] as String) != en[key], isTrue,
            reason: 'ar: $key must be translated');
      }
    });

    test('raw exception text never reaches the user', () async {
      final h = await _Harness.hydrated();
      h.auth.pendingUpdate = Completer<void>();

      final save = h.vm.saveProfile(name: _newName, imagePath: _pickedPath);
      await settle();
      h.uploader.pending!.completeError(StateError(_rawErrorText));
      h.auth.pendingUpdate!.completeError(StateError(_rawErrorText));
      final outcome = await save;

      final key = profileSaveFeedbackKey(outcome)!;
      final shownEn = arb('en')[key] as String;
      final shownAr = arb('ar')[key] as String;
      expect(shownEn, isNot(contains('PostgrestException')));
      expect(shownEn, isNot(contains('token')));
      expect(shownAr, isNot(contains('PostgrestException')));

      await h.dispose();
    });
  });
}
