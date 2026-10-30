import 'dart:async';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/contact_us_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/edit_profile_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/feedback_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/legal_information_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/notification_settings_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/profile_view.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/security_view.dart';
import 'package:broker_wallet/src/views/Screens/home/notifications/match_details_view.dart';
import 'package:broker_wallet/src/views/Screens/home/notifications/notifications_list_view.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'r2_test_fakes.dart';
import 'r3_test_fakes.dart';
import 'responsive_harness.dart';

final DateTime _created = DateTime.utc(2026, 10, 24, 8);

UserModel _longIdentityUser() => UserModel(
      uid: 'responsive-profile-user',
      name: 'A very long broker account display name for narrow screens',
      email:
          'very.long.broker.account.identity.for.responsive.testing@example.test',
      phoneNumber: '+971501234567',
      createdAt: _created,
      subscription: UserSubscription(
        plan: 'free',
        isActive: false,
        features: const [],
      ),
    );

RequestModel _request() => RequestModel(
      id: 'request-responsive',
      userId: 'user',
      requestType: 'rent',
      selectedCity: 'Abu Dhabi',
      selectedAreas: const [],
      location:
          'A deliberately long mixed-language request location أبوظبي جزيرة الريم',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '100000',
      maxPrice: '250000',
      notes: '',
      specificPropertyType: 'Residential apartment with a long description',
      rooms: 3,
      bathrooms: 2,
      createdAt: _created,
      updatedAt: _created,
    );

OfferModel _offer() => OfferModel(
      id: 'offer-responsive',
      userId: 'user',
      offerType: 'rent',
      selectedCity: 'Dubai',
      selectedAreas: const [],
      location:
          'A deliberately long mixed-language offer location دبي الخليج التجاري',
      phoneNumber: '',
      countryCode: '+971',
      minPrice: '120000',
      maxPrice: '260000',
      notes: '',
      specificPropertyType: 'Premium apartment with a long description',
      rooms: 3,
      bathrooms: 3,
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      createdAt: _created,
      updatedAt: _created,
      mediaUrls: const [],
    );

List<NotificationModel> _longNotifications() => List.generate(
      8,
      (index) => NotificationModel(
        id: 'notification-$index',
        title: index.isEven
            ? 'A long notification title that must remain usable on small phones $index'
            : 'عنوان إشعار طويل يجب أن يبقى قابلاً للاستخدام على شاشة صغيرة $index',
        body: index.isEven
            ? 'Long notification content with important account details and a clear action.'
            : 'محتوى إشعار طويل يحتوي على تفاصيل مهمة للحساب وإجراء واضح للمستخدم.',
        category: NotificationCategory
            .values[index % NotificationCategory.values.length],
        isRead: index.isOdd,
        createdAt: _created.subtract(Duration(minutes: index + 1)),
        data: const {},
      ),
    );

Future<void> _expectReachable(
  WidgetTester tester,
  Finder finder,
  ResponsiveCase scenario,
) async {
  await tester.scrollUntilVisible(
    finder,
    260,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pump();
  final rect = tester.getRect(finder);
  final viewport = Offset.zero & scenario.size;
  expect(rect.overlaps(viewport), isTrue);
  expectNoLayoutException(tester, scenario);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await prepareResponsiveAssets();
  });

  const profileCases = [
    ResponsiveCase(Size(280, 600)),
    ResponsiveCase(
      Size(320, 568),
      locale: Locale('ar'),
      dark: true,
      textScale: 2,
      safeArea: EdgeInsets.only(top: 28, bottom: 20),
    ),
    ResponsiveCase(
      Size(640, 360),
      locale: Locale('ar'),
      textScale: 1.6,
      safeArea: EdgeInsets.only(top: 20, bottom: 20),
    ),
    ResponsiveCase(Size(800, 1280), dark: true, textScale: 1.3),
  ];

  for (final scenario in profileCases) {
    testWidgets('Profile overview and final approved row: $scenario',
        (tester) async {
      await pumpResponsive(
        tester,
        scenario,
        home: withR3ScreenProviders(
          ProfileView(userRepository: QuietUserRepository()),
        ),
      );
      final shareLabel =
          scenario.locale.languageCode == 'ar' ? 'شارك التطبيق' : 'Share App';
      await _expectReachable(tester, find.text(shareLabel), scenario);
    });
  }

  const securityCases = [
    ResponsiveCase(Size(280, 600), textScale: 2),
    ResponsiveCase(
      Size(360, 640),
      locale: Locale('ar'),
      dark: true,
      textScale: 1.6,
    ),
    ResponsiveCase(Size(640, 360), textScale: 2),
  ];

  for (final scenario in securityCases) {
    testWidgets('Security long identity and delete row: $scenario',
        (tester) async {
      await pumpResponsive(
        tester,
        scenario,
        home: SecurityView(user: _longIdentityUser()),
      );
      final deleteLabel = scenario.locale.languageCode == 'ar'
          ? 'حذف الحساب'
          : 'Delete Account';
      await _expectReachable(tester, find.text(deleteLabel), scenario);
    });
  }

  const settingsCases = [
    ResponsiveCase(Size(280, 600), textScale: 2),
    ResponsiveCase(
      Size(320, 568),
      locale: Locale('ar'),
      dark: true,
      textScale: 2,
    ),
    ResponsiveCase(Size(640, 360), textScale: 1.6),
    ResponsiveCase(Size(800, 1280), dark: true, textScale: 1.3),
  ];

  for (final scenario in settingsCases) {
    testWidgets('Notification preferences toggles remain reachable: $scenario',
        (tester) async {
      await pumpResponsive(
        tester,
        scenario,
        home: withR3ScreenProviders(
          NotificationSettingsView(userRepository: QuietUserRepository()),
        ),
      );
      expect(find.byType(SwitchListTile), findsWidgets);
      final pushLabel = scenario.locale.languageCode == 'ar'
          ? 'الإشعارات الفورية'
          : 'Push notifications';
      await _expectReachable(tester, find.text(pushLabel), scenario);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pump();
      expectNoLayoutException(tester, scenario);
    });
  }

  testWidgets('Edit Profile keeps entered name through same-widget resize',
      (tester) async {
    const scenario = ResponsiveCase(
      Size(360, 640),
      textScale: 1.6,
      keyboard: 240,
      safeArea: EdgeInsets.only(top: 24, bottom: 16),
    );
    await pumpResponsive(
      tester,
      scenario,
      home: withR3ScreenProviders(
        EditProfileView(
          userRepository: QuietUserRepository(),
          authRepository: QuietAuthRepository(),
        ),
      ),
    );
    const entered = 'Long entered profile name kept across orientation';
    await tester.enterText(find.byType(TextField).first, entered);
    await tester.pump();
    expect(find.text(entered), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 720);
    await tester.pump();
    expect(find.text(entered), findsOneWidget);
    expectNoLayoutException(
      tester,
      const ResponsiveCase(
        Size(640, 360),
        textScale: 1.6,
        keyboard: 240,
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Save Changes').last,
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    expect(find.text('Save Changes'), findsOneWidget);
  });

  testWidgets('Edit Profile Arabic enlarged keyboard state remains usable',
      (tester) async {
    const scenario = ResponsiveCase(
      Size(320, 568),
      locale: Locale('ar'),
      dark: true,
      textScale: 2,
      keyboard: 240,
      safeArea: EdgeInsets.only(top: 28, bottom: 20),
    );
    await pumpResponsive(
      tester,
      scenario,
      home: withR3ScreenProviders(
        EditProfileView(
          userRepository: QuietUserRepository(),
          authRepository: QuietAuthRepository(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'اسم مستخدم طويل');
    await _expectReachable(tester, find.text('حفظ التغييرات'), scenario);
  });

  testWidgets('Profile child screen back control stays reachable',
      (tester) async {
    const scenario = ResponsiveCase(Size(320, 568), textScale: 1.6);
    await pumpResponsive(
      tester,
      scenario,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SecurityView(user: _longIdentityUser()),
                ),
              ),
              child: const Text('Open security'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open security'));
    await tester.pumpAndSettle();
    expect(find.byType(BackArrowButton), findsOneWidget);
    expect(
        tester
            .getRect(find.byType(BackArrowButton))
            .overlaps(Offset.zero & scenario.size),
        isTrue);
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Notifications loading state fits smallest viewport',
      (tester) async {
    const scenario = ResponsiveCase(Size(280, 600), textScale: 2);
    final repository = ControlledNotificationRepository();
    final vm = NotificationViewModel(repository: repository);
    addTearDown(() async {
      vm.dispose();
      await repository.close();
    });
    await pumpResponsive(
      tester,
      scenario,
      settle: false,
      home: ChangeNotifierProvider<NotificationViewModel>.value(
        value: vm,
        child: const NotificationsListView(),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Notifications empty and unavailable states fit Arabic',
      (tester) async {
    const scenario = ResponsiveCase(
      Size(320, 568),
      locale: Locale('ar'),
      dark: true,
      textScale: 2,
      safeArea: EdgeInsets.only(top: 28, bottom: 20),
    );
    final repository = ControlledNotificationRepository();
    final vm = NotificationViewModel(repository: repository)
      ..attachUser('responsive-user')
      ..attachUser(null);
    addTearDown(() async {
      vm.dispose();
      await repository.close();
    });
    await pumpResponsive(
      tester,
      scenario,
      home: ChangeNotifierProvider<NotificationViewModel>.value(
        value: vm,
        child: const NotificationsListView(),
      ),
    );
    expect(find.text('لقد قرأت كل شيء!'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(find.text('تحديث'), findsOneWidget);

    vm.attachUser('responsive-user');
    repository.emitError(StateError('offline test feed'));
    await tester.pump();
    expect(vm.isFeedUnavailable, isTrue);
    expectNoLayoutException(tester, scenario);
  });

  const notificationCases = [
    ResponsiveCase(Size(280, 600), textScale: 2),
    ResponsiveCase(
      Size(393, 852),
      locale: Locale('ar'),
      dark: true,
      textScale: 1.6,
    ),
    ResponsiveCase(Size(430, 932), dark: true, textScale: 1.3),
    ResponsiveCase(
      Size(640, 360),
      locale: Locale('ar'),
      textScale: 2,
      safeArea: EdgeInsets.only(top: 20, bottom: 20),
    ),
    ResponsiveCase(Size(800, 1280), dark: true, textScale: 1.3),
  ];

  for (final scenario in notificationCases) {
    testWidgets('Populated long notification list: $scenario', (tester) async {
      final repository = ControlledNotificationRepository();
      final vm = NotificationViewModel(repository: repository)
        ..attachUser('responsive-user');
      repository.emit(_longNotifications());
      repository.emitUnread(4);
      addTearDown(() async {
        vm.dispose();
        await repository.close();
      });
      await pumpResponsive(
        tester,
        scenario,
        home: ChangeNotifierProvider<NotificationViewModel>.value(
          value: vm,
          child: const NotificationsListView(),
        ),
      );
      expect(find.byType(Dismissible), findsWidgets);
      await _expectReachable(
        tester,
        find.text(_longNotifications().last.title),
        scenario,
      );
    });
  }

  const matchCases = [
    ResponsiveCase(Size(280, 600), textScale: 2),
    ResponsiveCase(
      Size(393, 852),
      locale: Locale('ar'),
      dark: true,
      textScale: 1.6,
    ),
    ResponsiveCase(Size(640, 360), textScale: 2),
  ];

  for (final scenario in matchCases) {
    testWidgets('Populated match notification detail: $scenario',
        (tester) async {
      await pumpResponsive(
        tester,
        scenario,
        home: MatchDetailsView(
          requestId: 'request-responsive',
          offerId: 'offer-responsive',
          matchScore: 0.98,
          requestLoader: (_) async => _request(),
          offerLoader: (_) async => _offer(),
        ),
      );
      await _expectReachable(
          tester, find.byType(OutlinedButton).last, scenario);
    });
  }

  testWidgets('Match notification detail loading and error states fit',
      (tester) async {
    const scenario = ResponsiveCase(
      Size(320, 568),
      locale: Locale('ar'),
      dark: true,
      textScale: 2,
    );
    final request = Completer<RequestModel?>();
    final offer = Completer<OfferModel?>();
    await pumpResponsive(
      tester,
      scenario,
      settle: false,
      home: MatchDetailsView(
        requestId: 'request-responsive',
        offerId: 'offer-responsive',
        requestLoader: (_) => request.future,
        offerLoader: (_) => offer.future,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    request.complete(null);
    offer.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsOneWidget);
    expectNoLayoutException(tester, scenario);
  });

  testWidgets('Contact, feedback, and legal controls remain reachable',
      (tester) async {
    const contactCase = ResponsiveCase(
      Size(280, 600),
      locale: Locale('ar'),
      dark: true,
      textScale: 2,
    );
    await pumpResponsive(
      tester,
      contactCase,
      home: const ContactUsView(),
    );
    await _expectReachable(tester, find.byType(FilledButton).last, contactCase);

    const feedbackCase = ResponsiveCase(
      Size(320, 568),
      textScale: 2,
      keyboard: 240,
    );
    await pumpResponsive(
      tester,
      feedbackCase,
      home: withR3ScreenProviders(const FeedbackView()),
    );
    await tester.enterText(
      find.byType(TextField),
      'Long feedback text that must remain visible with the keyboard open.',
    );
    await _expectReachable(
      tester,
      find.byType(ElevatedButton).last,
      feedbackCase,
    );

    const privacyCase = ResponsiveCase(
      Size(280, 600),
      locale: Locale('ar'),
      textScale: 1.6,
    );
    await pumpResponsive(
      tester,
      privacyCase,
      home: const PrivacyPolicyView(),
    );
    await _expectReachable(
      tester,
      find.byType(SettingsSectionCard).last,
      privacyCase,
    );

    const termsCase = ResponsiveCase(
      Size(640, 360),
      dark: true,
      textScale: 2,
    );
    await pumpResponsive(
      tester,
      termsCase,
      home: const TermsConditionsView(),
    );
    await _expectReachable(
      tester,
      find.byType(SettingsSectionCard).last,
      termsCase,
    );
  });
}
