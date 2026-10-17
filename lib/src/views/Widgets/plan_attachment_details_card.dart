import 'package:flutter/material.dart';

import 'package:broker_wallet/src/Views/Widgets/plan_attachment_actions.dart';
import 'package:broker_wallet/src/Views/Widgets/plan_attachment_section.dart'
    show PlanPreview, planFileSize, planKindLabel;
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';

/// The land / plot plan of an Offer or an Owner record on its Details screen.
///
/// Its own card — never part of the photo and video carousel — in the same
/// style as the Notes and Location cards: what the plan is, and what can be done
/// with it. An image and a PDF open inside Broker Wallet; a Word file has no
/// viewer here and opens in another app on the phone, which the card says so.
/// Share sends the file itself. No link, storage key or id is ever drawn.
class PlanAttachmentDetailsCard extends StatefulWidget {
  const PlanAttachmentDetailsCard({
    super.key,
    required this.parent,
    required this.parentId,
    required this.plan,
    this.actions,
  });

  final PlanParent parent;
  final String parentId;
  final PlanAttachmentRef plan;

  /// For tests; the app uses the standard actions.
  final PlanAttachmentActions? actions;

  @override
  State<PlanAttachmentDetailsCard> createState() =>
      _PlanAttachmentDetailsCardState();
}

class _PlanAttachmentDetailsCardState extends State<PlanAttachmentDetailsCard> {
  late final PlanAttachmentActions _actions =
      widget.actions ?? PlanAttachmentActions();
  bool _opening = false;
  bool _sharing = false;

  bool get _busy => _opening || _sharing;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _opening = true);
    try {
      await _actions.open(
        context,
        parent: widget.parent,
        parentId: widget.parentId,
        plan: widget.plan,
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _sharing = true);
    try {
      await _actions.share(
        context,
        parent: widget.parent,
        parentId: widget.parentId,
        plan: widget.plan,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);
    final plan = widget.plan;
    final name = plan.displayName ?? planKindLabel(loc, plan.kind);
    final size =
        plan.byteLength == null ? null : planFileSize(plan.byteLength!);
    final isWord = plan.kind == PlanAttachmentKind.word;

    return RepaintBoundary(
      child: Container(
        key: const Key('planAttachment.details'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.08),
              blurRadius: 16,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.map_outlined,
                      color: colors.secondary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.translate('planAttachmentTitle'),
                    style: texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.outline.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  PlanPreview(
                    kind: plan.kind,
                    signedUrl: plan.hasFreshUrl(DateTime.now())
                        ? plan.signedUrl
                        : null,
                    size: 64,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyText
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          size == null
                              ? planKindLabel(loc, plan.kind)
                              : '${planKindLabel(loc, plan.kind)} · $size',
                          style: texts.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        if (isWord) ...[
                          const SizedBox(height: 4),
                          Text(
                            loc.translate('planAttachmentOpensExternally'),
                            key: const Key(
                                'planAttachment.details.externalNote'),
                            style: texts.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key('planAttachment.details.open'),
                    onPressed: _busy ? null : _open,
                    icon: _opening
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.onPrimary,
                            ),
                          )
                        : Icon(
                            isWord
                                ? Icons.open_in_new_rounded
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                    label: Text(
                      loc.translate(
                          isWord ? 'planAttachmentOpen' : 'planAttachmentView'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('planAttachment.details.share'),
                    onPressed: _busy ? null : _share,
                    icon: _sharing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          )
                        : const Icon(Icons.share_outlined, size: 20),
                    label: Text(
                      loc.translate('share'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      minimumSize: const Size(0, 44),
                      side: BorderSide(color: colors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
