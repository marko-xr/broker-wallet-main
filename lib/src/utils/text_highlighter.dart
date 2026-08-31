import 'package:flutter/material.dart';

class TextHighlighter {
  /// Highlights matching text in a string with the specified color
  static Widget highlight(
    String text,
    String query, {
    TextStyle? style,
    Color? highlightColor,
    int? maxLines,
    TextOverflow? overflow,
    TextAlign? textAlign,
  }) {
    if (query.isEmpty || text.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }

    final normalizedText = text.toLowerCase();
    final normalizedQuery = query.toLowerCase().trim();

    // For phone numbers, try intelligent digit-based matching FIRST
    if (_isPhoneNumberQuery(normalizedQuery)) {
      final phoneHighlight = _highlightPhoneNumber(text, normalizedQuery, style,
          highlightColor, maxLines, overflow, textAlign);
      if (phoneHighlight != null) {
        return phoneHighlight;
      }
    }

    // Try direct text matching for non-phone or failed phone queries
    if (normalizedText.contains(normalizedQuery)) {
      return _buildHighlightedText(text, normalizedText, normalizedQuery, style,
          highlightColor, maxLines, overflow, textAlign);
    }

    // No matches found, return plain text
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }

  /// Check if the query looks like a phone number (contains mostly digits)
  static bool _isPhoneNumberQuery(String query) {
    final digitsOnly = query.replaceAll(RegExp(r'[^\d]'), '');
    return digitsOnly.length >= 3; // Consider it a phone number if 3+ digits
  }

  /// Smart phone number highlighting that matches digits across formatting
  static Widget? _highlightPhoneNumber(
      String text,
      String query,
      TextStyle? style,
      Color? highlightColor,
      int? maxLines,
      TextOverflow? overflow,
      TextAlign? textAlign) {
    final queryDigits = query.replaceAll(RegExp(r'[^\d]'), '');
    if (queryDigits.isEmpty) return null;

    // Find all digit positions in the text
    final List<int> digitPositions = [];
    final List<String> digits = [];

    for (int i = 0; i < text.length; i++) {
      if (text[i].contains(RegExp(r'\d'))) {
        digitPositions.add(i);
        digits.add(text[i]);
      }
    }

    final textDigitsString = digits.join('');
    final matchIndex = textDigitsString.indexOf(queryDigits);

    if (matchIndex == -1) {
      return null;
    }

    // Find the start and end positions in the original text
    final startDigitIndex = matchIndex;
    final endDigitIndex = matchIndex + queryDigits.length - 1;

    if (startDigitIndex >= digitPositions.length ||
        endDigitIndex >= digitPositions.length) {
      return null;
    }

    final startPos = digitPositions[startDigitIndex];
    final endPos = digitPositions[endDigitIndex] + 1;

    final List<TextSpan> spans = [];

    // Text before match
    if (startPos > 0) {
      spans.add(TextSpan(
        text: text.substring(0, startPos),
        style: style,
      ));
    }

    // Highlighted match
    spans.add(TextSpan(
      text: text.substring(startPos, endPos),
      style: style?.copyWith(
            backgroundColor:
                highlightColor ?? Colors.red.withValues(alpha: 0.3),
            fontWeight: FontWeight.bold,
          ) ??
          TextStyle(
            backgroundColor:
                highlightColor ?? Colors.red.withValues(alpha: 0.3),
            fontWeight: FontWeight.bold,
          ),
    ));

    // Text after match
    if (endPos < text.length) {
      spans.add(TextSpan(
        text: text.substring(endPos),
        style: style,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.ellipsis,
      textAlign: textAlign ?? TextAlign.start,
    );
  }

  /// Build highlighted text for regular string matches
  static Widget _buildHighlightedText(
    String text,
    String normalizedText,
    String normalizedQuery,
    TextStyle? style,
    Color? highlightColor,
    int? maxLines,
    TextOverflow? overflow,
    TextAlign? textAlign,
  ) {
    final List<TextSpan> spans = [];
    int currentIndex = 0;

    while (currentIndex < text.length) {
      final matchIndex = normalizedText.indexOf(normalizedQuery, currentIndex);

      if (matchIndex == -1) {
        // No more matches, add the rest of the text
        spans.add(TextSpan(
          text: text.substring(currentIndex),
          style: style,
        ));
        break;
      }

      // Add text before the match
      if (matchIndex > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, matchIndex),
          style: style,
        ));
      }

      // Add the highlighted match
      spans.add(TextSpan(
        text: text.substring(matchIndex, matchIndex + normalizedQuery.length),
        style: style?.copyWith(
              backgroundColor:
                  highlightColor ?? Colors.red.withValues(alpha: 0.3),
              fontWeight: FontWeight.bold,
            ) ??
            TextStyle(
              backgroundColor:
                  highlightColor ?? Colors.red.withValues(alpha: 0.3),
              fontWeight: FontWeight.bold,
            ),
      ));

      currentIndex = matchIndex + normalizedQuery.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.ellipsis,
      textAlign: textAlign ?? TextAlign.start,
    );
  }

  /// Creates a highlighted text widget for search results
  static Widget searchHighlight(
    String text,
    String query, {
    TextStyle? style,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    return highlight(
      text,
      query,
      style: style,
      highlightColor: Colors.red.withValues(alpha: 0.3),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
