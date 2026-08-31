import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:file_picker/file_picker.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/document_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signed_documents_storage.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:broker_wallet/src/services/clean_permission_service.dart';

class SignatureScreenPreview extends StatelessWidget {
  const SignatureScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const SignatureScreen();
  }
}

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  // Color palette used in the screenshot
  static const Color redLight = Color(0xFFF44336);
  static const Color redDark = Color(0xFFC62828);
  static const Color redDarker = Color(0xFFB71C1C);
  static const double horizontalPadding = 16.0;

  // Loading state for document upload
  bool _isLoading = false;

  // List of signed documents
  List<SignedDocument> _signedDocuments = [];

  // View mode: true = list view, false = grid view
  bool _isListView = false;

  // Selection mode
  bool _isSelectionMode = false;
  Set<int> _selectedDocuments = {};

  // Platform channel for MediaStore operations
  static const MethodChannel _channel = MethodChannel('file_saver');

  @override
  void initState() {
    super.initState();
    _loadSignedDocuments();
    _loadViewMode();
  }

  /// Load signed documents from storage
  Future<void> _loadSignedDocuments() async {
    final documents = await SignedDocumentsStorage.loadDocuments();
    if (mounted) {
      setState(() {
        _signedDocuments = documents;
      });
    }
  }

  /// Load view mode preference
  Future<void> _loadViewMode() async {
    final isListView = await SignedDocumentsStorage.loadViewMode();
    if (mounted) {
      setState(() {
        _isListView = isListView;
      });
    }
  }

  /// Toggle view mode
  void _toggleViewMode() {
    setState(() {
      _isListView = !_isListView;
    });
    SignedDocumentsStorage.saveViewMode(_isListView);
  }

  /// Enter selection mode
  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedDocuments.clear();
    });
  }

  /// Exit selection mode
  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedDocuments.clear();
    });
  }

  /// Toggle document selection
  void _toggleSelection(int index) {
    setState(() {
      if (_selectedDocuments.contains(index)) {
        _selectedDocuments.remove(index);
      } else {
        _selectedDocuments.add(index);
      }
    });
  }

  /// Delete selected documents
  Future<void> _deleteSelectedDocuments() async {
    final localization = AppLocalizations.of(context);
    final count = _selectedDocuments.length;

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
            onPressed: () => Navigator.pop(context, false),
            child: Text(localization.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
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
        final indicesToRemove = _selectedDocuments.toList()
          ..sort((a, b) => b.compareTo(a));

        for (final index in indicesToRemove) {
          final document = _signedDocuments[index];
          final file = File(document.filePath);

          if (await file.exists()) {
            await file.delete();
          }

          _signedDocuments.removeAt(index);
        }

        await SignedDocumentsStorage.saveDocuments(_signedDocuments);

        _exitSelectionMode();
        _loadSignedDocuments();

        SignedDocumentsHelper.showToast(
          '$count ${count == 1 ? localization.translate('documentDeleted') : localization.translate('documentsDeleted')}',
          Colors.green,
        );
      } catch (e) {
        SignedDocumentsHelper.showToast(
          localization.translate('failedToDeleteDocuments'),
          Colors.red,
        );
      }
    }
  }

  /// Save document to device storage (Downloads folder)
  Future<void> _saveToDeviceStorage(SignedDocument document) async {
    final localization = AppLocalizations.of(context);

    try {
      final pdfFile = File(document.filePath);

      if (!await pdfFile.exists()) {
        SignedDocumentsHelper.showToast(
          localization.translate('documentFileNotFound'),
          Colors.red,
        );
        return;
      }

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
              SignedDocumentsHelper.showToast(
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
            SignedDocumentsHelper.showToast(
              localization.translate('storagePermissionDenied'),
              Colors.red,
            );
            return;
          }
        }
      } else if (Platform.isIOS) {
        downloadsDirectory = await getApplicationDocumentsDirectory();
        locationName = 'Documents';
      }

      if (downloadsDirectory == null) {
        SignedDocumentsHelper.showToast(
          localization.translate('failedToAccessStorage'),
          Colors.red,
        );
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

      // Verify the file was created
      if (await destinationFile.exists()) {
        // Show success with actual path info
        SignedDocumentsHelper.showToast(
          '${localization.translate('pdfSavedTo')} $locationName\nFile: $uniqueFileName',
          Colors.green,
        );
      } else {
        throw Exception(
          'File was not created at destination: $destinationPath',
        );
      }
    } catch (e) {
      SignedDocumentsHelper.showToast(
        '${localization.translate('failedToSavePdf')}: ${e.toString()}',
        Colors.red,
      );
    }
  }

  /// Handle document upload
  Future<void> _uploadDocument() async {
    final localization = AppLocalizations.of(context);

    try {
      setState(() {
        _isLoading = true;
      });

      // Request storage permissions first using CleanPermissionService
      final permissionService = CleanPermissionService();
      final permissions =
          await permissionService.requestStoragePermissions(context);

      final hasPermission = permissions.values.any(
        (status) => status.isGranted || status.isLimited,
      );

      if (!hasPermission) {
        if (mounted) {
          _showToast(
          localization.translate('storagePermissionRequired'),
          Colors.red,
        );
        
        }
        return;
      }

      // Open file picker to select PDF document
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;

        // Navigate to document view with the selected file
        if (mounted) {
          final shouldRefresh = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => DocumentView(
                documentPath: filePath,
              ),
            ),
          );

          // Refresh list if document was saved
          if (shouldRefresh == true) {
            _loadSignedDocuments();
          }
        }
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        final localization = AppLocalizations.of(context);
        _showToast(
          localization.translate('error'),
          Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildHeaderCard() {
    final localization = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [redLight, redDarker],
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
              Icons.draw,
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
                  localization.translate('documentSignature'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  localization.translate('uploadAndSignDocuments'),
                  style: TextStyle(
                    color: Colors.white70,
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

  /// Build document card for list view
  Widget _buildDocumentCard(
    SignedDocument document,
    int index,
    AppLocalizations localization,
  ) {
    final isSelected = _selectedDocuments.contains(index);

    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? redLight : colors.outline.withValues(alpha: 0.2),
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
                onChanged: (_) => _toggleSelection(index),
                activeColor: redLight,
              )
            : Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: redLight.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.picture_as_pdf,
                  color: redLight,
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
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${document.pageCount} ${localization.translate('pages')} • ${SignedDocumentsHelper.formatFileSize(document.fileSize)}',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.visibility, color: redLight, size: 20),
              onPressed: () =>
                  SignedDocumentsHelper.previewDocument(context, document),
              tooltip: localization.translate('preview'),
              visualDensity: VisualDensity.compact,
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: colors.onSurfaceVariant),
              onSelected: (value) async {
                if (value == 'rename') {
                  await SignedDocumentsHelper.renameDocument(
                    context,
                    document,
                    _signedDocuments,
                  );
                  _loadSignedDocuments();
                } else if (value == 'share') {
                  await SignedDocumentsHelper.shareDocument(context, document);
                } else if (value == 'download') {
                  await _saveToDeviceStorage(document);
                } else if (value == 'delete') {
                  await SignedDocumentsHelper.deleteDocument(
                    context,
                    document,
                    _signedDocuments,
                  );
                  _loadSignedDocuments();
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
            _toggleSelection(index);
          } else {
            SignedDocumentsHelper.previewDocument(context, document);
          }
        },
      ),
    );
  }

  /// Build document card for grid view
  Widget _buildDocumentGridCard(
    SignedDocument document,
    int index,
    AppLocalizations localization,
  ) {
    final isSelected = _selectedDocuments.contains(index);
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.all(4),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? redLight : redLight.withValues(alpha: 0.2),
          width: isSelected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(index);
          } else {
            SignedDocumentsHelper.previewDocument(context, document);
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
                colors.surface,
                redLight.withValues(alpha: 0.02),
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
                                ? redLight
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
                            color: redLight.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.picture_as_pdf,
                            color: redLight,
                            size: 18,
                          ),
                        ),

                  const Spacer(),

                  // More options menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                    onSelected: (value) async {
                      if (value == 'rename') {
                        await SignedDocumentsHelper.renameDocument(
                          context,
                          document,
                          _signedDocuments,
                        );
                        _loadSignedDocuments();
                      } else if (value == 'share') {
                        await SignedDocumentsHelper.shareDocument(
                            context, document);
                      } else if (value == 'download') {
                        await _saveToDeviceStorage(document);
                      } else if (value == 'delete') {
                        await SignedDocumentsHelper.deleteDocument(
                          context,
                          document,
                          _signedDocuments,
                        );
                        _loadSignedDocuments();
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
                        value: 'download',
                        child: Row(
                          children: [
                            const Icon(Icons.download,
                                size: 18, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(localization.translate('download')),
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
                  color: redLight.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: redLight.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${document.pageCount} ${localization.translate('pages')} • PDF',
                  style: TextStyle(
                    color: redLight,
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
                  '${document.signatureCount} ${localization.translate('signatures')}',
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
                      SignedDocumentsHelper.formatFileSize(document.fileSize),
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
                    onTap: () => SignedDocumentsHelper.previewDocument(
                        context, document),
                    color: redLight,
                  ),
                  _buildGridActionButton(
                    icon: Icons.share,
                    onTap: () =>
                        SignedDocumentsHelper.shareDocument(context, document),
                    color: Colors.blue,
                  ),
                  _buildGridActionButton(
                    icon: Icons.download,
                    onTap: () => _saveToDeviceStorage(document),
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
          size: 16,
          color: color,
        ),
      ),
    );
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
    final theme = Theme.of(context);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      backgroundColor: colors.surface,
      appBar: AppBar(
        leading: const BackArrowButton(
          iconColor: Colors.white, // Set to white to match the green gradient
          backgroundColor: Colors
              .transparent, // Make background transparent since we have gradient
          showBackground: false, // Disable the default background circle
        ),
        title: Column(
          children: [
            Text(
              localization.translate('signDocument'),
              style: AppTextStyles.appBarTitle
                  .copyWith(fontSize: 20, color: Colors.white),
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
                const Color(0xFFF44336).withValues(alpha: 0.9),
                const Color(0xFFB71C1C).withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          ),
        ),
        actions: [
          if (_signedDocuments.isNotEmpty && !_isSelectionMode) ...[
            IconButton(
              icon: Icon(
                _isListView ? Icons.grid_view : Icons.list,
                color: Colors.white,
              ),
              onPressed: _toggleViewMode,
              tooltip: _isListView
                  ? localization.translate('gridView')
                  : localization.translate('listView'),
            ),
            IconButton(
              icon: const Icon(Icons.checklist, color: Colors.white),
              onPressed: _enterSelectionMode,
              tooltip: localization.translate('selectDocuments'),
            ),
          ] else if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: _selectedDocuments.isNotEmpty
                  ? () async {
                      final selectedDocs = _selectedDocuments
                          .map((index) => _signedDocuments[index])
                          .toList();
                      for (final doc in selectedDocs) {
                        await SignedDocumentsHelper.shareDocument(context, doc);
                      }
                      _exitSelectionMode();
                    }
                  : null,
              tooltip: localization.translate('shareSelected'),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed: _selectedDocuments.isNotEmpty
                  ? _deleteSelectedDocuments
                  : null,
              tooltip: localization.translate('deleteSelected'),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _exitSelectionMode,
              tooltip: localization.translate('cancelSelection'),
            ),
          ],
        ],
      ),

      body: CustomScrollView(
        slivers: [
          // Header space for transparent app bar
          const SliverToBoxAdapter(child: SizedBox(height: 120)),

          // Header card
          SliverToBoxAdapter(
            child: _buildHeaderCard(),
          ),

          // Show signed documents if available
          if (_signedDocuments.isNotEmpty) ...[
            // Documents header
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_copy,
                      size: 20,
                      color: redLight,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${localization.translate('signedDocuments')} (${_signedDocuments.length})',
                      style: AppTextStyles.bodyText.copyWith(
                        fontWeight: FontWeight.w600,
                        color: redLight,
                      ),
                    ),
                    const Spacer(),
                    if (_signedDocuments.isNotEmpty)
                      Text(
                        _isListView
                            ? localization.translate('gridView')
                            : localization.translate('listView'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Documents list or grid
            if (_isListView)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildDocumentCard(
                    _signedDocuments[index],
                    index,
                    localization,
                  ),
                  childCount: _signedDocuments.length,
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
                    (context, index) => _buildDocumentGridCard(
                      _signedDocuments[index],
                      index,
                      localization,
                    ),
                    childCount: _signedDocuments.length,
                  ),
                ),
              ),
          ] else ...[
            // Empty state
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: redLight.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.draw,
                          size: 56,
                          color: redLight.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      localization.translate('noSignedDocuments'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      localization.translate('uploadAndSignDocuments'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Bottom padding for FAB
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),

      // Floating button centered docked
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 18),
        child: FloatingActionButton.extended(
          onPressed: _isLoading ? null : _uploadDocument,
          elevation: 12,
          backgroundColor: _isLoading ? Colors.grey : redDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          icon: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.upload_file),
          label: Padding(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Text(
              _isLoading
                  ? localization.translate('loading')
                  : localization.translate('uploadDocument'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
