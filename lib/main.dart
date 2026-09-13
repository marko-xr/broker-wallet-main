import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/media_cache_manager.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/widgets/image_cache_manager.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorites_service.dart';
import 'package:broker_wallet/src/services/count_cache_service.dart';
import 'package:broker_wallet/src/services/offline_data_service.dart';
import 'package:broker_wallet/src/services/optimistic_favorites_service.dart';
import 'package:broker_wallet/src/services/map_data_cache_service.dart';
import 'package:broker_wallet/src/services/analytics_service.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/viewmodels/password_recovery_viewmodel.dart';
import 'package:broker_wallet/src/services/notification_service.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/signup_viewmodel.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/home_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/map/map_viewmodel.dart';
import 'src/Views/Screens/home/favorites/favorites_item_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/app.dart';
import 'src/viewmodels/theme_viewmodel.dart';
import 'src/viewmodels/locale_viewmodel.dart';
import 'src/viewmodels/fast_upload_viewmodel.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'firebase_options.dart';
import 'src/services/offline_image_service.dart';
import 'src/services/offline_media_service.dart';
import 'src/services/supabase_bootstrap_service.dart';
import 'src/config/supabase_config.dart';
import 'dart:async';

// Non-blocking language preloading - runs in background
void _preloadLanguagesAsync() {
  Future.microtask(() async {
    try {
      await AppLocalizations.preloadAllLanguages();
      // Languages preloaded for instant switching (log removed)
    } catch (e) {
      // Language preloading failed (log removed)
      // App continues working, just slower language switching
    }
  });
}

Future<void> initializeAppServices() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  // Initialize offline image error handling
  OfflineImageService.initialize();

  // CRITICAL: Preload languages in background - DON'T block app startup
  _preloadLanguagesAsync();

  try {
    // Firebase init with timeout for offline scenarios
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException(
            'Firebase init timeout', const Duration(seconds: 10));
      },
    );

    // Enable offline persistence for Firestore
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    // Firebase initialization failed - continuing in offline mode (log removed)
    // Ensure the app continues to work even if Firebase fails to initialize
  }

  await Hive.initFlutter();
  await SharedPreferences.getInstance();

  // Initialize Supabase using production defaults, with optional --dart-define
  // overrides for staging/testing. Firebase remains active for unmigrated
  // features during the migration.
  await SupabaseBootstrapService.initialize();

  // Initialize caches with timeouts and error handling - don't block startup
  _initializeCachesAsync();

  // Initialize Hive boxes for fast media upload service
  await Hive.openBox('pending_uploads');
  await Hive.openBox('local_media');

  // Initialize Hive boxes for fast profile upload service
  await Hive.openBox('pending_profile_uploads');
  await Hive.openBox('local_profile');

  // Initialize offline data service for saved items
  try {
    await OfflineDataService.instance.initialize();
  } catch (e) {}

  // Initialize offline media service for media caching
  try {
    await OfflineMediaService.instance.initialize();
  } catch (e) {
    // OfflineMediaService init failed (log removed)
  }

  // Initialize count cache service for instant count display
  try {
    await CountCacheService.instance.initialize();
  } catch (e) {
    // CountCacheService init failed (log removed)
  }

  // Initialize favorites cache with timeout
  Hive.registerAdapter(CachedFavoriteItemAdapter());
  await Hive.openBox<CachedFavoriteItem>('cached_favorites');

  // Initialize favorites service in background - don't block startup
  _initializeFavoritesServiceAsync();

  // Initialize map data cache in background - don't block startup
  _preloadMapDataAsync();

  // Initialize analytics service in background - don't block startup
  _initializeAnalyticsServiceAsync();

  // Initialize push notifications in background once Firebase is ready
  _initializeNotificationServiceAsync();

  // Note: Don't clear favorites cache on startup - let it persist for instant loading
  // The cache will be updated as favorites are added/removed
}

// Non-blocking cache initialization
void _initializeCachesAsync() {
  // Run cache initialization in background without blocking
  Future.microtask(() async {
    try {
      await ImageCacheManager().preloadSvgAssets().timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          );
    } catch (e) {
      // Image cache init failed (log removed)
    }

    try {
      await MediaCacheManager().initializeSvgCache().timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          );
    } catch (e) {
      // Media cache init failed (log removed)
    }
  });
}

// Non-blocking favorites service initialization
void _initializeFavoritesServiceAsync() {
  Future.microtask(() async {
    try {
      final favoriteService = FavoriteService();
      await favoriteService.initializeCache().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          // FavoriteService init timed out (log removed)
        },
      );
    } catch (e) {
      // FavoriteService init failed (log removed)
    }
  });
}

// Non-blocking map data preload - runs in background for instant map loading
void _preloadMapDataAsync() {
  // Map data is still Firebase-backed and is not part of the Supabase
  // Auth/Profile runtime. Avoid issuing those optional Firestore reads when
  // Supabase is the active identity/profile authority.
  if (SupabaseConfig.useSupabaseAuth) return;

  Future.microtask(() async {
    try {
      // Wait a bit to ensure Firebase auth is ready
      await Future.delayed(const Duration(milliseconds: 500));

      final mapDataCache = MapDataCacheService();
      await mapDataCache.preloadMapData().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          // Map data preload timed out (log removed)
        },
      );
    } catch (e) {
      // Map data preload failed - will load on map open (log removed)
      // Map will still work, just slower first load
    }
  });
}

// Non-blocking analytics service initialization
void _initializeAnalyticsServiceAsync() {
  Future.microtask(() async {
    try {
      await AnalyticsService.instance.initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          // AnalyticsService init timed out (log removed)
        },
      );
    } catch (e) {
      // AnalyticsService init failed (log removed)
      // Analytics will still work, just without cached data
    }
  });
}

// Non-blocking notification service initialization
void _initializeNotificationServiceAsync() {
  Future.microtask(() async {
    try {
      await NotificationService.instance.initialize().timeout(
            const Duration(seconds: 8),
            onTimeout: () => null,
          );
    } catch (e) {
      // NotificationService init failed (log removed)
    }
  });
}

void main() async {
  // Ensure all services are initialized before running the app
  await initializeAppServices();

  // Create instances of ViewModels that need to load persistent state
  final localeViewModel = LocaleViewModel();
  final themeViewModel = ThemeViewModel();
  final fastUploadViewModel = FastUploadViewModel();

  // Initialize the fast upload service with timeout - don't block startup
  try {
    await fastUploadViewModel.initialize().timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
  } catch (e) {
    // FastUploadViewModel init failed (log removed)
  }

  runApp(
    MultiProvider(
      providers: [
        // Use .value for pre-created instances
        ChangeNotifierProvider.value(value: themeViewModel),
        ChangeNotifierProvider.value(value: localeViewModel),
        ChangeNotifierProvider.value(value: fastUploadViewModel),

        // .create is fine for ViewModels without persistent state to load on start
        // IMPORTANT: AuthViewModel is created lazily when first accessed to ensure Firebase is ready
        // Use ProxyProvider to delay AuthViewModel creation until Firebase is ready
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(),
          lazy: true, // This ensures it's only created when first accessed
        ),
        // HomeViewModel must be lazy to avoid Firestore access before auth is ready
        // Password recovery must be listening before any deep link can arrive,
        // so this one is deliberately not lazy. It observes the repository's
        // existing auth pipeline and adds no second session authority.
        ChangeNotifierProvider(
          create: (_) {
            final repository = RepositoryProvider.instance.authRepository;
            return PasswordRecoveryViewModel(
              gateway: passwordCapabilityOf(repository),
              authRepository: repository,
            );
          },
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (_) => HomeViewModel(),
          lazy: true,
        ),
        ChangeNotifierProvider(
          create: (_) => SignUpViewModel(),
          lazy: true,
        ),
        ChangeNotifierProvider(
          create: (_) => MapViewViewModel(),
          lazy: true,
        ),

        // Add OptimisticFavoritesService
        ChangeNotifierProvider(
          create: (_) => OptimisticFavoritesService(),
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AuthViewModel, NotificationViewModel>(
          lazy: true,
          create: (_) => NotificationViewModel(
            repository: RepositoryProvider.instance.notificationRepository,
          ),
          update: (_, authVM, notifier) {
            notifier ??= NotificationViewModel(
              repository: RepositoryProvider.instance.notificationRepository,
            );
            // A recovery session must not start any account-scoped background
            // work. The router already keeps Home unreachable; passing null
            // here means the Realtime notification channel is never opened
            // even if some other surface were to read this provider.
            notifier.attachUser(
              authVM.isPasswordRecoveryActive ? null : authVM.currentUser?.uid,
            );
            return notifier;
          },
        ),
      ],
      child: const MyApp(),
    ),
  );
}
