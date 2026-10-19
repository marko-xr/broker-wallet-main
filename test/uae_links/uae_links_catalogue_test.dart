import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/data/models/uae_links_catalogue.dart';
import 'package:broker_wallet/src/data/models/uae_links_model.dart';
import 'package:broker_wallet/src/services/uae_links/uae_link_url_policy.dart';

final RegExp _arabic = RegExp('[؀-ۿ]');

void main() {
  final entries = UAELinksData.entries;

  group('identity', () {
    test('every service id is unique and kebab-case', () {
      final ids = entries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')), reason: id);
      }
    });

    test('no canonical URL is listed twice', () {
      final urls = <String, String>{};
      for (final e in entries) {
        final key = e.url.toLowerCase();
        expect(urls.containsKey(key), isFalse,
            reason: '${e.id} repeats the URL of ${urls[key]}');
        urls[key] = e.id;
      }
    });

    test('no service is listed twice under slightly different names', () {
      final titles = <String, String>{};
      for (final e in entries) {
        final key = e.titleEn.toLowerCase();
        expect(titles.containsKey(key), isFalse,
            reason: '${e.id} repeats the title of ${titles[key]}');
        titles[key] = e.id;
      }
    });
  });

  group('official URLs', () {
    test('every URL is safe, HTTPS and on its declared official domain', () {
      for (final e in entries) {
        final uri = UaeLinkUrlPolicy.parse(e.url);
        expect(uri, isNotNull, reason: '${e.id}: ${e.url}');
        expect(e.domain, uri!.host, reason: e.id);
        expect(UaeLinkUrlPolicy.isOfficialHost(e.domain), isTrue, reason: e.id);
        final alternative = e.alternativeUrl;
        if (alternative != null) {
          expect(UaeLinkUrlPolicy.isSafe(alternative), isTrue, reason: e.id);
        }
      }
    });

    test('no commercial, classified, shortener or referral destination', () {
      const banned = [
        'propertyfinder',
        'bayut',
        'dubizzle',
        'bit.ly',
        'tinyurl',
        't.co',
        'goo.gl',
        'ref=',
        'utm_',
        'affiliate',
      ];
      for (final e in entries) {
        final url = e.url.toLowerCase();
        for (final word in banned) {
          expect(url.contains(word), isFalse, reason: '${e.id} has $word');
        }
      }
    });

    test('no URL carries credentials, tokens or user identifiers', () {
      for (final e in entries) {
        final uri = Uri.parse(e.url);
        expect(uri.userInfo, isEmpty, reason: e.id);
        for (final name in uri.queryParameters.keys) {
          expect(
              name.toLowerCase(),
              isNot(
                  anyOf(contains('token'), contains('uid'), contains('user'))),
              reason: e.id);
        }
      }
    });
  });

  group('coverage', () {
    test('all seven emirates and the UAE-wide services are present', () {
      for (final emirate in UaeLinkEmirate.values) {
        expect(entries.where((e) => e.emirates.contains(emirate)), isNotEmpty,
            reason: emirate.name);
      }
    });

    test('every broker task has services', () {
      for (final task in UaeLinkTask.values) {
        expect(entries.where((e) => e.tasks.contains(task)), isNotEmpty,
            reason: task.name);
      }
    });

    test('federal services are federal only and local ones never are', () {
      for (final e in entries) {
        if (e.isFederal) {
          expect(e.emirates, {UaeLinkEmirate.uae}, reason: e.id);
        }
        expect(e.emirates, isNotEmpty, reason: e.id);
      }
    });

    test('each service id starts with the emirate it belongs to', () {
      const prefix = {
        UaeLinkEmirate.uae: ['uae-'],
        UaeLinkEmirate.dubai: ['dubai-'],
        UaeLinkEmirate.abuDhabi: ['abudhabi-'],
        UaeLinkEmirate.sharjah: ['sharjah-'],
        UaeLinkEmirate.ajman: ['ajman-'],
        UaeLinkEmirate.rasAlKhaimah: ['rak-'],
        UaeLinkEmirate.ummAlQuwain: ['uaq-'],
        UaeLinkEmirate.fujairah: ['fujairah-'],
      };
      for (final e in entries) {
        if (e.id.startsWith('northern-')) {
          expect(e.emirates.length, greaterThan(1), reason: e.id);
          expect(e.emirates, isNot(contains(UaeLinkEmirate.uae)));
          continue;
        }
        expect(e.emirates.length, 1, reason: e.id);
        final matches = prefix[e.emirates.single]!;
        expect(matches.any(e.id.startsWith), isTrue,
            reason: '${e.id} is filed under ${e.emirates.single.name}');
      }
    });

    test('each authority host belongs to the right emirate', () {
      // Hosts that identify one emirate's government.
      const hostEmirate = {
        'dubailand.gov.ae': UaeLinkEmirate.dubai,
        'dewa.gov.ae': UaeLinkEmirate.dubai,
        'rdc.gov.ae': UaeLinkEmirate.dubai,
        'adrec.gov.ae': UaeLinkEmirate.abuDhabi,
        'dari.ae': UaeLinkEmirate.abuDhabi,
        'tamm.abudhabi': UaeLinkEmirate.abuDhabi,
        'shjrerd.gov.ae': UaeLinkEmirate.sharjah,
        'shjmun.gov.ae': UaeLinkEmirate.sharjah,
        'sewa.gov.ae': UaeLinkEmirate.sharjah,
        'sharjah.ae': UaeLinkEmirate.sharjah,
        'ajmanre.gov.ae': UaeLinkEmirate.ajman,
        'am.gov.ae': UaeLinkEmirate.ajman,
        'ajman.ae': UaeLinkEmirate.ajman,
        'rak.ae': UaeLinkEmirate.rasAlKhaimah,
        'uaq.ae': UaeLinkEmirate.ummAlQuwain,
        'digitaluaq.ae': UaeLinkEmirate.ummAlQuwain,
        'fujmun.gov.ae': UaeLinkEmirate.fujairah,
        'fujairah.ae': UaeLinkEmirate.fujairah,
      };
      for (final e in entries) {
        for (final host in hostEmirate.keys) {
          if (e.domain == host || e.domain.endsWith('.$host')) {
            expect(e.emirates, {hostEmirate[host]}, reason: '${e.id} on $host');
          }
        }
      }
    });

    test('Tasdeeq is an Ajman service, never a Sharjah one', () {
      final tasdeeq = entries.where((e) =>
          e.domain == 'tasdeeq.am.gov.ae' ||
          e.keywords.any((k) => k.toLowerCase() == 'tasdeeq'));
      expect(tasdeeq, isNotEmpty);
      for (final e in tasdeeq) {
        expect(e.emirates, contains(UaeLinkEmirate.ajman), reason: e.id);
        expect(e.emirates, isNot(contains(UaeLinkEmirate.sharjah)),
            reason: e.id);
      }
      for (final e in entries.where((e) => e.id.startsWith('sharjah-'))) {
        expect(e.domain, isNot(contains('am.gov.ae')), reason: e.id);
      }
    });
  });

  group('Arabic and English content', () {
    test('every service has complete text in both languages', () {
      for (final e in entries) {
        for (final value in [
          e.titleEn,
          e.titleAr,
          e.descriptionEn,
          e.descriptionAr,
          e.authorityEn,
          e.authorityAr,
        ]) {
          expect(value.trim(), isNotEmpty, reason: e.id);
        }
        expect(_arabic.hasMatch(e.titleAr), isTrue, reason: '${e.id} title');
        expect(_arabic.hasMatch(e.descriptionAr), isTrue,
            reason: '${e.id} description');
        expect(_arabic.hasMatch(e.authorityAr), isTrue,
            reason: '${e.id} authority');
        expect(_arabic.hasMatch(e.titleEn), isFalse, reason: e.id);
        expect(_arabic.hasMatch(e.descriptionEn), isFalse, reason: e.id);
        expect(e.title('ar'), e.titleAr);
        expect(e.title('en'), e.titleEn);
      }
    });

    test('the UI strings exist in both ARB files', () {
      final en = jsonDecode(
              File('lib/src/common/localization/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
      final ar = jsonDecode(
              File('lib/src/common/localization/app_ar.arb').readAsStringSync())
          as Map<String, dynamic>;
      final keys = <String>{
        for (final e in UaeLinkEmirate.values) e.labelKey,
        for (final t in UaeLinkTask.values) t.labelKey,
        for (final t in UaeLinkType.values) t.labelKey,
        ...en.keys.where((k) => k.startsWith('ulx')),
      };
      for (final key in keys) {
        expect(en[key], isA<String>(), reason: 'en $key');
        expect(ar[key], isA<String>(), reason: 'ar $key');
        expect((ar[key] as String).trim(), isNotEmpty, reason: 'ar $key');
      }
      expect(
        en.keys.where((k) => k.startsWith('ulx')).toSet(),
        ar.keys.where((k) => k.startsWith('ulx')).toSet(),
      );
    });
  });

  group('verification metadata', () {
    test('only verified or manual-check entries are published', () {
      final published = UAELinksData.published;
      expect(published, isNotEmpty);
      for (final e in published) {
        expect(e.verification.isPublishable, isTrue, reason: e.id);
      }
      expect(UaeLinkVerification.unverified.isPublishable, isFalse);
      expect(UaeLinkVerification.retired.isPublishable, isFalse);
      expect(published.length,
          entries.where((e) => e.verification.isPublishable).length);
    });

    test('each entry records a real date and its evidence', () {
      final today = DateTime.now().add(const Duration(days: 1));
      for (final e in entries) {
        expect(e.lastVerified, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
            reason: e.id);
        final date = e.lastVerifiedDate;
        expect(date.isAfter(DateTime(2026, 10, 1)), isTrue, reason: e.id);
        expect(date.isBefore(today), isTrue, reason: e.id);
        expect(e.evidence.trim().length, greaterThan(20), reason: e.id);
      }
    });

    test('a manual-check entry says why the destination is not confirmed', () {
      final manual = entries.where((e) =>
          e.verification == UaeLinkVerification.officialManualCheckRequired);
      expect(manual, isNotEmpty);
      for (final e in manual) {
        final evidence = e.evidence.toLowerCase();
        expect(
          evidence.contains('not tested') ||
              evidence.contains('script-only') ||
              evidence.contains('not read') ||
              evidence.contains('not established') ||
              evidence.contains('no public') ||
              evidence.contains('not opened') ||
              evidence.contains('sign-in'),
          isTrue,
          reason: '${e.id} gives no limitation',
        );
      }
    });

    test('a login-wall page is never presented as a verified transaction', () {
      for (final e in entries.where((e) => e.requiresLogin)) {
        expect(
            e.type,
            anyOf(UaeLinkType.action, UaeLinkType.portal,
                UaeLinkType.information),
            reason: e.id);
      }
    });
  });

  group('payment platform and special cases', () {
    test('Noqodi is labelled as a payment platform, not a government body', () {
      final noqodi = entries.singleWhere((e) => e.id == 'dubai-noqodi');
      expect(noqodi.type, UaeLinkType.payment);
      expect(noqodi.authorityEn.toLowerCase(), contains('payment platform'));
      expect(noqodi.descriptionEn.toLowerCase(),
          contains('not a government department'));
      expect(
          noqodi.verification, UaeLinkVerification.officialManualCheckRequired);
      expect(entries.where((e) => e.type == UaeLinkType.payment).length, 1);
    });

    test('Madhmoun entries are actionable services, not articles', () {
      final madhmoun = entries.where((e) => e.id.contains('madhmoun'));
      expect(madhmoun, isNotEmpty);
      for (final e in madhmoun) {
        expect(e.type, UaeLinkType.action, reason: e.id);
        expect(e.domain, 'services.dari.ae', reason: e.id);
      }
    });
  });

  group('legacy links', () {
    test('outdated, moved or wrongly filed addresses are gone', () {
      const retired = [
        'md.uaq.ae',
        'rak.ae/wps',
        'rental-index-form-landing',
        'request-a-real-estate-permit',
        'sercatid=48',
        'ajmanre.gov.ae/en/services/eservices/',
        'our-services/registration-of-a-long-term-lease',
        'tasdeeq.am.gov.ae/en/index.html',
        'oqood.dubailand.gov.ae/OqoodPortal',
        'https://uaepass.ae/',
      ];
      final urls = entries.map((e) => e.url).toList();
      for (final fragment in retired) {
        expect(urls.where((u) => u.contains(fragment)), isEmpty,
            reason: fragment);
      }
    });

    test('the old code paths are not used any more', () {
      final model =
          File('lib/src/data/models/uae_links_model.dart').readAsStringSync();
      expect(model.contains('UAELinkCategory'), isFalse);
      expect(model.contains('translate('), isFalse);
    });
  });
}
