import 'package:flutter/material.dart';
import '../../common/localization/localization_delegate.dart';
import '../../data/models/property_status.dart';

/// Widget for displaying property status with icon and color
class PropertyStatusIndicator extends StatelessWidget {
  final PropertyStatus status;
  final bool showText;
  final double iconSize;
  final TextStyle? textStyle;

  const PropertyStatusIndicator({
    super.key,
    required this.status,
    this.showText = true,
    this.iconSize = 16.0,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final icon = _getStatusIcon();

    if (!showText) {
      return Icon(
        icon,
        color: color,
        size: iconSize,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: color,
          size: iconSize,
        ),
        const SizedBox(width: 4),
        Text(
          _localizedStatus(context, status),
          style: (textStyle ?? Theme.of(context).textTheme.bodySmall)?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor() {
    return Color(
        int.parse(status.colorCode.substring(1), radix: 16) + 0xFF000000);
  }

  IconData _getStatusIcon() {
    switch (status) {
      case PropertyStatus.available:
        return Icons.check_circle;
      case PropertyStatus.active:
        return Icons.sync;
      case PropertyStatus.sold:
        return Icons.attach_money;
      case PropertyStatus.rented:
        return Icons.vpn_key;
      case PropertyStatus.canceled:
        return Icons.cancel;
      case PropertyStatus.notAvailable:
        return Icons.remove_circle;
      case PropertyStatus.fulfilled:
        return Icons.task_alt;
      case PropertyStatus.closed:
        return Icons.highlight_off;
      case PropertyStatus.expired:
        return Icons.hourglass_bottom;
    }
  }
}

/// Chip-style status indicator for more prominent display
class PropertyStatusChip extends StatelessWidget {
  final PropertyStatus status;
  final VoidCallback? onTap;
  final double? fontSize;

  const PropertyStatusChip({
    super.key,
    required this.status,
    this.onTap,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        Color(int.parse(status.colorCode.substring(1), radix: 16) + 0xFF000000);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getStatusIcon(),
              color: color,
              size: 14,
            ),
            const SizedBox(width: 2),
            Text(
              _localizedStatus(context, status),
              style: TextStyle(
                color: color,
                fontSize: fontSize ?? 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (status) {
      case PropertyStatus.available:
        return Icons.check_circle;
      case PropertyStatus.active:
        return Icons.sync;
      case PropertyStatus.sold:
        return Icons.attach_money;
      case PropertyStatus.rented:
        return Icons.vpn_key;
      case PropertyStatus.canceled:
        return Icons.cancel;
      case PropertyStatus.notAvailable:
        return Icons.remove_circle;
      case PropertyStatus.fulfilled:
        return Icons.task_alt;
      case PropertyStatus.closed:
        return Icons.highlight_off;
      case PropertyStatus.expired:
        return Icons.hourglass_bottom;
    }
  }
}

/// Bottom sheet for selecting property status
class PropertyStatusSelector extends StatelessWidget {
  final PropertyStatus currentStatus;
  final Function(PropertyStatus) onStatusSelected;
  final List<PropertyStatus>? allowedStatuses;

  const PropertyStatusSelector({
    super.key,
    required this.currentStatus,
    required this.onStatusSelected,
    this.allowedStatuses,
  });

  @override
  Widget build(BuildContext context) {
    final statuses = allowedStatuses ?? PropertyStatus.allStatuses;
    final loc = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _translateWithFallback(loc, 'updatePropertyStatus'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ...statuses.map((status) => _buildStatusOption(
                context,
                status,
                status == currentStatus,
              )),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_translateWithFallback(loc, 'cancel')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusOption(
      BuildContext context, PropertyStatus status, bool isSelected) {
    final color =
        Color(int.parse(status.colorCode.substring(1), radix: 16) + 0xFF000000);

    return ListTile(
      leading: Icon(
        _getStatusIcon(status),
        color: color,
      ),
      title: Text(_localizedStatus(context, status)),
      trailing: isSelected ? Icon(Icons.check, color: color) : null,
      onTap: () {
        onStatusSelected(status);
        Navigator.of(context).pop();
      },
    );
  }

  IconData _getStatusIcon(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.available:
        return Icons.check_circle;
      case PropertyStatus.active:
        return Icons.sync;
      case PropertyStatus.sold:
        return Icons.attach_money;
      case PropertyStatus.rented:
        return Icons.vpn_key;
      case PropertyStatus.canceled:
        return Icons.cancel;
      case PropertyStatus.notAvailable:
        return Icons.remove_circle;
      case PropertyStatus.fulfilled:
        return Icons.task_alt;
      case PropertyStatus.closed:
        return Icons.highlight_off;
      case PropertyStatus.expired:
        return Icons.hourglass_bottom;
    }
  }
}

String _localizedStatus(BuildContext context, PropertyStatus status) {
  final loc = AppLocalizations.of(context);
  final translated = loc.translate(status.name);

  if (translated.startsWith('** ')) {
    return status.displayName;
  }

  return translated;
}

String _translateWithFallback(AppLocalizations loc, String key) {
  final translated = loc.translate(key);
  if (translated.startsWith('** ')) {
    return key;
  }
  return translated;
}
