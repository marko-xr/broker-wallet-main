
enum MediaFileType { image, video, pdf, unknown }

class MediaFileModel {
  final String id;
  final MediaFileType mediaType;
  final String format; // jpeg, mp4, pdf
  final String contentType; // image/jpeg, video/mp4, application/pdf
  final String downloadUrl;
  final String? thumbnailUrl;
  final String storagePath;
  final int? width;
  final int? height;
  final int? durationMs;
  final int sizeBytes;
  final String ownerUid;
  final DateTime createdAt;

  MediaFileModel({
    required this.id,
    required this.mediaType,
    required this.format,
    required this.contentType,
    required this.downloadUrl,
    this.thumbnailUrl,
    required this.storagePath,
    this.width,
    this.height,
    this.durationMs,
    required this.sizeBytes,
    required this.ownerUid,
    required this.createdAt,
  });
}

class MediaUploadProgress {
  final String
      stage; // 'compressing', 'uploading', 'thumbnail', 'done', 'failed'
  final double progress; // 0.0 to 1.0
  final String? error;

  const MediaUploadProgress({
    required this.stage,
    required this.progress,
    this.error,
  });

  bool get isComplete => stage == 'done';
  bool get hasFailed => stage == 'failed';

  String getLocalizedMessage(Function(String) translate) {
    switch (stage) {
      case 'compressing':
        return translate('compressingMedia');
      case 'uploading':
        return '${translate('uploading')} ${(progress * 100).toInt()}%';
      case 'thumbnail':
        return translate('generatingThumbnail');
      case 'done':
        return translate('uploadComplete');
      case 'failed':
        return error ?? translate('uploadFailed');
      default:
        return translate('processing');
    }
  }
}
