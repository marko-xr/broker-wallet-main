import 'dart:async';
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as path;

import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/fast_media_upload_service.dart';

class QuotationService {
  // Use lazy getters to avoid accessing Firebase before initialization
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String? get _currentUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;
  static const String _collectionName = 'users';

  // Generate new quotation ID without saving (for file uploads)
  String generateNewQuotationId() {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('quotations')
        .doc()
        .id;
  }

  // Save quotation with existing ID
  Future<String?> saveQuotation(QuotationModel quotation,
      {String? quotationId}) async {
    try {
      if (_currentUserId == null) {
        throw Exception('User not authenticated');
      }

      final String docId = quotationId ?? generateNewQuotationId();

      await _firestore
          .collection(_collectionName)
          .doc(_currentUserId!)
          .collection('quotations')
          .doc(docId)
          .set(
            quotation
                .copyWith(
                  id: docId,
                  userId: _currentUserId!,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                )
                .toFirestore(),
          );

      return docId;
    } catch (e) {
      // Error saving quotation - suppressed debug log
      rethrow;
    }
  }

  // Fast save method for quotations with media
  Future<String> saveQuotationWithMediaFast(
    QuotationModel quotation,
    List<File> logoFiles,
  ) async {
    try {
      if (_currentUserId == null) {
        throw Exception('User not authenticated');
      }

      final String quotationId = generateNewQuotationId();
      // Fast save quotation - generated ID (log suppressed)

      // Create data for FastMediaUploadService (no Timestamp objects)
      final quotationData = {
        'id': quotationId,
        'userId': _currentUserId!,
        'propertyTitle': quotation.propertyTitle,
        'propertyType': quotation.propertyType,
        'parking': quotation.parking,
        'subtitle': quotation.subtitle,
        'date': quotation.date,
        'startDate': quotation.startDate,
        'endDate': quotation.endDate,
        'currencyCode': quotation.currencyCode,
        'professionalFee': quotation.professionalFee,
        'totalAmount': quotation.totalAmount,
        'numberOfInstallments': quotation.numberOfInstallments,
        'paymentType': quotation.paymentType,
        'insuranceAmount': quotation.insuranceAmount,
        'insuranceReturnable': quotation.insuranceReturnable,
        'customNote': quotation.customNote,
        'welcomeMessageMode': quotation.welcomeMessageMode.asString,
        'customWelcomeMessage': quotation.customWelcomeMessage,
        'downpayments': quotation.downpayments
            .map((e) => {
                  'method': e.method.asString,
                  'number': e.number,
                  'date': e.date?.toIso8601String(), // Convert to ISO string
                  'amount': e.amount,
                })
            .toList(),
        'governmentFees': quotation.governmentFees.toMap(),
        'administrativeFees': quotation.administrativeFees.toMap(),
        'officeName': quotation.officeName,
        'pdfUrl': quotation.pdfUrl,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      };

      // Use FastMediaUploadService for proper logo upload
      final FastMediaUploadService _fastUploadService =
          FastMediaUploadService();
      final docId = await _fastUploadService.saveDataWithMedia(
        data: quotationData,
        mediaFiles: logoFiles,
        collection: 'quotations',
        documentId: quotationId,
      );

      // Wait a moment for the upload to start, then update officeLogoUrl from mediaUrls
      await _updateOfficeLogoUrlFromMediaUrls(quotationId);

      // Fast save quotation completed (log suppressed)
      return docId;
    } catch (e) {
      // Error in fast save quotation - suppressed debug log
      rethrow;
    }
  }

  /// Custom media upload for quotations that updates officeLogoUrl instead of mediaUrls

  /// Save media files locally
  /// Background upload for quotation logos
  Future<void> _uploadQuotationLogosInBackground(String quotationId) async {
    try {
      // Starting background logo upload for quotation (log suppressed)

      final pendingBox = await Hive.openBox('pending_uploads');
      final localBox = await Hive.openBox('local_media');

      final pendingData = pendingBox.get(quotationId);
      if (pendingData == null) {
        // No pending data found for quotation (log suppressed)
        return;
      }

      // Found pending data for quotation (log suppressed)

      // Upload logo files to Firebase Storage
      List<String> firebaseUrls = [];
      final logoFilePaths = List<String>.from(pendingData['logoFiles'] ?? []);

      // Found ${logoFilePaths.length} logo files to upload (log suppressed)

      for (int i = 0; i < logoFilePaths.length; i++) {
        final file = File(logoFilePaths[i]);
        if (await file.exists()) {
          // Uploading logo (log suppressed)
          final url = await _uploadLogoToFirebaseStorage(file, quotationId, i);
          firebaseUrls.add(url);

          // Map the Firebase URL to the local file for offline access
          await OfflineMediaService.instance
              .mapUrlToLocalFile(url, logoFilePaths[i]);
          // Uploaded logo (log suppressed)
        } else {
          // Logo file not found (log suppressed)
        }
      }

      // Update Firestore with final logo URL
      if (firebaseUrls.isNotEmpty) {
        // Updating Firestore with Firebase logo URL (log suppressed)
        await _firestore
            .collection('users')
            .doc(pendingData['userId'])
            .collection('quotations')
            .doc(quotationId)
            .update({
          'officeLogoUrl':
              firebaseUrls.first, // Use first logo as main office logo
          'status': 'synced',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Update local data with final URL
        final localData = localBox.get(quotationId);
        if (localData != null) {
          localData['status'] = 'synced';
          localData['officeLogoUrl'] = firebaseUrls.first;
          await localBox.put(quotationId, localData);
          // Updated local data with Firebase URL (log suppressed)
        }
      }

      // Clean up pending upload
      await pendingBox.delete(quotationId);
      // Quotation logo upload completed (log suppressed)
      // Final logo URL: ${firebaseUrls.isNotEmpty ? firebaseUrls.first : 'None'} (log suppressed)
    } catch (e) {
      // Error uploading quotation logos (log suppressed)
      // Don't rethrow - this is a background operation
    }
  }

  /// Upload logo to Firebase Storage
  Future<String> _uploadLogoToFirebaseStorage(
      File file, String quotationId, int index) async {
    try {
      final fileName = 'logo_$index${path.extension(file.path)}';
      final ref = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(_currentUserId!)
          .child('quotations')
          .child(quotationId)
          .child('logos')
          .child(fileName);

      // Uploading ${file.path} to Firebase Storage (log suppressed)
      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      // Upload completed (log suppressed)
      return downloadUrl;
    } catch (e) {
      // Error uploading logo to Firebase Storage (log suppressed)
      rethrow;
    }
  }

  /// Manually trigger background upload for pending quotations
  Future<void> triggerPendingUploads() async {
    try {
      final pendingBox = await Hive.openBox('pending_uploads');
      final keys = pendingBox.keys.toList();

      // Found ${keys.length} pending uploads to process (log suppressed)

      for (final key in keys) {
        if (key is String) {
          // Triggering upload for pending key (log suppressed)
          _uploadQuotationLogosInBackground(key);
        }
      }
    } catch (e) {
      // Error triggering pending uploads (log suppressed)
    }
  }

  Future<void> updateQuotation(
      String quotationId, QuotationModel quotation) async {
    try {
      if (_currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Update with all current model fields
      final updateData = quotation.toFirestore();
      updateData['updatedAt'] = Timestamp.fromDate(DateTime.now());

      await _firestore
          .collection(_collectionName)
          .doc(_currentUserId!)
          .collection('quotations')
          .doc(quotationId)
          .update(updateData);
    } catch (e) {
      // Error updating quotation (log suppressed)
      rethrow;
    }
  }

  // Update only PDF URL
  Future<void> updateQuotationPdfUrl(String quotationId, String pdfUrl) async {
    try {
      if (_currentUserId == null) {
        throw Exception('User not authenticated');
      }

      final updateData = {
        'pdfUrl': pdfUrl,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      await _firestore
          .collection(_collectionName)
          .doc(_currentUserId!)
          .collection('quotations')
          .doc(quotationId)
          .update(updateData);
    } catch (e) {
      // Error updating quotation PDF URL (log suppressed)
      rethrow;
    }
  }

  Stream<List<QuotationModel>> getUserQuotations() {
    if (_currentUserId == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('quotations')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => QuotationModel.fromFirestore(doc))
            .toList());
  }

  Future<QuotationModel?> getQuotationById(String quotationId) async {
    try {
      if (_currentUserId == null) {
        throw Exception('User not authenticated');
      }

      final doc = await _firestore
          .collection(_collectionName)
          .doc(_currentUserId!)
          .collection('quotations')
          .doc(quotationId)
          .get();

      if (doc.exists) {
        return QuotationModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      // Error getting quotation - suppressed debug log
      rethrow;
    }
  }

  Future<void> deleteQuotation(String quotationId) async {
    try {
      if (_currentUserId == null) {
        throw Exception('User not authenticated');
      }

      await _firestore
          .collection(_collectionName)
          .doc(_currentUserId!)
          .collection('quotations')
          .doc(quotationId)
          .delete();
    } catch (e) {
      // Error deleting quotation - suppressed debug log
      rethrow;
    }
  }

  // Batch operations for better performance
  Future<List<QuotationModel>> getUserQuotationsList() async {
    if (_currentUserId == null) {
      return [];
    }

    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .doc(_currentUserId!)
          .collection('quotations')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => QuotationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      // Error getting quotations list - suppressed debug log
      rethrow;
    }
  }

  // Search quotations
  Stream<List<QuotationModel>> searchQuotations(String searchTerm) {
    if (_currentUserId == null) {
      return Stream.value([]);
    }

    if (searchTerm.isEmpty) {
      return getUserQuotations();
    }

    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('quotations')
        .where('propertyTitle', isGreaterThanOrEqualTo: searchTerm)
        .where('propertyTitle', isLessThanOrEqualTo: searchTerm + '\uf8ff')
        .orderBy('propertyTitle')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => QuotationModel.fromFirestore(doc))
            .toList());
  }

  // Get quotations with pagination
  Future<List<QuotationModel>> getQuotationsPaginated({
    int limit = 10,
    DocumentSnapshot? startAfter,
  }) async {
    if (_currentUserId == null) {
      return [];
    }

    try {
      Query query = _firestore
          .collection(_collectionName)
          .doc(_currentUserId!)
          .collection('quotations')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => QuotationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      // Error getting paginated quotations - suppressed debug log
      rethrow;
    }
  }

  /// Update officeLogoUrl from mediaUrls array for PDF generation compatibility
  Future<void> _updateOfficeLogoUrlFromMediaUrls(String quotationId) async {
    try {
      if (_currentUserId == null) return;

      final docRef = _firestore
          .collection(_collectionName)
          .doc(_currentUserId!)
          .collection('quotations')
          .doc(quotationId);

      // Wait for initial document to be created, then check for mediaUrls
      await Future.delayed(const Duration(milliseconds: 500));

      final snapshot = await docRef.get();
      if (snapshot.exists) {
        final data = snapshot.data();
        final mediaUrls = data?['mediaUrls'] as List<dynamic>?;

        if (mediaUrls != null && mediaUrls.isNotEmpty) {
          final firstMediaUrl = mediaUrls.first as String;

          // Update officeLogoUrl with the first media URL
          await docRef.update({
            'officeLogoUrl': firstMediaUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // Updated officeLogoUrl (log suppressed)
        } else {
          // If no mediaUrls yet, set up a listener for background upload completion
          _setupMediaUrlsListener(quotationId);
        }
      }
    } catch (e) {
      // Error updating officeLogoUrl from mediaUrls (log suppressed)
    }
  }

  /// Set up listener for mediaUrls updates from background upload
  void _setupMediaUrlsListener(String quotationId) {
    if (_currentUserId == null) return;

    final docRef = _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('quotations')
        .doc(quotationId);

    late StreamSubscription subscription;
    subscription = docRef.snapshots().listen((snapshot) async {
      if (snapshot.exists) {
        final data = snapshot.data();
        final mediaUrls = data?['mediaUrls'] as List<dynamic>?;

        if (mediaUrls != null && mediaUrls.isNotEmpty) {
          final firstMediaUrl = mediaUrls.first as String;

          // Only update if it's a Firebase URL (not local://)
          if (firstMediaUrl.startsWith('https://')) {
            await docRef.update({
              'officeLogoUrl': firstMediaUrl,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            // Updated officeLogoUrl with Firebase URL (log suppressed)
            subscription.cancel(); // Stop listening once updated
          }
        }
      }
    });

    // Auto-cancel after 2 minutes to prevent memory leaks
    Future.delayed(const Duration(minutes: 2), () {
      subscription.cancel();
    });
  }
}
