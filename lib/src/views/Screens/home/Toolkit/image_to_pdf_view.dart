import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:broker_wallet/src/services/clean_media_service.dart';
import 'package:broker_wallet/src/services/clean_permission_service.dart';
import 'package:broker_wallet/src/services/quota_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// Model for converted PDF documents
class ConvertedPdfDocument {
  final String id;
  final String name;
  final String filePath;
  final DateTime createdAt;
  final int fileSize;
  final int imageCount;

  ConvertedPdfDocument({
    required this.id,
    required this.name,
    required this.filePath,
    required this.createdAt,
    required this.fileSize,
    required this.imageCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'filePath': filePath,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'fileSize': fileSize,
      'imageCount': imageCount,
    };
  }

  factory ConvertedPdfDocument.fromJson(Map<String, dynamic> json) {
    return ConvertedPdfDocument(
      id: json['id'],
      name: json['name'],
      filePath: json['filePath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
      fileSize: json['fileSize'],
      imageCount: json['imageCount'],
    );
  }
}

// Enhanced enums for professional PDF creation
enum PdfPageSize { a4, letter, legal, a3, a5, custom }

enum PdfOrientation { portrait, landscape, auto }

enum ImageQuality { low, medium, high, ultra }

enum PdfLayout { fitToPage, originalSize, centerFit, tileMultiple }

enum CompressionLevel { none, low, medium, high, maximum }

// Professional image processing result
class ProcessedImageData {
  final Uint8List imageBytes;
  final int originalSize;
  final int compressedSize;
  final int width;
  final int height;
  final double compressionRatio;

  ProcessedImageData({
    required this.imageBytes,
    required this.originalSize,
    required this.compressedSize,
    required this.width,
    required this.height,
    required this.compressionRatio,
  });
}

class ImageToPdfView extends StatefulWidget {
  const ImageToPdfView({Key? key}) : super(key: key);

  @override
  _ImageToPdfViewState createState() => _ImageToPdfViewState();
}

class _ImageToPdfViewState extends State<ImageToPdfView>
    with TickerProviderStateMixin {
  final List<File> _selectedImages = [];
  final List<ProcessedImageData> _processedImages = [];
  final List<ConvertedPdfDocument> _convertedDocuments = [];
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _fileNameController = TextEditingController();
  final PageController _previewPageController = PageController();

  // Processing state
  bool _isProcessing = false;
  double _processingProgress = 0.0;
  String _currentProcessingStep = '';
  bool _isViewMode = false; // true for list view, false for grid view

  // Selection mode state
  bool _isSelectionMode = false;
  Set<int> _selectedDocuments = {};

  // Advanced settings
  PdfPageSize _pageSize = PdfPageSize.a4;
  PdfOrientation _orientation = PdfOrientation.auto;
  ImageQuality _imageQuality = ImageQuality.high;
  PdfLayout _layout = PdfLayout.fitToPage;
  CompressionLevel _compression = CompressionLevel.medium;
  bool _addPageNumbers = false;
  bool _addTimestamp = false;
  bool _addWatermark = false;
  bool _protectWithPassword = false;
  String _password = '';
  double _margin = 20.0;

  // UI state
  bool _showPreview = false;
  bool _showSettings = false;
  int _currentPreviewIndex = 0;

  // Animation controllers
  late AnimationController _fabController;
  late AnimationController _settingsController;
  late Animation<double> _fabAnimation;
  late Animation<Offset> _settingsAnimation;

  // Platform channel for MediaStore operations
  static const MethodChannel _channel = MethodChannel('file_saver');

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _generateFileName();
    _loadConvertedDocuments();
    _loadViewModePreference();
  }

  void _initializeAnimations() {
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _settingsController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fabAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.elasticOut),
    );
    _settingsAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _settingsController,
      curve: Curves.easeOutBack,
    ));

    _fabController.forward();
  }

  @override
  void dispose() {
    _fabController.dispose();
    _settingsController.dispose();
    _previewPageController.dispose();
    _fileNameController.dispose();
    // Clear the lists to free memory
    _selectedImages.clear();
    _processedImages.clear();
    super.dispose();
  }

  void _generateFileName() {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    _fileNameController.text = 'PDF_Document_$timestamp';
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
  }

  // Load converted documents from storage
  Future<void> _loadConvertedDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final documentsJson =
          prefs.getStringList('converted_pdf_documents') ?? [];

      final documents = <ConvertedPdfDocument>[];
      for (final docJson in documentsJson) {
        try {
          final doc = ConvertedPdfDocument.fromJson(json.decode(docJson));
          // Check if file still exists
          if (await File(doc.filePath).exists()) {
            documents.add(doc);
          }
        } catch (e) {}
      }

      setState(() {
        _convertedDocuments.clear();
        _convertedDocuments.addAll(documents);
      });
    } catch (e) {
      // Error loading converted documents: $e (log removed)
    }
  }

  // Save converted documents to storage
  Future<void> _saveConvertedDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final documentsJson =
          _convertedDocuments.map((doc) => json.encode(doc.toJson())).toList();
      await prefs.setStringList('converted_pdf_documents', documentsJson);
    } catch (e) {
      // Error saving converted documents: $e (log removed)
    }
  }

  // Load and save view mode preference
  Future<void> _loadViewModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isViewMode = prefs.getBool('image_pdf_list_view_mode') ?? false;
      });
    } catch (e) {
      // Error loading view mode preference: $e (log removed)
    }
  }

  Future<void> _saveViewModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('image_pdf_list_view_mode', _isViewMode);
    } catch (e) {
      // Error saving view mode preference: $e (log removed)
    }
  }

  AppLocalizations get _localization => AppLocalizations.of(context);

  // Delete a converted document
  Future<void> _deleteConvertedDocument(ConvertedPdfDocument document) async {
    final localization = AppLocalizations.of(context);

    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.translate('confirmDelete')),
        content: Text(
            '${localization.translate('deleteDocumentConfirm')} "${document.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localization.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(localization.translate('delete')),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        // Delete the file
        final file = File(document.filePath);
        if (await file.exists()) {
          await file.delete();
        }

        // Remove from list and save
        setState(() {
          _convertedDocuments.removeWhere((doc) => doc.id == document.id);
        });

        await _saveConvertedDocuments();
        _showToast(localization.translate('documentDeleted'), Colors.green);
      } catch (e) {
        _showToast(
            localization.translate('failedToDeleteDocument'), Colors.red);
      }
    }
  }

  // Rename a converted document
  Future<void> _renameConvertedDocument(ConvertedPdfDocument document) async {
    final localization = AppLocalizations.of(context);
    final controller = TextEditingController(text: document.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.translate('renameDocument')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: localization.translate('documentName'),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(localization.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(localization.translate('rename')),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != document.name) {
      try {
        // Update the document name
        final updatedDoc = ConvertedPdfDocument(
          id: document.id,
          name: newName,
          filePath: document.filePath,
          createdAt: document.createdAt,
          fileSize: document.fileSize,
          imageCount: document.imageCount,
        );

        setState(() {
          final index =
              _convertedDocuments.indexWhere((doc) => doc.id == document.id);
          if (index != -1) {
            _convertedDocuments[index] = updatedDoc;
          }
        });

        await _saveConvertedDocuments();
        _showToast(localization.translate('documentRenamed'), Colors.green);
      } catch (e) {
        _showToast(
            localization.translate('failedToRenameDocument'), Colors.red);
      }
    }
  }

  // Share a converted document
  Future<void> _shareConvertedDocument(ConvertedPdfDocument document) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(document.filePath)]),
      );
    } catch (e) {
      final localization = AppLocalizations.of(context);
      _showToast(localization.translate('failedToShareDocument'), Colors.red);
    }
  }

  // Preview a converted document
  void _previewConvertedDocument(ConvertedPdfDocument document) {
    try {
      final file = File(document.filePath);
      if (!file.existsSync()) {
        _showToast(
            AppLocalizations.of(context).translate('documentFileNotFound'),
            Colors.red);
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PdfViewerScreen(
            localFile: file,
            title: document.name,
          ),
        ),
      );
    } catch (e) {
      _showToast(AppLocalizations.of(context).translate('failedToOpenDocument'),
          Colors.red);
    }
  }

  // Selection mode methods
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

  void _toggleDocumentSelection(int index) {
    setState(() {
      if (_selectedDocuments.contains(index)) {
        _selectedDocuments.remove(index);
      } else {
        _selectedDocuments.add(index);
      }
    });
  }

  Future<void> _shareBulkDocuments() async {
    try {
      final selectedDocs = _selectedDocuments
          .map((index) => _convertedDocuments[index])
          .toList();

      final files = selectedDocs.map((doc) => XFile(doc.filePath)).toList();
      await SharePlus.instance.share(
        ShareParams(files: files),
      );

      _exitSelectionMode();
    } catch (e) {
      final localization = AppLocalizations.of(context);
      _showToast(localization.translate('failedToShareDocuments'), Colors.red);
    }
  }

  Future<void> _deleteBulkDocuments() async {
    final localization = AppLocalizations.of(context);
    final count = _selectedDocuments.length;

    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.translate('confirmDelete')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == 1
                  ? localization.translate('areYouSureDeleteOneDocument')
                  : '${localization.translate('areYouSureDelete')} $count ${localization.translate('documents')}?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              localization.translate('cannotRestoreItems'),
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
            child: Text(localization.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(localization.translate('delete')),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        // Delete files and remove from list
        final indicesToRemove = _selectedDocuments.toList()
          ..sort((a, b) => b.compareTo(a));

        for (final index in indicesToRemove) {
          final document = _convertedDocuments[index];
          final file = File(document.filePath);

          if (await file.exists()) {
            await file.delete();
          }

          _convertedDocuments.removeAt(index);
        }

        await _saveConvertedDocuments();
        _exitSelectionMode();

        _showToast(
          '$count ${count == 1 ? localization.translate('documentDeleted') : localization.translate('documentsDeleted')}',
          Colors.green,
        );
      } catch (e) {
        _showToast(
            localization.translate('failedToDeleteDocuments'), Colors.red);
      }
    }
  }

  // Professional image processing with advanced options
  static Future<ProcessedImageData> _processImageAdvanced({
    required String imagePath,
    required ImageQuality quality,
    required CompressionLevel compression,
    required PdfOrientation orientation,
  }) async {
    try {
      final File imageFile = File(imagePath);
      final Uint8List originalBytes = await imageFile.readAsBytes();
      final int originalSize = originalBytes.length;

      img.Image? image = img.decodeImage(originalBytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      final int originalWidth = image.width;
      final int originalHeight = image.height;

      // Auto-rotation based on orientation setting
      if (orientation == PdfOrientation.auto) {
        // Auto-detect orientation and rotate if needed - fix the logic
        if (originalWidth < originalHeight &&
            orientation == PdfOrientation.auto) {
          // Keep portrait as is
        }
      } else if (orientation == PdfOrientation.landscape &&
          originalHeight > originalWidth) {
        image = img.copyRotate(image, angle: 90);
      }

      // Quality-based resizing
      int targetMaxDimension;
      switch (quality) {
        case ImageQuality.low:
          targetMaxDimension = 800;
          break;
        case ImageQuality.medium:
          targetMaxDimension = 1200;
          break;
        case ImageQuality.high:
          targetMaxDimension = 1800;
          break;
        case ImageQuality.ultra:
          targetMaxDimension = 2400;
          break;
      }

      // Resize if needed
      if (image.width > targetMaxDimension ||
          image.height > targetMaxDimension) {
        if (image.width > image.height) {
          image = img.copyResize(image, width: targetMaxDimension);
        } else {
          image = img.copyResize(image, height: targetMaxDimension);
        }
      }

      // Remove the enhancement that might be causing issues
      // image = _enhanceImage(image);

      // Compression-based encoding
      int jpegQuality;
      switch (compression) {
        case CompressionLevel.none:
          jpegQuality = 100;
          break;
        case CompressionLevel.low:
          jpegQuality = 95;
          break;
        case CompressionLevel.medium:
          jpegQuality = 85;
          break;
        case CompressionLevel.high:
          jpegQuality = 75;
          break;
        case CompressionLevel.maximum:
          jpegQuality = 60;
          break;
      }

      final Uint8List processedBytes =
          Uint8List.fromList(img.encodeJpg(image, quality: jpegQuality));

      return ProcessedImageData(
        imageBytes: processedBytes,
        originalSize: originalSize,
        compressedSize: processedBytes.length,
        width: image.width,
        height: image.height,
        compressionRatio: (1 - processedBytes.length / originalSize) * 100,
      );
    } catch (e) {
      // Error in _processImageAdvanced: $e (log removed)
      throw Exception('Failed to process image: $e');
    }
  }

  // Simple image processing fallback method
  static Future<ProcessedImageData> _processImageSimple(
      String imagePath) async {
    try {
      final File imageFile = File(imagePath);
      final Uint8List originalBytes = await imageFile.readAsBytes();
      final int originalSize = originalBytes.length;

      // Try to get image dimensions, fallback to defaults if it fails
      int width = 800;
      int height = 600;

      try {
        img.Image? image = img.decodeImage(originalBytes);
        if (image != null) {
          width = image.width;
          height = image.height;
        }
      } catch (e) {
        // Use original bytes and default dimensions
      }

      return ProcessedImageData(
        imageBytes: originalBytes,
        originalSize: originalSize,
        compressedSize: originalBytes.length,
        width: width,
        height: height,
        compressionRatio: 0.0,
      );
    } catch (e) {
      // Error in _processImageSimple: $e (log removed)
      throw Exception('Failed to process image: $e');
    }
  }

  Future<void> _pickImages() async {
    final localization = AppLocalizations.of(context);
    try {
      final cleanMediaService = CleanMediaService();
      final images =
          await cleanMediaService.pickMultipleImagesFromGallery(context);

      if (images != null && images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
        });

        // Auto-process images for preview
        await _preprocessImages();
      }
    } catch (e) {
      _showToast(localization.translate('failedToPickImages'), Colors.red);
    }
  }

  Future<void> _takePhoto() async {
    final localization = AppLocalizations.of(context);
    try {
      final cleanMediaService = CleanMediaService();
      final image = await cleanMediaService.pickImageFromCamera(context);

      if (image != null) {
        setState(() {
          _selectedImages.add(image);
        });

        await _preprocessImages();
      }
    } catch (e) {
      _showToast(localization.translate('failedToCapturePhoto'), Colors.red);
    }
  } // Preprocess images for preview and size calculation

  Future<void> _preprocessImages() async {
    if (_selectedImages.isEmpty) return;

    final localization = AppLocalizations.of(context);
    setState(() {
      _isProcessing = true;
      _processingProgress = 0.0;
      _currentProcessingStep = localization.translate('preprocessingImages');
    });

    try {
      _processedImages.clear();

      for (int i = 0; i < _selectedImages.length; i++) {
        setState(() {
          _processingProgress = i / _selectedImages.length;
          _currentProcessingStep =
              '${localization.translate('processingImage').replaceAll('{current}', '${i + 1}').replaceAll('{total}', '${_selectedImages.length}')}';
        });

        try {
          final processedData = await _processImageAdvanced(
            imagePath: _selectedImages[i].path,
            quality: _imageQuality,
            compression: _compression,
            orientation: _orientation,
          );
          _processedImages.add(processedData);
        } catch (e) {
          // Fallback to simple processing
          final processedData =
              await _processImageSimple(_selectedImages[i].path);
          _processedImages.add(processedData);
        }

        await Future.delayed(const Duration(milliseconds: 50));
      }

      setState(() {
        _isProcessing = false;
        _processingProgress = 1.0;
        _currentProcessingStep = localization.translate('readyForConversion');
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showToast(
          localization.translate('failedToPreprocessImages'), Colors.red);
    }
  }

  PdfPageFormat _getPdfPageFormat() {
    switch (_pageSize) {
      case PdfPageSize.a4:
        return _orientation == PdfOrientation.landscape
            ? PdfPageFormat.a4.landscape
            : PdfPageFormat.a4;
      case PdfPageSize.letter:
        return _orientation == PdfOrientation.landscape
            ? PdfPageFormat.letter.landscape
            : PdfPageFormat.letter;
      case PdfPageSize.legal:
        return _orientation == PdfOrientation.landscape
            ? PdfPageFormat.legal.landscape
            : PdfPageFormat.legal;
      case PdfPageSize.a3:
        return _orientation == PdfOrientation.landscape
            ? PdfPageFormat.a3.landscape
            : PdfPageFormat.a3;
      case PdfPageSize.a5:
        return _orientation == PdfOrientation.landscape
            ? PdfPageFormat.a5.landscape
            : PdfPageFormat.a5;
      default:
        return PdfPageFormat.a4;
    }
  }

  // Professional PDF generation with advanced features
  Future<void> _convertToPDF() async {
    final localization = AppLocalizations.of(context);
    if (_selectedImages.isEmpty) {
      _showToast(
          localization.translate('pleaseSelectImagesFirst'), Colors.orange);
      return;
    }

    // QUOTA CHECK: Check if user can add more image-to-pdf documents
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final canAdd = await QuotaHelper.checkAndWarnQuota(
        context: context,
        uid: user.uid,
        section: 'imageToPdf',
        toolName: 'imageToPdf',
      );

      if (!canAdd) {
        return; // User hit quota limit
      }
    }

    setState(() {
      _isProcessing = true;
      _processingProgress = 0.0;
      _currentProcessingStep =
          localization.translate('initializingPdfCreation');
    });

    try {
      // Create PDF document with metadata
      final pdf = pw.Document(
        title: _fileNameController.text.trim(),
        author: 'Broker Wallet Pro',
        creator: 'JPG to PDF Converter',
        subject: 'Converted Images to PDF',
        keywords: 'images, pdf, conversion, professional',
      );

      final pageFormat = _getPdfPageFormat();
      final int totalImages = _selectedImages.length;

      // Add cover page if enabled
      if (_addTimestamp || _addWatermark) {
        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.all(_margin.toDouble()),
            build: (pw.Context context) => _buildCoverPage(),
          ),
        );
      }

      // Process and add each image
      for (int i = 0; i < _selectedImages.length; i++) {
        setState(() {
          _processingProgress = (i / totalImages) * 0.8;
          _currentProcessingStep = localization
              .translate('convertingImage')
              .replaceAll('{current}', '${i + 1}')
              .replaceAll('{total}', '$totalImages');
        });

        ProcessedImageData processedData;
        if (i < _processedImages.length) {
          processedData = _processedImages[i];
        } else {
          // Try advanced processing, fallback to simple processing
          try {
            processedData = await _processImageAdvanced(
              imagePath: _selectedImages[i].path,
              quality: _imageQuality,
              compression: _compression,
              orientation: _orientation,
            );
          } catch (e) {
            // Fallback to simple processing
            processedData = await _processImageSimple(_selectedImages[i].path);
          }
        }

        final image = pw.MemoryImage(processedData.imageBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.all(_margin.toDouble()),
            build: (pw.Context context) => _buildImagePage(
              image,
              i + 1,
              totalImages,
              processedData,
            ),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 10));
      }

      setState(() {
        _processingProgress = 0.9;
        _currentProcessingStep = localization.translate('finalizingPdf');
      });

      // Save PDF
      final output = await getApplicationDocumentsDirectory();
      final sanitizedName = _sanitizeFileName(_fileNameController.text.trim());
      final fileName =
          sanitizedName.isEmpty ? 'converted_images' : sanitizedName;
      final file = File('${output.path}/$fileName.pdf');

      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);

      setState(() {
        _processingProgress = 1.0;
        _currentProcessingStep = 'PDF created successfully!';
        _isProcessing = false;
      });

      // Create and save the converted document record
      final convertedDoc = ConvertedPdfDocument(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: fileName,
        filePath: file.path,
        createdAt: DateTime.now(),
        fileSize: pdfBytes.length,
        imageCount: _selectedImages.length,
      );

      setState(() {
        _convertedDocuments.insert(0, convertedDoc);
      });

      await _saveConvertedDocuments();

      // Update quota count
      if (user != null) {
        await _incrementQuotaCount(user.uid, 'imageToPdf');
      }

      _resetForm();

      // Show success toast instead of dialog
      _showToast(
        '${localization.translate('pdfCreatedSuccessfully')} "${fileName}.pdf"',
        Colors.green,
      );
    } catch (e) {
      setState(() => _isProcessing = false);
      _showToast(localization.translate('failedToCreatePdf'), Colors.red);
    }
  }

  Future<void> _incrementQuotaCount(String uid, String section) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'counts': {section: FieldValue.increment(1)},
        'lifetimeCreated': {section: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (e) {}
  }

  // Build cover page with professional layout
  pw.Widget _buildCoverPage() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Header(
          level: 0,
          child: pw.Text(
            'PDF Document',
            style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 40),
        pw.Container(
          padding: const pw.EdgeInsets.all(20),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Document Information',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),
              pw.Text('Title: ${_fileNameController.text.trim()}'),
              pw.Text('Total Images: ${_selectedImages.length}'),
              pw.Text('Page Size: ${_pageSize.name.toUpperCase()}'),
              pw.Text('Orientation: ${_orientation.name.toUpperCase()}'),
              pw.Text('Quality: ${_imageQuality.name.toUpperCase()}'),
              if (_addTimestamp)
                pw.Text('Created: ${DateTime.now().toString().split('.')[0]}'),
              pw.Text('Generated by: Broker Wallet Pro'),
            ],
          ),
        ),
        pw.Spacer(),
        if (_addWatermark)
          pw.Center(
            child: pw.Opacity(
              opacity: 0.1,
              child: pw.Text(
                'BROKER WALLET PRO',
                style:
                    pw.TextStyle(fontSize: 48, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  // Build individual image page with advanced layout
  pw.Widget _buildImagePage(
    pw.MemoryImage image,
    int pageNumber,
    int totalPages,
    ProcessedImageData data,
  ) {
    pw.Widget imageWidget;

    switch (_layout) {
      case PdfLayout.fitToPage:
        imageWidget = pw.Expanded(
          child: pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        );
        break;
      case PdfLayout.originalSize:
        imageWidget = pw.Center(
          child: pw.Image(image),
        );
        break;
      case PdfLayout.centerFit:
        imageWidget = pw.Expanded(
          child: pw.Center(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Image(image, fit: pw.BoxFit.cover),
            ),
          ),
        );
        break;
      case PdfLayout.tileMultiple:
        imageWidget = pw.Expanded(
          child: pw.Image(image, fit: pw.BoxFit.cover),
        );
        break;
    }

    return pw.Column(
      children: [
        imageWidget,
        if (_addPageNumbers || _addTimestamp)
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (_addPageNumbers)
                  pw.Text(
                    'Page $pageNumber of $totalPages',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                if (_addTimestamp)
                  pw.Text(
                    'Size: ${data.width}×${data.height} | ${(data.compressedSize / 1024).toStringAsFixed(1)}KB',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
              ],
            ),
          ),
        if (_addWatermark)
          pw.Positioned(
            right: 20,
            bottom: 20,
            child: pw.Opacity(
              opacity: 0.3,
              child: pw.Text(
                'Broker Wallet',
                style: pw.TextStyle(fontSize: 12, color: PdfColors.grey),
              ),
            ),
          ),
      ],
    );
  }

  void _resetForm() {
    setState(() {
      _selectedImages.clear();
      _processedImages.clear();
      _currentPreviewIndex = 0;
    });
    _generateFileName();
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      if (index < _processedImages.length) {
        _processedImages.removeAt(index);
      }
    });
  }

  void _reorderImages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _selectedImages.removeAt(oldIndex);
      _selectedImages.insert(newIndex, item);

      if (oldIndex < _processedImages.length &&
          newIndex < _processedImages.length) {
        final processedItem = _processedImages.removeAt(oldIndex);
        _processedImages.insert(newIndex, processedItem);
      }
    });
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AdvancedSettingsSheet(
        pageSize: _pageSize,
        orientation: _orientation,
        imageQuality: _imageQuality,
        layout: _layout,
        compression: _compression,
        addPageNumbers: _addPageNumbers,
        addTimestamp: _addTimestamp,
        addWatermark: _addWatermark,
        margin: _margin,
        onSettingsChanged: (settings) {
          setState(() {
            _pageSize = settings['pageSize'] ?? _pageSize;
            _orientation = settings['orientation'] ?? _orientation;
            _imageQuality = settings['imageQuality'] ?? _imageQuality;
            _layout = settings['layout'] ?? _layout;
            _compression = settings['compression'] ?? _compression;
            _addPageNumbers = settings['addPageNumbers'] ?? _addPageNumbers;
            _addTimestamp = settings['addTimestamp'] ?? _addTimestamp;
            _addWatermark = settings['addWatermark'] ?? _addWatermark;
            _margin = settings['margin'] ?? _margin;
          });

          // Reprocess images with new settings
          if (_selectedImages.isNotEmpty) {
            _preprocessImages();
          }
        },
      ),
    );
  }

  void _showPreviewDialog() {
    if (_processedImages.isEmpty) return;

    final localization = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      localization.translate('pdfPreview'),
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _previewPageController,
                  itemCount: _processedImages.length,
                  onPageChanged: (index) {
                    setState(() => _currentPreviewIndex = index);
                  },
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Image.memory(
                        _processedImages[index].imageBytes,
                        fit: BoxFit.contain,
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(localization
                        .translate('pageOf')
                        .replaceAll('{current}', '${_currentPreviewIndex + 1}')
                        .replaceAll('{total}', '${_processedImages.length}')),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios),
                          onPressed: _currentPreviewIndex > 0
                              ? () => _previewPageController.previousPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  )
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios),
                          onPressed: _currentPreviewIndex <
                                  _processedImages.length - 1
                              ? () => _previewPageController.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  )
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// Enhanced _saveToDeviceStorage method with proper Android 11+ support
  Future<void> _saveToDeviceStorage(File pdfFile) async {
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
            final fileName = pdfFile.path.split('/').last;
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final nameWithoutExt = fileName.replaceAll('.pdf', '');
            final uniqueFileName = '${nameWithoutExt}_$timestamp.pdf';
            final fileBytes = await pdfFile.readAsBytes();

            final result = await _channel.invokeMethod('saveFileToDownloads', {
              'fileName': uniqueFileName,
              'fileBytes': fileBytes,
              'mimeType': 'application/pdf',
            });

            if (result['success'] == true) {
              _showToast(
                '${localization.translate('pdfSavedTo')} Downloads\nFile: $uniqueFileName\n(Accessible via Files app)',
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
      final fileName = pdfFile.path.split('/').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final nameWithoutExt = fileName.replaceAll('.pdf', '');
      final uniqueFileName = '${nameWithoutExt}_$timestamp.pdf';
      final destinationPath = '${downloadsDirectory.path}/$uniqueFileName';

      // Ensure the directory exists
      await downloadsDirectory.create(recursive: true);

      // Copy the file to the destination
      final destinationFile = File(destinationPath);
      await pdfFile.copy(destinationPath);

      // Verify the file was created and get its actual size
      if (await destinationFile.exists()) {
        // Show success with actual path info
        _showToast(
          '${localization.translate('pdfSavedTo')} $locationName\nFile: $uniqueFileName',
          Colors.green,
        );

        // Additional debug info
        try {
          final files = await downloadsDirectory.list().toList();
          for (var file in files) {
            if (file.path.contains('.pdf')) {}
          }
        } catch (e) {}
      } else {
        throw Exception(
            'File was not created at destination: $destinationPath');
      }
    } catch (e) {
      _showToast(
          '${localization.translate('failedToSavePdf')}: ${e.toString()}',
          Colors.red);
    }
  }

  void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
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

  PreferredSizeWidget _buildAdvancedAppBar(
      AppLocalizations localization, ColorScheme colors) {
    return AppBar(
      leading: const BackArrowButton(
        iconColor: Colors.white, // Set to white to match the green gradient
        backgroundColor: Colors
            .transparent, // Make background transparent since we have gradient
        showBackground: false, // Disable the default background circle
      ),
      title: Column(
        children: [
          Text(
            _isSelectionMode
                ? '${_selectedDocuments.length} ${localization.translate('selected')}'
                : localization.translate('imageToPdf'),
            style: AppTextStyles.appBarTitle
                .copyWith(fontSize: 20, color: Colors.white),
          ),
          if (_convertedDocuments.isNotEmpty && !_isSelectionMode)
            Text(
              '${_convertedDocuments.length} ${localization.translate('documents')}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          if (_selectedImages.isNotEmpty && !_isSelectionMode)
            Text(
              '${_selectedImages.length} ${_selectedImages.length == 1 ? localization.translate('image') : localization.translate('images')}',
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
              const Color(0xFF4CAF50).withValues(alpha: 0.9),
              const Color(0xFF2E7D32).withValues(alpha: 0.7),
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
            tooltip: localization.translate('shareSelected'),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed:
                _selectedDocuments.isNotEmpty ? _deleteBulkDocuments : null,
            tooltip: localization.translate('deleteSelected'),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _exitSelectionMode,
            tooltip: localization.translate('cancelSelection'),
          ),
        ] else ...[
          if (_convertedDocuments.isNotEmpty) ...[
            IconButton(
              icon: Icon(
                _isViewMode ? Icons.grid_view : Icons.view_list,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() => _isViewMode = !_isViewMode);
                _saveViewModePreference();
              },
              tooltip: _isViewMode
                  ? localization.translate('gridView')
                  : localization.translate('listView'),
            ),
            IconButton(
              icon: const Icon(Icons.checklist, color: Colors.white),
              onPressed: _enterSelectionMode,
              tooltip: localization.translate('selectDocuments'),
            ),
          ] else if (_selectedImages.isNotEmpty && !_isProcessing) ...[
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: _showSettingsBottomSheet,
              tooltip: localization.translate('settings'),
            ),
            IconButton(
              icon: const Icon(Icons.clear_all, color: Colors.white),
              onPressed: () => setState(() {
                _selectedImages.clear();
                _processedImages.clear();
              }),
              tooltip: localization.translate('clearAll'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildBody(AppLocalizations localization, ColorScheme colors) {
    return CustomScrollView(
      slivers: [
        // Header space for transparent app bar
        const SliverToBoxAdapter(child: SizedBox(height: 120)),

        // Header info card
        SliverToBoxAdapter(
          child: _buildHeaderCard(localization, colors),
        ),

        // Processing indicator
        if (_isProcessing)
          SliverToBoxAdapter(
            child: _buildProcessingIndicator(localization, colors),
          ),

        // Show creation interface when creating new PDFs
        if (_selectedImages.isNotEmpty) ...[
          // File name input
          SliverToBoxAdapter(
            child: _buildFileNameInput(localization, colors),
          ),
          // Selected images header
          SliverToBoxAdapter(
            child: _buildSelectedImagesHeader(localization),
          ),
          // Selected images list
          SliverReorderableList(
            itemCount: _selectedImages.length,
            onReorder: _reorderImages,
            itemBuilder: (context, index) {
              return _buildImageCard(index, colors, localization);
            },
          ),
        ] else if (_convertedDocuments.isEmpty) ...[
          // Empty state when no documents exist
          SliverToBoxAdapter(
            child: _buildEmptyState(localization, colors),
          ),
        ] else ...[
          // Converted documents header
          SliverToBoxAdapter(
            child: _buildConvertedDocumentsHeader(localization),
          ),
          // Converted documents list or grid
          if (_isViewMode)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _buildConvertedDocumentCard(
                      _convertedDocuments[index], index, colors, localization);
                },
                childCount: _convertedDocuments.length,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return _buildConvertedDocumentGridCard(
                        _convertedDocuments[index],
                        index,
                        colors,
                        localization);
                  },
                  childCount: _convertedDocuments.length,
                ),
              ),
            ),
        ],

        // Bottom padding for FAB
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildHeaderCard(AppLocalizations localization, ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.picture_as_pdf,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization.translate('imageToPdfConverter'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localization.translate('convertYourImages'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
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
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentProcessingStep,
                      style: AppTextStyles.bodyText.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(_processingProgress * 100).toInt()}% ${localization.translate('complete')}',
                      style: AppTextStyles.bodyText.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _processingProgress,
            backgroundColor: colors.outline.withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
          ),
        ],
      ),
    );
  }

  Widget _buildFileNameInput(
      AppLocalizations localization, ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit, size: 20, color: const Color(0xFF4CAF50)),
              const SizedBox(width: 8),
              Text(
                localization.translate('fileName'),
                style: AppTextStyles.bodyText.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fileNameController,
            decoration: InputDecoration(
              hintText: localization.translate('enterFileName'),
              suffixText: '.pdf',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations localization, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Color(0xFF4CAF50),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localization.translate('noImagesSelected'),
            style: AppTextStyles.bodyText.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localization.translate('selectImagesToConvertToPdf'),
            style: AppTextStyles.bodyText.copyWith(
              color: colors.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedImagesHeader(AppLocalizations localization) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and settings button row
          Row(
            children: [
              Text(
                '${localization.translate('selectedImages')} (${_selectedImages.length})',
                style: AppTextStyles.bodyText.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _showSettingsBottomSheet,
                icon: const Icon(Icons.tune),
                tooltip: localization.translate('pdfSettings'),
                style: IconButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF4CAF50).withValues(alpha: 0.1),
                  foregroundColor: const Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Action buttons row
          Row(
            children: [
              // Camera button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: Text(localization.translate('camera')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Add images button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(localization.translate('add')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.tilePrimary,
                    foregroundColor: const Color(0xFF4CAF50),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Preview button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      _processedImages.isNotEmpty ? _showPreviewDialog : null,
                  icon: const Icon(Icons.preview, size: 18),
                  label: Text(localization.translate('preview')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _processedImages.isNotEmpty
                        ? AppColors.tilePrimary
                        : Colors.grey.withValues(alpha: 0.2),
                    foregroundColor: _processedImages.isNotEmpty
                        ? const Color(0xFF4CAF50)
                        : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard(
      int index, ColorScheme colors, AppLocalizations localization) {
    final file = _selectedImages[index];

    return Container(
      key: ValueKey(file.path),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 80,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              fit: BoxFit.cover,
            ),
          ),
        ),
        title: Text(
          '${localization.translate('image')} ${index + 1}',
          style: AppTextStyles.bodyText.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            localization
                .translate('positionOf')
                .replaceAll('{position}', '${index + 1}')
                .replaceAll('{total}', '${_selectedImages.length}'),
            style: AppTextStyles.bodyText.copyWith(
              color: colors.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.outline.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.drag_handle,
                color: colors.onSurface.withValues(alpha: 0.6),
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: colors.error,
                size: 20,
              ),
              onPressed: () => _removeImage(index),
              tooltip: localization.translate('removeImage'),
              style: IconButton.styleFrom(
                backgroundColor: colors.error.withValues(alpha: 0.1),
                foregroundColor: colors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConvertedDocumentsHeader(AppLocalizations localization) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.picture_as_pdf,
              color: const Color(0xFF4CAF50),
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${localization.translate('convertedDocuments')} (${_convertedDocuments.length})',
            style: AppTextStyles.bodyText.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF4CAF50),
            ),
          ),
          const Spacer(),
          if (_convertedDocuments.isNotEmpty)
            Text(
              _isViewMode
                  ? localization.translate('gridView')
                  : localization.translate('listView'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConvertedDocumentCard(ConvertedPdfDocument document, int index,
      ColorScheme colors, AppLocalizations localization) {
    final isSelected = _selectedDocuments.contains(index);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF4CAF50)
              : colors.outline.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.05),
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
                activeColor: const Color(0xFF4CAF50),
              )
            : Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.picture_as_pdf,
                  color: const Color(0xFF4CAF50),
                  size: 24,
                ),
              ),
        title: Text(
          document.name,
          style: AppTextStyles.bodyText.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: colors.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                '${document.imageCount} ${localization.translate('images')} • ${_formatFileSize(document.fileSize)}',
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.visibility, color: Color(0xFF4CAF50), size: 20),
              onPressed: () => _previewConvertedDocument(document),
              tooltip: localization.translate('preview'),
              visualDensity: VisualDensity.compact,
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  color: colors.onSurface.withValues(alpha: 0.6)),
              onSelected: (value) {
                switch (value) {
                  case 'share':
                    _shareConvertedDocument(document);
                    break;
                  case 'download':
                    _saveToDeviceStorage(File(document.filePath));
                    break;
                  case 'rename':
                    _renameConvertedDocument(document);
                    break;
                  case 'delete':
                    _deleteConvertedDocument(document);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      const Icon(Icons.share, size: 18, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(localization.translate('share')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      const Icon(Icons.download, size: 18, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(localization.translate('download')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(localization.translate('rename')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        localization.translate('delete'),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () {
          if (_isSelectionMode) {
            _toggleDocumentSelection(index);
          } else {
            _previewConvertedDocument(document);
          }
        },
      ),
    );
  }

  Widget _buildConvertedDocumentGridCard(ConvertedPdfDocument document,
      int index, ColorScheme colors, AppLocalizations localization) {
    final isSelected = _selectedDocuments.contains(index);
    return Card(
      margin: const EdgeInsets.all(2),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF4CAF50)
              : const Color(0xFF4CAF50).withValues(alpha: 0.2),
          width: isSelected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            _toggleDocumentSelection(index);
          } else {
            _previewConvertedDocument(document);
          }
        },
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
                const Color(0xFF4CAF50).withValues(alpha: 0.02),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row with PDF icon and more options menu
              Row(
                children: [
                  // Selection indicator or document type icon
                  _isSelectionMode
                      ? Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF4CAF50)
                                : Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isSelected
                                ? Icons.check
                                : Icons.radio_button_unchecked,
                            color: isSelected ? Colors.white : Colors.grey,
                            size: 18,
                          ),
                        )
                      : Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF4CAF50).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.picture_as_pdf,
                            color: const Color(0xFF4CAF50),
                            size: 18,
                          ),
                        ),

                  const Spacer(),

                  // More options menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'preview':
                          _previewConvertedDocument(document);
                          break;
                        case 'share':
                          _shareConvertedDocument(document);
                          break;
                        case 'download':
                          _saveToDeviceStorage(File(document.filePath));
                          break;
                        case 'rename':
                          _renameConvertedDocument(document);
                          break;
                        case 'delete':
                          _deleteConvertedDocument(document);
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
                            Text(localization.translate('rename')),
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
                              localization.translate('delete'),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Document name
              Text(
                document.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: colors.onSurface,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 6),

              // Document format and image count
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${document.imageCount} ${localization.translate('images')} • PDF',
                  style: TextStyle(
                    color: const Color(0xFF4CAF50),
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(height: 6),

              // Date and file size with fixed height
              SizedBox(
                height: 14, // Fixed height for date
                child: Text(
                  _formatDateTime(document.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                ),
              ),

              const SizedBox(height: 6),

              // File size with fixed height
              SizedBox(
                height: 12, // Fixed height for file size row
                child: Row(
                  children: [
                    Icon(
                      Icons.folder,
                      size: 10,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _formatFileSize(document.fileSize),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),

              // Fixed spacing instead of Spacer for consistent layout
              const SizedBox(height: 10),

              // Quick action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildGridActionButton(
                    icon: Icons.visibility,
                    onTap: () => _previewConvertedDocument(document),
                    color: const Color(0xFF4CAF50),
                  ),
                  _buildGridActionButton(
                    icon: Icons.share,
                    onTap: () => _shareConvertedDocument(document),
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
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: color,
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton(AppLocalizations localization) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: _selectedImages.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isProcessing ? null : _convertToPDF,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_isProcessing
                  ? '${localization.translate('converting')} ${(_processingProgress * 100).toInt()}%'
                  : localization.translate('convertToPdf')),
              backgroundColor:
                  _isProcessing ? Colors.grey : const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
            )
          : FloatingActionButton.extended(
              onPressed: _pickImages,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(localization.translate('selectImages')),
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: false, // Prevent keyboard from moving the form
      backgroundColor: colors.surface,
      extendBodyBehindAppBar: true,
      appBar: _buildAdvancedAppBar(localization, colors),
      body: _buildBody(localization, colors),
      floatingActionButton: _buildFloatingActionButton(localization),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

// Advanced Settings Sheet Widget for professional PDF configuration
class _AdvancedSettingsSheet extends StatefulWidget {
  final PdfPageSize pageSize;
  final PdfOrientation orientation;
  final ImageQuality imageQuality;
  final PdfLayout layout;
  final CompressionLevel compression;
  final bool addPageNumbers;
  final bool addTimestamp;
  final bool addWatermark;
  final double margin;
  final Function(Map<String, dynamic>) onSettingsChanged;

  const _AdvancedSettingsSheet({
    required this.pageSize,
    required this.orientation,
    required this.imageQuality,
    required this.layout,
    required this.compression,
    required this.addPageNumbers,
    required this.addTimestamp,
    required this.addWatermark,
    required this.margin,
    required this.onSettingsChanged,
  });

  @override
  State<_AdvancedSettingsSheet> createState() => _AdvancedSettingsSheetState();
}

class _AdvancedSettingsSheetState extends State<_AdvancedSettingsSheet> {
  late PdfPageSize _pageSize;
  late PdfOrientation _orientation;
  late ImageQuality _imageQuality;
  late PdfLayout _layout;
  late CompressionLevel _compression;
  late bool _addPageNumbers;
  late bool _addTimestamp;
  late bool _addWatermark;
  late double _margin;

  @override
  void initState() {
    super.initState();
    _pageSize = widget.pageSize;
    _orientation = widget.orientation;
    _imageQuality = widget.imageQuality;
    _layout = widget.layout;
    _compression = widget.compression;
    _addPageNumbers = widget.addPageNumbers;
    _addTimestamp = widget.addTimestamp;
    _addWatermark = widget.addWatermark;
    _margin = widget.margin;
  }

  void _applySettings() {
    widget.onSettingsChanged({
      'pageSize': _pageSize,
      'orientation': _orientation,
      'imageQuality': _imageQuality,
      'layout': _layout,
      'compression': _compression,
      'addPageNumbers': _addPageNumbers,
      'addTimestamp': _addTimestamp,
      'addWatermark': _addWatermark,
      'margin': _margin,
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4CAF50),
                  const Color(0xFF4CAF50).withValues(alpha: 0.8)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings, color: AppColors.white, size: 28),
                const SizedBox(width: 12),
                Text(
                  localization.translate('advancedPdfSettings'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppColors.white),
                ),
              ],
            ),
          ),

          // Settings content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Page Format Section
                  _buildSectionHeader(
                      localization.translate('pageFormat'), Icons.aspect_ratio),
                  const SizedBox(height: 12),
                  _buildDropdownField<PdfPageSize>(
                    localization.translate('pageSize'),
                    _pageSize,
                    PdfPageSize.values,
                    (value) => setState(() => _pageSize = value!),
                    (size) => size.name.toUpperCase(),
                  ),
                  const SizedBox(height: 12),
                  _buildDropdownField<PdfOrientation>(
                    localization.translate('orientation'),
                    _orientation,
                    PdfOrientation.values,
                    (value) => setState(() => _orientation = value!),
                    (orientation) {
                      switch (orientation) {
                        case PdfOrientation.portrait:
                          return localization.translate('portrait');
                        case PdfOrientation.landscape:
                          return localization.translate('landscape');
                        case PdfOrientation.auto:
                          return localization.translate('auto');
                      }
                    },
                  ),

                  const SizedBox(height: 24),

                  // Image Quality Section
                  _buildSectionHeader(localization.translate('imageProcessing'),
                      Icons.photo_filter),
                  const SizedBox(height: 12),
                  _buildDropdownField<ImageQuality>(
                    localization.translate('imageQuality'),
                    _imageQuality,
                    ImageQuality.values,
                    (value) => setState(() => _imageQuality = value!),
                    (quality) {
                      switch (quality) {
                        case ImageQuality.low:
                          return localization.translate('low');
                        case ImageQuality.medium:
                          return localization.translate('medium');
                        case ImageQuality.high:
                          return localization.translate('high');
                        case ImageQuality.ultra:
                          return localization.translate('ultra');
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildDropdownField<CompressionLevel>(
                    localization.translate('compression'),
                    _compression,
                    CompressionLevel.values,
                    (value) => setState(() => _compression = value!),
                    (compression) {
                      switch (compression) {
                        case CompressionLevel.none:
                          return localization.translate('none');
                        case CompressionLevel.low:
                          return localization.translate('low');
                        case CompressionLevel.medium:
                          return localization.translate('medium');
                        case CompressionLevel.high:
                          return localization.translate('high');
                        case CompressionLevel.maximum:
                          return localization.translate('maximum');
                      }
                    },
                  ),

                  const SizedBox(height: 24),

                  // Layout Section
                  _buildSectionHeader(localization.translate('layoutAndDesign'),
                      Icons.design_services),
                  const SizedBox(height: 12),
                  _buildDropdownField<PdfLayout>(
                    localization.translate('layoutStyle'),
                    _layout,
                    PdfLayout.values,
                    (value) => setState(() => _layout = value!),
                    (layout) {
                      switch (layout) {
                        case PdfLayout.fitToPage:
                          return localization.translate('fitToPage');
                        case PdfLayout.originalSize:
                          return localization.translate('originalSize');
                        case PdfLayout.centerFit:
                          return localization.translate('centerFit');
                        case PdfLayout.tileMultiple:
                          return localization.translate('tileMultiple');
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildSliderField(
                    localization.translate('pageMargin'),
                    _margin,
                    0.0,
                    50.0,
                    (value) => setState(() => _margin = value),
                    '${_margin.toInt()}px',
                  ),

                  const SizedBox(height: 24),

                  // Professional Features Section
                  _buildSectionHeader(
                      localization.translate('professionalFeatures'),
                      Icons.business_center),
                  const SizedBox(height: 12),
                  _buildSwitchTile(
                    localization.translate('addPageNumbers'),
                    localization.translate('includePageNumbersBottom'),
                    _addPageNumbers,
                    (value) => setState(() => _addPageNumbers = value),
                    Icons.format_list_numbered,
                  ),
                  _buildSwitchTile(
                    localization.translate('addTimestamp'),
                    localization.translate('includeCreationDateTime'),
                    _addTimestamp,
                    (value) => setState(() => _addTimestamp = value),
                    Icons.access_time,
                  ),
                  _buildSwitchTile(
                    localization.translate('addWatermark'),
                    localization.translate('includeAppWatermark'),
                    _addWatermark,
                    (value) => setState(() => _addWatermark = value),
                    Icons.branding_watermark,
                  ),

                  const SizedBox(height: 32),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.cancel),
                          label: Text(localization.translate('cancel')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.card,
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _applySettings,
                          icon: const Icon(Icons.check),
                          label: Text(localization.translate('applySettings')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.tilePrimary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF4CAF50), size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField<T>(
    String label,
    T value,
    List<T> options,
    ValueChanged<T?> onChanged,
    String Function(T) displayText,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.card),
            borderRadius: BorderRadius.circular(8),
            color: AppColors.surface,
          ),
          child: DropdownButton<T>(
            value: value,
            onChanged: onChanged,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: AppColors.surface,
            items: options.map((option) {
              return DropdownMenuItem<T>(
                value: option,
                child: Text(
                  displayText(option),
                  style: TextStyle(color: AppColors.textPrimary),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderField(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    String displayValue,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                displayValue,
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF4CAF50),
            inactiveTrackColor: AppColors.card,
            thumbColor: const Color(0xFF4CAF50),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / 5).round(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
            color: value
                ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
                : AppColors.card),
        borderRadius: BorderRadius.circular(12),
        color: value
            ? const Color(0xFF4CAF50).withValues(alpha: 0.05)
            : AppColors.surface,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
                  : AppColors.card,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: value ? const Color(0xFF4CAF50) : AppColors.textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF4CAF50).withValues(alpha: 0.5),
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFF4CAF50).withValues(alpha: 0.8);
              }
              return Colors.grey.shade400;
            }),
          ),
        ],
      ),
    );
  }
}
