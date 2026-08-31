import 'package:flutter/material.dart';

class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int maxLines;
  final TextOverflow overflow;

  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.highlightStyle,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Default highlight style if none provided
    final defaultHighlightStyle = highlightStyle ??
        (style ?? const TextStyle()).copyWith(
          backgroundColor: colors.primary.withValues(alpha: 0.2),
          fontWeight: FontWeight.w700,
          color: colors.primary,
        );

    if (query.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final spans =
        _buildHighlightedSpans(text, query, style, defaultHighlightStyle);

    return RichText(
      maxLines: maxLines,
      overflow: overflow,
      text: TextSpan(children: spans),
    );
  }

  List<TextSpan> _buildHighlightedSpans(
    String text,
    String query,
    TextStyle? normalStyle,
    TextStyle highlightStyle,
  ) {
    if (query.isEmpty) {
      return [TextSpan(text: text, style: normalStyle)];
    }

    final List<TextSpan> spans = [];
    final String lowerText = text.toLowerCase();
    final String lowerQuery = query.toLowerCase();

    // Handle phone number highlighting differently
    if (_isNumericQuery(query)) {
      return _buildPhoneNumberHighlightedSpans(
          text, query, normalStyle, highlightStyle);
    }

    int start = 0;
    int index = lowerText.indexOf(lowerQuery);

    while (index != -1) {
      // Add text before the match
      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: normalStyle,
        ));
      }

      // Add the highlighted match
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: highlightStyle,
      ));

      start = index + query.length;
      index = lowerText.indexOf(lowerQuery, start);
    }

    // Add remaining text
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: normalStyle,
      ));
    }

    return spans.isEmpty ? [TextSpan(text: text, style: normalStyle)] : spans;
  }

  List<TextSpan> _buildPhoneNumberHighlightedSpans(
    String text,
    String query,
    TextStyle? normalStyle,
    TextStyle highlightStyle,
  ) {
    final List<TextSpan> spans = [];
    final cleanQuery = query.replaceAll(RegExp(r'[^\d]'), '');

    if (cleanQuery.isEmpty) {
      return [TextSpan(text: text, style: normalStyle)];
    }

    // Remove formatting from phone number for matching
    final cleanText = text.replaceAll(RegExp(r'[^\d]'), '');
    final matchIndex = cleanText.indexOf(cleanQuery);

    if (matchIndex == -1) {
      return [TextSpan(text: text, style: normalStyle)];
    }

    // Find the position in the original formatted text
    int charCount = 0;
    int startIndex = -1;
    int endIndex = -1;

    for (int i = 0; i < text.length; i++) {
      if (RegExp(r'\d').hasMatch(text[i])) {
        if (charCount == matchIndex && startIndex == -1) {
          startIndex = i;
        }
        if (charCount == matchIndex + cleanQuery.length - 1) {
          endIndex = i + 1;
          break;
        }
        charCount++;
      }
    }

    if (startIndex != -1 && endIndex != -1) {
      // Add text before match
      if (startIndex > 0) {
        spans.add(TextSpan(
          text: text.substring(0, startIndex),
          style: normalStyle,
        ));
      }

      // Add highlighted match
      spans.add(TextSpan(
        text: text.substring(startIndex, endIndex),
        style: highlightStyle,
      ));

      // Add text after match
      if (endIndex < text.length) {
        spans.add(TextSpan(
          text: text.substring(endIndex),
          style: normalStyle,
        ));
      }
    } else {
      // Fallback to normal text if highlighting fails
      spans.add(TextSpan(text: text, style: normalStyle));
    }

    return spans;
  }

  bool _isNumericQuery(String query) {
    return query.length >= 1 && RegExp(r'^[0-9]+$').hasMatch(query);
  }
}
