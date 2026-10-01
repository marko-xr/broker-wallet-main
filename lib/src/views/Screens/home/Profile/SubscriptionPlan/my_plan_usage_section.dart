import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// Per-section usage counters, shown on the Plan usage screen under
/// Subscription & Billing.
///
/// LEGACY READ, ISOLATED ON PURPOSE. The counters still live in the Firestore
/// `users/{uid}` document that the existing quota code maintains, so this is
/// the one place the subscription screens still read it. It reads ONLY `counts` and
/// `lifetimeCreated`; it never reads the old `plan`/`subscription` fields, and
/// whether limits apply comes from the caller ([showLimits]), which gets it
/// from the new subscription presentation state. When the document cannot be
/// read (for example the account has no Firestore session) the section simply
/// does not appear — the plan itself never depends on it.
class MyPlanUsageSection extends StatefulWidget {
  const MyPlanUsageSection({
    super.key,
    required this.userId,
    required this.showLimits,
  });

  final String userId;

  /// True when the free-plan limits are what the user is living with.
  final bool showLimits;

  @override
  State<MyPlanUsageSection> createState() => _MyPlanUsageSectionState();
}

class _UsageEntry {
  const _UsageEntry(this.key, this.labelKey, this.icon);

  final String key;
  final String labelKey;
  final String icon;
}

class _MyPlanUsageSectionState extends State<MyPlanUsageSection> {
  /// Free-plan creation limit, as enforced by `QuotaHelper`.
  static const int _freeLimit = 3;

  static const List<_UsageEntry> _sections = [
    _UsageEntry('offers', 'offers', SvgIcon.offersSvg),
    _UsageEntry('requests', 'requests', SvgIcon.requestedSvg),
    _UsageEntry('owners', 'owners', SvgIcon.ownersSvg),
    _UsageEntry('offices', 'offices', SvgIcon.officesSvg),
    _UsageEntry('brokers', 'brokers', SvgIcon.brokersSvg),
    _UsageEntry('watchmen', 'watchmen', SvgIcon.watchmanSvg),
    _UsageEntry('quotations', 'quotations', SvgIcon.quotationSvg),
  ];

  static const List<_UsageEntry> _tools = [
    _UsageEntry('scanner', 'scanner', SvgIcon.scanIcon),
    _UsageEntry('signature', 'signature', SvgIcon.signatureIcon),
    _UsageEntry('imageToPdf', 'convertImagesToPdf', SvgIcon.galleryIcon),
    _UsageEntry('combinePdfs', 'combinePdfs', SvgIcon.combinePdfsIcon),
  ];

  late Stream<DocumentSnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _open();
  }

  @override
  void didUpdateWidget(MyPlanUsageSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _stream = _open();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _open() =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .snapshots();

  static int _count(Map<String, dynamic> source, String key) =>
      (source[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data?.data();
        if (data == null) return const SizedBox.shrink();

        final counts = (data['counts'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final lifetime =
            (data['lifetimeCreated'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};

        return _UsageBody(
          counts: counts,
          lifetime: lifetime,
          showLimits: widget.showLimits,
          sections: _sections,
          tools: _tools,
          limit: _freeLimit,
        );
      },
    );
  }
}

class _UsageBody extends StatelessWidget {
  const _UsageBody({
    required this.counts,
    required this.lifetime,
    required this.showLimits,
    required this.sections,
    required this.tools,
    required this.limit,
  });

  final Map<String, dynamic> counts;
  final Map<String, dynamic> lifetime;
  final bool showLimits;
  final List<_UsageEntry> sections;
  final List<_UsageEntry> tools;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlusSectionTitle(l10n.translate('mainSections')),
        _group(context, sections),
        const SizedBox(height: 24),
        PlusSectionTitle(l10n.translate('toolkitTools')),
        _group(context, tools),
      ],
    );
  }

  Widget _group(BuildContext context, List<_UsageEntry> entries) {
    final colors = Theme.of(context).colorScheme;
    return PlusCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: colors.outline.withValues(alpha: 0.15),
              ),
            _UsageRow(
              entry: entries[i],
              count: _MyPlanUsageSectionState._count(counts, entries[i].key),
              lifetimeCount:
                  _MyPlanUsageSectionState._count(lifetime, entries[i].key),
              limit: limit,
              showLimits: showLimits,
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.entry,
    required this.count,
    required this.lifetimeCount,
    required this.limit,
    required this.showLimits,
  });

  final _UsageEntry entry;
  final int count;
  final int lifetimeCount;
  final int limit;
  final bool showLimits;

  String _description(AppLocalizations l10n, bool reachedLimit) {
    if (!showLimits) return l10n.translate('unlimitedItemsAvailable');
    if (reachedLimit) return l10n.translate('quotaLimitReached');
    if (count == 0) return l10n.translate('youHaveThreeItemsAvailable');
    final remaining = limit - count;
    if (remaining == 1) return l10n.translate('oneSlotRemaining');
    if (remaining == 2) return l10n.translate('twoSlotsRemaining');
    return l10n.translate('allSlotsUsed');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final reachedLimit = showLimits && lifetimeCount >= limit;
    final accent = reachedLimit ? colors.error : colors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SvgPicture.asset(
              entry.icon,
              colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate(entry.labelKey),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _description(l10n, reachedLimit),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: reachedLimit
                        ? colors.error
                        : colors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              showLimits ? '$count / $limit' : '$count',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
