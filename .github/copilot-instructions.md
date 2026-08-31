# Broker Wallet - AI Coding Agent Instructions

## Project Overview
Real estate toolkit app for property professionals. Flutter/Dart mobile app with Firebase backend (Firestore, Auth, Storage, Cloud Functions) supporting offline-first workflows, quota management, and bilingual UI (English/Arabic with RTL).

## Architecture Patterns

### MVVM with Provider State Management
- **ViewModels**: Extend `ChangeNotifier`, manage business logic and state
- **Provider Pattern**: Use `ChangeNotifierProvider` for scoped state, `ChangeNotifierProvider.value` for pre-initialized instances (see `main.dart` lines 216-238)
- **Lazy vs Eager**: `AuthViewModel`, `SignUpViewModel`, `MapViewViewModel` are lazy-loaded to ensure Firebase readiness
- **Access Pattern**: `Provider.of<T>(context, listen: false)` for one-time reads, `Consumer<T>` or `context.watch<T>()` for reactive updates

### Offline-First Design Philosophy
**Critical**: Every feature must work offline before syncing to cloud

#### Offline Services Architecture
```dart
// 1. Hive for local persistence (see main.dart lines 85-115)
await Hive.openBox('pending_uploads');        // Media upload queue
await Hive.openBox('local_media');            // Local media storage
await Hive.openBox('pending_profile_uploads'); // Profile upload queue
Hive.registerAdapter(CachedFavoriteItemAdapter());
await Hive.openBox<CachedFavoriteItem>('cached_favorites');

// 2. Key Offline Services (initialized in main.dart)
OfflineDataService.instance    // Saved items cache
OfflineMediaService.instance   // Media file caching with local:// URLs
OfflineImageService           // Image error handling
CountCacheService.instance    // Instant count display
```

#### Fast Media Upload Pattern (see `fast_media_upload_service.dart`)
```dart
// Immediate local save (~1s) + background upload
// 1. Save files locally with temp URLs (local://docId/media_0.jpg)
// 2. Map temp URLs via OfflineMediaService for instant UI display
// 3. Save basic Firestore doc immediately
// 4. Queue background upload to Firebase Storage
// 5. Update doc with real URLs when complete
// 6. Emit UploadCompletedEvent for UI updates
```

### Server-Side Quota System
**All quota-enforced item creation MUST use `QuotaService`** (see `quota_service.dart` and `functions/README.md`)

```dart
// CORRECT: Server-enforced with idempotency
final result = await QuotaService().addItem(
  section: 'offers',           // offers, requests, owners, offices, tools, quotations
  payload: data,               // Your item data (do NOT include ownerId, createdAt, etc.)
  idempotencyToken: uuid.v4(), // Prevents duplicates on retry
);

// WRONG: Direct Firestore write bypasses quota
await FirebaseFirestore.instance.collection('users/$uid/offers').add(data); // ❌ FORBIDDEN
```

**Quota Limits**: Free plan = 5 items/section (30 total), Premium = unlimited
**Cloud Function**: `addItemWithQuota` (Node.js, Firebase Functions v2, us-central1)
**Error Handling**: Catch `QuotaExceededException` → show upgrade dialog

### Firestore Security Rules Pattern
```javascript
// Client can read/update but NOT modify 'counts' field (server-managed)
allow update: if isOwner(userId) 
  && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['counts']);

// Quota sections (offers, requests, etc.) are SERVER-ONLY writes
allow write: if false; // Must use Cloud Functions
```

### Localization & RTL Support
- **Preload Strategy**: `AppLocalizations.preloadAllLanguages()` runs async at startup (see `main.dart` line 17-24)
- **Cache-First**: Uses `_cachedStrings` for instant language switching
- **ARB Files**: `lib/src/common/localization/app_{en|ar}.arb`
- **RTL Detection**: `isRTL = locale.languageCode == 'ar'` in `app.dart`
- **Global Directionality**: Applied via `MaterialApp.builder` wrapper (see `app.dart` lines 151-161)

### Navigation Architecture (GoRouter)
- **Shell Routing**: `StatefulShellRoute.indexedStack` for bottom nav tabs (home, search, favorites, profile)
- **Auth Redirect**: `AuthViewModel` as `refreshListenable`, redirects protected routes to `/welcome`
- **Phone OTP Pattern**: Uses `PhoneOtpArgs` passed via `state.extra` (see `app.dart` lines 134-152)
- **Debug Navigation**: Look for `print('🔀 Router redirect check:')` logs in auth flows
- **Fade Transitions**: `CustomTransitionPage` with 150ms fade for tab switches

### Firebase Initialization Pattern
```dart
// Timeout-aware init for offline scenarios (main.dart lines 54-70)
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
  .timeout(Duration(seconds: 10), onTimeout: () {
    print('⚠️ Firebase initialization timed out, continuing offline');
    throw TimeoutException('Firebase init timeout');
  });

// Enable unlimited offline cache
FirebaseFirestore.instance.settings = Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);
```

## Code Conventions

### Emoji Logging System
Use consistent emoji prefixes for log statements:
- `🚀` Starting operation
- `✅` Success/completion
- `⚠️` Warning/degraded mode
- `❌` Error/failure
- `📁` File operation
- `💾` Data save
- `🔀` Navigation/routing
- `🔥` Firebase operation

### File Organization
```
lib/src/
├── Views/Screens/       # UI screens (not "views" - these ARE the views)
│   ├── Sign-Up-Log-In/  # Auth flows
│   ├── ViewAdd/         # Create/edit forms (AddOffersView, AddRequestedView, etc.)
│   ├── ViewDetails/     # Detail pages (OffersDetailsView, etc.)
│   ├── ViewLists/       # List screens (OffersListView, etc.)
│   └── home/            # Main app sections (Profile/, Toolkit/, map/, search/, favorites/)
├── viewmodels/          # MVVM view models (business logic)
├── services/            # Standalone services (offline, auth, quota, media)
├── data/models/         # Data models (ScreensModel/ for domain entities)
├── common/              # Shared utilities (localization/, themes/, routes/, enums/)
└── widgets/             # Reusable UI components
```

### Naming Conventions
- **ViewModels**: `{Feature}ViewModel` extends `ChangeNotifier` (e.g., `AddOffersViewModel`)
- **Services**: `{Feature}Service` (e.g., `QuotaService`, `OfflineMediaService`)
- **Models**: `{Entity}Model` (e.g., `OfferModel`, `BrokerModel`, `RequestModel`)
- **Views**: `{Feature}View` (e.g., `OffersDetailsView`, `AddRequestedView`)
- **Enums**: `Add{Entity}Mode` for edit/add states (see `lib/src/common/enums/`)

### Critical Development Patterns

#### 1. Media Upload Flow
```dart
// ALWAYS use FastMediaUploadService for media-heavy operations
final uploadService = FastMediaUploadService();
final docId = await uploadService.saveDataWithMedia(
  data: itemData,
  mediaFiles: selectedFiles,
  collection: 'offers',    // or requests, owners, etc.
  documentId: existingId,  // null for new docs
);

// Listen for background completion
FastMediaUploadService.onUploadCompleted.listen((event) {
  if (event.documentId == myDocId) {
    // Update UI with real Firebase URLs
  }
});
```

#### 2. Provider Initialization Order
```dart
// Pre-initialized instances (.value) for persistent state
ChangeNotifierProvider.value(value: themeViewModel),
ChangeNotifierProvider.value(value: localeViewModel),
ChangeNotifierProvider.value(value: fastUploadViewModel),

// Lazy instances (.create) for Firebase-dependent services
ChangeNotifierProvider(create: (_) => AuthViewModel(), lazy: true),
```

#### 3. Async Initialization Pattern
```dart
// Non-blocking background initialization (see main.dart)
void _initializeCachesAsync() {
  Future.microtask(() async {
    try {
      await SomeCache().init().timeout(Duration(seconds: 5), 
        onTimeout: () => print('⚠️ Cache init timed out'));
    } catch (e) {
      print('⚠️ Cache init failed: $e');
      // App continues without cache
    }
  });
}
```

## Build & Deployment

### Flutter Commands
```bash
# Run app with verbose logging
flutter run --verbose

# Build Android APK
flutter build apk --release

# Build iOS (macOS only)
flutter build ios --release

# Generate launcher icons
flutter pub run flutter_launcher_icons

# Code generation (Hive adapters)
flutter pub run build_runner build --delete-conflicting-outputs
```

### Firebase Deployment
```bash
# Deploy Cloud Functions
cd functions && firebase deploy --only functions

# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy Storage rules
firebase deploy --only storage

# View function logs
firebase functions:log --only addItemWithQuota --tail
```

### Platform-Specific Config
- **Android**: `android/build.gradle` - AGP 8.6.1, Kotlin 2.1.0
- **iOS**: Requires macOS with Xcode
- **Firebase**: `firebase.json` - Firestore in `australia-southeast1`
- **Gradle**: Uses wrapper (`gradlew.bat` on Windows, `./gradlew` on Unix)

## Common Pitfalls & Solutions

### ❌ Direct Firestore Writes on Quota Sections
```dart
// WRONG - bypasses quota
await FirebaseFirestore.instance.collection('users/$uid/offers').add(data);

// CORRECT - enforced by server
await QuotaService().addItem(section: 'offers', payload: data);
```

### ❌ Modifying Server-Managed Fields
```dart
// WRONG - 'counts' is server-only
userDoc.update({'counts.offers': newCount});

// CORRECT - let Cloud Functions manage counts
// Counts update automatically when using QuotaService.addItem()
```

### ❌ Not Handling Offline Mode
```dart
// WRONG - crashes offline
final doc = await FirebaseFirestore.instance.doc('path').get();
final data = doc.data();

// CORRECT - check cache first
final cachedData = OfflineDataService.instance.getCachedSavedItems(userId);
if (cachedData.isNotEmpty) {
  // Use cached data
} else {
  // Try fetching from Firestore
}
```

### ❌ Blocking App Startup
```dart
// WRONG - delays app launch
await SomeService().initialize(); // 3+ seconds

// CORRECT - run in background
_initializeServiceAsync(); // Returns immediately
```

### ⚠️ Video Compression Note
Video compression is **backend-only** due to Android Gradle Plugin (AGP) 8.6+ compatibility issues. `light_compressor` and `better_player` are removed. Use `VideoCompressionService` which delegates to backend.

## Testing Guidance

### Manual Testing Checklist
- [ ] Test offline mode: Enable airplane mode, verify cached data loads
- [ ] Test quota limits: Create 5 items as free user, verify 6th shows upgrade dialog
- [ ] Test language switch: Toggle English ↔ Arabic, verify RTL layout and instant switching
- [ ] Test media upload: Add item with photos/videos, verify local display → background upload
- [ ] Test auth flow: Sign up → email verify → phone OTP → home redirect

### Firebase Emulator Testing
```bash
# Start emulators (Firestore, Auth, Functions, Storage)
firebase emulators:start

# Run functions tests
cd functions && npm test
```

## App Features & Screen Architecture

### Core Screens (Bottom Navigation Tabs)

#### 1. Home (`home_view.dart`)
- **Grid Dashboard**: Shows all property categories (Offers, Requests, Owners, Offices, Brokers, Watchmen, Tools, Quotations)
- **Filter System**: `HomeFilterChips` for quick category filtering
- **Instant Count Display**: Uses `CountCacheService` for responsive counts without waiting for Firestore
- **Smart Refresh**: Pull-to-refresh updates counts from server
- **Profile Header**: Shows user avatar (offline-aware image loading) + display name

#### 2. Search (`search_view.dart`)
- **Universal Search**: Searches across all item types (offers, requests, owners, etc.)
- **Animated Hints**: Rotating localized search suggestions
- **Filter Chips**: Category-specific filtering (requests, offers, owners, offices, brokers, watchmen)
- **Optimized Scrolling**: `cacheExtent: 1400` for silky-smooth performance
- **Sticky Filters**: `SliverAppBar` with pinned filters during scroll
- **Empty State**: Custom `EmptyState` widget for no results

#### 3. Favorites (`favorites_view.dart`)
- **Optimistic Updates**: `OptimisticFavoritesService` for instant UI feedback (toggle favorite without waiting)
- **Offline Support**: `FavoriteService` with Hive caching (`cached_favorites` box)
- **Smart Filtering**: 7 filter chips (Recently Added, Requests, Offers, Owners, Offices, Watchmen, Brokers)
- **Filter Logic**: `toggleFilter()` in ViewModel - can select multiple filters simultaneously
- **Sync Status Chip**: Animated indicator showing "Syncing..." or "Synced" with checkmark
- **Cache Strategy**: Persist favorites locally, sync in background via `_refreshThrottleTimer`
- **Pull-to-Refresh**: Syncs with server while showing cached data (no blank screen)
- **Gradient Background**: Subtle gradient from surface to scaffold background
- **Empty States**: Different messages for "no favorites" vs "no results for filter"
- **Optimized Grid**: Uses `_OptimizedFavoritesGrid` with `cacheExtent: 1200` for smooth scrolling
- **Favorite Card**: Shows thumbnail, title, type badge, date - taps navigate to detail view

#### 4. Map View (`map_view.dart`)
- **Google Maps Integration**: Full-featured property map with custom markers (`GoogleMap` widget)
- **Real-Time Listeners**: Live Firestore snapshots for instant marker updates
- **Location Filters**: 5 filter buttons (All, Offers, Owners, Offices, Watchmen) with `LocationFilter` enum
- **Filter Toggle**: `setFilter()` method - multi-select enabled, updates `filteredMarkers` in real-time
- **Custom Markers**: Color-coded pins by location type via `LocationColors.getColor()`
- **Marker Icons**: Custom `BitmapDescriptor` for each type (created from assets)
- **Search Bar**: Geocoding-based address search with `locationFromAddress()` - animates camera to result
- **Expandable Legend**: Floating card showing location type colors, counts, and filter chips
- **Permission Handling**: Requests location permission post-frame, graceful fallback if denied
- **My Location**: Blue dot shows user location if permission granted (`myLocationEnabled: true`)
- **Map Cache**: `MapDataCacheService` preloads map data during app startup (see `main.dart`)
- **Marker Tap**: Opens detail view by fetching full entity data via service (e.g., `OfferService().getOffer()`)
- **Toast Notifications**: Success/error toasts for search results and navigation
- **Map Types**: Support for normal, satellite, terrain (configurable in ViewModel)
- **Camera Controls**: Programmatic camera animation via `animateToLocation()`

#### 5. Profile (`profile_view.dart`)
- **User Info Card**: Avatar (offline-aware), display name, email with edit button
- **Profile Picture**: Shows `profileImageUrl` from user doc, falls back to avatar placeholder
- **Settings Tiles**: Using custom `SettingsTile` widget with SVG icons
- **Language Settings**: Navigate to `/language` - instant switch between English/Arabic with RTL
- **Theme Toggle**: Switch between light/dark mode with live preview (managed by `ThemeViewModel`)
- **Notifications Toggle**: Enable/disable push notifications (stored in user preferences)
- **Subscription Card**: 
  - Shows "Free Plan" with "Upgrade to Premium" badge OR
  - Shows "⭐ Premium - MONTHLY/YEARLY" with check icon
  - Displays current plan status from `UserModel.subscription.plan`
  - Navigate to `/subscription` for upgrade flow
- **My Plan**: Navigate to `/my-plan` - shows quota usage across all sections
- **Feedback**: Navigate to `/feedback` - submit app feedback
- **Share App**: Share via social media using `share_plus` package
- **Sign Out**: Logout with confirmation dialog via `ProfileViewModel.logout()`
- **Loading State**: Shows spinner while fetching user data from Firestore
- **Scroll Behavior**: Bouncing physics for smooth scrolling experience

### Data Management Screens

#### List Views (`ViewLists/`)
All follow consistent pattern with ViewModel-driven architecture:
- **Offers List** (`offers_list_view.dart`) - Property listings for sale/rent
- **Requests List** (`requests_list_view.dart`) - Property search requests
- **Owners List** (`owners_list_view.dart`) - Property owner contacts
- **Offices List** (`offices_list_view.dart`) - Real estate office contacts
- **Brokers List** (`brokers_list_view.dart`) - Broker contacts
- **Watchmen List** (`watchmen_list_view.dart`) - Security/watchmen contacts
- **Quotation List** (`list_quotation_view.dart`) - Generated property quotations

**Common List Features**:
- Paginated loading with scroll detection
- Pull-to-refresh
- Empty state handling
- Search/filter capability
- Offline-aware image loading
- Swipe-to-delete (with undo option)

#### Add/Edit Views (`ViewAdd/`)
All use `Add{Entity}Mode` enum (add/edit) and ViewModels:
- **Add Offers** (`add_offers_view.dart`) - Property listings with media, location picker
- **Add Requests** (`add_requested_view.dart`) - Property search criteria
- **Add Owners** (`add_owners_view.dart`) - Owner contact info + properties
- **Add Offices** (`add_offices_view.dart`) - Office details + location
- **Add Brokers** (`add_brokers_view.dart`) - Broker contact + portfolio
- **Add Watchmen** (`add_watchmen_view.dart`) - Watchmen contact + assigned properties
- **Add Quotation** (`add_quotation_view.dart`) - Professional property quotations with PDF export

**Common Add/Edit Patterns**:
- **Mode Detection**: Check `isEditMode` to show "Save" vs "Update"
- **Delayed Spinner**: Only show loading if data takes >500ms (prevents flicker)
- **Prefill Forms**: `_prefillFormWith{Entity}()` for edit mode
- **Media Management**: `FastMediaUploadService.saveDataWithMedia()` for instant local save
- **Location Picker**: `LocationCapableViewModel` interface + `PickupLocationWidget`
- **Phone Validation**: `PhoneInputService` for international format conversion
- **Media Removal**: Track `_removedMediaUrls` separately, remove via `removeMediaUrls()`
- **Validation**: Form-level validation before submission

#### Detail Views (`ViewDetails/`)
All follow consistent media-rich detail pattern:
- **Offers Details** (`offers_view_details.dart`) - Full property details + media gallery
- **Request Details** (`requested_view_details.dart`) - Request criteria + contact info
- **Owners Details** (`owners_view_details.dart`) - Owner profile + owned properties
- **Offices Details** (`offices_view_details.dart`) - Office info + agents
- **Brokers Details** (`brokers_view_details.dart`) - Broker profile + portfolio
- **Watchmen Details** (`watchmen_view_details.dart`) - Watchmen info + assignments

**Common Detail Features**:
- **Favorite Button**: `OptimizedFavoriteButton` with optimistic updates via `OptimisticFavoritesService`
- **Media Gallery**: `MediaGalleryWidget` with image/video preview, fullscreen viewer
- **Share Options**: `ShareOptionsDialog` - WhatsApp, Email, SMS, LinkedIn, etc.
- **Upload Completion Listener**: Subscribe to `FastMediaUploadService.onUploadCompleted` to update UI when background uploads finish
- **Action Buttons**: Call, WhatsApp, Email, Navigate (via `url_launcher`)
- **Edit/Delete**: Contextual actions based on ownership
- **Offline Media**: `OfflineMediaService.buildOfflineAwareImage()` for cached images

### Toolkit Features (`home/Toolkit/`)

#### Document Scanner (`scanner_view.dart`)
- **Camera Integration**: `flutter_doc_scanner` for document capture
- **Edge Detection**: Auto-detects document boundaries
- **Multi-Page Support**: Scan multiple pages into single PDF
- **Image Processing**: Crop, rotate, adjust contrast
- **Export**: Save as PDF or images

#### Signature Tool (`signature/signature_view.dart`)
- **Digital Signature**: `hand_signature` package for smooth drawing
- **Multiple Formats**: Export as PNG, SVG, or embedded in PDF
- **Document Integration**: Add signatures to scanned documents
- **Signature Library**: Save frequently used signatures

#### Image to PDF (`image_to_pdf_view.dart`)
- **Batch Conversion**: Convert multiple images to single PDF
- **Reordering**: Drag-and-drop page arrangement
- **Settings**: Page size, orientation, margins, compression
- **Preview**: See final PDF before saving
- **Advanced Options**: `_AdvancedSettingsSheet` for quality control

#### PDF Combiner (`combine_pdfs_view.dart`)
- **Merge PDFs**: Combine multiple PDF files
- **Page Selection**: Choose specific pages from each PDF
- **Reorder Pages**: Drag-and-drop interface
- **Preview**: `PdfViewerScreen` integration

#### UAE Links (`uae_links_view.dart`)
- **Quick Links**: Government services, utilities, real estate portals
- **Categorized**: Organized by service type
- **Deep Linking**: Opens URLs in browser or app

### Authentication Flow (`Sign-Up-Log-In/`)

1. **Welcome View** (`welcome_view.dart`) - Entry point with sign up/sign in options
2. **Sign Up View** (`signup_view.dart`) - Email/password registration + social auth (Google, Facebook)
3. **Email Verification** (`email_verification_view.dart`) - Email confirmation with resend option
4. **Phone OTP** (`phone_otp_view.dart`) - SMS verification with auto-detect (uses `smart_auth`)
5. **Sign In View** (`login_view.dart`) - Email/password + social login
6. **Auth Wrapper** (`auth_wrapper.dart`) - Auth state listener, redirects to home or welcome

**Auth Features**:
- **Firebase Auth**: Email/password, Google, Facebook, Phone
- **Auto OTP Detection**: `smart_auth` fills OTP automatically
- **Resend Timers**: Countdown before allowing resend
- **Offline Auth**: `OfflineAuthService` caches last logged-in user
- **Navigation**: Uses `PhoneOtpArgs` passed via `state.extra` in router

### Profile Management (`home/Profile/`)

#### Edit Profile (`edit_profile_view.dart`)
- **Profile Photo**: Camera/gallery picker, instant upload with FastMediaUploadService
- **Form Fields**: Display name, email (read-only), phone number with validation
- **Save Changes**: Updates Firestore user document with optimistic UI
- **Avatar Preview**: Shows current photo with option to change
- **Validation**: Real-time form validation before allowing save

#### Language Selector (`language_view.dart`)
- **Language Options**: English and Arabic with native script display
- **Instant Switch**: Changes app-wide language immediately via `LocaleViewModel`
- **RTL Layout**: Automatically flips layout direction for Arabic
- **Checkmark Indicator**: Shows currently selected language
- **Cached Strings**: Uses preloaded localization for instant switching (no reload)

#### Subscription Plans (`subscription_view.dart`)
- **Plan Cards**: Monthly (15 AED/month) and Yearly (120 AED/year, save 33%)
- **Recommended Badge**: Yellow badge on yearly plan
- **Plan Selection**: Toggle between monthly/yearly with visual feedback
- **Feature List**: Shows included features (unlimited properties, priority support, export reports)
- **Subscribe Button**: Navigates to payment selection or processes upgrade
- **Test Mode**: Debug toggle for testing subscription flow without payment
- **Loading State**: Disables button during subscription processing

#### My Plan View (`my_plan_view.dart`)
- **Plan Status Card**: Shows current plan (Free/Premium) with total quota usage
- **Progress Bars**: Visual quota usage per section (offers, requests, owners, etc.)
- **Section Breakdown**: 7 main sections + 4 toolkit tools with individual counts
- **Quota Display**: "X / 5" for free plan, "X / Unlimited" for premium
- **Real-Time Updates**: Stream from Firestore `users/{uid}` for live counts
- **Color Coding**: Green for safe, amber for warning, red for limit reached
- **Lifetime Stats**: Shows total items created across all time (separate from current quota)
- **Upgrade CTA**: Prominent button if on free plan approaching limits

#### Payment Selection (`payment_selection_view.dart`)
- **Payment Methods**: Credit Card, PayPal, Apple Pay, Google Pay (UI only)
- **Plan Summary**: Shows selected plan price and billing cycle
- **Secure Badge**: Visual trust indicators for payment security
- **Process Payment**: Navigates to payment gateway (placeholder)

#### Share App (`share_app_view.dart`)
- **Social Sharing**: WhatsApp, Email, SMS, LinkedIn, Twitter, Facebook
- **Referral System**: Generate and share referral codes (future feature)
- **App Store Links**: Share direct download links
- **Custom Message**: Pre-filled share text with app benefits

#### Feedback (`feedback_view.dart`)
- **Rating Widget**: Star rating system (1-5 stars)
- **Feedback Form**: Multi-line text input for detailed feedback
- **Category Selection**: Bug Report, Feature Request, General Feedback
- **Submit Handler**: Sends to Firestore feedback collection
- **Success Dialog**: Confirmation after successful submission
- **Email Integration**: Optional email follow-up via `FeedbackService`

### Quotation System (`home/quotation/`)

#### Add Quotation (`add_quotation_view.dart`)
- **Professional Quotations**: Multi-section form for property quotation generation
- **Collapsible Sections**: `_CollapsibleSection` widgets for:
  - General Information (title, type, parking, dates)
  - Property Details (owner name, location, area, rooms, bathrooms)
  - Owner Information (name, phone, email)
  - Pricing Details (rent, maintenance, security deposit, agency fees)
  - Downpayments Table (payment method, number, date, amount per installment)
  - Terms & Conditions (customizable multi-line text)
- **Smart Date Pickers**: `_SmartDatePickerField` for start/end dates
- **Payment Methods Enum**: Cash, Cheque, Bank Transfer, Other (see `PaymentMethod` in `quotation_model.dart`)
- **Logo Upload**: Optional company logo for professional PDF branding
- **Save/Preview Flow**: Save to Firestore → Generate PDF → Preview → Share
- **QuotationService**: `saveQuotationWithMediaFast()` for logo upload
- **PDF Generation**: Uses `syncfusion_flutter_pdf` to create professional PDFs
- **Validation**: Comprehensive form validation before save

#### List Quotations (`list_quotation_view.dart`)
- **Quotation Cards**: Grid/list view of saved quotations
- **Stream Updates**: Real-time Firestore stream via `getUserQuotations()`
- **Quick Actions**: View, Edit, Delete, Share PDF
- **Empty State**: Shows when no quotations exist
- **Swipe-to-Delete**: Long-press or swipe gesture to delete quotation
- **Navigation**: Tap to view full quotation details or edit

#### Quotation Model (`quotation_model.dart`)
- **Comprehensive Data**: 265 lines covering all quotation fields
- **Nested Structures**: `DownpaymentItem` class for payment installments
- **Enums**: `PaymentMethod`, `WelcomeMessageMode` for PDF customization
- **Firestore Mapping**: `toMap()` and `fromMap()` for serialization
- **Date Handling**: Converts between `DateTime` and Firestore `Timestamp`

### Reusable Widgets (`lib/src/widgets/` & `lib/src/Views/Widgets/`)

**Critical Widgets**:
- `quota_aware_section_page.dart` - Wraps screens requiring quota enforcement
- `favorite_button.dart` - Optimistic favorite toggle
- `media_picker_dialog.dart` - Choose images/videos/files
- `unified_media_preview_grid.dart` - Display media with delete/reorder
- `universal_media_viewer.dart` - Fullscreen image/video viewer
- `pickup_location_widget.dart` - Map-based location picker
- `empty_state.dart` - Consistent "no data" UI
- `notification_icon.dart` - Notification bell with badge
- `quota_status_card.dart` - Shows remaining quota

## Screen Services (`lib/src/services/ScreenServices/`)

Each entity has dedicated service for Firestore operations:
- `offer_service.dart` - CRUD for offers + `saveOfferWithMediaFast()`
- `request_service.dart` - CRUD for requests
- `owner_service.dart` - CRUD for owners + media handling
- `office_service.dart` - CRUD for offices
- `broker_service.dart` - CRUD for brokers
- `watchmen_service.dart` - CRUD for watchmen

**Common Service Pattern**:
```dart
class OfferService {
  final FastMediaUploadService _fastUploadService = FastMediaUploadService();
  
  Future<String> saveOfferWithMediaFast({
    required OfferModel offer,
    required List<File> mediaFiles,
    String? offerId,
  }) async {
    final docId = await _fastUploadService.saveDataWithMedia(
      data: offerData,
      mediaFiles: mediaFiles,
      collection: 'offers',
      documentId: offerId,
    );
    return docId;
  }
}
```

## Key Files Reference
- **Main Entry**: `lib/main.dart` - Service initialization, Provider setup
- **Router**: `lib/app.dart` - GoRouter config, auth guards, shell navigation
- **Quota Logic**: `lib/src/services/quota_service.dart` + `functions/index.js`
- **Offline Media**: `lib/src/services/fast_media_upload_service.dart`
- **Localization**: `lib/src/common/localization/localization_delegate.dart`
- **Firestore Rules**: `firestore.rules` - Security model documentation
- **Cloud Functions**: `functions/README.md` - Comprehensive quota system guide
- **Home ViewModel**: `lib/src/viewmodels/home_viewmodel.dart` - Dashboard state
- **Search ViewModel**: `lib/src/Views/Screens/home/search/search_viewmodel.dart` - Search logic
- **Map ViewModel**: `lib/src/Views/Screens/home/map/map_viewmodel.dart` - Map state + markers

## When Adding New Features

1. **Offline First**: Implement local caching before cloud sync
2. **Quota Aware**: Use `QuotaService` if creating user data (offers, requests, owners, offices, tools, quotations)
3. **Localized**: Add strings to both `app_en.arb` and `app_ar.arb`
4. **RTL Compatible**: Test Arabic layout, avoid hardcoded left/right
5. **Provider Pattern**: Create ViewModel for complex state, use ChangeNotifier
6. **Logging**: Use emoji prefixes for consistent debugging
7. **Error Handling**: Wrap Firebase calls in try-catch with offline fallback
8. **Background Init**: Don't block `main()` - use `Future.microtask` for heavy tasks
9. **Media Upload**: Use `FastMediaUploadService.saveDataWithMedia()` for instant local save + background upload
10. **Favorites**: Integrate `OptimisticFavoritesService` for instant UI feedback
11. **List/Detail Pattern**: Follow existing `{Entity}ListView` → `{Entity}DetailsView` → `Add{Entity}View` structure
12. **Screen Services**: Create dedicated `{entity}_service.dart` for Firestore CRUD operations
13. **Mode Enums**: Use `Add{Entity}Mode.add|edit` for create/update screens
