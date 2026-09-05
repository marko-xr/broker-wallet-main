import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_pad_view.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf;
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signed_documents_storage.dart';
import 'package:broker_wallet/src/services/quota_helper.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Model class to represent a signature overlay on the document
/// Uses RELATIVE coordinates (0.0 to 1.0) for position and size
/// This ensures signatures stay in the correct position regardless of
/// screen size, zoom level, or PDF rendering resolution
class SignatureOverlay {
  Uint8List imageData;
  // Relative position (0.0 to 1.0) - dx is fraction of page width, dy is fraction of page height
  double dx;
  double dy;
  // Relative size (0.0 to 1.0) - fractions of page dimensions
  double widthFraction;
  double heightFraction;
  double scale; // Additional scaling factor for interactive editing
  int pageNumber; // Which PDF page this signature belongs to
  bool isPinned; // Whether signature is pinned to the page
  SignatureOverlay({
    required this.imageData,
    required this.dx,
    required this.dy,
    required this.widthFraction,
    required this.heightFraction,
    this.scale = 1.0,
    required this.pageNumber,
    this.isPinned = false, // By default, signatures are unpinned (movable)
  });

  /// Get absolute position in pixels from relative coordinates
  Offset getAbsolutePosition(double pageWidth, double pageHeight) {
    return Offset(
      dx * pageWidth,
      dy * pageHeight,
    );
  }

  /// Get absolute size in pixels from relative dimensions
  Size getAbsoluteSize(double pageWidth, double pageHeight) {
    return Size(
      widthFraction * pageWidth * scale,
      heightFraction * pageHeight * scale,
    );
  }

  /// Update position from absolute pixel coordinates
  void setAbsolutePosition(
      Offset position, double pageWidth, double pageHeight) {
    dx = (position.dx / pageWidth).clamp(0.0, 1.0);
    dy = (position.dy / pageHeight).clamp(0.0, 1.0);
  }
}

/// A screen that displays a document with signature overlay functionality.
///
/// Features:
/// - Display PDF documents
/// - Add signature overlay
/// - Drag signature to reposition
/// - Pinch to resize signature
/// - Tap signature to replace it
class DocumentView extends StatefulWidget {
  /// Path to the document file (PDF)
  final String documentPath;
  const DocumentView({
    super.key,
    required this.documentPath,
  });
  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  // List of signature overlays on the document
  final List<SignatureOverlay> _signatures = [];
  // Currently selected signature index (for editing/replacing)
  int? _selectedSignatureIndex;
  // PDF view controller
  int? _totalPages;
  int _currentPage = 0;
  // Flag to hide/show FAB when dragging signature
  bool _isInteractingWithSignature = false;
  // Flag to show zoom slider
  bool _showZoomSlider = false;
  // PDF page dimensions for coordinate conversions
  final GlobalKey _pdfViewKey = GlobalKey();
  Size _pdfViewSize = Size.zero; // The size of the PDFView widget
  Size _pdfPageSize = Size.zero; // The actual size of the rendered PDF page
  Offset _pdfPageOffset =
      Offset.zero; // The offset of the rendered page within the view
  @override
  void initState() {
    super.initState();
    // Schedule a post-frame callback to get page dimensions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePdfViewSize();
    });
  }

  /// Update the PDF view size from the widget's RenderBox
  void _updatePdfViewSize() {
    final RenderBox? renderBox =
        _pdfViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      setState(() {
        _pdfViewSize = renderBox.size;
      });
    }
  }

  /// This method is called from onRender of the PDFView.
  /// It calculates the actual size and offset of the rendered PDF page.
  Future<void> _calculatePageLayout(int page) async {
    if (_pdfViewSize == Size.zero) return;
    final sf_pdf.PdfDocument document = sf_pdf.PdfDocument(
        inputBytes: await File(widget.documentPath).readAsBytes());
    if (page >= document.pages.count) {
      document.dispose();
      return;
    }
    final sf_pdf.PdfPage pdfPage = document.pages[page];
    final Size pageSize = pdfPage.size;
    document.dispose();
    final double pageAspectRatio = pageSize.width / pageSize.height;
    final double viewAspectRatio = _pdfViewSize.width / _pdfViewSize.height;
    double renderedWidth;
    double renderedHeight;
    // The flutter_pdfview package uses 'aspectFit' scaling.
    if (pageAspectRatio > viewAspectRatio) {
      // Page is wider than view, so width is the constraint.
      renderedWidth = _pdfViewSize.width;
      renderedHeight = renderedWidth / pageAspectRatio;
    } else {
      // Page is taller than view, so height is the constraint.
      renderedHeight = _pdfViewSize.height;
      renderedWidth = renderedHeight * pageAspectRatio;
    }
    // Calculate the offset to center the page within the view.
    final double offsetX = (_pdfViewSize.width - renderedWidth) / 2;
    final double offsetY = (_pdfViewSize.height - renderedHeight) / 2;
    setState(() {
      _pdfPageSize = Size(renderedWidth, renderedHeight);
      _pdfPageOffset = Offset(offsetX, offsetY);
    });
  }

  /// Open signature pad to add a new signature
  void _addSignature() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SignaturePadView(
          onConfirm: (signatureData) {
            setState(() {
              // Calculate image aspect ratio from PNG bytes
              final imageAspect = _getImageAspectRatio(signatureData);
              // Default signature size: 25% of page width
              const double defaultWidthFraction = 0.25;
              final double heightFraction = defaultWidthFraction / imageAspect;
              // Center the signature on the page
              final double dx = (1.0 - defaultWidthFraction) / 2;
              final double dy = (1.0 - heightFraction) / 2;
              // Add new signature with relative coordinates
              _signatures.add(
                SignatureOverlay(
                  imageData: signatureData,
                  dx: dx,
                  dy: dy,
                  widthFraction: defaultWidthFraction,
                  heightFraction: heightFraction,
                  scale: 1.0,
                  pageNumber: _currentPage, // Bind to current page
                  isPinned: false, // Start unpinned so user can position it
                ),
              );
              _selectedSignatureIndex = null;
            });
          },
        ),
      ),
    );
  }

  /// Helper to compute image aspect ratio (width/height) from PNG bytes
  double _getImageAspectRatio(Uint8List pngBytes) {
    try {
      if (pngBytes.length >= 24 && pngBytes[0] == 0x89 && pngBytes[1] == 0x50) {
        final width = pngBytes.buffer.asByteData().getUint32(16);
        final height = pngBytes.buffer.asByteData().getUint32(20);
        if (height != 0) return width / height;
      }
    } catch (_) {}
    return 2.0; // Default 2:1 aspect ratio for signatures
  }

  /// Replace an existing signature
  void _replaceSignature(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SignaturePadView(
          initialSignature: _signatures[index].imageData,
          onConfirm: (signatureData) {
            setState(() {
              _signatures[index].imageData = signatureData;
              _selectedSignatureIndex = null;
            });
          },
        ),
      ),
    );
  }

  /// Delete a signature
  void _deleteSignature(int index) {
    setState(() {
      _signatures.removeAt(index);
      _selectedSignatureIndex = null;
    });
  }

  /// Show options for a signature (Replace or Delete)
  void _showSignatureOptions(int index) {
    final localization = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title
                Text(
                  localization.translate('signatureOptions'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 16),
                // Option cards
                _buildOptionCard(
                  icon: Icons.zoom_in,
                  iconColor: Colors.green,
                  iconBackground: Colors.green.withValues(alpha: 0.1),
                  title: localization.translate('resizeSignature'),
                  subtitle: localization.translate('adjustSignatureSize'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _showZoomSlider = true;
                    });
                  },
                ),
                const SizedBox(height: 8),
                _buildOptionCard(
                  icon: Icons.edit_outlined,
                  iconColor: Colors.blue,
                  iconBackground: Colors.blue.withValues(alpha: 0.1),
                  title: localization.translate('replaceSignature'),
                  subtitle: localization.translate('drawNewSignature'),
                  onTap: () {
                    Navigator.pop(context);
                    _replaceSignature(index);
                  },
                ),
                const SizedBox(height: 8),
                _buildOptionCard(
                  icon: Icons.delete_outline,
                  iconColor: Colors.red,
                  iconBackground: Colors.red.withValues(alpha: 0.1),
                  title: localization.translate('deleteSignature'),
                  subtitle: localization.translate('removeFromDocument'),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteSignature(index);
                  },
                ),
                const SizedBox(height: 16),
                // Cancel button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey[300]!, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      localization.translate('cancel'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build an option card for the bottom sheet
  Widget _buildOptionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[200]!, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  /// Save the document with signatures
  Future<void> _saveDocument() async {
    final localization = AppLocalizations.of(context);
    if (_signatures.isEmpty) {
      SignedDocumentsHelper.showToast(
        localization.translate('pleaseAddSignatureFirst'),
        Colors.orange,
      );
      return;
    }

    try {
      // QUOTA CHECK: Check if user can add more signed documents
      final currentUserId =
          RepositoryProvider.instance.authRepository.currentUserId;
      if (currentUserId == null) {
        SignedDocumentsHelper.showToast(
          localization.translate('pleaseLoginFirst'),
          Colors.red,
        );
        return;
      }

      final canAdd = await QuotaHelper.checkAndWarnQuota(
        context: context,
        uid: currentUserId,
        section: 'signature',
        toolName: 'signature',
      );

      if (!canAdd) {
        return; // User hit quota limit
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(localization.translate('savingDocument')),
                ],
              ),
            ),
          ),
        ),
      );
      // Read original PDF
      final originalPdfBytes = await File(widget.documentPath).readAsBytes();
      // Load the PDF document using Syncfusion
      final sf_pdf.PdfDocument document =
          sf_pdf.PdfDocument(inputBytes: originalPdfBytes);
      // Store page count before disposal
      final int pageCount = document.pages.count;
      // Group signatures by page number
      final signaturesByPage = <int, List<SignatureOverlay>>{};
      for (final sig in _signatures) {
        signaturesByPage.putIfAbsent(sig.pageNumber, () => []).add(sig);
      }
      // Add signatures to their respective pages
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        final pageSigs = signaturesByPage[pageIndex];
        if (pageSigs == null || pageSigs.isEmpty) continue;
        final sf_pdf.PdfPage page = document.pages[pageIndex];
        // Get page dimensions (in PDF points, 72 DPI)
        final double pageWidth = page.size.width;
        final double pageHeight = page.size.height;
        // Add each signature to the PDF using relative coordinates
        for (final signature in pageSigs) {
          // Convert signature image to bitmap
          final sf_pdf.PdfBitmap bitmap = sf_pdf.PdfBitmap(signature.imageData);
          // Calculate absolute position and size from relative coordinates
          // This ensures signatures appear in the exact same position
          final double x = signature.dx * pageWidth;
          final double y = signature.dy * pageHeight;
          final double width =
              signature.widthFraction * signature.scale * pageWidth;
          final double height =
              signature.heightFraction * signature.scale * pageHeight;
          // Draw the signature image on the PDF
          page.graphics.drawImage(
            bitmap,
            Rect.fromLTWH(x, y, width, height),
          );
        }
      }
      // Save the modified PDF
      final List<int> bytes = await document.save();
      document.dispose();
      // Generate file name automatically
      final fileName = 'signed_doc_${DateTime.now().millisecondsSinceEpoch}';
      // Get save path
      final savePath = await SignedDocumentsStorage.getDocumentsPath();
      final savedFile = File('$savePath/$fileName.pdf');
      await savedFile.writeAsBytes(bytes);
      // Create signed document record
      final signedDoc = SignedDocument(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: fileName,
        filePath: savedFile.path,
        createdAt: DateTime.now(),
        fileSize: bytes.length,
        pageCount: pageCount,
        signatureCount: _signatures.length,
      );
      // Load existing documents and add new one
      final documents = await SignedDocumentsStorage.loadDocuments();
      documents.insert(0, signedDoc);
      await SignedDocumentsStorage.saveDocuments(documents);

      // Update quota count
      await _incrementQuotaCount(currentUserId, 'signature');

      // Close loading dialog
      if (mounted) Navigator.pop(context);
      // Show success message
      SignedDocumentsHelper.showToast(
        localization.translate('documentSavedSuccessfully'),
        Colors.green,
      );
      // Go back to signature screen
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      SignedDocumentsHelper.showToast(
        '${localization.translate('failedToSaveDocument')}: $e',
        Colors.red,
      );
    }
  }

  Future<void> _incrementQuotaCount(String uid, String section) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'counts': {section: FieldValue.increment(1)},
        'lifetimeCreated': {section: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final file = File(widget.documentPath);
    final fileExists = file.existsSync();
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: Text(
          localization.translate('signDocument'),
          style: const TextStyle(
            fontSize: 20,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFF44336),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: fileExists
          ? Stack(
              children: [
                // Document viewer (PDF)
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.only(
                      left: 8,
                      right: 8,
                      top: 8,
                      bottom:
                          80, // Add bottom padding so content doesn't hide behind FAB
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PDFView(
                        key: _pdfViewKey,
                        filePath: widget.documentPath,
                        enableSwipe: true,
                        swipeHorizontal: false,
                        autoSpacing: true,
                        pageFling: true,
                        pageSnap: true,
                        onRender: (pages) {
                          setState(() {
                            _totalPages = pages;
                          });
                          // Update view size and then calculate page layout
                          Future.delayed(const Duration(milliseconds: 100), () {
                            _updatePdfViewSize();
                            _calculatePageLayout(_currentPage);
                          });
                        },
                        onPageChanged: (page, total) {
                          setState(() {
                            _currentPage = page ?? 0;
                          });
                          _calculatePageLayout(_currentPage);
                        },
                        onError: (error) {
                          debugPrint('PDF Error: $error');
                        },
                      ),
                    ),
                  ),
                ),
                // This container provides a visual border and shadow for the PDF page.
                // It's sized and positioned to match the actual rendered page.
                // IgnorePointer ensures it doesn't block touch events for scrolling.
                if (_pdfPageSize != Size.zero)
                  Positioned(
                    left: _pdfPageOffset.dx + 8, // +8 for container margin
                    top: _pdfPageOffset.dy + 8, // +8 for container margin
                    width: _pdfPageSize.width,
                    height: _pdfPageSize.height,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: Colors.grey[300]!, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Signature overlays are placed in a Stack that is positioned
                // exactly over the rendered PDF page.
                if (_pdfPageSize != Size.zero)
                  Positioned(
                    left: _pdfPageOffset.dx + 8, // +8 for container margin
                    top: _pdfPageOffset.dy + 8, // +8 for container margin
                    width: _pdfPageSize.width,
                    height: _pdfPageSize.height,
                    child: Stack(
                      children: _signatures.asMap().entries.where((entry) {
                        // Only show signatures for the current page
                        return entry.value.pageNumber == _currentPage;
                      }).map((entry) {
                        final index = entry.key;
                        final signature = entry.value;
                        return _SignatureWidget(
                          key: ValueKey('signature_$index'),
                          signature: signature,
                          pageWidth: _pdfPageSize.width,
                          pageHeight: _pdfPageSize.height,
                          isSelected: _selectedSignatureIndex == index,
                          onTap: () {
                            setState(() {
                              _selectedSignatureIndex = index;
                            });
                            _showSignatureOptions(index);
                          },
                          onPositionChanged: (newPosition) {
                            setState(() {
                              // Update relative coordinates from absolute position
                              signature.setAbsolutePosition(newPosition,
                                  _pdfPageSize.width, _pdfPageSize.height);
                            });
                          },
                          onInteractionStart: () {
                            // Hide FAB when user starts dragging signature
                            setState(() {
                              _isInteractingWithSignature = true;
                            });
                          },
                          onInteractionEnd: () {
                            // Show FAB again after a short delay
                            Future.delayed(const Duration(milliseconds: 300),
                                () {
                              if (mounted) {
                                setState(() {
                                  _isInteractingWithSignature = false;
                                });
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                // Zoom slider for selected signature
                if (_showZoomSlider &&
                    _selectedSignatureIndex != null &&
                    _selectedSignatureIndex! < _signatures.length)
                  Positioned(
                    bottom: 160,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.zoom_out,
                                color: Color(0xFFF44336),
                                size: 20,
                              ),
                              Expanded(
                                child: Slider(
                                  value: _signatures[_selectedSignatureIndex!]
                                      .scale,
                                  min: 0.3,
                                  max: 3.0,
                                  divisions: 27,
                                  activeColor: const Color(0xFFF44336),
                                  inactiveColor: Colors.grey[300],
                                  onChanged: (value) {
                                    setState(() {
                                      _signatures[_selectedSignatureIndex!]
                                          .scale = value;
                                    });
                                  },
                                ),
                              ),
                              const Icon(
                                Icons.zoom_in,
                                color: Color(0xFFF44336),
                                size: 20,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                localization.translate('resizeSignature'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _showZoomSlider = false;
                                    _selectedSignatureIndex = null;
                                  });
                                },
                                child: Text(
                                  localization.translate('done'),
                                  style: const TextStyle(
                                    color: Color(0xFFF44336),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                // Page indicator
                if (_totalPages != null && _totalPages! > 1)
                  Positioned(
                    bottom: 80,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentPage + 1} / $_totalPages',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    localization.translate('documentNotFound'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: fileExists && !_isInteractingWithSignature
          ? AnimatedOpacity(
              opacity: _isInteractingWithSignature ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Save Document Button (only show if signatures exist)
                  if (_signatures.isNotEmpty) ...[
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _saveDocument,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 8,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        icon: const Icon(Icons.save, size: 20),
                        label: Text(
                          localization.translate('save'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // Add Signature Button
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _addSignature,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF44336),
                        foregroundColor: Colors.white,
                        elevation: 8,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: const Icon(Icons.draw, size: 20),
                      label: Text(
                        localization.translate('addSignature'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

/// Widget that displays a single signature with drag functionality
/// Uses page dimensions to convert between relative and absolute coordinates
class _SignatureWidget extends StatefulWidget {
  final SignatureOverlay signature;
  final double pageWidth;
  final double pageHeight;
  final bool isSelected;
  final VoidCallback onTap;
  final Function(Offset) onPositionChanged;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  const _SignatureWidget({
    super.key,
    required this.signature,
    required this.pageWidth,
    required this.pageHeight,
    required this.isSelected,
    required this.onTap,
    required this.onPositionChanged,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });
  @override
  State<_SignatureWidget> createState() => _SignatureWidgetState();
}

class _SignatureWidgetState extends State<_SignatureWidget> {
  late Offset _position; // Absolute position in pixels
  Offset _startPosition = Offset.zero;
  Offset _dragStartPosition = Offset.zero;
  @override
  void initState() {
    super.initState();
    // Convert relative coordinates to absolute pixels for rendering
    _position = widget.signature
        .getAbsolutePosition(widget.pageWidth, widget.pageHeight);
  }

  @override
  void didUpdateWidget(_SignatureWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature ||
        oldWidget.pageWidth != widget.pageWidth ||
        oldWidget.pageHeight != widget.pageHeight) {
      // Recalculate absolute position if signature or page dimensions changed
      _position = widget.signature
          .getAbsolutePosition(widget.pageWidth, widget.pageHeight);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get absolute size for rendering
    final size =
        widget.signature.getAbsoluteSize(widget.pageWidth, widget.pageHeight);
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        // Handle tap to show options
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        // Handle dragging with pan gesture
        onPanStart: (details) {
          // Notify parent that interaction started (hide FAB)
          widget.onInteractionStart();
          _startPosition = _position;
          _dragStartPosition = details.globalPosition;
        },
        onPanUpdate: (details) {
          setState(() {
            // Calculate the delta from the start position
            final delta = details.globalPosition - _dragStartPosition;
            final newX = _startPosition.dx + delta.dx;
            final newY = _startPosition.dy + delta.dy;
            // Clamp position to keep signature within page bounds
            final currentSize = widget.signature
                .getAbsoluteSize(widget.pageWidth, widget.pageHeight);
            _position = Offset(
              newX.clamp(0.0, widget.pageWidth - currentSize.width),
              newY.clamp(0.0, widget.pageHeight - currentSize.height),
            );
          });
        },
        onPanEnd: (details) {
          widget.onPositionChanged(_position);
          // Notify parent that interaction ended (show FAB again)
          widget.onInteractionEnd();
        },
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Image.memory(
            widget.signature.imageData,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
