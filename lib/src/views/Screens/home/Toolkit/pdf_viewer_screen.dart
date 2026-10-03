import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/share/share_live.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_preparer.dart'
    show ShareAttachmentKind;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class PdfViewerScreen extends StatefulWidget {
  final File? localFile;
  final String? networkUrl;
  final String title;

  const PdfViewerScreen({
    super.key,
    this.localFile,
    this.networkUrl,
    this.title = 'PDF Viewer',
  }) : assert(localFile != null || networkUrl != null,
            'Either localFile or networkUrl must be provided');

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  String? _errorMessage;
  bool _isLoading = true;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    // Add a small delay to ensure smooth transition
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: textTheme.titleLarge?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Share button for PDFs. The button's own box is where an iPad anchors
          // the share sheet; it is off while a share is being prepared.
          Builder(
            builder: (buttonContext) => IconButton(
              icon: Icon(Icons.share, color: colors.onSurface),
              onPressed: _isSharing
                  ? null
                  : () => _sharePdf(ShareLive.originOf(buttonContext)),
              tooltip: loc.translate('share'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: colors.primary),
                  const SizedBox(height: 16),
                  Text(
                    loc.translate('loadingPdf'),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? _buildErrorView(context, loc)
              : _buildPdfViewer(),
    );
  }

  Widget _buildPdfViewer() {
    try {
      if (widget.localFile != null) {
        // Display local PDF file
        return SfPdfViewer.file(
          widget.localFile!,
          key: _pdfViewerKey,
          onDocumentLoadFailed: (details) {
            setState(() {
              _errorMessage = details.error;
            });
          },
          canShowScrollHead: false,
          canShowPaginationDialog: true,
          enableDoubleTapZooming: true,
          enableTextSelection: true,
        );
      } else if (widget.networkUrl != null) {
        // Display network PDF (Firebase URL)
        return SfPdfViewer.network(
          widget.networkUrl!,
          key: _pdfViewerKey,
          onDocumentLoadFailed: (details) {
            setState(() {
              _errorMessage = details.error;
            });
          },
          canShowScrollHead: false,
          canShowPaginationDialog: true,
          enableDoubleTapZooming: true,
          enableTextSelection: true,
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    }

    return _buildErrorView(context);
  }

  Widget _buildErrorView(BuildContext context, [AppLocalizations? loc]) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final localization = loc ?? AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: colors.error,
            ),
            const SizedBox(height: 16),
            Text(
              localization.translate('failedToLoadPdf'),
              style: textTheme.headlineSmall?.copyWith(
                color: colors.error,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ??
                  localization.translate('errorOccurredLoadingPdf'),
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: Text(localization.translate('goBack')),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Shares the PDF as a file under the document's own title. A PDF held on
  // this phone is shared from there; one that was opened from a link is
  // downloaded first. The link itself is never shared, and a failure shows a
  // short localized message rather than the error.
  Future<void> _sharePdf(ShareOrigin? origin) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    try {
      File? source;
      var isTemporary = false;
      final local = widget.localFile;
      if (local != null && await local.exists()) {
        source = local;
      } else if (widget.networkUrl != null && widget.networkUrl!.isNotEmpty) {
        source = await _downloadPdfToCache(widget.networkUrl!);
        isTemporary = true;
      }

      if (source == null || !await source.exists()) {
        _showShareToast(
          local == null && widget.networkUrl == null
              ? loc.translate('noPdfAvailableToShare')
              : loc.translate('failedToSharePdf'),
          colors.error,
        );
        return;
      }

      await ShareLive.sendNamedFile(
        source,
        kind: ShareAttachmentKind.pdf,
        baseName: widget.title,
        origin: origin,
        isTemporary: isTemporary,
        text: widget.title,
        subject: widget.title,
      );
    } catch (_) {
      // A ShareFailure or anything else: one short message, never the error.
      _showShareToast(loc.translate('failedToSharePdf'), colors.error);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _showShareToast(String message, Color background) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: background,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  Future<File?> _downloadPdfToCache(String url) async {
    try {
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return null;

      final dir = await getTemporaryDirectory();
      final fileName = widget.title.trim().isNotEmpty
          ? widget.title.replaceAll(RegExp(r'[^\w\.-]+'), '_')
          : 'document';
      final file = File('${dir.path}/$fileName.pdf');

      await file.writeAsBytes(res.bodyBytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    // Clean up resources if needed
    super.dispose();
  }
}
