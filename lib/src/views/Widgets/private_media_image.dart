import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:broker_wallet/src/services/private_media_images.dart';

/// An Offer or Owner detail image addressed by its account-scoped key
/// (tracker §7AZ, M1c), drawn from [PrivateMediaImages].
///
/// A file already mapped is drawn on the first frame. Otherwise [placeholder]
/// shows while the copy is looked up or fetched; [errorWidget] shows when a
/// link was in hand and the image still could not be had, or its bytes do
/// not decode. With no link and no copy it keeps [placeholder]: the screen's
/// media resolution supplies the link, and a new [signedUrl] retries.
class PrivateMediaImage extends StatefulWidget {
  const PrivateMediaImage({
    super.key,
    required this.cacheKey,
    this.signedUrl,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.placeholder,
    this.errorWidget,
  });

  final String cacheKey;
  final String? signedUrl;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  State<PrivateMediaImage> createState() => _PrivateMediaImageState();
}

class _PrivateMediaImageState extends State<PrivateMediaImage> {
  File? _file;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant PrivateMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _file = null;
      _start();
    } else if (_file == null && oldWidget.signedUrl != widget.signedUrl) {
      _start();
    }
  }

  @override
  void dispose() {
    _request++; // a late answer is ignored; the fetch itself still completes
    super.dispose();
  }

  void _start() {
    _failed = false;
    _file = PrivateMediaImages.heldNow(widget.cacheKey);
    if (_file != null) return;
    final request = ++_request;
    final link = widget.signedUrl?.trim();
    unawaited(
        PrivateMediaImages.load(widget.cacheKey, signedUrl: link).then((file) {
      if (!mounted || request != _request) return;
      setState(() {
        _file = file;
        _failed = file == null && link != null && link.isNotEmpty;
      });
    }));
  }

  Widget get _placeholder => widget.placeholder ?? const SizedBox.expand();

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file != null) {
      return Image.file(
        file,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _placeholder;
        },
        errorBuilder: (context, error, stackTrace) =>
            widget.errorWidget ?? _placeholder,
      );
    }
    if (_failed) return widget.errorWidget ?? _placeholder;
    return _placeholder;
  }
}
