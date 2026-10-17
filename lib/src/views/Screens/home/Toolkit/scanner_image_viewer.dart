import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// Shows one scanned page from a local file, zoomable. Used for the Scanner's
/// image documents and the pages under review; nothing is sent anywhere.
class ScannerImageViewer extends StatelessWidget {
  const ScannerImageViewer({
    super.key,
    required this.file,
    required this.title,
  });

  final File file;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
        ),
        centerTitle: true,
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.onSurface),
      ),
      body: PhotoView(
        imageProvider: FileImage(file),
        backgroundDecoration: BoxDecoration(color: colors.surface),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Icon(Icons.broken_image_outlined,
              size: 56, color: colors.onSurface.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}
