// import 'dart:io';
// import 'package:broker_wallet/src/services/optimized_storage_service.dart';
// import 'package:broker_wallet/src/services/storage_performance_monitor.dart';
// import 'package:broker_wallet/src/widgets/fast_network_image.dart';
// import 'package:flutter/material.dart';

// /// Example integration showing how to upgrade existing services to use optimized storage
// ///
// /// This file demonstrates:
// /// 1. How to replace existing Firebase Storage calls with optimized versions
// /// 2. How to integrate performance monitoring
// /// 3. How to use the new image widgets
// /// 4. Best practices for different use cases

// class StorageIntegrationExamples {
//   /// Example 1: Upgrade profile image upload
//   ///
//   /// BEFORE (slow):
//   /// ```dart
//   /// final ref = FirebaseStorage.instance.ref('profile/${userId}/avatar.jpg');
//   /// await ref.putFile(imageFile);
//   /// final url = await ref.getDownloadURL();
//   /// ```
//   ///
//   /// AFTER (fast):
//   static Future<String> uploadProfileImageOptimized(File imageFile) async {
//     final bytes = await imageFile.readAsBytes();

//     // Use mutable=true for profile images since they can change
//     return await OptimizedStorageService.uploadImageFast(
//       originalBytes: bytes,
//       path: 'profile/avatar.jpg',
//       isMutable: true, // Short cache for images that might change
//       quality: 85, // Higher quality for profile photos
//       maxWidth: 800, // Reasonable size for profiles
//       maxHeight: 800,
//     );
//   }

//   /// Example 2: Upgrade property listing images with thumbnails
//   ///
//   /// BEFORE (slow):
//   /// ```dart
//   /// for (File image in images) {
//   ///   final ref = FirebaseStorage.instance.ref('offers/${offerId}/${image.name}');
//   ///   await ref.putFile(image);
//   ///   urls.add(await ref.getDownloadURL());
//   /// }
//   /// ```
//   ///
//   /// AFTER (fast with thumbnails):
//   static Future<Map<String, Map<String, String>>> uploadPropertyImagesOptimized(
//     List<File> imageFiles,
//     String offerId,
//   ) async {
//     final results = <String, Map<String, String>>{};

//     // Upload images in parallel for speed
//     final futures = imageFiles.asMap().entries.map((entry) async {
//       final index = entry.key;
//       final imageFile = entry.value;
//       final bytes = await imageFile.readAsBytes();

//       // Upload with multiple sizes for responsive loading
//       final urls = await OptimizedStorageService.uploadImageWithThumbnails(
//         originalBytes: bytes,
//         basePath: 'offers/$offerId/image_$index',
//         isMutable: false, // Property images don't change often
//         sizes: ImageSizes.propertyListing, // Predefined sizes
//       );

//       return MapEntry('image_$index', urls);
//     });

//     final uploadResults = await Future.wait(futures);

//     for (final entry in uploadResults) {
//       results[entry.key] = entry.value;
//     }

//     return results;
//   }

//   /// Example 3: Upgrade image display in list widgets
//   ///
//   /// BEFORE (inefficient):
//   /// ```dart
//   /// CachedNetworkImage(
//   ///   imageUrl: fullSizeUrl,
//   ///   fit: BoxFit.cover,
//   ///   placeholder: (context, url) => CircularProgressIndicator(),
//   /// )
//   /// ```
//   ///
//   /// AFTER (optimized for lists):
//   static Widget buildOptimizedListImage({
//     required Map<String, String> imageUrls,
//     required double size,
//     String? heroTag,
//     VoidCallback? onTap,
//   }) {
//     // Select the right size based on display context
//     final url = ImageSizeSelector.selectBestSize(
//       urls: imageUrls,
//       targetWidth: size,
//       targetHeight: size,
//       devicePixelRatio: 2.0, // Assume high-DPI display
//     );

//     return ListImageWidget(
//       url: url,
//       size: size,
//       heroTag: heroTag,
//       onTap: onTap,
//     );
//   }

//   /// Example 4: Upgrade detail view images with performance monitoring
//   ///
//   /// BEFORE (basic):
//   /// ```dart
//   /// Image.network(url, fit: BoxFit.cover)
//   /// ```
//   ///
//   /// AFTER (optimized with progressive loading):
//   static Widget buildOptimizedDetailImage({
//     required Map<String, String> imageUrls,
//     required double width,
//     required double height,
//     String? heroTag,
//     VoidCallback? onTap,
//   }) {
//     final thumbnailUrl = imageUrls['thumb640'] ?? imageUrls['thumb320'];
//     final fullUrl = imageUrls['full'] ?? imageUrls['large'];

//     return GalleryImageWidget(
//       url: fullUrl ?? thumbnailUrl ?? '',
//       thumbnailUrl: thumbnailUrl,
//       width: width,
//       height: height,
//       heroTag: heroTag,
//       onTap: onTap,
//     );
//   }

//   /// Example 5: Upgrade with performance measurement
//   ///
//   /// Wrap existing operations to measure performance:
//   static Future<String> measureAndUploadImage(
//       File imageFile, String path) async {
//     final bytes = await imageFile.readAsBytes();

//     return await StoragePerformanceMonitor.monitorUpload(
//       'Legacy Image Upload Migration',
//       () => OptimizedStorageService.uploadImageFast(
//         originalBytes: bytes,
//         path: path,
//         isMutable: false,
//       ),
//       additionalInfo: 'File: ${imageFile.path}, Size: ${bytes.length} bytes',
//     );
//   }

//   /// Example 6: Preload images for smooth scrolling
//   ///
//   /// Use in list widgets to preload images that will be visible soon:
//   static void preloadUpcomingImages(
//     BuildContext context,
//     List<Map<String, String>> imageUrlsList,
//     int currentIndex,
//   ) {
//     // Preload next 3 images
//     final upcomingUrls = <String>[];

//     for (int i = currentIndex + 1;
//         i <= currentIndex + 3 && i < imageUrlsList.length;
//         i++) {
//       final imageUrls = imageUrlsList[i];
//       final thumbnailUrl = imageUrls['thumb640'] ?? imageUrls['thumb320'];
//       if (thumbnailUrl != null) {
//         upcomingUrls.add(thumbnailUrl);
//       }
//     }

//     if (upcomingUrls.isNotEmpty) {
//       ImagePreloader.preloadImages(
//         context,
//         upcomingUrls,
//         maxConcurrent: 2, // Don't overwhelm the network
//         targetWidth: 640,
//         targetHeight: 640,
//       );
//     }
//   }

//   /// Example 7: Complete service upgrade for OfferService
//   ///
//   /// This shows how to upgrade your existing OfferService:
//   static Future<String> upgradeOfferServiceUpload({
//     required List<File> mediaFiles,
//     required String offerId,
//     BuildContext? context, // For performance monitoring
//   }) async {
//     final uploadResults = <String, dynamic>{};

//     // Upload images with thumbnails
//     if (mediaFiles.isNotEmpty) {
//       final imageUrls =
//           await uploadPropertyImagesOptimized(mediaFiles, offerId);
//       uploadResults['images'] = imageUrls;
//     }

//     // If context is available, measure complete flow performance
//     if (context != null && mediaFiles.isNotEmpty) {
//       final firstImageUrls =
//           uploadResults['images']?.values?.first as Map<String, String>?;
//       if (firstImageUrls != null) {
//         final thumbnailUrl = firstImageUrls['thumb320'] ?? '';
//         if (thumbnailUrl.isNotEmpty) {
//           await StoragePerformanceMonitor.monitorImageLoad(
//             url: thumbnailUrl,
//             context: context,
//             operationName: 'Offer Image Complete Flow',
//             targetWidth: 320,
//             targetHeight: 320,
//           );
//         }
//       }
//     }

//     return offerId;
//   }

//   /// Example 8: Avatar upload and display pattern
//   ///
//   /// Complete pattern for user avatars:
//   static Future<Map<String, String>> uploadAvatarOptimized(
//       File imageFile) async {
//     final bytes = await imageFile.readAsBytes();

//     return await OptimizedStorageService.uploadImageWithThumbnails(
//       originalBytes: bytes,
//       basePath: 'profile/avatar',
//       isMutable: true, // Avatars can change
//       sizes: ImageSizes.avatar, // Predefined avatar sizes
//     );
//   }

//   static Widget buildOptimizedAvatar({
//     Map<String, String>? imageUrls,
//     double size = 40,
//     String? initials,
//     VoidCallback? onTap,
//   }) {
//     String? url;
//     if (imageUrls != null) {
//       // Select appropriate size based on display size
//       if (size <= 50) {
//         url = imageUrls['small'];
//       } else if (size <= 100) {
//         url = imageUrls['medium'];
//       } else {
//         url = imageUrls['large'];
//       }
//     }

//     return FastAvatarWidget(
//       url: url,
//       size: size,
//       initials: initials,
//       onTap: onTap,
//     );
//   }
// }

// /// Migration checklist for existing services:
// ///
// /// 1. Replace FirebaseStorage.instance.ref().putFile() calls with OptimizedStorageService.uploadImageFast()
// /// 2. Add compression and proper cache headers using the new service
// /// 3. Generate thumbnails for images that will be displayed in lists
// /// 4. Replace CachedNetworkImage widgets with FastNetworkImage or specialized widgets
// /// 5. Add performance monitoring to measure improvements
// /// 6. Use ImagePreloader for smooth scrolling experiences
// /// 7. Update data models to store multiple image sizes
// /// 8. Implement progressive loading (thumbnail → full image)
// ///
// /// Performance targets after migration:
// /// - Upload time: < 2 seconds for typical images
// /// - First image display: < 500ms for thumbnails
// /// - List scrolling: No frame drops with proper preloading
// /// - Cache hit rate: > 90% for frequently accessed images
// ///
// /// Example data model update:
// /// ```dart
// /// class PropertyModel {
// ///   // BEFORE:
// ///   // List<String> imageUrls;
// ///
// ///   // AFTER:
// ///   Map<String, Map<String, String>> images; // imageId -> sizeMap
// ///   // e.g., {
// ///   //   'image_0': {'thumb320': 'url1', 'thumb640': 'url2', 'full': 'url3'},
// ///   //   'image_1': {'thumb320': 'url4', 'thumb640': 'url5', 'full': 'url6'},
// ///   // }
// /// }
// /// ```
