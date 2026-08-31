import 'package:cloud_firestore/cloud_firestore.dart';

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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'mediaType': mediaType.name,
      'format': format,
      'contentType': contentType,
      'downloadUrl': downloadUrl,
      'thumbnailUrl': thumbnailUrl,
      'storagePath': storagePath,
      'width': width,
      'height': height,
      'durationMs': durationMs,
      'sizeBytes': sizeBytes,
      'ownerUid': ownerUid,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory MediaFileModel.fromMap(Map<String, dynamic> map) {
    return MediaFileModel(
      id: map['id'] ?? '',
      mediaType: MediaFileType.values.firstWhere(
        (e) => e.name == map['mediaType'],
        orElse: () => MediaFileType.unknown,
      ),
      format: map['format'] ?? '',
      contentType: map['contentType'] ?? '',
      downloadUrl: map['downloadUrl'] ?? '',
      thumbnailUrl: map['thumbnailUrl'],
      storagePath: map['storagePath'] ?? '',
      width: map['width'],
      height: map['height'],
      durationMs: map['durationMs'],
      sizeBytes: map['sizeBytes'] ?? 0,
      ownerUid: map['ownerUid'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory MediaFileModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MediaFileModel.fromMap({...data, 'id': doc.id});
  }
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
