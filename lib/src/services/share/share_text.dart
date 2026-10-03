import 'package:broker_wallet/src/services/share/share_format.dart';
import 'package:broker_wallet/src/services/share/share_labels.dart';

/// Assembles the message of a share from labelled lines.
///
/// The layout is the one the app's share text has always had — a title, a rule,
/// emoji-headed sections of bulleted lines, a rule, the app's signature — with
/// the rough edges removed: a line with no value is left out (never `Phone:`
/// with nothing after it), a section with no lines is left out, and sections are
/// separated by exactly one blank line however many were skipped.
class ShareTextBuilder {
  ShareTextBuilder(this.labels);

  final ShareLabels labels;

  final List<String> _sections = <String>[];

  /// The rule above and below the body.
  static const String rule = '========================';

  /// `• Label: value`, or null when the label or the value is missing.
  String? line(String labelKey, String? value) {
    final text = ShareFormat.clean(value);
    final label = labels.maybe(labelKey);
    if (text == null || label == null) return null;
    return '• $label: $text';
  }

  /// A section: `🏡 Heading:` and its lines. Skipped when it has no lines.
  void section(String emoji, String headingKey, Iterable<String?> lines) {
    final body = <String>[
      for (final line in lines)
        if (line != null) line,
    ];
    if (body.isEmpty) return;
    final heading = labels.maybe(headingKey);
    _sections.add([
      if (heading != null) '$emoji $heading:',
      ...body,
    ].join('\n'));
  }

  /// A single line without bullet: `💰 Price: AED 2,500,000`.
  void single(String emoji, String labelKey, String? value) {
    final text = ShareFormat.clean(value);
    final label = labels.maybe(labelKey);
    if (text == null || label == null) return;
    _sections.add('$emoji $label: $text');
  }

  /// A section whose body is the person's own text, kept as they wrote it.
  void paragraph(String emoji, String headingKey, String? value) {
    final text = ShareFormat.clean(value)?.replaceAll('\r\n', '\n');
    if (text == null) return;
    final heading = labels.maybe(headingKey);
    _sections.add([
      if (heading != null) '$emoji $heading:',
      text,
    ].join('\n'));
  }

  bool get isEmpty => _sections.isEmpty;

  /// The finished message under [titleKey], or null when no section was written
  /// (a share of files only carries no message).
  String? build(String titleKey, {String footerKey = 'sharedByBrokerWallet'}) {
    if (_sections.isEmpty) return null;
    final title = labels.maybe(titleKey);
    final signature = labels.maybe(footerKey);
    return [
      if (title != null) title,
      rule,
      '',
      _sections.join('\n\n'),
      '',
      rule,
      if (signature != null) '\u{1F4F1} $signature',
    ].join('\n');
  }
}
