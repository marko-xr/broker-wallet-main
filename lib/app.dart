import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/Views/Screens/Sign-Up-Log-In/auth_wrapper.dart';
import 'package:broker_wallet/src/Views/Screens/Sign-Up-Log-In/signup_view.dart';
import 'package:broker_wallet/src/Views/Screens/Sign-Up-Log-In/login_view.dart';
import 'package:broker_wallet/src/Views/Screens/Sign-Up-Log-In/email_verification_view.dart';
import 'package:broker_wallet/src/Views/Screens/Sign-Up-Log-In/phone_otp_view.dart';
import 'package:broker_wallet/src/Views/Screens/Sign-Up-Log-In/welcome_view.dart';

import 'package:broker_wallet/src/Views/Screens/ViewAdd/add_brokers_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewAdd/add_offers_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewAdd/add_offices_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewAdd/add_owners_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewAdd/add_requested_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewAdd/add_watchmen_view.dart';

import 'package:broker_wallet/src/Views/Screens/ViewDetails/brokers_view_details.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/offers_view_details.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/offices_view_details.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/owners_view_details.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/requested_view_details.dart';
import 'package:broker_wallet/src/Views/Screens/ViewDetails/watchmen_view_details.dart';

import 'package:broker_wallet/src/Views/Screens/ViewLists/brokers_list_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewLists/offers_list_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewLists/offices_list_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewLists/owners_list_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewLists/requests_list_view.dart';
import 'package:broker_wallet/src/Views/Screens/ViewLists/watchmen_list_view.dart';

import 'package:broker_wallet/src/Views/Screens/home/Profile/about_broker_wallet_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/edit_profile_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/feedback_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/info_placeholder_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/language_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/payment_selection_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/profile_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/share_app_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/SubscriptionPlan/subscription_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/my_plan_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/notification_settings_view.dart';
import 'package:broker_wallet/src/data/models/info_placeholder_args.dart';

import 'package:broker_wallet/src/Views/Screens/home/Toolkit/combine_pdfs_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/image_to_pdf_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/scanner_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/toolkit_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/uae_links_view.dart';

import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/map/map_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/add_quotation_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotation_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_view.dart';
import 'package:broker_wallet/src/Views/Screens/home_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/analytics/analytics_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/notifications/notifications_list_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/notifications/match_details_view.dart';

import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/request_service.dart';

import 'package:broker_wallet/src/common/enums/add_brokers_mode.dart';
import 'package:broker_wallet/src/common/enums/add_offers_mode.dart';
import 'package:broker_wallet/src/common/enums/add_offices_mode.dart';
import 'package:broker_wallet/src/common/enums/add_owners_mode.dart';
import 'package:broker_wallet/src/common/enums/add_requested_mode.dart';
import 'package:broker_wallet/src/common/enums/add_watchmen_mode.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/routes/app_routes.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';

import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';

import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/Profile/SubscriptionPlan/subscription_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/theme_viewmodel.dart';
import 'package:broker_wallet/src/data/models/phone_otp_args.dart';

// ===== Global navigator key (kept global for dialogs/global nav helpers) =====
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    _router = _createRouter(authVM);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeViewModel, LocaleViewModel>(
      builder: (context, themeVM, localeVM, _) {
        final locale = localeVM.locale;
        final isRTL = locale.languageCode == 'ar';

        return MaterialApp.router(
          // Generate the title lazily via onGenerateTitle so Localizations are
          // available in the provided context. Calling AppLocalizations.of
          // directly here can return null because MaterialApp hasn't created
          // the Localizations widgets yet.
          onGenerateTitle: (ctx) =>
              AppLocalizations.of(ctx).translate('appName'),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeVM.themeMode,
          locale: locale,
          routerConfig: _router,
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
          ],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Restore explicit fallback so device locales like ar_AE resolve cleanly
          localeResolutionCallback: (deviceLocale, supported) {
            if (deviceLocale == null) return supported.first;
            for (final s in supported) {
              if (s.languageCode == deviceLocale.languageCode) return s;
            }
            return supported.first;
          },
          // Centralized Directionality + SafeArea (matches your original intent)
          builder: (context, child) {
            return Directionality(
              textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
              child: SafeArea(
                top: false,
                bottom: true,
                left: false,
                right: false,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}

/// Routes that require an authenticated session.
const _protectedRoutes = <String>{
  '/home',
  '/search',
  '/favorites',
  '/profile',
};

/// Logged-out entry screens.
const _authRoutes = <String>{
  '/welcome',
  '/sign-up',
  '/sign-in',
};

/// Flows that own their own routing and are deliberately exempt.
const _selfRoutedFlows = <String>{
  '/email-verification',
  '/phone-otp',
};

/// The single authentication navigation authority.
///
/// AuthWrapper, SignInView and SignUpView each used to schedule their own
/// post-frame `context.go` in addition to this redirect, so one auth
/// transition could be acted on by several authorities at once. They no longer
/// navigate; this function decides every general auth transition, and it is a
/// top-level pure function so the real routing rules are directly testable.
///
/// [status] is bootstrap state. Auth *operation* state (a sign-in in flight)
/// is deliberately not an input here.
String? resolveAuthRedirect(AuthStatus status, String currentPath) {
  // Bootstrap must resolve before any application or auth route is selected.
  if (status == AuthStatus.unknown) {
    return currentPath == '/' ? null : '/';
  }

  // These flows manage their own routing.
  if (_selfRoutedFlows.contains(currentPath)) {
    return null;
  }

  final isAuthenticated = status == AuthStatus.authenticated;

  final isProtected = _protectedRoutes.any(
    (route) => currentPath == route || currentPath.startsWith('$route/'),
  );

  if (!isAuthenticated && isProtected) {
    return '/welcome';
  }

  // Authenticated users never sit on an auth screen. This is also what carries
  // them off `/sign-in` once the session resolves after a successful login.
  if (isAuthenticated && _authRoutes.contains(currentPath)) {
    return '/home';
  }

  if (currentPath == '/') {
    // The root path is the bootstrap gate only. Once bootstrap has resolved,
    // this redirect is the single authority that leaves it — AuthWrapper no
    // longer navigates, so both outcomes must be sent onward from here or the
    // app would remain on the splash gate indefinitely.
    return isAuthenticated ? '/home' : '/welcome';
  }

  return null;
}

GoRouter _createRouter(AuthViewModel authViewModel) {
  // Per-branch navigator keys (local is fine)
  final homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'homeBranch');
  final searchNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'searchBranch');
  final favoritesNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'favoritesBranch');
  final profileNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'profileBranch');

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: authViewModel,
    redirect: (context, state) =>
        resolveAuthRedirect(authViewModel.status, state.uri.path),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const AuthWrapper(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeView(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpView(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInView(),
      ),
      GoRoute(
        path: '/phone-otp',
        builder: (context, state) {
          final extra = state.extra;
          PhoneOtpArgs? args;

          if (extra is Map<String, dynamic>) {
            // New format from ViewModels
            args = PhoneOtpArgs(
              phoneNumber: extra['phoneNumber'] ?? '',
              verificationId: extra['verificationId'] ?? '',
              isSignup: extra['isSignup'] ?? false,
              displayName: extra['displayName'],
              resendToken: extra['resendToken'],
            );
          } else if (extra is PhoneOtpArgs) {
            // Legacy format
            args = extra;
          }

          if (args == null) {
            return const SignInView();
          }
          return PhoneOtpView(args: args);
        },
      ),

      GoRoute(
        path: '/email-verification',
        builder: (context, state) {
          final email = state.extra as String? ?? '';
          return EmailVerificationView(email: email);
        },
      ),

      // ===== Main tabs with bottom navigation (with fade transition restored) =====
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) => CustomTransitionPage(
          key: state.pageKey,
          child: MainScaffold(navigationShell: navigationShell),
          transitionDuration: const Duration(milliseconds: 150),
          reverseTransitionDuration: const Duration(milliseconds: 150),
          transitionsBuilder: (context, anim, secAnim, child) => FadeTransition(
            opacity: CurvedAnimation(
              parent: anim,
              curve: Curves.easeInOut,
            ),
            child: child,
          ),
        ),
        builder: (context, state, navigationShell) {
          // Fallback if CustomTransitionPage isn’t used for some reason
          return MainScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: homeNavigatorKey,
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeView(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: searchNavigatorKey,
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchView(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: favoritesNavigatorKey,
            routes: [
              GoRoute(
                path: '/favorites',
                builder: (context, state) => const FavoritesView(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: profileNavigatorKey,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileView(),
              ),
            ],
          ),
        ],
      ),

      // ===== Standalone list screens =====
      GoRoute(
        path: '/requested-list',
        builder: (context, state) => const RequestedListView(),
      ),
      GoRoute(
        path: '/offers-list',
        builder: (context, state) => const OffersListView(),
      ),
      GoRoute(
        path: '/owners-list',
        builder: (context, state) => const OwnersListView(),
      ),
      GoRoute(
        path: '/offices-list',
        builder: (context, state) => const OfficesListView(),
      ),
      GoRoute(
        path: '/watchmen-list',
        builder: (context, state) => const WatchmenListView(),
      ),
      GoRoute(
        path: '/brokers-list',
        builder: (context, state) => const BrokersListView(),
      ),
      GoRoute(
        path: '/toolkit-list',
        builder: (context, state) => const ToolkitView(),
      ),
      GoRoute(
        path: '/quotation-list',
        builder: (context, state) => const QuotationListView(),
      ),
      GoRoute(
        path: '/map-view',
        builder: (context, state) => const MapViewScreen(),
      ),
      GoRoute(
        path: '/analytics',
        builder: (context, state) => const AnalyticsView(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsListView(),
      ),
      GoRoute(
        path: '/notification-settings',
        builder: (context, state) => const NotificationSettingsView(),
      ),
      GoRoute(
        path: '/match-details',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>?;
          return MatchDetailsView(
            requestId: data?['requestId'] ?? '',
            offerId: data?['offerId'] ?? '',
            matchScore: data?['matchScore'] as double?,
          );
        },
      ),

      // ===== Add screens =====
      GoRoute(
        path: '/add-requested',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          final id = state.uri.queryParameters['id'];
          final data = state.extra as RequestModel?;
          final selected =
              mode == 'edit' ? AddRequestedMode.edit : AddRequestedMode.add;
          return AddRequestedView(
            mode: selected,
            requestId: id,
            requestData: data,
          );
        },
      ),
      GoRoute(
        path: '/add-offers',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          final id = state.uri.queryParameters['id'];
          final data = state.extra as OfferModel?;
          final selected =
              mode == 'edit' ? AddOffersMode.edit : AddOffersMode.add;
          return AddOffersView(
            mode: selected,
            offerId: id,
            offerData: data,
          );
        },
      ),
      GoRoute(
        path: '/add-owners',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          final id = state.uri.queryParameters['id'];
          final data = state.extra as OwnerModel?;
          final selected =
              mode == 'edit' ? AddOwnersMode.edit : AddOwnersMode.add;
          return AddOwnersView(
            mode: selected,
            ownerId: id,
            ownerData: data,
          );
        },
      ),
      GoRoute(
        path: '/add-offices',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          final id = state.uri.queryParameters['id'];
          final data = state.extra as OfficeModel?;
          final selected =
              mode == 'edit' ? AddOfficesMode.edit : AddOfficesMode.add;
          return AddOfficesView(
            mode: selected,
            officeId: id,
            officeData: data,
          );
        },
      ),
      GoRoute(
        path: '/add-watchmen',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          final id = state.uri.queryParameters['id'];
          final data = state.extra as WatchmenModel?;
          final selected =
              mode == 'edit' ? AddWatchmenMode.edit : AddWatchmenMode.add;
          return AddWatchmenView(
            mode: selected,
            watchmenId: id,
            watchmenData: data,
          );
        },
      ),
      GoRoute(
        path: '/add-brokers',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          final id = state.uri.queryParameters['id'];
          final data = state.extra as BrokerModel?;
          final selected =
              mode == 'edit' ? AddBrokersMode.edit : AddBrokersMode.add;
          return AddBrokersView(
            mode: selected,
            brokerId: id,
            brokerData: data,
          );
        },
      ),
      GoRoute(
        path: '/add-quotation',
        builder: (context, state) => const AddQuotationView(),
      ),

      // ===== Details screens =====
      GoRoute(
        path: '/requested-details',
        builder: (context, state) {
          final request = state.extra as RequestModel;
          return RequestDetailsView(request: request);
        },
      ),
      // Route for navigating by ID (used by notifications)
      GoRoute(
        path: '/requested-details-by-id/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return _RequestDetailsLoader(requestId: id);
        },
      ),
      GoRoute(
        path: '/offers-details',
        builder: (context, state) {
          final offer = state.extra as OfferModel;
          return OffersDetailsView(offer: offer);
        },
      ),
      // Route for navigating by ID (used by notifications)
      GoRoute(
        path: '/offers-details-by-id/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return _OfferDetailsLoader(offerId: id);
        },
      ),
      GoRoute(
        path: '/owners-details',
        builder: (context, state) {
          final owner = state.extra as OwnerModel;
          return OwnersDetailsView(owner: owner);
        },
      ),
      GoRoute(
        path: '/offices-details',
        builder: (context, state) {
          final office = state.extra as OfficeModel;
          return OfficesDetailsView(office: office);
        },
      ),
      GoRoute(
        path: '/watchmen-details',
        builder: (context, state) {
          final watchmen = state.extra as WatchmenModel;
          return WatchmenDetailsView(watchmen: watchmen);
        },
      ),
      GoRoute(
        path: '/brokers-details',
        builder: (context, state) {
          final broker = state.extra as BrokerModel;
          return BrokersDetailsView(broker: broker);
        },
      ),

      // ===== Toolkit & Profile (standalone) =====
      GoRoute(
        path: '/scanner',
        builder: (context, state) => const ScannerView(),
      ),
      GoRoute(
        path: '/signature',
        builder: (context, state) => const SignatureScreen(),
      ),
      GoRoute(
        path: '/imageToPdf',
        builder: (context, state) => const ImageToPdfView(),
      ),
      GoRoute(
        path: '/combine-pdfs',
        builder: (context, state) => const CombinePdfsView(),
      ),
      GoRoute(
        path: '/uae-links',
        builder: (context, state) => const UAELinksView(),
      ),
      GoRoute(
        path: '/language',
        builder: (context, state) => const LanguageView(),
      ),
      GoRoute(
        path: '/edit-profile',
        builder: (context, state) => const EditProfileView(),
      ),
      GoRoute(
        path: '/subscription',
        builder: (context, state) => const SubscriptionView(),
      ),
      GoRoute(
        path: '/my-plan',
        builder: (context, state) => const MyPlanView(),
      ),
      GoRoute(
        path: '/payment-selection/:plan',
        builder: (context, state) {
          final planName = state.pathParameters['plan'] ?? 'monthly';
          final plan = planName == 'monthly'
              ? SubscriptionPlan.monthly
              : SubscriptionPlan.yearly;
          return PaymentSelectionView(selectedPlan: plan);
        },
      ),
      GoRoute(
        path: '/feedback',
        builder: (context, state) => const FeedbackView(),
      ),
      GoRoute(
        path: '/share-app',
        builder: (context, state) => const ShareAppView(),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutBrokerWalletView(),
      ),
      GoRoute(
        path: '/info-placeholder',
        builder: (context, state) {
          final args = state.extra is InfoPlaceholderArgs
              ? state.extra as InfoPlaceholderArgs
              : const InfoPlaceholderArgs(title: '', message: '');
          return InfoPlaceholderView(args: args);
        },
      ),
    ],
  );
}

/// Loader widget that fetches an offer by ID and displays the details view
class _OfferDetailsLoader extends StatefulWidget {
  const _OfferDetailsLoader({required this.offerId});
  final String offerId;

  @override
  State<_OfferDetailsLoader> createState() => _OfferDetailsLoaderState();
}

class _OfferDetailsLoaderState extends State<_OfferDetailsLoader> {
  late Future<OfferModel?> _offerFuture;
  final _offerService = OfferService();

  @override
  void initState() {
    super.initState();
    _offerFuture = _offerService.getOffer(widget.offerId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OfferModel?>(
      future: _offerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Offer not found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          );
        }

        return OffersDetailsView(offer: snapshot.data!);
      },
    );
  }
}

/// Loader widget that fetches a request by ID and displays the details view
class _RequestDetailsLoader extends StatefulWidget {
  const _RequestDetailsLoader({required this.requestId});
  final String requestId;

  @override
  State<_RequestDetailsLoader> createState() => _RequestDetailsLoaderState();
}

class _RequestDetailsLoaderState extends State<_RequestDetailsLoader> {
  late Future<RequestModel?> _requestFuture;
  final _requestService = RequestService();

  @override
  void initState() {
    super.initState();
    _requestFuture = _requestService.getRequest(widget.requestId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RequestModel?>(
      future: _requestFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Request not found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          );
        }

        return RequestDetailsView(request: snapshot.data!);
      },
    );
  }
}
