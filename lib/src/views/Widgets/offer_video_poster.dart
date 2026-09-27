import 'dart:io';

import 'package:flutter/material.dart';

import 'package:broker_wallet/src/services/offer_video_poster_service.dart';

/// A private Offer video's still frame.
///
/// Draws, in order: the frame the caller already knows ([posterPath]), the
/// one this device keeps under the video's stable identity ([cacheKey]), or
/// — for a ready video with neither — [loading] while one is made from the
/// video through its signed link ([signedUrl]), then that frame. When no
/// frame exists or can be made, [placeholder]. Never keyed by the link.
class OfferVideoPoster extends StatefulWidget {
  const OfferVideoPoster({
    super.key,
    required this.cacheKey,
    required this.placeholder,
    this.signedUrl,
    this.posterPath,
    this.loading,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String? cacheKey;
  final String? signedUrl;
  final String? posterPath;
  final Widget placeholder;
  final Widget? loading;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  State<OfferVideoPoster> createState() => _OfferVideoPosterState();
}

class _OfferVideoPosterState extends State<OfferVideoPoster> {
  String? _path;
  bool _preparing = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant OfferVideoPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.posterPath != widget.posterPath ||
        (_path == null && oldWidget.signedUrl != widget.signedUrl)) {
      _resolve();
    }
  }

  void _resolve() {
    final request = ++_request;
    final given = widget.posterPath;
    if (given != null && given.isNotEmpty && File(given).existsSync()) {
      _path = given;
      _preparing = false;
      return;
    }
    final service = OfferVideoPosterService.instance;
    final kept = service.localPoster(widget.cacheKey);
    if (kept != null) {
      _path = kept;
      _preparing = false;
      return;
    }
    _path = null;
    final url = widget.signedUrl?.trim() ?? '';
    if (widget.cacheKey == null || url.isEmpty) {
      _preparing = false;
      return;
    }
    _preparing = true;
    service.ensure(cacheKey: widget.cacheKey, signedUrl: url).then((path) {
      if (!mounted || request != _request) return;
      setState(() {
        _path = path;
        _preparing = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path != null) {
      return Image.file(
        File(path),
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => widget.placeholder,
      );
    }
    return _preparing
        ? (widget.loading ?? widget.placeholder)
        : widget.placeholder;
  }
}
