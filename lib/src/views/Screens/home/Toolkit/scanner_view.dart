import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:broker_wallet/src/services/quota_helper.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:broker_wallet/src/services/clean_permission_service.dart';

enum ScanMode {
  document,
  receipt,
  businessCard,
  passport,
  book,
  magazine,
}

enum ExportFormat {
  pdf,
  images,
}

enum ScanQuality {
  low,
  medium,
  high,
  ultra,
}

class ScannedPage {
  final String filePath;
  final ScanMode scanMode;
  final DateTime createdAt;
  final String name;
  final ExportFormat format;

  ScannedPage({
    required this.filePath,
    required this.scanMode,
    required this.createdAt,
    required this.name,
    required this.format,
  });
}

class ScannedDocument {
  final String filePath;
  final ScanMode scanType;
  final DateTime createdAt;
  final int fileSize;
  final String name;
  final ExportFormat format;
  final int pageCount;

  ScannedDocument({
    required this.filePath,
    required this.scanType,
    required this.createdAt,
    required this.name,
    required this.fileSize,
    required this.format,
    this.pageCount = 1,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'scanType': scanType.name,
      'createdAt': createdAt.toIso8601String(),
      'name': name,
      'format': format.name,
      'pageCount': pageCount,
      'fileSize': fileSize,
    };
  }

  // Create from JSON
  factory ScannedDocument.fromJson(Map<String, dynamic> json) {
    return ScannedDocument(
      filePath: json['filePath'],
      scanType: ScanMode.values.firstWhere((e) => e.name == json['scanType']),
      createdAt: DateTime.parse(json['createdAt']),
      name: json['name'],
      format: ExportFormat.values.firstWhere((e) => e.name == json['format']),
      pageCount: json['pageCount'] ?? 1,
      fileSize: json['fileSize'] ?? 0,
    );
  }
}

// Document corner detection model
class DocumentCorner {
  final double x;
  final double y;

  DocumentCorner(this.x, this.y);

  @override
  String toString() => 'Corner($x, $y)';
}

class DocumentBounds {
  final DocumentCorner topLeft;
  final DocumentCorner topRight;
  final DocumentCorner bottomLeft;
  final DocumentCorner bottomRight;
  final double confidence;

  DocumentBounds({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    this.confidence = 0.0,
  });

  List<DocumentCorner> get corners =>
      [topLeft, topRight, bottomRight, bottomLeft];
}

class ScannerView extends StatefulWidget {
  const ScannerView({Key? key}) : super(key: key);

  @override
  _ScannerViewState createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView>
    with TickerProviderStateMixin {
  final FlutterDocScanner _docScanner = FlutterDocScanner();
  final TextEditingController _fileNameController = TextEditingController();
  final PageController _pageController = PageController();
  final List<ScannedDocument> _scannedDocuments = [];
  final List<ScannedPage> _scannedPages = [];

  // Processing state
  bool _isProcessing = false;
  bool _isScanning = false;
  double _processingProgress = 0.0;
  String _currentProcessingStep = '';

  // Scan settings
  ScanMode _selectedScanType = ScanMode.document;
  ScanMode _scanMode = ScanMode.document;
  ExportFormat _selectedFormat = ExportFormat.pdf;
  ExportFormat _exportFormat = ExportFormat.pdf;
  ScanQuality _scanQuality = ScanQuality.high;
  int _maxPages = 5;

  bool _autoEnhance = true;
  bool _autoCrop = true;
  bool _removeBackground = false;
  bool _ocrEnabled = false;
  bool _batchMode = false;

  // UI state
  bool _isGridView = true;
  int? _selectedPageIndex;
  bool _showSettings = false;
  bool _showPreview = false;
  bool _isSelectionMode = false;
  Set<int> _selectedDocuments = {};

  // Animation controllers
  late AnimationController _settingsController;
  late AnimationController _previewController;
  late Animation<Offset> _settingsAnimation;
  late Animation<double> _previewAnimation;

  // Platform channel for MediaStore operations
  static const MethodChannel _channel = MethodChannel('file_saver');

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _generateFileName();
    _requestPermissions();
    _loadSavedDocuments();
    _loadViewModePreference();
  }

  void _initializeAnimations() {
    _settingsController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _previewController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _settingsAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _settingsController,
      curve: Curves.easeOutBack,
    ));
    _previewAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _previewController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _settingsController.dispose();
    _previewController.dispose();
    _fileNameController.dispose();
    super.dispose();
  }

  void _generateFileName() {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    _fileNameController.text = '${_scanMode.name}_scan_$timestamp';
  }

  Future<void> _requestPermissions() async {
    // NOTE: We don't request permissions here anymore!
    // Permissions are requested just-in-time when user initiates an action
    // (e.g., when they press the scan button)
    // This follows best practices for UX and platform guidelines
  }

  Future<bool> _requestStoragePermissions() async {
    if (Platform.isAndroid) {
      // For Android 13+ (API 33+), request media permissions
      try {
        final photos = await Permission.photos.request();
        if (photos.isGranted) {
          return true;
        }
      } catch (e) {
        // Photos permission not available: $e (log removed)
      }

      // For Android 11+ (API 30+), try manage external storage
      try {
        final manageStorage = await Permission.manageExternalStorage.request();
        if (manageStorage.isGranted) {
          return true;
        }
      } catch (e) {
        // Manage external storage permission not available: $e (log removed)
      }

      // For older Android versions, request storage permission
      try {
        final storage = await Permission.storage.request();
        if (storage.isGranted) {
          return true;
        }
      } catch (e) {
        // Storage permission not available: $e (log removed)
      }

      return false;
    }

    // iOS doesn't need special permissions for app documents
    return true;
  }

  void _showToast(String message, Color color) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: color,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  // Persistence methods for saving/loading scanned documents
  Future<void> _saveDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> documentsJson =
          _scannedDocuments.map((doc) => jsonEncode(doc.toJson())).toList();
      await prefs.setStringList('scanned_documents', documentsJson);
    } catch (e) {
      // Error saving documents: $e (log removed)
    }
  }

  Future<void> _loadSavedDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? documentsJson =
          prefs.getStringList('scanned_documents');

      if (documentsJson != null) {
        final List<ScannedDocument> loadedDocuments = [];

        for (final docJson in documentsJson) {
          try {
            final Map<String, dynamic> docMap = jsonDecode(docJson);
            final document = ScannedDocument.fromJson(docMap);

            // Check if the file still exists before adding to the list
            final file = File(document.filePath);
            if (await file.exists()) {
              // Update file size if it's 0 or missing
              int actualFileSize = document.fileSize;
              if (actualFileSize == 0) {
                try {
                  actualFileSize = await file.length();
                } catch (e) {}
              }

              // Create document with updated file size if needed
              final updatedDocument = actualFileSize != document.fileSize
                  ? ScannedDocument(
                      filePath: document.filePath,
                      scanType: document.scanType,
                      createdAt: document.createdAt,
                      name: document.name,
                      format: document.format,
                      pageCount: document.pageCount,
                      fileSize: actualFileSize,
                    )
                  : document;

              loadedDocuments.add(updatedDocument);
            }
          } catch (e) {
            // Error parsing document: $e (log removed)
            // Skip corrupted documents
          }
        }

        setState(() {
          _scannedDocuments.clear();
          _scannedDocuments.addAll(loadedDocuments);
        });

        // Save updated documents with corrected file sizes
        await _saveDocuments();
      }
    } catch (e) {
      // Error loading documents: $e (log removed)
    }
  }

  // Load and save view mode preference
  Future<void> _loadViewModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isGridView = prefs.getBool('scanner_grid_view_mode') ?? true;
      });
    } catch (e) {
      // Error loading view mode preference: $e (log removed)
    }
  }

  Future<void> _saveViewModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('scanner_grid_view_mode', _isGridView);
    } catch (e) {
      // Error saving view mode preference: $e (log removed)
    }
  }

  AppLocalizations get _localization => AppLocalizations.of(context);

  Future<void> _startScanning() async {
    if (_isScanning) return;

    try {
      setState(() => _isScanning = true);

      // Check camera permission using CleanPermissionService
      final permissionService = CleanPermissionService();
      final cameraPermission =
          await permissionService.requestCameraPermission(context);

      if (!cameraPermission.isGranted) {
        _showToast(
            _localization.translate('cameraPermissionRequired'), Colors.red);
        setState(() => _isScanning = false);
        return;
      }

      dynamic scannedResult;

      if (_selectedFormat == ExportFormat.pdf) {
        // Get scanned document as PDF
        scannedResult =
            await _docScanner.getScannedDocumentAsPdf(page: _maxPages);
      } else {
        // Get scanned document as images
        scannedResult =
            await _docScanner.getScannedDocumentAsImages(page: _maxPages);
      }

      // Clear loading state immediately after scan completes
      setState(() => _isScanning = false);

      if (scannedResult != null) {
        await _processScannedResult(scannedResult);
      } else {
        _showToast(_localization.translate('scanningCancelled'), Colors.orange);
      }
    } on PlatformException catch (e) {
      setState(() => _isScanning = false);
      _showToast('${_localization.translate('scanningFailed')}: ${e.message}',
          Colors.red);
    } catch (e) {
      setState(() => _isScanning = false);
      _showToast(_localization.translate('errorOccurredScanning'), Colors.red);
    }
  }

  Future<void> _processScannedResult(dynamic result) async {
    try {
      String? pdfPath;
      int pageCount = 1;

      if (result is String) {
        // Single file path (PDF)
        pdfPath = result;
        pageCount = 1;
      } else if (result is Map) {
        // Handle the result map from flutter_doc_scanner
        if (result.containsKey('pdfUri')) {
          // Extract PDF URI and clean it
          pdfPath = result['pdfUri'].toString().replaceFirst("file://", "");
          pageCount = result['pageCount'] ?? 1;
        } else if (result.containsKey('images')) {
          // Handle multiple images result
          final images = result['images'] as List?;
          if (images != null && images.isNotEmpty) {
            // For now, take the first image
            pdfPath = images.first.toString();
            pageCount = images.length;
          }
        }
      } else if (result is List) {
        // Multiple image paths
        if (_selectedFormat == ExportFormat.images) {
          // Save individual images
          int successCount = 0;
          for (int i = 0; i < result.length; i++) {
            final saved =
                await _saveScannedDocument(result[i], 1, pageIndex: i);
            if (saved) successCount++;
          }
          if (successCount > 0) {
            _showToast(
                successCount == result.length
                    ? _localization.translate('documentsScannedSuccessfully')
                    : '${successCount} ${_localization.translate('documentsSaved')}',
                Colors.green);
          }
          return;
        } else {
          // Take first image for PDF
          pdfPath = result.first;
          pageCount = result.length;
        }
      }

      if (pdfPath != null && pdfPath.isNotEmpty) {
        // Directly save the scanned document to the list
        final saved = await _saveScannedDocument(pdfPath, pageCount);
        if (saved) {
          _showToast(_localization.translate('documentSavedSuccessfully'),
              Colors.green);
        }
      } else {
        _showToast(
            _localization.translate('noValidDocumentFound'), Colors.orange);
      }
    } catch (e) {
      // Error processing scan result: $e (log removed)
      _showToast(_localization.translate('failedToProcessScanned'), Colors.red);
    }
  }

  Future<bool> _saveScannedDocument(String filePath, int pageCount,
      {int? pageIndex}) async {
    try {
      // QUOTA CHECK: Check if user can add more scanned documents
      final currentUserId =
          RepositoryProvider.instance.authRepository.currentUserId;
      if (currentUserId == null) {
        _showToast(
            _localization.translate('pleaseLoginFirst'), Colors.red);
        return false;
      }

      final canAdd = await QuotaHelper.checkAndWarnQuota(
        context: context,
        uid: currentUserId,
        section: 'scanner',
        toolName: 'scanner',
      );

      if (!canAdd) {
        return false; // User hit quota limit
      }

      // Check storage permissions first
      final hasPermission = await _requestStoragePermissions();

      if (!hasPermission) {
        _showToast(
            _localization.translate('storagePermissionRequired'), Colors.red);
        return false;
      }

      final directory = await getApplicationDocumentsDirectory();
      final sanitizedName = _sanitizeFileName(_fileNameController.text.trim());
      final fileName =
          sanitizedName.isEmpty ? 'scanned_document' : sanitizedName;

      String finalFileName;
      if (pageIndex != null) {
        finalFileName = '${fileName}_page_${pageIndex + 1}';
      } else {
        finalFileName = fileName;
      }

      final extension = _selectedFormat == ExportFormat.pdf ? '.pdf' : '.jpg';
      final finalPath = path.join(directory.path, '$finalFileName$extension');

      // Copy the scanned file to our app directory
      final sourceFile = File(filePath);
      final targetFile = File(finalPath);
      await sourceFile.copy(targetFile.path);

      // Add to our list
      final scannedDoc = ScannedDocument(
        filePath: targetFile.path,
        scanType: _selectedScanType,
        createdAt: DateTime.now(),
        name: finalFileName,
        format: _selectedFormat,
        pageCount: pageCount,
        fileSize: await targetFile.length(),
      );

      setState(() {
        _scannedDocuments.insert(0, scannedDoc);
      });

      // Save documents to persistent storage
      await _saveDocuments();

      // Update quota count
      await _incrementQuotaCount(currentUserId, 'scanner');

      // Generate new filename for next scan
      _generateFileName();

      return true; // Successfully saved
    } catch (e) {
      // Failed to save document: $e (log removed)
      _showToast(_localization.translate('failedToSaveDocument'), Colors.red);
      return false;
    }
  }

  Future<void> _incrementQuotaCount(String uid, String section) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'counts': {section: FieldValue.increment(1)},
        'lifetimeCreated': {section: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (e) {
      // Failed to update quota count: $e (log removed)
    }
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
  }

  Future<void> _shareDocument(ScannedDocument document) async {
    try {
      final file = XFile(document.filePath);
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          text:
              '${_localization.translate('scannedDocument')}: ${document.name}',
        ),
      );
    } catch (e) {
      _showToast(_localization.translate('failedToShareDocument'), Colors.red);
    }
  }

  // Enhanced _saveToDeviceStorage method with proper Android 11+ support
  Future<void> _saveToDeviceStorage(File documentFile) async {
    final localization = AppLocalizations.of(context);

    try {
      Directory? downloadsDirectory;
      String locationName = 'Documents'; // Default value

      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt >= 30) {
          // Android 11+ (API 30+) - Use MediaStore for proper public Downloads saving
          locationName = 'Downloads';
          try {
            final fileName = documentFile.path.split('/').last;
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final nameWithoutExt = fileName
                .replaceAll('.pdf', '')
                .replaceAll('.jpg', '')
                .replaceAll('.jpeg', '')
                .replaceAll('.png', '');
            final extension = fileName.split('.').last;
            final uniqueFileName = '${nameWithoutExt}_$timestamp.$extension';
            final fileBytes = await documentFile.readAsBytes();

            String mimeType = 'application/pdf';
            if (extension.toLowerCase() == 'jpg' ||
                extension.toLowerCase() == 'jpeg') {
              mimeType = 'image/jpeg';
            } else if (extension.toLowerCase() == 'png') {
              mimeType = 'image/png';
            }

            final result = await _channel.invokeMethod('saveFileToDownloads', {
              'fileName': uniqueFileName,
              'fileBytes': fileBytes,
              'mimeType': mimeType,
            });

            if (result['success'] == true) {
              _showToast(
                '${localization.translate('documentSavedToDownloads')} Downloads\nFile: $uniqueFileName\n(Accessible via Files app)',
                Colors.green,
              );
              return; // Success, exit method
            } else {
              throw Exception('MediaStore save failed');
            }
          } catch (e) {
            // Continue to fallback method below
            final externalDir = await getExternalStorageDirectory();
            if (externalDir != null) {
              downloadsDirectory = Directory('${externalDir.path}/Downloads');
              locationName = 'App Downloads';
              if (!await downloadsDirectory.exists()) {
                await downloadsDirectory.create(recursive: true);
              }
            } else {
              downloadsDirectory = await getApplicationDocumentsDirectory();
              locationName = 'App Documents';
            }
          }
        } else {
          // Android 10 and below - Request storage permission
          locationName = 'Downloads';
          final cleanPermissionService = CleanPermissionService();
          final storagePermissions =
              await cleanPermissionService.requestStoragePermissions(context);
          final hasStorageAccess =
              storagePermissions.values.any((s) => s.isGranted || s.isLimited);

          if (hasStorageAccess) {
            try {
              downloadsDirectory = Directory('/storage/emulated/0/Download');
              if (!await downloadsDirectory.exists()) {
                // Fallback paths
                final fallbackPaths = [
                  '/sdcard/Download',
                  '/storage/self/primary/Download',
                ];

                for (String path in fallbackPaths) {
                  final testDir = Directory(path);
                  if (await testDir.exists()) {
                    downloadsDirectory = testDir;
                    break;
                  }
                }

                // Last resort - external storage
                if (downloadsDirectory == null ||
                    !await downloadsDirectory.exists()) {
                  downloadsDirectory = await getExternalStorageDirectory();
                  locationName = 'External Storage';
                }
              }
            } catch (e) {
              downloadsDirectory = await getExternalStorageDirectory();
              locationName = 'External Storage';
            }
          } else {
            _showToast(
                localization.translate('storagePermissionDenied'), Colors.red);
            return;
          }
        }
      } else if (Platform.isIOS) {
        downloadsDirectory = await getApplicationDocumentsDirectory();
        locationName = 'Documents';
      }

      if (downloadsDirectory == null) {
        _showToast(localization.translate('failedToAccessStorage'), Colors.red);
        return;
      }

      // Create the destination file path with timestamp to avoid conflicts
      final fileName = documentFile.path.split('/').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final nameWithoutExt = fileName
          .replaceAll('.pdf', '')
          .replaceAll('.jpg', '')
          .replaceAll('.jpeg', '')
          .replaceAll('.png', '');
      final extension = fileName.split('.').last;
      final uniqueFileName = '${nameWithoutExt}_$timestamp.$extension';
      final destinationPath = '${downloadsDirectory.path}/$uniqueFileName';

      // Ensure the directory exists
      await downloadsDirectory.create(recursive: true);

      // Copy the file to the destination
      final destinationFile = File(destinationPath);
      await documentFile.copy(destinationPath);

      // Verify the file was created and get its actual size
      if (await destinationFile.exists()) {
        // Show success with actual path info
        _showToast(
          '${localization.translate('documentSavedToDownloads')} $locationName\nFile: $uniqueFileName',
          Colors.green,
        );

        // Additional debug info
        try {
          final files = await downloadsDirectory.list().toList();
          for (var file in files) {
            if (file.path.contains('.pdf') ||
                file.path.contains('.jpg') ||
                file.path.contains('.png')) {}
          }
        } catch (e) {}
      } else {
        throw Exception(
            'File was not created at destination: $destinationPath');
      }
    } catch (e) {
      _showToast(
          '${localization.translate('failedToSaveDocument')}: ${e.toString()}',
          Colors.red);
    }
  }

  Future<void> _renameDocument(ScannedDocument document, int index) async {
    final controller = TextEditingController(text: document.name);

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_localization.translate('renameDocument')),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: _localization.translate('documentName'),
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_localization.translate('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != document.name) {
                  await _performRename(document, index, newName);
                }
                Navigator.of(context).pop();
              },
              child: Text(_localization.translate('rename')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performRename(
      ScannedDocument document, int index, String newName) async {
    try {
      final oldFile = File(document.filePath);
      final directory = oldFile.parent;
      final extension = path.extension(document.filePath);
      final newPath = path.join(directory.path, '$newName$extension');

      // Rename the actual file
      await oldFile.rename(newPath);

      // Update the document in our list
      final updatedDocument = ScannedDocument(
        filePath: newPath,
        scanType: document.scanType,
        createdAt: document.createdAt,
        name: newName,
        format: document.format,
        pageCount: document.pageCount,
        fileSize: await File(newPath).length(),
      );

      setState(() {
        _scannedDocuments[index] = updatedDocument;
      });

      // Save documents to persistent storage
      await _saveDocuments();

      _showToast(
          _localization.translate('documentRenamedSuccessfully'), Colors.green);
    } catch (e) {
      // Error renaming document: $e (log removed)
      _showToast(_localization.translate('failedToRenameDocument'), Colors.red);
    }
  }

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedDocuments.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedDocuments.clear();
    });
  }

  Future<void> _shareBulkDocuments() async {
    try {
      final selectedDocs =
          _selectedDocuments.map((index) => _scannedDocuments[index]).toList();

      final files = selectedDocs.map((doc) => XFile(doc.filePath)).toList();

      await SharePlus.instance.share(
        ShareParams(
          files: files,
          text: _localization
              .translate('sharingDocuments')
              .replaceAll('{count}', '${files.length}'),
        ),
      );

      _exitSelectionMode();
    } catch (e) {
      _showToast(_localization.translate('failedToDeleteSelected'), Colors.red);
    }
  }

  Future<void> _deleteBulkDocuments() async {
    final count = _selectedDocuments.length;

    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(_localization.translate('confirmDelete')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 1
                        ? _localization.translate('areYouSureDeleteOneDocument')
                        : '${_localization.translate('areYouSureDelete')} $count ${_localization.translate('documents')}?',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _localization.translate('cannotRestoreItems'),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.red[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(_localization.translate('cancel')),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_localization.translate('delete')),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirmed) return;

      // Delete files and remove from list
      final indicesToRemove = _selectedDocuments.toList()
        ..sort((a, b) => b.compareTo(a));

      for (final index in indicesToRemove) {
        final document = _scannedDocuments[index];
        final file = File(document.filePath);
        if (await file.exists()) {
          await file.delete();
        }
        _scannedDocuments.removeAt(index);
      }

      // Save documents to persistent storage
      await _saveDocuments();

      setState(() {});
      _exitSelectionMode();

      _showToast(
        '$count ${count == 1 ? _localization.translate('documentDeleted') : _localization.translate('documentsDeleted')}',
        Colors.green,
      );
    } catch (e) {
      _showToast(_localization.translate('failedToDeleteSelected'), Colors.red);
    }
  }

  void _toggleDocumentSelection(int index) {
    setState(() {
      if (_selectedDocuments.contains(index)) {
        _selectedDocuments.remove(index);
      } else {
        _selectedDocuments.add(index);
      }
    });
  }

  Future<void> _deleteDocument(int index) async {
    try {
      final document = _scannedDocuments[index];
      final file = File(document.filePath);

      if (await file.exists()) {
        await file.delete();
      }

      setState(() {
        _scannedDocuments.removeAt(index);
      });

      // Save documents to persistent storage
      await _saveDocuments();

      _showToast(_localization.translate('documentDeleted'), Colors.green);
    } catch (e) {
      _showToast(_localization.translate('failedToDeleteDocument'), Colors.red);
    }
  }

  Future<void> _previewDocument(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _showToast(_localization.translate('documentFileNotFound'), Colors.red);
        return;
      }

      // Check if it's a PDF file - if so, use inline PDF viewer
      if (filePath.toLowerCase().endsWith('.pdf')) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PdfViewerScreen(
              localFile: file,
              title: path.basenameWithoutExtension(filePath),
            ),
          ),
        );
        return;
      }

      // For non-PDF files, use external app
      final result = await OpenFilex.open(filePath);

      if (result.type != ResultType.done) {
        // Fallback: Show a preview dialog with basic info
        _showDocumentInfoDialog(filePath);
      }
    } catch (e) {
      // Error opening document: $e (log removed)
      _showDocumentInfoDialog(filePath);
    }
  }

  void _showDocumentInfoDialog(String filePath) {
    final file = File(filePath);
    final stats = file.statSync();
    final sizeInMB = (stats.size / (1024 * 1024)).toStringAsFixed(2);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_localization.translate('documentInfo')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${_localization.translate('file')}: ${path.basename(filePath)}'),
            Text('${_localization.translate('size')}: ${sizeInMB} MB'),
            Text(
                '${_localization.translate('type')}: ${_selectedFormat.name.toUpperCase()}'),
            Text(
                '${_localization.translate('created')}: ${DateTime.now().toString().split('.')[0]}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_localization.translate('close')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _saveScannedDocument(filePath, 1);
              _showToast(_localization.translate('documentSavedSuccessfully'),
                  Colors.green);
            },
            child: Text(_localization.translate('saveDocument')),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  void _resetForm() {
    setState(() {
      _scannedDocuments.clear();
      _selectedPageIndex = null;
    });
    _generateFileName();
  }

  void _showScanSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return _buildScanSettings(setModalState);
        },
      ),
    );
  }

  Widget _buildScanSettings(StateSetter setModalState) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _localization.translate('scanSettings'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Scan Mode
                  _buildSettingSection(
                    _localization.translate('scanMode'),
                    Column(
                      children: ScanMode.values.map((mode) {
                        return RadioListTile<ScanMode>(
                          title: Text(_getScanTypeLabel(mode)),
                          subtitle: Text(_getScanModeDescription(mode)),
                          value: mode,
                          groupValue: _selectedScanType,
                          onChanged: (ScanMode? value) {
                            if (value != null) {
                              setState(() {
                                _selectedScanType = value;
                                _scanMode = value;
                              });
                              setModalState(() {
                                _selectedScanType = value;
                                _scanMode = value;
                              });
                              _generateFileName();
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Export Format
                  _buildSettingSection(
                    _localization.translate('exportFormat'),
                    Column(
                      children: ExportFormat.values.map((format) {
                        return RadioListTile<ExportFormat>(
                          title: Text(format.name.toUpperCase()),
                          subtitle: Text(_getFormatDescription(format)),
                          value: format,
                          groupValue: _selectedFormat,
                          onChanged: (ExportFormat? value) {
                            if (value != null) {
                              setState(() {
                                _selectedFormat = value;
                                _exportFormat = value;
                              });
                              setModalState(() {
                                _selectedFormat = value;
                                _exportFormat = value;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Quality Settings
                  _buildSettingSection(
                    _localization.translate('scanQuality'),
                    Column(
                      children: ScanQuality.values.map((quality) {
                        return RadioListTile<ScanQuality>(
                          title:
                              Text(_getScanQualityLabel(quality).toUpperCase()),
                          value: quality,
                          groupValue: _scanQuality,
                          onChanged: (ScanQuality? value) {
                            if (value != null) {
                              setState(() => _scanQuality = value);
                              setModalState(() => _scanQuality = value);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Advanced Options
                  _buildSettingSection(
                    _localization.translate('advancedOptions'),
                    Column(
                      children: [
                        SwitchListTile(
                          title: Text(_localization.translate('autoEnhance')),
                          subtitle: Text(_localization
                              .translate('automaticallyEnhanceImageQuality')),
                          value: _autoEnhance,
                          onChanged: (value) {
                            setState(() => _autoEnhance = value);
                            setModalState(() => _autoEnhance = value);
                          },
                        ),
                        SwitchListTile(
                          title: Text(_localization.translate('autoCrop')),
                          subtitle: Text(_localization
                              .translate('automaticallyDetectAndCrop')),
                          value: _autoCrop,
                          onChanged: (value) {
                            setState(() => _autoCrop = value);
                            setModalState(() => _autoCrop = value);
                          },
                        ),
                        SwitchListTile(
                          title:
                              Text(_localization.translate('removeBackground')),
                          subtitle: Text(_localization
                              .translate('removeBackgroundKeepDocument')),
                          value: _removeBackground,
                          onChanged: (value) {
                            setState(() => _removeBackground = value);
                            setModalState(() => _removeBackground = value);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  String _getScanTypeLabel(ScanMode type) {
    switch (type) {
      case ScanMode.document:
        return _localization.translate('document');
      case ScanMode.receipt:
        return _localization.translate('receipt');
      case ScanMode.businessCard:
        return _localization.translate('businessCard');
      case ScanMode.passport:
        return _localization.translate('passport');
      case ScanMode.book:
        return _localization.translate('book');
      case ScanMode.magazine:
        return _localization.translate('magazine');
    }
  }

  String _getFormatDescription(ExportFormat format) {
    switch (format) {
      case ExportFormat.pdf:
        return _localization.translate('singlePdfWithAllPages');
      case ExportFormat.images:
        return _localization.translate('individualImageFiles');
    }
  }

  String _getFormatLabel(ExportFormat format) {
    switch (format) {
      case ExportFormat.pdf:
        return _localization.translate('pdf');
      case ExportFormat.images:
        return _localization.translate('images');
    }
  }

  String _getScanQualityLabel(ScanQuality quality) {
    switch (quality) {
      case ScanQuality.low:
        return _localization.translate('low');
      case ScanQuality.medium:
        return _localization.translate('medium');
      case ScanQuality.high:
        return _localization.translate('high');
      case ScanQuality.ultra:
        return _localization.translate('ultra');
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: colors.surface,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      appBar: _buildAdvancedAppBar(localization, colors),
      body: _buildBody(localization, colors, size),
      floatingActionButton: _buildAdvancedFAB(localization),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      // bottomNavigationBar: _buildBottomAppBar(colors),
    );
  }

  PreferredSizeWidget _buildAdvancedAppBar(
      AppLocalizations localization, ColorScheme colors) {
    return AppBar(
      leading: const BackArrowButton(
        iconColor: Colors.white, // Set to white to match the primary gradient
        backgroundColor: Colors
            .transparent, // Make background transparent since we have gradient
        showBackground: false, // Disable the default background circle
      ),
      title: Column(
        children: [
          Text(
            _isSelectionMode
                ? '${_selectedDocuments.length} ${_localization.translate('selected')}'
                : _localization.translate('Scanner'),
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 20),
          ),
          if (_scannedDocuments.isNotEmpty && !_isSelectionMode)
            Text(
              '${_scannedDocuments.length} ${_localization.translate('documentsScanned')}',
              style: TextStyle(
                  fontSize: 12, color: colors.onSurface.withValues(alpha: 0.7)),
            ),
        ],
      ),
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withValues(alpha: 0.9),
              AppColors.primary.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
      ),
      actions: [
        if (_isSelectionMode) ...[
          // Bulk actions when in selection mode
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed:
                _selectedDocuments.isNotEmpty ? _shareBulkDocuments : null,
            tooltip: _localization.translate('shareSelected'),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed:
                _selectedDocuments.isNotEmpty ? _deleteBulkDocuments : null,
            tooltip: _localization.translate('deleteSelected'),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _exitSelectionMode,
            tooltip: _localization.translate('cancelSelection'),
          ),
        ] else ...[
          if (_scannedDocuments.isNotEmpty) ...[
            IconButton(
              icon: Icon(
                _isGridView ? Icons.view_list : Icons.grid_view,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() => _isGridView = !_isGridView);
                _saveViewModePreference();
              },
              tooltip: _isGridView
                  ? _localization.translate('listView')
                  : _localization.translate('gridView'),
            ),
            IconButton(
              icon: const Icon(Icons.checklist, color: Colors.white),
              onPressed: _enterSelectionMode,
              tooltip: _localization.translate('selectDocuments'),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _showScanSettings,
            tooltip: _localization.translate('scanSettings'),
          ),
        ],
      ],
    );
  }

  Widget _buildBody(
      AppLocalizations localization, ColorScheme colors, Size size) {
    return CustomScrollView(
      slivers: [
        // Header space for transparent app bar
        const SliverToBoxAdapter(child: SizedBox(height: 120)),

        // Mode indicator
        SliverToBoxAdapter(
          child: _buildModeIndicator(localization, colors),
        ),

        // Processing indicator
        if (_isProcessing)
          SliverToBoxAdapter(
            child: _buildProcessingIndicator(localization, colors),
          ),

        // Scanned documents
        if (_scannedDocuments.isNotEmpty) ...[
          // Scanned documents header
          SliverToBoxAdapter(
            child: _buildScannedDocumentsHeader(localization),
          ),
          _isGridView
              ? SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.8,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final document = _scannedDocuments[index];
                        return _buildDocumentGridCard(document, index);
                      },
                      childCount: _scannedDocuments.length,
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final document = _scannedDocuments[index];
                      return _buildDocumentCard(document, index);
                    },
                    childCount: _scannedDocuments.length,
                  ),
                ),
        ] else
          SliverToBoxAdapter(
            child: _buildEmptyState(),
          ),

        // Bottom padding for FAB
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildModeIndicator(
      AppLocalizations localization, ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getScanModeIcon(_scanMode),
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localization.translate('scanModeLabel').replaceAll(
                      '{mode}', _getScanTypeLabel(_scanMode).toUpperCase()),
                  style: AppTextStyles.sectionLabel.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getScanModeDescription(_scanMode),
                  style: AppTextStyles.bodyText.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildFeatureChip(_localization.translate('qualityLabel'),
                        _getScanQualityLabel(_scanQuality)),
                    const SizedBox(width: 6),
                    if (_autoEnhance)
                      _buildFeatureChip(
                          'AI', _localization.translate('aiEnhanced')),
                    const SizedBox(width: 6),
                    if (_autoCrop)
                      _buildFeatureChip(
                          _localization.translate('autoCropLabel'),
                          _localization.translate('autoCropLabel')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildProcessingIndicator(
      AppLocalizations localization, ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircularProgressIndicator(
                value: _processingProgress,
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentProcessingStep,
                      style: AppTextStyles.bodyText
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _localization.translate('percentComplete').replaceAll(
                          '{percent}',
                          '${(_processingProgress * 100).toInt()}'),
                      style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _processingProgress,
            backgroundColor: colors.outline.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedFAB(AppLocalizations localization) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: FloatingActionButton.extended(
        onPressed: _isScanning ? null : _startScanning,
        icon: _isScanning
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.camera_alt),
        label: Text(
          _isScanning
              ? _localization.translate('scanningProgress')
              : _scannedDocuments.isEmpty
                  ? _localization.translate('startScanning')
                  : _localization.translate('scanMore'),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 8,
      ),
    );
  }

  // Helper methods
  IconData _getScanModeIcon(ScanMode mode) {
    switch (mode) {
      case ScanMode.document:
        return Icons.description;
      case ScanMode.receipt:
        return Icons.receipt;
      case ScanMode.businessCard:
        return Icons.credit_card;
      case ScanMode.passport:
        return Icons.person;
      case ScanMode.book:
        return Icons.menu_book;
      case ScanMode.magazine:
        return Icons.collections;
    }
  }

  String _getScanModeDescription(ScanMode mode) {
    switch (mode) {
      case ScanMode.document:
        return _localization.translate('optimizedForTextDocuments');
      case ScanMode.receipt:
        return _localization.translate('highContrastForReceipts');
      case ScanMode.businessCard:
        return _localization.translate('preservesColorsAndDetails');
      case ScanMode.passport:
        return _localization.translate('maintainsOriginalColors');
      case ScanMode.book:
        return _localization.translate('reducesShadowsImproves');
      case ScanMode.magazine:
        return _localization.translate('enhancedColorReproduction');
    }
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.scanner,
              size: 80,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _localization.translate('noDocumentsScannedYet'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _localization.translate('tapScanButtonToStart'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannedDocumentsHeader(AppLocalizations localization) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.scanner,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '${localization.translate('scannedDocuments')} (${_scannedDocuments.length})',
            style: AppTextStyles.bodyText.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const Spacer(),
          if (_scannedDocuments.isNotEmpty)
            Text(
              _isGridView
                  ? _localization.translate('gridView')
                  : _localization.translate('listView'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(ScannedDocument document, int index) {
    final isSelected = _selectedDocuments.contains(index);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleDocumentSelection(index),
                activeColor: AppColors.primary,
              )
            : Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  document.format == ExportFormat.pdf
                      ? Icons.picture_as_pdf
                      : Icons.image,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
        onTap: _isSelectionMode ? () => _toggleDocumentSelection(index) : null,
        onLongPress: _isSelectionMode ? null : () => _enterSelectionMode(),
        title: Text(
          document.name,
          style: AppTextStyles.bodyText.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_getScanTypeLabel(document.scanType).toUpperCase()} • ${_getFormatLabel(document.format).toUpperCase()}',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDateTime(document.createdAt),
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  if (document.pageCount > 1) ...[
                    Text(
                      ' • ${document.pageCount} ${_localization.translate('pages')}',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.visibility, color: AppColors.primary, size: 20),
              onPressed: () => _previewDocument(document.filePath),
              tooltip: _localization.translate('preview'),
              visualDensity: VisualDensity.compact,
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6)),
              onSelected: (value) {
                switch (value) {
                  case 'share':
                    _shareDocument(document);
                    break;
                  case 'download':
                    _saveToDeviceStorage(File(document.filePath));
                    break;
                  case 'rename':
                    _renameDocument(document, index);
                    break;
                  case 'delete':
                    _deleteDocument(index);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, size: 20, color: Colors.blue),
                      const SizedBox(width: 12),
                      Text(_localization.translate('share')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 20, color: Colors.green),
                      const SizedBox(width: 12),
                      Text(_localization.translate('download')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20, color: Colors.grey),
                      const SizedBox(width: 12),
                      Text(_localization.translate('rename')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      const SizedBox(width: 12),
                      Text(_localization.translate('delete')),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} ${_localization.translate('daysAgo')}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${_localization.translate('hoursAgo')}';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${_localization.translate('minutesAgo')}';
    } else {
      return _localization.translate('justNow');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildDocumentGridCard(ScannedDocument document, int index) {
    final isSelected = _selectedDocuments.contains(index);

    return Card(
      margin: const EdgeInsets.all(4),
      elevation: isSelected ? 8 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: AppColors.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: _isSelectionMode ? () => _toggleDocumentSelection(index) : null,
        onLongPress: _isSelectionMode ? null : () => _enterSelectionMode(),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                AppColors.primary.withValues(alpha: 0.02),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row with selection indicator and menu
              Row(
                children: [
                  // Selection indicator or document icon
                  if (_isSelectionMode)
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.grey,
                          width: 2,
                        ),
                        color:
                            isSelected ? AppColors.primary : Colors.transparent,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 14)
                          : null,
                    )
                  else
                    // Document type icon
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        document.format == ExportFormat.pdf
                            ? Icons.picture_as_pdf
                            : Icons.image,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),

                  const Spacer(),

                  // More options menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (value) async {
                      switch (value) {
                        case 'preview':
                          await _previewDocument(document.filePath);
                          break;
                        case 'share':
                          await _shareDocument(document);
                          break;
                        case 'save_to_downloads':
                          await _saveToDeviceStorage(File(document.filePath));
                          break;
                        case 'rename':
                          await _renameDocument(document, index);
                          break;
                        case 'delete':
                          await _deleteDocument(index);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            const Icon(Icons.edit,
                                size: 18, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(_localization.translate('rename')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _localization.translate('delete'),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Document name
              Text(
                document.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 6),

              // Document type and format
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${_getScanTypeLabel(document.scanType)} • ${_getFormatLabel(document.format)}',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(height: 6),

              // Date and page count with fixed height
              SizedBox(
                height: 16, // Fixed height for date
                child: Text(
                  _formatDateTime(document.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                ),
              ),

              const SizedBox(height: 6),

              // File size with fixed height
              SizedBox(
                height: 14, // Fixed height for file size row
                child: Row(
                  children: [
                    Icon(
                      Icons.folder,
                      size: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _formatFileSize(document.fileSize),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),

              // Fixed spacing instead of Spacer for consistent layout
              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildGridActionButton(
                    icon: Icons.visibility,
                    onTap: () => _previewDocument(document.filePath),
                    color: AppColors.primary,
                  ),
                  _buildGridActionButton(
                    icon: Icons.share,
                    onTap: () => _shareDocument(document),
                    color: Colors.blue,
                  ),
                  _buildGridActionButton(
                    icon: Icons.download,
                    onTap: () => _saveToDeviceStorage(File(document.filePath)),
                    color: Colors.green,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: color,
        ),
      ),
    );
  }
}
