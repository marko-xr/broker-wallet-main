// The header of Home, Search and Favorites is one widget, so the three cannot
// drift apart again: same avatar, same name style, same gap, same subtitle size
// and colour. Each screen contributes only its own subtitle, and that subtitle
// says what the screen is: Home welcomes, Search says what it searches,
// Favorites names the favorites. Source and string checks; no engine needed.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

Map<String, dynamic> _arb(String code) => json.decode(
      File('lib/src/common/localization/app_$code.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  const header = 'lib/src/views/Widgets/user_screen_header.dart';
  final screens = {
    'Home': 'lib/src/views/Screens/home_view.dart',
    'Search': 'lib/src/views/Screens/home/search/search_view.dart',
    'Favorites': 'lib/src/views/Screens/home/favorites/favorites_view.dart',
  };
  final subtitleKeys = {
    'Home': 'welcomeMessage',
    'Search': 'searchHeaderSubtitle',
    'Favorites': 'favoritesOverviewTitle',
  };

  group('one header for the three tabs', () {
    for (final entry in screens.entries) {
      test('${entry.key} draws the shared header and none of its own', () {
        final source = _source(entry.value);
        expect(RegExp(r'UserScreenHeader\(').allMatches(source).length, 1);
        expect(source.contains('user_screen_header.dart'), isTrue);
        for (final own in [
          'class _Header',
          '_buildHeader',
          'CurrentUserAvatar(',
          'NotificationIcon(',
          'hiGreeting',
          'headlineSmall',
          "'/edit-profile'",
        ]) {
          expect(source.contains(own), isFalse,
              reason: '${entry.key} must not carry its own `$own`');
        }
      });

      test('${entry.key} passes only its own subtitle', () {
        final squashed = _squash(_source(entry.value));
        final key = subtitleKeys[entry.key]!;
        expect(
          RegExp("UserScreenHeader\\( subtitle: \\w+\\.translate\\('$key'\\), \\)")
              .hasMatch(squashed),
          isTrue,
          reason: '${entry.key} -> $key',
        );
      });
    }

    test('the sizes, gap, colour and overflow are set once, in the widget', () {
      final source = _source(header);
      final squashed = _squash(source);
      expect(source.contains('static const double avatarSize = 48;'), isTrue);
      expect(source.contains('static const double avatarGap = 12;'), isTrue);
      expect(source.contains('static const double lineGap = 2;'), isTrue);
      expect(source.contains('static const double subtitleOpacity = 0.6;'),
          isTrue);
      // The name is the theme's headline, the subtitle its body text in the
      // theme's own colour: nothing hard-coded.
      expect(squashed.contains('style: textTheme.headlineSmall'), isTrue);
      expect(squashed.contains('textTheme.bodyMedium?.copyWith('), isTrue);
      expect(
          squashed
              .contains('colors.onSurface.withValues(alpha: subtitleOpacity)'),
          isTrue);
      expect(source.contains('Colors.'), isFalse,
          reason: 'no colour of its own');
      expect(source.contains('fontSize'), isFalse,
          reason: 'no font size of its own');
      // Both lines stay on one line however long the name or the translation.
      expect(RegExp(r'maxLines: 1,').allMatches(source).length, 2);
      expect(
          RegExp(r'overflow: TextOverflow\.ellipsis,')
              .allMatches(source)
              .length,
          2);
    });

    test('it listens to the profile, so a new name shows on every tab', () {
      final source = _source(header);
      expect(source.contains('Provider.of<AuthViewModel>(context)'), isTrue);
      expect(source.contains('listen: false'), isFalse);
    });
  });

  group('each screen says what it is', () {
    for (final code in ['en', 'ar']) {
      final table = _arb(code);

      test('$code: the three lines exist, and are three different lines', () {
        final lines = {
          for (final entry in subtitleKeys.entries)
            entry.key: (table[entry.value] as String?)?.trim(),
        };
        for (final entry in lines.entries) {
          expect(entry.value, isNotNull, reason: '$code ${entry.key}');
          expect(entry.value, isNotEmpty, reason: '$code ${entry.key}');
        }
        expect(lines.values.toSet(), hasLength(3),
            reason: '$code: no two screens share a subtitle');
      });
    }

    test('Favorites names the favorites, not "saved" items', () {
      expect(_arb('en')['favoritesOverviewTitle'], 'Your favorites');
      final arabic = _arb('ar')['favoritesOverviewTitle'] as String;
      expect(arabic.contains('المفضلة'), isTrue,
          reason: 'it says "the favorite(s)"');
      expect(arabic.contains('المحفوظة'), isFalse,
          reason: 'it no longer says "the saved"');
    });

    test('Search says what it searches, and does not welcome the user again',
        () {
      final english = _arb('en');
      expect(english['searchHeaderSubtitle'], 'Search all your items');
      expect(english['searchHeaderSubtitle'], isNot(english['welcomeMessage']));
      expect(
          (english['searchHeaderSubtitle'] as String)
              .toLowerCase()
              .contains('welcome'),
          isFalse);
      expect(_arb('ar')['searchHeaderSubtitle'],
          isNot(_arb('ar')['welcomeMessage']));
    });

    test('Home welcomes the user', () {
      expect(_arb('en')['welcomeMessage'], 'Welcome to Broker Wallet');
    });
  });
}
