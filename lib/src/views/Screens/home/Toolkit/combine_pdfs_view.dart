import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:broker_wallet/src/services/quota_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:broker_wallet/src/services/clean_permission_service.dart';

// Model for combined PDF documents
class CombinedPdfDocument {
  final String id;
  final String name;
  final String filePath;
  final DateTime createdAt;
  final int fileSize;
  final int pageCount;

  CombinedPdfDocument({
    required this.id,
    required this.name,
    required this.filePath,
    required this.createdAt,
    required this.fileSize,
    required this.pageCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'filePath': filePath,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'fileSize': fileSize,
      'pageCount': pageCount,
    };
  }

  factory CombinedPdfDocument.fromJson(Map<String, dynamic> json) {
    return CombinedPdfDocument(
      id: json['id'],
      name: json['name'],
      filePath: json['filePath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
      fileSize: json['fileSize'],
      pageCount: json['pageCount'],
    );
  }
}

class CombinePdfsView extends StatefulWidget {
  const CombinePdfsView({Key? key}) : super(key: key);

  @override
  _CombinePdfsViewState createState() => _CombinePdfsViewState();
}

class _CombinePdfsViewState extends State<CombinePdfsView> {
  final List<File> _selectedPdfs = [];
  final List<CombinedPdfDocument> _combinedDocuments = [];
  final TextEditingController _fileNameController = TextEditingController();
  bool _isProcessing = false;
  double _processingProgress = 0.0;
  String _currentProcessingStep = '';
  bool _isViewMode = false; // true for list view, false for grid view

  // Selection mode state
  bool _isSelectionMode = false;
  Set<int> _selectedDocuments = {};

  // Platform channel for MediaStore operations
  static const MethodChannel _channel = MethodChannel('file_saver');

  @override
  void initState() {
    super.initState();
    _fileNameController.text =
        'combined_pdfs_${DateTime.now().millisecondsSinceEpoch}';
    _loadCombinedDocuments();
    _loadViewModePreference();
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    // Clear the list to free memory
    _selectedPdfs.clear();
    super.dispose();
  }

  // Load combined documents from storage
  Future<void> _loadCombinedDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final documentsJson = prefs.getStringList('combined_pdf_documents') ?? [];

      final documents = <CombinedPdfDocument>[];
      for (final docJson in documentsJson) {
        try {
          final doc = CombinedPdfDocument.fromJson(json.decode(docJson));
          // Check if file still exists
          if (await File(doc.filePath).exists()) {
            documents.add(doc);
          }
        } catch (e) {
          // Error loading a document - suppressed debug log
        }
      }

      setState(() {
        _combinedDocuments.clear();
        _combinedDocuments.addAll(documents);
      });
    } catch (e) {
      // Error loading combined documents - suppressed debug log
    }
  }

  // Save combined documents to storage
  Future<void> _saveCombinedDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final documentsJson =
          _combinedDocuments.map((doc) => json.encode(doc.toJson())).toList();
      await prefs.setStringList('combined_pdf_documents', documentsJson);
    } catch (e) {
      // Error saving combined documents - suppressed debug log
    }
  }

  // Load and save view mode preference
  Future<void> _loadViewModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isViewMode = prefs.getBool('combine_pdf_list_view_mode') ?? false;
      });
    } catch (e) {
      // Error loading view mode preference - suppressed debug log
    }
  }

  Future<void> _saveViewModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('combine_pdf_list_view_mode', _isViewMode);
    } catch (e) {
      // Error saving view mode preference - suppressed debug log
    }
  }

  // Delete a combined document
  Future<void> _deleteCombinedDocument(CombinedPdfDocument document) async {
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
          _combinedDocuments.removeWhere((doc) => doc.id == document.id);
        });

        await _saveCombinedDocuments();
        _showToast(localization.translate('documentDeleted'), Colors.green);
      } catch (e) {
        _showToast(
            localization.translate('failedToDeleteDocument'), Colors.red);
      }
    }
  }

  // Rename a combined document
  Future<void> _renameCombinedDocument(CombinedPdfDocument document) async {
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
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(localization.translate('rename')),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != document.name) {
      try {
        // Update the document name
        final updatedDoc = CombinedPdfDocument(
          id: document.id,
          name: newName,
          filePath: document.filePath,
          createdAt: document.createdAt,
          fileSize: document.fileSize,
          pageCount: document.pageCount,
        );

        setState(() {
          final index =
              _combinedDocuments.indexWhere((doc) => doc.id == document.id);
          if (index != -1) {
            _combinedDocuments[index] = updatedDoc;
          }
        });

        await _saveCombinedDocuments();
        _showToast(localization.translate('documentRenamed'), Colors.green);
      } catch (e) {
        _showToast(
            localization.translate('failedToRenameDocument'), Colors.red);
      }
    }
  }

  // Share a combined document
  Future<void> _shareCombinedDocument(CombinedPdfDocument document) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(document.filePath)]),
      );
    } catch (e) {
      final localization = AppLocalizations.of(context);
      _showToast(localization.translate('failedToShareDocument'), Colors.red);
    }
  }

  // Preview a combined document
  void _previewCombinedDocument(CombinedPdfDocument document) {
    try {
      final file = File(document.filePath);
      if (!file.existsSync()) {
        final localization = AppLocalizations.of(context);
        _showToast(localization.translate('documentFileNotFound'), Colors.red);
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
      final localization = AppLocalizations.of(context);
      _showToast(localization.translate('failedToOpenDocument'), Colors.red);
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
      final selectedDocs =
          _selectedDocuments.map((index) => _combinedDocuments[index]).toList();

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
          final document = _combinedDocuments[index];
          final file = File(document.filePath);

          if (await file.exists()) {
            await file.delete();
          }

          _combinedDocuments.removeAt(index);
        }

        await _saveCombinedDocuments();
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

  Future<void> _pickPDFs() async {
    final localization = AppLocalizations.of(context);
    // _pickPDFs called (log removed)

    try {
      // Request storage permissions first using CleanPermissionService
      final permissionService = CleanPermissionService();
      final permissions =
          await permissionService.requestStoragePermissions(context);

      final hasPermission = permissions.values.any(
        (status) => status.isGranted || status.isLimited,
      );

      if (!hasPermission) {
        _showToast(
          localization.translate('storagePermissionRequired'),
          Colors.red,
        );
        return;
      }

      // Attempting to pick files... (log removed)
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );

      // File picker result: $result (log removed)

      if (result != null && result.files.isNotEmpty) {
        // Found ${result.files.length} files (log removed)
        final validPdfs = <File>[];

        for (final file in result.files) {
          if (file.path != null) {
            final pdfFile = File(file.path!);
            // Debug: checking file path (log suppressed)
            // Validate file exists and is readable
            if (await pdfFile.exists()) {
              try {
                await pdfFile.readAsBytes(); // Test readability
                validPdfs.add(pdfFile);
              } catch (e) {
                // Cannot read file - suppressed debug log
              }
            } else {
              // File does not exist - suppressed debug log
            }
          }
        }

        if (validPdfs.isNotEmpty) {
          // Adding valid PDFs to selection (log suppressed)
          setState(() {
            _selectedPdfs.addAll(validPdfs);
          });
        } else {
          // No valid PDF files found (log suppressed)
          final localization = AppLocalizations.of(context);
          _showToast(localization.translate('noValidPdfFiles'), Colors.orange);
        }
      } else {
        // No files selected or result is null (log removed)
      }
    } catch (e) {
      // Error in _pickPDFs: $e (log removed)
      final localization = AppLocalizations.of(context);
      _showToast(localization.translate('failedToPickPdf'), Colors.red);
    }
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
  }

  Future<void> _combinePDFs() async {
    final localization = AppLocalizations.of(context);

    if (_selectedPdfs.length < 2) {
      _showToast(localization.translate('pleaseSelectAtLeast2'), Colors.orange);
      return;
    }

    // QUOTA CHECK: Check if user can add more combined PDFs
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final canAdd = await QuotaHelper.checkAndWarnQuota(
        context: context,
        uid: user.uid,
        section: 'combinePdfs',
        toolName: 'combinePdfs',
      );

      if (!canAdd) {
        return; // User hit quota limit
      }
    }

    setState(() {
      _isProcessing = true;
      _processingProgress = 0.0;
      _currentProcessingStep = localization.translate('preparingFiles');
    });

    try {
      // Create a list to store all PDF bytes
      final List<Uint8List> pdfBytesList = [];

      // Starting to combine ${_selectedPdfs.length} PDFs (log removed)

      // Read all PDF files as bytes first
      for (int i = 0; i < _selectedPdfs.length; i++) {
        final file = _selectedPdfs[i];
        final fileName = file.path.split(Platform.pathSeparator).last;

        setState(() {
          _processingProgress =
              (i / _selectedPdfs.length) * 0.3; // 30% for reading files
          _currentProcessingStep =
              '${localization.translate('readingFile')} ${i + 1}/${_selectedPdfs.length}';
        });

        // Reading PDF ${i + 1}: $fileName (log removed)

        try {
          // Read the PDF file as bytes
          final Uint8List pdfBytes = await file.readAsBytes();

          // Validate that it's a valid PDF by trying to load it
          final PdfDocument testDocument = PdfDocument(inputBytes: pdfBytes);
          // Validation passed (debug log suppressed)
          testDocument.dispose();

          // Add to our list
          pdfBytesList.add(pdfBytes);

          // Small delay to allow UI updates
          await Future.delayed(const Duration(milliseconds: 10));
        } catch (e) {
          // Error reading PDF (log suppressed)
          // Continue with other files even if one fails
          _showToast(
              '${localization.translate('errorProcessingFile')} $fileName',
              Colors.orange);
          continue;
        }
      }

      // Check if we have any valid PDFs
      if (pdfBytesList.isEmpty) {
        setState(() => _isProcessing = false);
        _showToast(localization.translate('noValidPdfFiles'), Colors.red);
        return;
      }

      setState(() {
        _processingProgress = 0.4;
        _currentProcessingStep = localization.translate('preparingCombination');
      });

      // Successfully read ${pdfBytesList.length} PDF files (log removed)

      // Create a new combined PDF document
      final PdfDocument combinedDocument = PdfDocument();
      int totalPagesImported = 0;

      // Process each PDF and add its pages to the combined document
      for (int i = 0; i < pdfBytesList.length; i++) {
        setState(() {
          _processingProgress = 0.4 +
              (i / pdfBytesList.length) * 0.5; // 40% to 90% for processing
          _currentProcessingStep =
              '${localization.translate('processingDocument')} ${i + 1}/${pdfBytesList.length}';
        });
        try {
          final PdfDocument sourceDocument =
              PdfDocument(inputBytes: pdfBytesList[i]);

          // Processing source document (debug log suppressed)

          // Manually copy each page to the combined document
          for (int pageIndex = 0;
              pageIndex < sourceDocument.pages.count;
              pageIndex++) {
            try {
              // Get the page from the source document
              final PdfPage sourcePage = sourceDocument.pages[pageIndex];

              // Get the source page size to preserve original dimensions
              final Size sourcePageSize = sourcePage.getClientSize();

              // Add a new page to the combined document with the same size as source
              final PdfPage newPage = combinedDocument.pages.add();

              // Get the graphics object from the new page
              final PdfGraphics graphics = newPage.graphics;

              // Save graphics state
              graphics.save();

              // Calculate the drawing area to preserve original dimensions
              final Size newPageSize = newPage.getClientSize();

              // Determine if we need to scale the content
              double scaleX = 1.0;
              double scaleY = 1.0;

              // If source page is larger than target page, scale down proportionally
              if (sourcePageSize.width > newPageSize.width ||
                  sourcePageSize.height > newPageSize.height) {
                scaleX = newPageSize.width / sourcePageSize.width;
                scaleY = newPageSize.height / sourcePageSize.height;
                // Use the smaller scale to ensure content fits completely
                final double scale = scaleX < scaleY ? scaleX : scaleY;
                scaleX = scale;
                scaleY = scale;
              }

              // Create a template from the source page
              final PdfTemplate template = sourcePage.createTemplate();

              // Calculate the drawing rectangle to center content if scaled
              final double drawWidth = sourcePageSize.width * scaleX;
              final double drawHeight = sourcePageSize.height * scaleY;
              final double offsetX = (newPageSize.width - drawWidth) / 2;
              final double offsetY = (newPageSize.height - drawHeight) / 2;

              // Draw the template with proper scaling and positioning
              final Rect drawingRect =
                  Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight);
              graphics.drawPdfTemplate(
                  template, Offset(offsetX, offsetY), drawingRect.size);

              // Restore graphics state
              graphics.restore();

              totalPagesImported++;
              // Imported page (debug log suppressed)
            } catch (pageError) {
              // Error importing page (log suppressed)
              continue;
            }
          }

          // Dispose the source document
          sourceDocument.dispose();
        } catch (e) {
          // Error processing document (log suppressed)
          continue;
        }
      }

      // Check if we successfully imported any pages
      if (totalPagesImported == 0) {
        combinedDocument.dispose();
        setState(() => _isProcessing = false);
        _showToast(localization.translate('noValidPagesFound'), Colors.red);
        return;
      }

      // Successfully combined pages (debug log suppressed)

      setState(() {
        _processingProgress = 0.95;
        _currentProcessingStep = localization.translate('generatingPdf');
      });

      // Save the combined PDF
      final List<int> bytes = await combinedDocument.save();
      combinedDocument.dispose();

      // Write to file with sanitized name
      final output = await getApplicationDocumentsDirectory();
      final sanitizedName = _sanitizeFileName(_fileNameController.text.trim());
      final fileName = sanitizedName.isEmpty ? 'combined_pdfs' : sanitizedName;
      final file = File('${output.path}/$fileName.pdf');
      await file.writeAsBytes(bytes);

      // Combined PDF saved to: ${file.path} (log removed)

      setState(() {
        _processingProgress = 1.0;
        _currentProcessingStep = localization.translate('completed');
        _isProcessing = false;
      });

      // Create and save the combined document record
      final combinedDoc = CombinedPdfDocument(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: fileName,
        filePath: file.path,
        createdAt: DateTime.now(),
        fileSize: bytes.length,
        pageCount: totalPagesImported,
      );

      setState(() {
        _combinedDocuments.insert(0, combinedDoc);
      });

      await _saveCombinedDocuments();

      // Update quota count
      if (user != null) {
        await _incrementQuotaCount(user.uid, 'combinePdfs');
      }

      _resetForm();
      _showToast(
          localization.translate('pdfsCombinedSuccessfully'), Colors.green);
    } catch (e) {
      setState(() => _isProcessing = false);
      _showToast(
          '${localization.translate('failedToCombinePdfs')}: ${e.toString()}',
          Colors.red);
      // Error combining PDFs: $e (log removed)
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

  AppLocalizations get _localization => AppLocalizations.of(context);

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
          final storageStatus = await Permission.storage.request();

          if (storageStatus.isGranted) {
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

  void _removePdf(int index) {
    setState(() {
      _selectedPdfs.removeAt(index);
    });
  }

  void _resetForm() {
    setState(() {
      _selectedPdfs.clear();
      _fileNameController.text =
          'combined_pdfs_${DateTime.now().millisecondsSinceEpoch}';
    });
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

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      appBar: _buildAdvancedAppBar(localization, colors),
      body: _buildBody(localization, colors),
      floatingActionButton: _buildFloatingActionButton(localization),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  PreferredSizeWidget _buildAdvancedAppBar(
      AppLocalizations localization, ColorScheme colors) {
    return AppBar(
      leading: const BackArrowButton(
        iconColor: Colors.white, // Set to white to match the orange gradient
        backgroundColor: Colors
            .transparent, // Make background transparent since we have gradient
        showBackground: false, // Disable the default background circle
      ),
      title: Column(
        children: [
          Text(
            _isSelectionMode
                ? '${_selectedDocuments.length} ${localization.translate('selected')}'
                : localization.translate('combinePdfs'),
            style: AppTextStyles.appBarTitle
                .copyWith(fontSize: 20, color: Colors.white),
          ),
          if (_combinedDocuments.isNotEmpty && !_isSelectionMode)
            Text(
              '${_combinedDocuments.length} ${localization.translate('documents')}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.9),
              ),
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
              const Color(0xFFFF9800).withValues(alpha: 0.9),
              const Color(0xFFFF6F00).withValues(alpha: 0.7),
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
          if (_combinedDocuments.isNotEmpty) ...[
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
          ] else if (_selectedPdfs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all, color: Colors.white),
              onPressed: () => setState(() => _selectedPdfs.clear()),
              tooltip: localization.translate('clearAll'),
            ),
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
        if (_selectedPdfs.isNotEmpty) ...[
          // File name input
          SliverToBoxAdapter(
            child: _buildFileNameInput(localization, colors),
          ),
          // Selected files header
          SliverToBoxAdapter(
            child: _buildSelectedFilesHeader(localization),
          ),
          // Selected files list
          SliverReorderableList(
            itemCount: _selectedPdfs.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _selectedPdfs.removeAt(oldIndex);
                _selectedPdfs.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              return _buildFileCard(index, colors, localization);
            },
          ),
        ] else if (_combinedDocuments.isEmpty) ...[
          // Empty state when no documents exist
          SliverToBoxAdapter(
            child: _buildEmptyState(localization, colors),
          ),
        ] else ...[
          // Combined documents header
          SliverToBoxAdapter(
            child: _buildCombinedDocumentsHeader(localization),
          ),
          // Combined documents list/grid
          if (_isViewMode)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildCombinedDocumentCard(
                    _combinedDocuments[index], index, colors, localization),
                childCount: _combinedDocuments.length,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildCombinedDocumentGridCard(
                      _combinedDocuments[index], index, colors, localization),
                  childCount: _combinedDocuments.length,
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
          colors: [Color(0xFFFF9800), Color(0xFFFF6F00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9800).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
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
              Icons.merge_type,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization.translate('combineMultiplePdfs'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localization.translate('combineDescription'),
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
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
              ),
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
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
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
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
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
            color: colors.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit, size: 20, color: const Color(0xFFFF9800)),
              const SizedBox(width: 8),
              Text(
                localization.translate('fileName'),
                style: AppTextStyles.bodyText.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFF9800),
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
              suffixStyle: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: colors.outline.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFFF9800), width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              filled: true,
              fillColor: colors.surface,
            ),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.picture_as_pdf,
              size: 64,
              color: const Color(0xFFFF9800).withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localization.translate('noCombinedDocuments'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            localization.translate('createFirstCombinedPdf'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedDocumentsHeader(AppLocalizations localization) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.folder_copy,
            size: 20,
            color: const Color(0xFFFF9800),
          ),
          const SizedBox(width: 8),
          Text(
            '${localization.translate('combinedDocuments')} (${_combinedDocuments.length})',
            style: AppTextStyles.bodyText.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFF9800),
            ),
          ),
          const Spacer(),
          if (_combinedDocuments.isNotEmpty)
            Text(
              _isViewMode
                  ? localization.translate('listView')
                  : localization.translate('gridView'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCombinedDocumentCard(CombinedPdfDocument document, int index,
      ColorScheme colors, AppLocalizations localization) {
    final isSelected = _selectedDocuments.contains(index);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? const Color(0xFFFF9800)
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
                activeColor: const Color(0xFFFF9800),
              )
            : Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.picture_as_pdf,
                  color: const Color(0xFFFF9800),
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
                '${document.pageCount} ${localization.translate('pages')} • ${(document.fileSize / 1024).toStringAsFixed(1)} KB',
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
              icon: Icon(Icons.visibility, color: Color(0xFFFF9800), size: 20),
              onPressed: () => _previewCombinedDocument(document),
              tooltip: localization.translate('preview'),
              visualDensity: VisualDensity.compact,
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  color: colors.onSurface.withValues(alpha: 0.6)),
              onSelected: (value) {
                switch (value) {
                  case 'share':
                    _shareCombinedDocument(document);
                    break;
                  case 'download':
                    _saveToDeviceStorage(File(document.filePath));
                    break;
                  case 'rename':
                    _renameCombinedDocument(document);
                    break;
                  case 'delete':
                    _deleteCombinedDocument(document);
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
                      Text(localization.translate('share')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 20, color: Colors.green),
                      const SizedBox(width: 12),
                      Text(localization.translate('download')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20, color: Colors.grey),
                      const SizedBox(width: 12),
                      Text(localization.translate('rename')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      const SizedBox(width: 12),
                      Text(localization.translate('delete')),
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
            _previewCombinedDocument(document);
          }
        },
      ),
    );
  }

  Widget _buildCombinedDocumentGridCard(CombinedPdfDocument document, int index,
      ColorScheme colors, AppLocalizations localization) {
    final isSelected = _selectedDocuments.contains(index);
    return Card(
      margin: const EdgeInsets.all(4),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFFFF9800)
              : const Color(0xFFFF9800).withValues(alpha: 0.2),
          width: isSelected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            _toggleDocumentSelection(index);
          } else {
            _previewCombinedDocument(document);
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
                const Color(0xFFFF9800).withValues(alpha: 0.02),
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
                                ? const Color(0xFFFF9800)
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
                                const Color(0xFFFF9800).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.picture_as_pdf,
                            color: const Color(0xFFFF9800),
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
                        case 'rename':
                          _renameCombinedDocument(document);
                          break;
                        case 'delete':
                          _deleteCombinedDocument(document);
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

              // Document format and page count
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${document.pageCount} ${localization.translate('pages')} • PDF',
                  style: TextStyle(
                    color: const Color(0xFFFF9800),
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
                height: 16, // Fixed height for date
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
                height: 14, // Fixed height for file size row
                child: Row(
                  children: [
                    Icon(
                      Icons.folder,
                      size: 10,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${(document.fileSize / 1024).toStringAsFixed(1)} KB',
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

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildGridActionButton(
                    icon: Icons.visibility,
                    onTap: () => _previewCombinedDocument(document),
                    color: const Color(0xFFFF9800),
                  ),
                  _buildGridActionButton(
                    icon: Icons.share,
                    onTap: () => _shareCombinedDocument(document),
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

  Widget _buildSelectedFilesHeader(AppLocalizations localization) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.folder_copy,
            size: 20,
            color: const Color(0xFFFF9800),
          ),
          const SizedBox(width: 8),
          Text(
            '${localization.translate('selectedPdfs')} (${_selectedPdfs.length})',
            style: AppTextStyles.bodyText.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFF9800),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _pickPDFs,
            icon: const Icon(Icons.add, size: 18),
            label: Text(localization.translate('addMore')),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF9800),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(
      int index, ColorScheme colors, AppLocalizations localization) {
    final file = _selectedPdfs[index];
    final fileName = file.path.split(Platform.pathSeparator).last;

    return Container(
      key: ValueKey(file.path),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
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
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.picture_as_pdf,
            color: const Color(0xFFFF9800),
            size: 24,
          ),
        ),
        title: Text(
          fileName,
          style: AppTextStyles.bodyText.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: FutureBuilder<int>(
          future: file.length(),
          builder: (context, snapshot) {
            final size = snapshot.data ?? 0;
            final sizeInKB = (size / 1024).toStringAsFixed(1);
            return Padding(
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
                    '${localization.translate('fileSize')}: $sizeInKB KB',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Order indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: const Color(0xFFFF9800),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.drag_handle,
              color: colors.onSurface.withValues(alpha: 0.4),
              size: 20,
            ),
            IconButton(
              icon: Icon(Icons.close, color: colors.error, size: 20),
              onPressed: () => _removePdf(index),
              tooltip: localization.translate('remove'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton(AppLocalizations localization) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: _selectedPdfs.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isProcessing ? null : _combinePDFs,
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              elevation: 8,
              icon: _isProcessing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.merge_type),
              label: Text(
                _isProcessing
                    ? '${localization.translate('combining')} ${(_processingProgress * 100).toInt()}%'
                    : localization.translate('combinePdfsButton'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            )
          : FloatingActionButton.extended(
              onPressed: _pickPDFs,
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              elevation: 8,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(
                _combinedDocuments.isEmpty
                    ? localization.translate('createFirstPdf')
                    : localization.translate('createNewPdf'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
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
}
