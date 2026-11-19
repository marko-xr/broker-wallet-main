import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'offer_details_style.dart';
import 'package:broker_wallet/src/views/Widgets/field_icons.dart';

class DetailsSection extends StatelessWidget {
  const DetailsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  static const double spacing = 12;
  static const double fieldColumnGap = 8;

  static BoxDecoration decoration(ColorScheme colors) => BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: colors.onSurface.withValues(alpha: 0.025), width: 0.7),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: decoration(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, color: colors.primary, size: 18),
            const SizedBox(width: 7),
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            if (action != null) action!,
          ]),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class DetailsFields extends StatelessWidget {
  const DetailsFields({
    super.key,
    required this.title,
    required this.rows,
  });

  final String title;
  final List<DetailsField> rows;

  @override
  Widget build(BuildContext context) {
    return DetailsSection(
      title: title,
      icon: Icons.description_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

/// The record's Edit and Delete, as the overflow menu at the end of the
/// Details header: they act on the whole record, so they sit with the other
/// record actions (Favorite, Share) rather than inside one section.
class DetailsActionsMenu extends StatelessWidget {
  const DetailsActionsMenu({
    super.key,
    required this.deleteLabel,
    required this.onEdit,
    required this.onDelete,
    this.tooltip,
  });

  final String deleteLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('details-actions'),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert, size: 21 * OfferDetailsStyle.scale(context)),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(kMinInteractiveDimension),
      ),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const ValueKey('details-edit'),
          value: onEdit,
          child: DetailsMenuLabel(label: loc.translate('edit')),
        ),
        PopupMenuItem(
          key: const ValueKey('details-delete'),
          value: onDelete,
          child: DetailsMenuLabel(label: deleteLabel, destructive: true),
        ),
      ],
    );
  }
}

class DetailsMenuLabel extends StatelessWidget {
  const DetailsMenuLabel({
    super.key,
    required this.label,
    this.destructive = false,
  });

  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive ? colors.error : colors.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(destructive ? Icons.delete_outline : Icons.edit_outlined,
            color: color, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child:
              Text(label, style: destructive ? TextStyle(color: color) : null),
        ),
      ],
    );
  }
}

class DetailsField extends StatelessWidget {
  const DetailsField({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onCopy,
    this.isMissing = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;
  final bool isMissing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labelStyle = theme.textTheme.bodyMedium;
    return InkWell(
      onTap: onCopy,
      child: Container(
        constraints: BoxConstraints(
          minHeight: MediaQuery.textScalerOf(context)
              .scale(kMinInteractiveDimension)
              .clamp(kMinInteractiveDimension, double.infinity),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
        ),
        child: Row(children: [
          Icon(icon, size: 15, color: FieldIcons.colorIn(colors)),
          const SizedBox(width: 7),
          Expanded(flex: 4, child: Text(label, style: labelStyle)),
          const SizedBox(width: DetailsSection.fieldColumnGap),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textDirection: onCopy == null ? null : TextDirection.ltr,
              textAlign: Directionality.of(context) == TextDirection.rtl
                  ? TextAlign.left
                  : TextAlign.right,
              style: labelStyle?.copyWith(
                color: isMissing ? colors.onSurfaceVariant : null,
                fontWeight: isMissing ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ),
          if (onCopy != null) ...[
            const SizedBox(width: 5),
            Icon(Icons.copy_outlined, size: 13, color: colors.primary),
          ],
        ]),
      ),
    );
  }
}

/// When a record was added and, if it changed on a later day, last updated:
/// how fresh the broker's information is.
class DetailsDates {
  const DetailsDates._();

  static String format(BuildContext context, DateTime date) {
    final locale = AppLocalizations.of(context).locale.toString();
    return DateFormat.yMMMd(DateFormat.localeExists(locale) ? locale : 'en_US')
        .format(date);
  }

  /// Whether [updated] is worth its own row: a later day than [created], so a
  /// save that only finished the record (its media, say) is not an "update".
  static bool showsUpdate(DateTime created, DateTime? updated) =>
      updated != null &&
      updated.isAfter(created) &&
      !DateUtils.isSameDay(created, updated);

  /// The rows for [DetailsFields]; none when the record has no added date.
  static List<DetailsField> fields(BuildContext context,
      {required DateTime? createdAt, required DateTime? updatedAt}) {
    if (createdAt == null) return const [];
    final loc = AppLocalizations.of(context);
    return [
      DetailsField(
        key: const ValueKey('details-date-added'),
        icon: Icons.event_outlined,
        label: loc.translate('dateAdded'),
        value: format(context, createdAt),
      ),
      if (showsUpdate(createdAt, updatedAt))
        DetailsField(
          key: const ValueKey('details-last-updated'),
          icon: Icons.update,
          label: loc.translate('lastUpdated'),
          value: format(context, updatedAt!),
        ),
    ];
  }
}

class DetailsSummary extends StatelessWidget {
  const DetailsSummary({
    super.key,
    required this.title,
    this.titleLabel,
    this.titleMissing = false,
    this.subtitle,
    this.subtitleLabel,
    this.icon = Icons.location_on,
  });

  final String title;
  final String? titleLabel;
  final bool titleMissing;
  final String? subtitle;
  final String? subtitleLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          semanticsLabel: titleLabel == null ? null : '$titleLabel: $title',
          style: theme.textTheme.titleLarge?.copyWith(
            color: titleMissing ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 7),
          Row(children: [
            Icon(icon, color: FieldIcons.colorIn(theme.colorScheme), size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                subtitle!,
                semanticsLabel:
                    subtitleLabel == null ? null : '$subtitleLabel: $subtitle',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ]),
        ],
      ],
    );
  }
}

class DetailsStatusBadge extends StatelessWidget {
  const DetailsStatusBadge({
    super.key,
    required this.background,
    required this.onTap,
    required this.child,
  });

  final Color background;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    if (onTap == null) {
      return Material(color: background, borderRadius: radius, child: child);
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kMinInteractiveDimension,
            minHeight: kMinInteractiveDimension,
          ),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            widthFactor: 1,
            heightFactor: 1,
            child: Ink(
              decoration:
                  BoxDecoration(color: background, borderRadius: radius),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class DetailsNotes extends StatelessWidget {
  const DetailsNotes({super.key, required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return DetailsSection(
      title: AppLocalizations.of(context).translate('notes'),
      icon: Icons.description_outlined,
      child: Text(notes,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
    );
  }
}

class DetailsMap extends StatelessWidget {
  const DetailsMap({
    super.key,
    required this.title,
    this.address,
    this.onOpen,
    this.preview,
  });

  final String title;
  final String? address;
  final VoidCallback? onOpen;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    return DetailsSection(
      title: title,
      icon: Icons.location_on_outlined,
      action: onOpen == null
          ? null
          // Not Flexible: the title's Expanded is the row's only flex
          // child, so it absorbs exactly the space up to this button,
          // leaving no leftover slack trailing after it.
          : TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new, size: 13),
              label: Text(loc.translate('maps')),
              style: TextButton.styleFrom(
                textStyle: theme.textTheme.labelSmall,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size.square(kMinInteractiveDimension),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: OfferDetailsStyle.accentText(theme.colorScheme,
                    theme.colorScheme.surfaceContainerLowest),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (address != null) ...[
            Text(address!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
          ],
          if (preview != null)
            preview!
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(Icons.location_off_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(loc.translate('mapLocationNotAvailable'),
                      style: theme.textTheme.bodyMedium),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
