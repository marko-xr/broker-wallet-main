import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/viewmodels/combine_pdf/combine_pdf_viewmodel.dart';

/// The final page order of the pending combine, exactly as the combined PDF
/// will have it. The user can drag a page to a new place (also between files),
/// turn it, or take it out. The list is the view model's plan itself, so what
/// is shown here is what is combined.
class CombinePagesScreen extends StatelessWidget {
  const CombinePagesScreen({Key? key, required this.viewModel})
      : super(key: key);

  final CombinePdfViewModel viewModel;

  static const Color _accent = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final plan = viewModel.plan;
        final pages = plan.pages;
        return Scaffold(
          backgroundColor: colors.surface,
          appBar: AppBar(
            title: Column(
              children: [
                Text(
                  loc.translate('combineReviewTitle'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  loc
                      .translate('combineTotalPages')
                      .replaceAll('{count}', '${pages.length}'),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            centerTitle: true,
            backgroundColor: colors.surface,
            elevation: 0,
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  loc.translate('combineReviewHint'),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              Expanded(
                child: pages.isEmpty
                    ? Center(
                        child: Text(loc.translate('combineErrNoPages')),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: pages.length,
                        onReorderItem: viewModel.movePage,
                        itemBuilder: (context, index) {
                          final page = pages[index];
                          final source = plan.sourceById(page.sourceId);
                          final label = loc
                              .translate('combinePageLabel')
                              .replaceAll('{name}', source?.displayName ?? '')
                              .replaceAll('{page}', '${page.pageIndex + 1}');
                          return Container(
                            key: ValueKey<String>(
                                '${page.sourceId}:${page.pageIndex}'),
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: colors.outline.withValues(alpha: 0.2)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsetsDirectional.only(
                                  start: 12, end: 4),
                              leading: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: _accent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              title: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyText.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: page.quarterTurns == 0
                                  ? null
                                  : Text(
                                      '+${page.quarterTurns * 90}°',
                                      style: const TextStyle(
                                          fontSize: 12, color: _accent),
                                    ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.rotate_right,
                                        size: 20),
                                    tooltip: loc.translate('combineRotatePage'),
                                    onPressed: viewModel.isMerging
                                        ? null
                                        : () => viewModel.rotatePage(index, 1),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close,
                                        size: 20, color: colors.error),
                                    tooltip: loc.translate('combineRemovePage'),
                                    onPressed: viewModel.isMerging
                                        ? null
                                        : () => viewModel.removePage(index),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    enabled: !viewModel.isMerging,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        Icons.drag_handle,
                                        size: 20,
                                        color: colors.onSurface
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
