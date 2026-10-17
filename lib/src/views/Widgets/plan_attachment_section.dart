import 'dart:io';

import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_form.dart';

/// Where a land / plot plan can come from.
enum PlanAttachmentSource { camera, gallery, files }

/// Shows the plan source sheet — Camera, Gallery, Files — and returns what the
/// user chose, or null when they dismiss it.
Future<PlanAttachmentSource?> showPlanAttachmentSourceSheet(
    BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return showModalBottomSheet<PlanAttachmentSource>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const PlanAttachmentSourceSheet(),
  );
}

/// The compact attachment sheet of the plan: the same three-section layout as
/// the photo and video sheet, with every section available.
class PlanAttachmentSourceSheet extends StatelessWidget {
  const PlanAttachmentSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    void choose(PlanAttachmentSource source) =>
        Navigator.of(context).pop(source);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Text(
              loc.translate('planAttachmentTitle'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 16),
            child: Text(
              loc.translate('planAttachmentSheetSubtitle'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SourceTile(
                    key: const Key('planAttachmentSource.camera'),
                    icon: Icons.photo_camera_outlined,
                    label: loc.translate('planAttachmentSourceCamera'),
                    hint: loc.translate('planAttachmentSourceCameraHint'),
                    onTap: () => choose(PlanAttachmentSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceTile(
                    key: const Key('planAttachmentSource.gallery'),
                    icon: Icons.photo_library_outlined,
                    label: loc.translate('planAttachmentSourceGallery'),
                    hint: loc.translate('planAttachmentSourceGalleryHint'),
                    onTap: () => choose(PlanAttachmentSource.gallery),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceTile(
                    key: const Key('planAttachmentSource.files'),
                    icon: Icons.description_outlined,
                    label: loc.translate('planAttachmentSourceFiles'),
                    hint: loc.translate('planAttachmentSourceFilesHint'),
                    onTap: () => choose(PlanAttachmentSource.files),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Semantics(
      button: true,
      label: '$label. $hint',
      excludeSemantics: true,
      child: Material(
        color: colors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: colors.primary, size: 26),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short, localized name for a plan's file type.
String planKindLabel(AppLocalizations loc, PlanAttachmentKind kind) =>
    switch (kind) {
      PlanAttachmentKind.image => loc.translate('planAttachmentTypeImage'),
      PlanAttachmentKind.pdf => loc.translate('planAttachmentTypePdf'),
      PlanAttachmentKind.word => loc.translate('planAttachmentTypeWord'),
    };

IconData planKindIcon(PlanAttachmentKind kind) => switch (kind) {
      PlanAttachmentKind.image => Icons.image_outlined,
      PlanAttachmentKind.pdf => Icons.picture_as_pdf_outlined,
      PlanAttachmentKind.word => Icons.description_outlined,
    };

/// "512 B", "48.2 KB", "3.4 MB": the same plain units the app already shows.
String planFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The preview of a plan: its image when there is one to draw, otherwise its
/// type's icon. [busy] covers it with a progress indicator while it uploads.
class PlanPreview extends StatelessWidget {
  const PlanPreview({
    super.key,
    required this.kind,
    this.localPath,
    this.signedUrl,
    this.busy = false,
    this.size = 56,
  });

  final PlanAttachmentKind kind;
  final String? localPath;
  final String? signedUrl;
  final bool busy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = Container(
      color: colors.primary.withValues(alpha: 0.1),
      alignment: Alignment.center,
      child: Icon(planKindIcon(kind), color: colors.primary, size: size * 0.5),
    );

    Widget content = fallback;
    final path = localPath;
    final url = signedUrl;
    if (kind == PlanAttachmentKind.image && path != null) {
      content = Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else if (kind == PlanAttachmentKind.image && url != null) {
      content = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (busy)
              Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The land / plot plan section of an Add/Edit Offer or Owner form.
///
/// Empty it is one tappable field like the media field above it. With a plan it
/// is one card: what is attached, what will happen to it when the record is
/// saved, and the few actions that make sense in that state. It never shows a
/// link, a storage key or an id.
class PlanAttachmentSection extends StatelessWidget {
  const PlanAttachmentSection({
    super.key,
    required this.view,
    required this.localization,
    required this.onSelect,
    required this.onRemove,
    required this.onKeep,
    required this.onRetry,
  });

  final PlanAttachmentView view;
  final AppLocalizations localization;

  /// Opens the source sheet (add or replace).
  final VoidCallback onSelect;

  /// Drops the chosen file, or marks the server's plan for removal.
  final VoidCallback onRemove;

  /// Takes back a removal that was marked but not yet saved.
  final VoidCallback onKeep;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!view.hasContent)
      return _EmptyField(onTap: onSelect, loc: localization);
    return _PlanCard(
      view: view,
      loc: localization,
      onSelect: onSelect,
      onRemove: onRemove,
      onKeep: onKeep,
      onRetry: onRetry,
    );
  }
}

class _EmptyField extends StatelessWidget {
  const _EmptyField({required this.onTap, required this.loc});

  final VoidCallback onTap;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hint = loc.translate('planAttachmentHint');
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('planAttachment.add'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.map_outlined,
                  size: 22, color: Color(0xFF8B959A)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.hintText,
                ),
              ),
              Container(
                margin: const EdgeInsets.all(7),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.add, color: colors.onPrimary, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.view,
    required this.loc,
    required this.onSelect,
    required this.onRemove,
    required this.onKeep,
    required this.onRetry,
  });

  final PlanAttachmentView view;
  final AppLocalizations loc;
  final VoidCallback onSelect;
  final VoidCallback onRemove;
  final VoidCallback onKeep;
  final VoidCallback onRetry;

  String? _stateText() => switch (view.display) {
        PlanDisplay.draft => loc.translate('planAttachmentWillUpload'),
        PlanDisplay.replacing => loc.translate('planAttachmentReplaces'),
        PlanDisplay.removalPending => loc.translate('planAttachmentWillRemove'),
        PlanDisplay.working => loc.translate(view.isRemoval
            ? 'planAttachmentRemoving'
            : 'planAttachmentUploading'),
        PlanDisplay.failed => view.failure == null
            ? loc.translate('planAttachmentUploadFailed')
            : loc.translate(view.failure!.messageKey),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final kind = view.kind ?? PlanAttachmentKind.pdf;
    final busy = view.display == PlanDisplay.working;
    final failed = view.display == PlanDisplay.failed;
    final removing = view.display == PlanDisplay.removalPending;
    final canRetry = failed && (view.failure?.isRetryable ?? true);
    final state = _stateText();
    final name = view.displayName ?? planKindLabel(loc, kind);
    final size =
        view.byteLength == null ? null : planFileSize(view.byteLength!);

    return Container(
      key: const Key('planAttachment.card'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: failed ? Border.all(color: colors.error) : null,
      ),
      child: Opacity(
        opacity: removing ? 0.6 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PlanPreview(
              kind: kind,
              localPath: view.localPath,
              signedUrl: view.signedUrl,
              busy: busy,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyText
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    size == null
                        ? planKindLabel(loc, kind)
                        : '${planKindLabel(loc, kind)} · $size',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  if (state != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      state,
                      key: const Key('planAttachment.state'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: failed ? colors.error : colors.primary,
                      ),
                    ),
                  ],
                  // Under the explanation rather than beside it, so a phone's
                  // narrow card keeps its width for the words.
                  if (canRetry)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        key: const Key('planAttachment.retry'),
                        onPressed: onRetry,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(loc.translate('planAttachmentRetry')),
                      ),
                    ),
                ],
              ),
            ),
            if (!busy) ..._actions(colors),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(ColorScheme colors) {
    if (view.display == PlanDisplay.removalPending) {
      return [
        TextButton(
          key: const Key('planAttachment.keep'),
          onPressed: onKeep,
          child: Text(loc.translate('planAttachmentKeep')),
        ),
      ];
    }
    return [
      IconButton(
        key: const Key('planAttachment.replace'),
        tooltip: loc.translate('planAttachmentReplace'),
        onPressed: onSelect,
        icon: Icon(Icons.swap_horiz_rounded, color: colors.primary),
      ),
      IconButton(
        key: const Key('planAttachment.remove'),
        tooltip: loc.translate('planAttachmentRemove'),
        onPressed: onRemove,
        icon: Icon(Icons.delete_outline_rounded, color: colors.error),
      ),
    ];
  }
}
