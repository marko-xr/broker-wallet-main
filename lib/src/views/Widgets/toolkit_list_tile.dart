// lib/src/widgets/toolkit_list_tile.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/data/models/toolkit_item_model.dart';

class ToolkitListTile extends StatelessWidget {
  final ToolkitItemModel item;

  const ToolkitListTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar (SVG)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromARGB((0.1 * 255).round(), colors.primary.red,
                      colors.primary.green, colors.primary.blue),
                ),
                child: ClipOval(
                  child: SvgPicture.asset(
                    item.avatarAsset,
                    fit: BoxFit.cover,
                    width: 48,
                    height: 48,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // File name and file type
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fileName,
                      style: texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.fileType,
                      style: texts.bodyMedium?.copyWith(
                        color: Color.fromARGB(
                            (0.7 * 255).round(),
                            colors.onSurface.red,
                            colors.onSurface.green,
                            colors.onSurface.blue),
                      ),
                    ),
                  ],
                ),
              ),

              // Date
              Text(
                item.date,
                style: texts.bodySmall?.copyWith(
                  color: Color.fromARGB(
                      (0.6 * 255).round(),
                      colors.onSurface.red,
                      colors.onSurface.green,
                      colors.onSurface.blue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
