import 'package:broker_wallet/src/data/models/uae_links_model.dart';

/// The entries shown under one heading.
class UaeLinkGroup {
  const UaeLinkGroup(this.emirate, this.entries);

  final UaeLinkEmirate emirate;
  final List<UaeLinkEntry> entries;
}

/// Searching and filtering of the directory. Pure, so it runs without a phone.
abstract final class UaeLinksSearch {
  static final RegExp _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static const Map<UaeLinkEmirate, List<String>> _emirateNames = {
    UaeLinkEmirate.uae: ['uae', 'united arab emirates', 'federal', 'الامارات'],
    UaeLinkEmirate.dubai: ['dubai', 'دبي'],
    UaeLinkEmirate.abuDhabi: ['abu dhabi', 'abudhabi', 'ابوظبي', 'ابو ظبي'],
    UaeLinkEmirate.sharjah: ['sharjah', 'الشارقه'],
    UaeLinkEmirate.ajman: ['ajman', 'عجمان'],
    UaeLinkEmirate.rasAlKhaimah: [
      'ras al khaimah',
      'rak',
      'رأس الخيمه',
      'راس الخيمه'
    ],
    UaeLinkEmirate.ummAlQuwain: ['umm al quwain', 'uaq', 'ام القيوين'],
    UaeLinkEmirate.fujairah: ['fujairah', 'الفجيره'],
  };

  /// Lower-cases, folds the Arabic spellings people mix (hamza forms of alef,
  /// ya / alef maqsura, ta marbuta, diacritics, tatweel, Arabic-Indic digits)
  /// and turns every other symbol into a single space.
  static String normalize(String input) {
    final folded = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      // Arabic diacritics (0x064B-0x065F, 0x0670) and tatweel (0x0640).
      if ((rune >= 0x064B && rune <= 0x065F) ||
          rune == 0x0670 ||
          rune == 0x0640) {
        continue;
      }
      switch (rune) {
        case 0x0623: // hamza above alef
        case 0x0625: // hamza below alef
        case 0x0622: // alef with madda
        case 0x0671: // alef wasla
          folded.writeCharCode(0x0627); // plain alef
        case 0x0649: // alef maqsura
        case 0x0626: // ya with hamza
          folded.writeCharCode(0x064A); // ya
        case 0x0629: // ta marbuta
          folded.writeCharCode(0x0647); // ha
        case 0x0624: // waw with hamza
          folded.writeCharCode(0x0648); // waw
        default:
          if (rune >= 0x0660 && rune <= 0x0669) {
            folded.writeCharCode(0x30 + rune - 0x0660);
          } else if (rune >= 0x06F0 && rune <= 0x06F9) {
            folded.writeCharCode(0x30 + rune - 0x06F0);
          } else {
            folded.writeCharCode(rune);
          }
      }
    }
    return folded.toString().replaceAll(_separators, ' ').trim();
  }

  /// Everything a search may match, in both languages.
  static String haystack(UaeLinkEntry entry) {
    final parts = <String>[
      entry.titleEn,
      entry.titleAr,
      entry.descriptionEn,
      entry.descriptionAr,
      entry.authorityEn,
      entry.authorityAr,
      ...entry.keywords,
      for (final emirate in entry.emirates) ...?_emirateNames[emirate],
    ];
    return normalize(parts.join(' '));
  }

  static final Expando<String> _haystacks = Expando<String>('uaeLinkHaystack');

  static String _cachedHaystack(UaeLinkEntry entry) =>
      _haystacks[entry] ??= haystack(entry);

  /// Whether [entry] matches every word of [query] (an empty query matches).
  static bool matchesQuery(UaeLinkEntry entry, String query) {
    final words = normalize(query).split(' ').where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final text = _cachedHaystack(entry);
    return words.every(text.contains);
  }

  /// [entries] narrowed by the search words, the emirate and the task, in the
  /// catalogue's order. A null emirate or task means "all".
  static List<UaeLinkEntry> filter(
    Iterable<UaeLinkEntry> entries, {
    String query = '',
    UaeLinkEmirate? emirate,
    UaeLinkTask? task,
  }) {
    return [
      for (final entry in entries)
        if ((emirate == null || entry.emirates.contains(emirate)) &&
            (task == null || entry.tasks.contains(task)) &&
            matchesQuery(entry, query))
          entry,
    ];
  }

  /// [entries] as the screen shows them: the search words and the task narrow
  /// the list, the emirate picks the headings.
  ///
  ///  * no emirate: one heading per emirate, UAE-wide first, each service once
  ///    under the first emirate it applies to;
  ///  * an emirate: that emirate's services, then the UAE-wide ones, so a
  ///    federal service is never hidden by an emirate choice;
  ///  * UAE-wide: only the federal services.
  static List<UaeLinkGroup> group(
    Iterable<UaeLinkEntry> entries, {
    String query = '',
    UaeLinkEmirate? emirate,
    UaeLinkTask? task,
  }) {
    final matches = filter(entries, query: query, task: task);
    final groups = <UaeLinkGroup>[];
    void add(UaeLinkEmirate heading, Iterable<UaeLinkEntry> list) {
      final items = list.toList();
      if (items.isNotEmpty) groups.add(UaeLinkGroup(heading, items));
    }

    if (emirate == null) {
      for (final heading in UaeLinkEmirate.values) {
        add(
          heading,
          matches.where((e) => _primaryEmirate(e) == heading),
        );
      }
    } else if (emirate == UaeLinkEmirate.uae) {
      add(emirate, matches.where((e) => e.isFederal));
    } else {
      add(emirate, matches.where((e) => e.emirates.contains(emirate)));
      add(UaeLinkEmirate.uae, matches.where((e) => e.isFederal));
    }
    return groups;
  }

  static UaeLinkEmirate _primaryEmirate(UaeLinkEntry entry) =>
      UaeLinkEmirate.values.firstWhere(entry.emirates.contains);
}
