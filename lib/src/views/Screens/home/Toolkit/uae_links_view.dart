import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/tool_header_card.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/data/models/uae_links_catalogue.dart';
import 'package:broker_wallet/src/data/models/uae_links_model.dart';
import 'package:broker_wallet/src/services/uae_links/uae_link_launcher.dart';
import 'package:broker_wallet/src/services/uae_links/uae_link_report.dart';
import 'package:broker_wallet/src/services/uae_links/uae_links_search.dart';

/// The curated directory of official UAE real-estate services.
///
/// Opening a link only hands the verified address to the phone's browser; the
/// app never signs in, never completes a transaction and never says one was
/// done. The collaborators are parameters so the screen can be exercised
/// without a phone.
class UAELinksView extends StatefulWidget {
  const UAELinksView({
    super.key,
    this.launcher = const UaeLinkLauncher(),
    this.copyToClipboard,
    this.shareText,
    this.now,
  });

  final UaeLinkLauncher launcher;

  /// Puts text on the clipboard. May throw.
  final Future<void> Function(String text)? copyToClipboard;

  /// Opens the system share sheet with [text]. May throw.
  final Future<void> Function(String text, String subject)? shareText;

  final DateTime Function()? now;

  @override
  State<UAELinksView> createState() => _UAELinksViewState();
}

/// The screen's blue identity (unchanged from the previous version).
const Color _brand = Color(0xFF1976D2);
const Color _brandDark = Color(0xFF0D47A1);

class _UAELinksViewState extends State<UAELinksView> {
  final TextEditingController _search = TextEditingController();
  final List<UaeLinkEntry> _all = UAELinksData.published;
  UaeLinkEmirate? _emirate;
  UaeLinkTask? _task;
  late List<UaeLinkGroup> _groups = _compute();

  bool get _filtering =>
      _search.text.trim().isNotEmpty || _emirate != null || _task != null;

  List<UaeLinkGroup> _compute() => UaeLinksSearch.group(
        _all,
        query: _search.text,
        emirate: _emirate,
        task: _task,
      );

  void _refresh(VoidCallback change) => setState(() {
        change();
        _groups = _compute();
      });

  void _reset() {
    _search.clear();
    _refresh(() {
      _emirate = null;
      _task = null;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AppLocalizations get _l => AppLocalizations.of(context);
  String get _lang => _l.locale.languageCode;

  void _snack(String message, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: error ? TextStyle(color: scheme.onError) : null,
        ),
        backgroundColor: error ? scheme.error : null,
        duration: Duration(seconds: error ? 4 : 2),
      ),
    );
  }

  Future<void> _open(UaeLinkEntry entry) async {
    final result = await widget.launcher.open(entry.url);
    if (!mounted) return;
    switch (result) {
      case UaeLinkOpenResult.opened:
        break; // The browser took over; nothing more to say.
      case UaeLinkOpenResult.rejected:
        _snack(_l.translate('ulxOpenRejected'), error: true);
      case UaeLinkOpenResult.failed:
        _snack(_l.translate('ulxOpenFailed'), error: true);
    }
  }

  Future<void> _copyText(String text) async {
    final copy = widget.copyToClipboard ??
        (String value) => Clipboard.setData(ClipboardData(text: value));
    await copy(text);
  }

  Future<void> _copyLink(UaeLinkEntry entry) async {
    try {
      await _copyText(entry.url);
    } catch (_) {
      if (mounted) _snack(_l.translate('ulxCopyFailed'), error: true);
      return;
    }
    if (mounted) _snack(_l.translate('linkCopiedToClipboard'));
  }

  String _reportText(UaeLinkEntry entry, UaeLinkIssue issue) =>
      UaeLinkReport.build(
        entry: entry,
        issue: issue,
        reportedAt: (widget.now ?? DateTime.now)(),
      );

  Future<void> _copyReport(UaeLinkEntry entry, UaeLinkIssue issue) async {
    try {
      await _copyText(_reportText(entry, issue));
    } catch (_) {
      if (mounted) _snack(_l.translate('ulxReportCopyFailed'), error: true);
      return;
    }
    if (mounted) _snack(_l.translate('ulxReportCopied'));
  }

  Future<void> _shareReport(UaeLinkEntry entry, UaeLinkIssue issue) async {
    final share = widget.shareText ?? _shareWithSystem;
    try {
      await share(
          _reportText(entry, issue), 'Broker Wallet - UAE Links report');
    } catch (_) {
      if (mounted) _snack(_l.translate('ulxReportShareFailed'), error: true);
    }
  }

  static Future<void> _shareWithSystem(String text, String subject) async {
    final result = await SharePlus.instance.share(
      ShareParams(text: text, subject: subject),
    );
    if (result.status == ShareResultStatus.unavailable) {
      throw StateError('share unavailable');
    }
  }

  void _openReportSheet(UaeLinkEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _ReportSheet(
        entry: entry,
        languageCode: _lang,
        translate: _l.translate,
        reportText: (issue) => _reportText(entry, issue),
        onCopy: (issue) {
          Navigator.of(sheetContext).pop();
          _copyReport(entry, issue);
        },
        onShare: (issue) {
          Navigator.of(sheetContext).pop();
          _shareReport(entry, issue);
        },
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final l = _l;
    final colors = Theme.of(context).colorScheme;
    final rows = _buildRows(l);

    // The bar floats over the page like the other tools: its gradient fades
    // out, and the content starts below the status bar and toolbar.
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      backgroundColor: colors.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // BackArrowButton pads itself by 16 px unless told otherwise; with zero
        // padding and a 48 px leading slot the arrow sits on the content edge.
        leadingWidth: 48,
        leading: const BackArrowButton(
          iconColor: Colors.white,
          iconSize: 24,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          showBackground: false,
        ),
        title: Text(
          l.translate('uaeLinks'),
          style: AppTextStyles.appBarTitle
              .copyWith(fontSize: 20, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _brand.withValues(alpha: 0.9),
                _brandDark.withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 4),
              child: _searchField(l),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: rows.length,
                itemBuilder: (context, index) => rows[index],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRows(AppLocalizations l) {
    final rows = <Widget>[
      _header(l),
      const SizedBox(height: 12),
      _chipRow<UaeLinkEmirate?>(
        rowKey: const Key('uaeLinksEmirateChips'),
        semanticsLabel: l.translate('ulxEmirateFilterLabel'),
        options: <UaeLinkEmirate?>[null, ...UaeLinkEmirate.values],
        selected: _emirate,
        label: (e) => l.translate(e == null ? 'all' : e.labelKey),
        chipKey: (e) => Key('uaeLinksEmirate-${e?.name ?? 'all'}'),
        onSelected: (e) => _refresh(() => _emirate = e),
      ),
      const SizedBox(height: 8),
      _chipRow<UaeLinkTask?>(
        rowKey: const Key('uaeLinksTaskChips'),
        semanticsLabel: l.translate('ulxTaskFilterLabel'),
        options: <UaeLinkTask?>[null, ...UaeLinkTask.values],
        selected: _task,
        label: (t) => l.translate(t == null ? 'ulxAllTasks' : t.labelKey),
        chipKey: (t) => Key('uaeLinksTask-${t?.name ?? 'all'}'),
        onSelected: (t) => _refresh(() => _task = t),
      ),
      const SizedBox(height: 8),
      _resultsBar(l),
    ];

    if (_groups.isEmpty) {
      rows.add(_emptyState(l));
    } else {
      for (final group in _groups) {
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Semantics(
            header: true,
            child: Row(
              children: [
                const Icon(Icons.place_outlined, size: 20, color: _brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${l.translate(group.emirate.labelKey)} (${group.entries.length})',
                    style: AppTextStyles.bodyText.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _brand,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
        for (final entry in group.entries) {
          rows.add(Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ServiceCard(
              key: Key('uaeLink-${entry.id}'),
              entry: entry,
              languageCode: _lang,
              translate: l.translate,
              onOpen: () => _open(entry),
              onCopy: () => _copyLink(entry),
              onReport: () => _openReportSheet(entry),
            ),
          ));
        }
      }
    }

    rows.add(_footer(l));
    return rows;
  }

  Widget _searchField(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    return TextField(
      key: const Key('uaeLinksSearchField'),
      controller: _search,
      textInputAction: TextInputAction.search,
      onChanged: (_) => _refresh(() {}),
      decoration: InputDecoration(
        hintText: l.translate('ulxSearchHint'),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                key: const Key('uaeLinksSearchClear'),
                tooltip: l.translate('ulxSearchClear'),
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _search.clear();
                  _refresh(() {});
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _header(AppLocalizations l) {
    return ToolHeaderCard(
      icon: Icons.verified_rounded,
      title: l.translate('ulxHeaderTitle'),
      subtitle: l.translate('ulxHeaderBody'),
      gradient: const [_brand, _brandDark],
      // The list around it already pads the sides.
      margin: EdgeInsets.zero,
    );
  }

  Widget _chipRow<T>({
    required Key rowKey,
    required String semanticsLabel,
    required List<T> options,
    required T selected,
    required String Function(T) label,
    required Key Function(T) chipKey,
    required ValueChanged<T> onSelected,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: SingleChildScrollView(
        key: rowKey,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final option in options)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  key: chipKey(option),
                  label: Text(label(option)),
                  selected: option == selected,
                  showCheckmark: false,
                  onSelected: (_) => onSelected(option),
                  selectedColor: _brand.withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                    color: option == selected ? _brand : colors.onSurface,
                    fontWeight:
                        option == selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultsBar(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    final count = _groups.fold<int>(0, (sum, g) => sum + g.entries.length);
    // A Wrap, not a Row: with large text the reset button takes the whole
    // width and drops to its own line instead of squeezing the count.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l.translate('ulxResultsCount').replaceAll('{count}', '$count'),
          key: const Key('uaeLinksResultCount'),
          style: TextStyle(
            fontSize: 13,
            color: colors.onSurface.withValues(alpha: 0.7),
          ),
        ),
        if (_filtering)
          TextButton.icon(
            key: const Key('uaeLinksReset'),
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l.translate('ulxResetFilters')),
          ),
      ],
    );
  }

  Widget _emptyState(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('uaeLinksEmpty'),
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 56, color: colors.onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            l.translate('noLinksFound'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.translate('ulxEmptyHint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('uaeLinksEmptyReset'),
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(l.translate('ulxResetFilters')),
          ),
        ],
      ),
    );
  }

  Widget _footer(AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    final latest = _all
        .map((e) => e.lastVerified)
        .fold<String>('', (a, b) => a.compareTo(b) >= 0 ? a : b);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Text(
        '${l.translate('ulxFooterNote')}\n'
        '${l.translate('ulxLastReview').replaceAll('{date}', latest)}',
        key: const Key('uaeLinksFooter'),
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: colors.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// One service: what it is, who runs it, what opening it will do.
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    super.key,
    required this.entry,
    required this.languageCode,
    required this.translate,
    required this.onOpen,
    required this.onCopy,
    required this.onReport,
  });

  final UaeLinkEntry entry;
  final String languageCode;
  final String Function(String) translate;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onReport;

  static IconData _iconFor(UaeLinkType type) => switch (type) {
        UaeLinkType.action => Icons.touch_app_rounded,
        UaeLinkType.verification => Icons.fact_check_rounded,
        UaeLinkType.information => Icons.menu_book_rounded,
        UaeLinkType.portal => Icons.account_balance_rounded,
        UaeLinkType.payment => Icons.payments_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = entry.title(languageCode);
    final emirates = entry.emirates
        .map((e) => translate(e.labelKey))
        .join(languageCode == 'ar' ? '، ' : ', ');

    return Card(
      margin: EdgeInsets.zero,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _brand.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: Key('uaeLinkOpenArea-${entry.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _brand.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child:
                            Icon(_iconFor(entry.type), color: _brand, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              entry.authority(languageCode),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _brand,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.description(languageCode),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: colors.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Tag(
                        text: translate(entry.type.labelKey),
                        icon: _iconFor(entry.type),
                      ),
                      if (entry.requiresLogin)
                        _Tag(
                          text: translate('ulxLoginRequired'),
                          icon: Icons.lock_outline_rounded,
                        ),
                      if (entry.verification ==
                          UaeLinkVerification.officialManualCheckRequired)
                        _Tag(
                          text: translate('ulxCheckOnSite'),
                          icon: Icons.info_outline_rounded,
                          warning: true,
                        ),
                      if (entry.emirates.length > 1 && !entry.isFederal)
                        _Tag(
                          text: translate('ulxAppliesTo')
                              .replaceAll('{emirates}', emirates),
                          icon: Icons.place_outlined,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  key: Key('uaeLinkReport-${entry.id}'),
                  tooltip: translate('ulxReportIssue'),
                  icon: const Icon(Icons.flag_outlined, size: 20),
                  onPressed: onReport,
                ),
                IconButton(
                  key: Key('uaeLinkCopy-${entry.id}'),
                  tooltip: translate('copyLink'),
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: onCopy,
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  key: Key('uaeLinkOpen-${entry.id}'),
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(translate('ulxOpen')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.icon, this.warning = false});

  final String text;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = warning ? colors.tertiary : colors.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.withValues(alpha: 0.8)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                color: color.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "report a broken link" sheet: the user picks the problem, sees exactly
/// the text, and copies or shares it themselves. Nothing is sent from here.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.entry,
    required this.languageCode,
    required this.translate,
    required this.reportText,
    required this.onCopy,
    required this.onShare,
  });

  final UaeLinkEntry entry;
  final String languageCode;
  final String Function(String) translate;
  final String Function(UaeLinkIssue) reportText;
  final ValueChanged<UaeLinkIssue> onCopy;
  final ValueChanged<UaeLinkIssue> onShare;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  UaeLinkIssue _issue = UaeLinkIssue.doesNotOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = widget.translate;
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('ulxReportTitle'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.entry.title(widget.languageCode),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      widget.entry.authority(widget.languageCode),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(t('ulxReportWhat'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    for (final issue in UaeLinkIssue.values)
                      ListTile(
                        key: Key('uaeLinkIssue-${issue.name}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        selected: issue == _issue,
                        leading: Icon(
                          issue == _issue
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: issue == _issue ? _brand : null,
                        ),
                        title: Text(t(issue.labelKey)),
                        onTap: () => setState(() => _issue = issue),
                      ),
                    const SizedBox(height: 8),
                    Text(t('ulxReportPreview'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        widget.reportText(_issue),
                        key: const Key('uaeLinkReportPreview'),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t('ulxReportNote'),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('uaeLinkReportCopy'),
                      onPressed: () => widget.onCopy(_issue),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(t('ulxCopyReport')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('uaeLinkReportShare'),
                      onPressed: () => widget.onShare(_issue),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: Text(t('ulxShareReport')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
