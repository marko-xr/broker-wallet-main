import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'dart:io';

enum MediaPickerType { image, video, pdf, any }

class MediaPickerDialog {
  static Future<File?> show({
    required BuildContext context,
    required MediaPickerType type,
  }) async {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return showModalBottomSheet<File>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _getTitle(type, loc),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),

            // Options
            ..._buildOptions(context, type, loc),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  static String _getTitle(MediaPickerType type, AppLocalizations loc) {
    switch (type) {
      case MediaPickerType.image:
        return loc.translate('selectImage');
      case MediaPickerType.video:
        return loc.translate('selectVideo');
      case MediaPickerType.pdf:
        return loc.translate('selectPdf');
      case MediaPickerType.any:
        return loc.translate('selectMedia');
    }
  }

  static List<Widget> _buildOptions(
    BuildContext context,
    MediaPickerType type,
    AppLocalizations loc,
  ) {
    final options = <Widget>[];

    if (type == MediaPickerType.image || type == MediaPickerType.any) {
      options.addAll([
        _buildOption(
          context: context,
          icon: Icons.camera_alt,
          title: loc.translate('takePhoto'),
          subtitle: loc.translate('imageSizeLimit'),
          onTap: () async {
            final file = await _pickFromCamera(ImageSource.camera);
            if (context.mounted) Navigator.pop(context, file);
          },
        ),
        _buildOption(
          context: context,
          icon: Icons.photo_library,
          title: loc.translate('chooseFromGallery'),
          subtitle: loc.translate('imageSizeLimit'),
          onTap: () async {
            final file = await _pickFromGallery();
            if (context.mounted) Navigator.pop(context, file);
          },
        ),
      ]);
    }

    if (type == MediaPickerType.video || type == MediaPickerType.any) {
      options.add(
        _buildOption(
          context: context,
          icon: Icons.videocam,
          title: loc.translate('selectVideo'),
          subtitle: loc.translate('videoSizeLimit'),
          onTap: () async {
            final file = await _pickVideo();
            if (context.mounted) Navigator.pop(context, file);
          },
        ),
      );
    }

    if (type == MediaPickerType.pdf || type == MediaPickerType.any) {
      options.add(
        _buildOption(
          context: context,
          icon: Icons.picture_as_pdf,
          title: loc.translate('selectPdf'),
          subtitle: loc.translate('pdfSizeLimit'),
          onTap: () async {
            final file = await _pickPdf();
            if (context.mounted) Navigator.pop(context, file);
          },
        ),
      );
    }

    return options;
  }

  static Widget _buildOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: colors.primary),
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: colors.onSurface.withValues(alpha: 0.6),
        ),
      ),
      onTap: onTap,
    );
  }

  static Future<File?> _pickFromCamera(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      return image != null ? File(image.path) : null;
    } catch (e) {
      return null;
    }
  }

  static Future<File?> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      return image != null ? File(image.path) : null;
    } catch (e) {
      return null;
    }
  }

  static Future<File?> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final XFile? video = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      return video != null ? File(video.path) : null;
    } catch (e) {
      return null;
    }
  }

  static Future<File?> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        return File(result.files.single.path!);
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
