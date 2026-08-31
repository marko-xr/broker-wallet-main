import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

import 'list_quotations_viewmodel.dart';
import '../Toolkit/pdf_viewer_screen.dart';

class QuotationListView extends StatefulWidget {
  const QuotationListView({super.key});

  @override
  State<QuotationListView> createState() => _QuotationListViewState();
}

class _QuotationListViewState extends State<QuotationListView> {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return ChangeNotifierProvider(
      create: (_) => QuotationListViewModel(),
      child: Consumer<QuotationListViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: colors.surface,
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(
                loc.translate('quotation'),
                style: texts.titleLarge,
              ),
              centerTitle: true,
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => context.push('/add-quotation'),
              backgroundColor: colors.primary,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, color: Colors.white),
            ),
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: StreamBuilder<List<QuotationModel>>(
                    stream: vm.quotationsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildShimmerLoading();
                      }

                      if (snapshot.hasError) {
                        return _buildErrorWidget(
                            vm, colors, texts, loc, snapshot.error.toString());
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return _buildEmptyWidget(colors, texts, loc);
                      }

                      return _buildQuotationsList(
                          snapshot.data!, vm, loc, colors, texts);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          5,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: _ShimmerContainer(
              height: 120,
              width: double.infinity,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(QuotationListViewModel vm, ColorScheme colors,
      TextTheme texts, AppLocalizations loc,
      [String? errorMessage]) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE6E6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: const Color(0xFFFF6B6B),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              loc.translate('errorLoading'),
              style: texts.headlineSmall?.copyWith(
                color: const Color(0xFFE53E3E),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                errorMessage ?? vm.error ?? loc.translate('errorLoading'),
                style: texts.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget(
      ColorScheme colors, TextTheme texts, AppLocalizations loc) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.tertiary.withValues(alpha: 0.1),
                    colors.primary.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: SvgPicture.asset(
                'assets/icons/quotation-svg.svg',
                width: 64,
                height: 64,
                colorFilter: ColorFilter.mode(
                  colors.primary,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              loc.translate('noQuotationsYet'),
              style: texts.headlineSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                loc.translate('addFirstQuotation'),
                style: texts.bodyLarge?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.6),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotationsList(
    List<QuotationModel> quotations,
    QuotationListViewModel vm,
    AppLocalizations loc,
    ColorScheme colors,
    TextTheme texts,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Statistics Card
          if (quotations.isNotEmpty)
            _buildStatisticsCard(quotations, colors, texts, loc),

          const SizedBox(height: 24),

          // Quotations List
          ...quotations.asMap().entries.map((entry) {
            final index = entry.key;
            final quotation = entry.value;
            return AnimatedContainer(
              duration: Duration(milliseconds: 300 + (index * 100)),
              curve: Curves.easeOutBack,
              margin: const EdgeInsets.only(bottom: 16),
              child: _EnhancedQuotationTile(
                quotation: quotation,
                onDelete: () =>
                    _showDeleteConfirmation(quotation, vm, loc, colors),
                onView: () => _viewPdf(quotation),
                onShare: () => _sharePdf(quotation),
                viewModel: vm, // Pass the ViewModel
                loc: loc,
                index: index,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard(List<QuotationModel> quotations,
      ColorScheme colors, TextTheme texts, AppLocalizations loc) {
    final totalQuotations = quotations.length;
    final quotationsWithPdf = quotations
        .where((q) => q.pdfUrl != null && q.pdfUrl!.isNotEmpty)
        .length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary.withValues(alpha: 0.8), colors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.tertiary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
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
            child: const Icon(Icons.description_outlined,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  totalQuotations.toString(),
                  style: texts.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  loc.translate('totalQuotations'),
                  style: texts.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(Icons.picture_as_pdf_outlined,
                    color: Colors.white, size: 20),
                const SizedBox(height: 4),
                Text(
                  '$quotationsWithPdf',
                  style: texts.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // View PDF functionality - Displays PDFs within the app
  Future<void> _viewPdf(QuotationModel quotation) async {
    if (quotation.pdfUrl != null && quotation.pdfUrl!.isNotEmpty) {
      try {
        if (quotation.pdfUrl!.startsWith('local://')) {
          // Local file - display in-app using Syncfusion PDF viewer
          final localPath = quotation.pdfUrl!.substring('local://'.length);
          final file = File(localPath);

          if (await file.exists()) {
            // Navigate to in-app PDF viewer with local file
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PdfViewerScreen(
                  localFile: file,
                  title:
                      '${AppLocalizations.of(context).translate('quotation')} - ${quotation.propertyTitle.isEmpty ? AppLocalizations.of(context).translate('untitled') : quotation.propertyTitle}',
                ),
              ),
            );
          } else {
            if (context.mounted) {
              _showToast(
                  'PDF file not found locally. Please wait for upload to complete.',
                  Colors.orange);
            }
          }
          return;
        } else {
          // Firebase URL - display in-app using Syncfusion PDF viewer
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PdfViewerScreen(
                networkUrl: quotation.pdfUrl!,
                title:
                    '${AppLocalizations.of(context).translate('quotation')} - ${quotation.propertyTitle.isEmpty ? AppLocalizations.of(context).translate('untitled') : quotation.propertyTitle}',
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          _showToast('Could not open PDF: ${e.toString()}', Colors.red);
        }
      }
    } else {
      if (context.mounted) {
        _showToast('PDF not available for this quotation', Colors.orange);
      }
    }
  }

  // Share PDF functionality - Instant sharing with smooth UX
  Future<void> _sharePdf(QuotationModel quotation) async {
    if (quotation.pdfUrl == null || quotation.pdfUrl!.isEmpty) {
      if (context.mounted) {
        _showToast('PDF not available for this quotation', Colors.orange);
      }
      return;
    }

    try {
      // First, try to find and immediately share the local PDF file
      final localPath = await _getLocalPdfPath(quotation);
      if (localPath != null) {
        final localFile = File(localPath);
        if (await localFile.exists()) {
          // Instantly share the local file without any loading message
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(localPath)],
              text: 'Quotation for ${quotation.propertyTitle}',
              subject: 'Quotation Document',
            ),
          );
          return; // Exit early - successful instant share!
        }
      }

      // Only show loading message if we need to download from Firebase
      if (context.mounted) {
        _showToast('Preparing PDF for sharing...', Colors.blue);
      }

      // Download the PDF from Firebase Storage
      final response = await http.get(Uri.parse(quotation.pdfUrl!));

      if (response.statusCode == 200) {
        // Get application documents directory for consistent storage
        final appDir = await getApplicationDocumentsDirectory();

        // Create a filename for the PDF (consistent with PDF generation service)
        final fileName =
            'quotation_${quotation.id ?? DateTime.now().millisecondsSinceEpoch}.pdf';
        final filePath = '${appDir.path}/$fileName';

        // Write the PDF to local file
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        // Share the PDF file using the system share sheet
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(filePath)],
            text: 'Quotation for ${quotation.propertyTitle}',
            subject: 'Quotation Document',
          ),
        );

        // Keep the file for future instant sharing
      } else {
        throw Exception(
            'Failed to download PDF (Status: ${response.statusCode})');
      }
    } catch (e) {
      if (context.mounted) {
        _showToast('Could not share PDF: ${e.toString()}', Colors.red);
      }
    }
  }

  // Helper method to get local PDF path - Optimized for instant access
  Future<String?> _getLocalPdfPath(QuotationModel quotation) async {
    try {
      // Priority 1: Check if PDF URL is already a local path (most common case)
      if (quotation.pdfUrl != null &&
          quotation.pdfUrl!.startsWith('local://')) {
        final localPath = quotation.pdfUrl!.substring('local://'.length);
        final file = File(localPath);
        if (await file.exists()) {
          return localPath;
        }
      }

      // Priority 2: Look for standard filename pattern (fast check)
      if (quotation.id != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = 'quotation_${quotation.id}.pdf';
        final filePath = '${appDir.path}/$fileName';

        final file = File(filePath);
        if (await file.exists()) {
          return filePath;
        }

        // Priority 3: Only do expensive directory search as last resort
        // (This should rarely happen in normal operation)
        final directory = Directory(appDir.path);
        try {
          final files = await directory.list().toList();
          for (final fileEntity in files) {
            if (fileEntity is File &&
                fileEntity.path.contains('quotation_${quotation.id}') &&
                fileEntity.path.endsWith('.pdf')) {
              return fileEntity.path;
            }
          }
        } catch (dirError) {
          // If directory listing fails, just return null - don't crash
        }
      }

      return null;
    } catch (e) {
      // Silently handle errors to avoid breaking the sharing flow
      return null;
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

  // Show delete confirmation dialog
  Future<void> _showDeleteConfirmation(
    QuotationModel quotation,
    QuotationListViewModel vm,
    AppLocalizations loc,
    ColorScheme colors,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: const Color(0xFFC81E1E),
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'Delete Quotation',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this quotation?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.8),
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE6E6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFFCCCC),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description,
                      size: 18,
                      color: const Color(0xFFC81E1E),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        quotation.propertyTitle.isNotEmpty
                            ? quotation.propertyTitle
                            : 'Unknown Property',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFC81E1E),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                // Cancel Button
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.surface,
                      foregroundColor: colors.onSurface,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: colors.outline.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          loc.translate('cancel'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: colors.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Delete Button
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC81E1E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      shadowColor:
                          const Color(0xFFC81E1E).withValues(alpha: 0.4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.delete_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          loc.translate('delete'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      if (quotation.id != null) {
        await vm.deleteQuotation(quotation.id!, context);
      }
    }
  }
}

class _EnhancedQuotationTile extends StatefulWidget {
  final QuotationModel quotation;
  final VoidCallback onDelete;
  final VoidCallback onView;
  final VoidCallback onShare;
  final QuotationListViewModel viewModel; // Add ViewModel parameter
  final AppLocalizations loc;
  final int index;

  const _EnhancedQuotationTile({
    required this.quotation,
    required this.onDelete,
    required this.onView,
    required this.onShare,
    required this.viewModel, // Add to constructor
    required this.loc,
    required this.index,
  });

  @override
  State<_EnhancedQuotationTile> createState() => _EnhancedQuotationTileState();
}

class _EnhancedQuotationTileState extends State<_EnhancedQuotationTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Dismissible(
      key: Key('quotation_${widget.quotation.id ?? widget.index}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        widget.onDelete();
        return false; // Don't dismiss automatically, let the confirmation dialog handle it
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFC72828),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: isRTL ? Alignment.centerLeft : Alignment.centerRight,
        padding: EdgeInsets.only(
          left: isRTL ? 20 : 0,
          right: isRTL ? 0 : 20,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete_outline,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              widget.loc.translate('delete'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.surface.withValues(alpha: 0.6),
                colors.surface.withValues(alpha: 0.4),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colors.tertiary.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
            border: Border.all(
              color: colors.tertiary.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {},
              onTapDown: (_) => _controller.forward(),
              onTapUp: (_) => _controller.reverse(),
              onTapCancel: () => _controller.reverse(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary.withValues(alpha: 0.1),
                          ),
                          child: Icon(
                            Icons.description_outlined,
                            color: colors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.quotation.propertyTitle.isNotEmpty
                                    ? widget.quotation.propertyTitle
                                    : 'Unknown Property',
                                style: texts.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colors.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.quotation.officeName.isNotEmpty
                                    ? widget.quotation.officeName
                                    : 'Unknown Office',
                                style: texts.bodySmall?.copyWith(
                                  color:
                                      colors.onSurface.withValues(alpha: 0.6),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // PDF Status Indicator
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (widget.quotation.pdfUrl != null &&
                                    widget.quotation.pdfUrl!.isNotEmpty)
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.picture_as_pdf,
                                size: 16,
                                color: (widget.quotation.pdfUrl != null &&
                                        widget.quotation.pdfUrl!.isNotEmpty)
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (widget.quotation.pdfUrl != null &&
                                        widget.quotation.pdfUrl!.isNotEmpty)
                                    ? widget.loc.translate('pdf')
                                    : widget.loc.translate('noPdf'),
                                style: texts.bodySmall?.copyWith(
                                  color: (widget.quotation.pdfUrl != null &&
                                          widget.quotation.pdfUrl!.isNotEmpty)
                                      ? Colors.green
                                      : Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Details Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailItemWithCustomIcon(
                            customIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/images/UAE_Dirham.png',
                                  width: 16,
                                  height: 16,
                                  color: colors.primary,
                                ),
                              ],
                            ),
                            label: widget.loc.translate('totalAmount'),
                            value: widget.quotation.totalAmount != null
                                ? 'AED ${widget.quotation.totalAmount!.toStringAsFixed(2)}'
                                : widget.loc.translate('notSpecified'),
                            colors: colors,
                            texts: texts,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: colors.outline.withValues(alpha: 0.2),
                        ),
                        Expanded(
                          child: _buildDetailItem(
                            icon: Icons.schedule_outlined,
                            label: widget.loc.translate('installments'),
                            value: widget.quotation.numberOfInstallments != null
                                ? widget.quotation.numberOfInstallments
                                    .toString()
                                : widget.loc.translate('na'),
                            colors: colors,
                            texts: texts,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

// Date and Property Type Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailItem(
                            icon: Icons.calendar_today_outlined,
                            label: widget.loc.translate('date'),
                            value: widget.quotation.date?.isNotEmpty == true
                                ? widget.quotation.date!
                                : widget.loc.translate('notSpecified'),
                            colors: colors,
                            texts: texts,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: colors.outline.withValues(alpha: 0.2),
                        ),
                        Expanded(
                          child: _buildDetailItem(
                            icon: Icons.home_outlined,
                            label: widget.loc.translate('propertyType'),
                            value: widget.quotation.propertyType?.isNotEmpty ==
                                    true
                                ? widget.quotation.propertyType!
                                : widget.loc.translate('notSpecified'),
                            colors: colors,
                            texts: texts,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Action Buttons Row
                    Row(
                      children: [
                        // View PDF Button (always shows, but disabled if no PDF)
                        Expanded(
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: (widget.quotation.pdfUrl != null &&
                                      widget.quotation.pdfUrl!.isNotEmpty)
                                  ? const Color(0xFFE3F2FD) // Blue for View PDF
                                  : const Color(0xFFF5F5F5), // Disabled gray
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: (widget.quotation.pdfUrl != null &&
                                        widget.quotation.pdfUrl!.isNotEmpty)
                                    ? widget.onView // View existing PDF
                                    : null, // Disabled if no PDF
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons
                                          .visibility_outlined, // Always use view icon
                                      color: (widget.quotation.pdfUrl != null &&
                                              widget
                                                  .quotation.pdfUrl!.isNotEmpty)
                                          ? const Color(
                                              0xFF1976D2) // Blue for view
                                          : Colors.grey, // Grey for disabled
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      (widget.quotation.pdfUrl != null &&
                                              widget
                                                  .quotation.pdfUrl!.isNotEmpty)
                                          ? widget.loc.translate('viewPdf')
                                          : widget.loc.translate(
                                              'noPdf'), // Show "No PDF" if not available
                                      style: texts.bodyMedium?.copyWith(
                                        color:
                                            (widget.quotation.pdfUrl != null &&
                                                    widget.quotation.pdfUrl!
                                                        .isNotEmpty)
                                                ? const Color(0xFF1976D2)
                                                : Colors.grey,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Share Button (only active if PDF exists)
                        Expanded(
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: (widget.quotation.pdfUrl != null &&
                                      widget.quotation.pdfUrl!.isNotEmpty)
                                  ? const Color(0xFFFFF3E0) // Orange for share
                                  : const Color(0xFFF5F5F5), // Disabled gray
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: (widget.quotation.pdfUrl != null &&
                                        widget.quotation.pdfUrl!.isNotEmpty)
                                    ? widget.onShare
                                    : null,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.share_outlined,
                                      color: (widget.quotation.pdfUrl != null &&
                                              widget
                                                  .quotation.pdfUrl!.isNotEmpty)
                                          ? const Color(
                                              0xFFFF9800) // Orange for share
                                          : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      widget.loc.translate('share'),
                                      style: texts.bodyMedium?.copyWith(
                                        color: (widget.quotation.pdfUrl !=
                                                    null &&
                                                widget.quotation.pdfUrl!
                                                    .isNotEmpty)
                                            ? const Color(
                                                0xFFFF9800) // Orange for share
                                            : Colors.grey,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colors,
    required TextTheme texts,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Icon(
            icon,
            size: 18,
            color: colors.primary,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: texts.bodySmall?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.6),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: texts.bodySmall?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItemWithCustomIcon({
    required Widget customIcon,
    required String label,
    required String value,
    required ColorScheme colors,
    required TextTheme texts,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          SizedBox(
            height: 18,
            child: customIcon,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: texts.bodySmall?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.6),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: texts.bodySmall?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ShimmerContainer extends StatefulWidget {
  final double height;
  final double width;

  const _ShimmerContainer({
    required this.height,
    required this.width,
  });

  @override
  State<_ShimmerContainer> createState() => _ShimmerContainerState();
}

class _ShimmerContainerState extends State<_ShimmerContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                colors.surface.withValues(alpha: 0.4),
                colors.surface.withValues(alpha: 0.8),
                colors.surface.withValues(alpha: 0.4),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(-1.0 + _animation.value, 0.0),
              end: Alignment(1.0 + _animation.value, 0.0),
            ),
          ),
        );
      },
    );
  }
}
