import 'package:broker_wallet/src/services/share/share_format.dart';
import 'package:broker_wallet/src/services/share/share_labels.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_text.dart';

/// The emoji that head a shared message's sections.
abstract final class ShareEmoji {
  static const String property = '\u{1F3E1}';
  static const String price = '\u{1F4B0}';
  static const String location = '\u{1F4CD}';
  static const String contact = '\u{1F4DE}';
  static const String notes = '\u{1F4DD}';
  static const String person = '\u{1F464}';
  static const String document = '\u{1F4C4}';
}

/// What one record offers for sharing: which parts exist, which are chosen at
/// first, how each is written and which files can be attached.
///
/// A source is built from the record as the screen already holds it, so sharing
/// works without a network and never asks the backend for anything a screen had
/// not already been allowed to read. Only attached media is fetched, and only
/// through the record's own authorized path.
///
/// An option exists only when there is something behind it: a part the record
/// has no data for is not offered, and neither is media a record has none of.
abstract class ShareSource {
  const ShareSource({
    this.media = const <ShareMediaItem>[],
    this.document,
  });

  /// The record's photos and videos that can be attached, in gallery order.
  final List<ShareMediaItem> media;

  /// The record's document, when it has one.
  final ShareDocument? document;

  /// The ARB key of the dialog's title (`shareOffer`).
  String get titleKey;

  /// The ARB key of the message's heading and the e-mail subject
  /// (`offerDetails`).
  String get subjectKey;

  /// Message-only labels; the default also serves as the e-mail subject.
  String messageTitleKey(ShareLabels labels) => subjectKey;

  String messageFooterKey(ShareLabels labels) => 'sharedByBrokerWallet';

  /// The text parts this record has data for.
  Set<ShareSection> get textAvailable;

  /// The text parts chosen when the dialog opens.
  Set<ShareSection> get textDefaults;

  /// Writes the sections of [selected] (text parts only) into [builder].
  void writeSections(
    ShareTextBuilder builder,
    ShareLabels labels,
    Set<ShareSection> selected,
  );

  /// Every part that can be shared, in the order the dialog lists them.
  List<ShareSection> get available => <ShareSection>[
        for (final section in ShareSection.values)
          if (_isAvailable(section)) section,
      ];

  bool _isAvailable(ShareSection section) => switch (section) {
        ShareSection.media => media.isNotEmpty,
        ShareSection.document => document != null,
        _ => textAvailable.contains(section),
      };

  /// The parts chosen when the dialog opens. Large things start unchosen: a
  /// record's photos are chosen at first, its videos are not, and a record with
  /// only videos starts with none, so nothing heavy is fetched unless asked for.
  Set<ShareSection> get defaultSelection => <ShareSection>{
        ...textDefaults.where(textAvailable.contains),
        if (defaultMediaKeys.isNotEmpty) ShareSection.media,
        if (document != null) ShareSection.document,
      };

  /// The photos chosen when the dialog opens.
  Set<String> get defaultMediaKeys => <String>{
        for (final item in media)
          if (!item.isVideo) item.key,
      };

  /// The ARB key of [section]'s row title.
  String sectionTitleKey(ShareSection section) => section.labelKey;

  /// A short line under [section]'s title saying what it contains, or null.
  String? sectionDetail(ShareSection section, ShareLabels labels) => null;

  /// The message for the chosen parts, or null when no text part is chosen.
  String? composeText(Set<ShareSection> selected, ShareLabels labels) {
    final chosen = selected.where((s) => s.isText && textAvailable.contains(s));
    if (chosen.isEmpty) return null;
    final builder = ShareTextBuilder(labels);
    writeSections(builder, labels, chosen.toSet());
    return builder.build(
      messageTitleKey(labels),
      footerKey: messageFooterKey(labels),
    );
  }

  /// The name, without extension, of the [position]th shared media file.
  ///
  /// A file's name never says more than the person chose to share: a place name
  /// is added only when the location is among the chosen parts.
  String mediaBaseName(
    ShareMediaItem item,
    int position,
    Set<ShareSection> selected,
    ShareLabels labels,
  );

  /// `01`, `02`, … for a file's place among the shared ones.
  static String ordinal(int position) => position.toString().padLeft(2, '0');

  // ---------- Pieces shared by several record types ----------

  /// The contact section: the record's phone number.
  static void writeContact(
    ShareTextBuilder builder,
    ShareLabels labels,
    String? phone,
  ) {
    builder.section(ShareEmoji.contact, 'contactInfo', [
      builder.line('phone', ShareFormat.phone(phone, labels)),
    ]);
  }

  static void writeNotes(ShareTextBuilder builder, String? notes) {
    builder.paragraph(ShareEmoji.notes, 'notes', notes);
  }

  /// The location section: the lines of the chosen location text and, when the
  /// map is chosen too, the address and the map link — one section, headed
  /// `Location Details` or, with only the map chosen, `Map Location`.
  static void writeLocation(
    ShareTextBuilder builder,
    ShareLabels labels, {
    required bool includeLocation,
    required bool includeMap,
    required List<String?> locationLines,
    String? address,
    double? latitude,
    double? longitude,
  }) {
    final lines = <String?>[
      if (includeLocation) ...locationLines,
    ];
    final hasMap = includeMap && ShareFormat.validLatLng(latitude, longitude);
    if (hasMap) {
      lines
        ..add(builder.line('address', address))
        ..add(builder.line(
          'mapLink',
          ShareFormat.ltr(ShareFormat.mapLink(latitude!, longitude!), labels),
        ));
    }
    builder.section(
      ShareEmoji.location,
      includeLocation ? 'locationDetails' : 'mapLocation',
      lines,
    );
  }
}
