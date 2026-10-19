import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/data/models/uae_links_catalogue.dart';
import 'package:broker_wallet/src/data/models/uae_links_model.dart';
import 'package:broker_wallet/src/services/uae_links/uae_link_launcher.dart';
import 'package:broker_wallet/src/services/uae_links/uae_link_report.dart';
import 'package:broker_wallet/src/services/uae_links/uae_link_url_policy.dart';
import 'package:broker_wallet/src/services/uae_links/uae_links_search.dart';

List<String> ids(Iterable<UaeLinkEntry> entries) =>
    entries.map((e) => e.id).toList();

void main() {
  final all = UAELinksData.published;

  group('URL policy', () {
    test('accepts HTTPS addresses on official domains and sub-domains', () {
      for (final url in [
        'https://dubailand.gov.ae/en/',
        'https://services.dari.ae/services/',
        'https://www.tamm.abudhabi/',
        'https://WWW.UAEPASS.AE/',
        'https://u.ae/en/information-and-services/housing',
        'https://portal.fujmun.gov.ae/OnlineEServices/en/x.aspx?RK=rental',
        'https://dubailand.gov.ae:443/en/',
      ]) {
        expect(UaeLinkUrlPolicy.isSafe(url), isTrue, reason: url);
      }
    });

    test('rejects other schemes, hosts, ports and malformed text', () {
      for (final url in [
        null,
        '',
        '   ',
        'http://dubailand.gov.ae/en/',
        'ftp://dubailand.gov.ae/',
        'javascript:alert(1)',
        'intent://dubailand.gov.ae#Intent;scheme=https;end',
        'file:///etc/passwd',
        'tel:+971500000000',
        'mailto:info@dubailand.gov.ae',
        'data:text/html,<b>x</b>',
        'https://evil.example.com/',
        'https://dubailand.gov.ae.evil.com/',
        'https://evil.com/dubailand.gov.ae',
        'https://notgov.ae/',
        'https://fakegov.ae/',
        'https://dubailand-gov.ae/',
        'https://dubailand.gov.ae@evil.com/',
        'https://user:pass@dubailand.gov.ae/',
        'https://dubailand.gov.ae:8443/',
        'https://127.0.0.1/',
        'https://192.168.0.1/gov.ae',
        'https://xn--dubailand-8fb.gov.ae/',
        'https://dubailand.gov.ae./',
        'https://dubailand.gov.ae/ x',
        'https://dubailand.gov.ae/\\evil',
        'https://aqari.ae/',
        '//dubailand.gov.ae/',
        'dubailand.gov.ae',
        'not a url',
      ]) {
        expect(UaeLinkUrlPolicy.isSafe(url), isFalse, reason: '$url');
      }
    });
  });

  group('launcher', () {
    test('opens an approved address in the external browser, unchanged',
        () async {
      Uri? launched;
      final launcher = UaeLinkLauncher(launch: (uri) async {
        launched = uri;
        return true;
      });
      final result = await launcher.open('https://dubailand.gov.ae/en/');
      expect(result, UaeLinkOpenResult.opened);
      expect(launched.toString(), 'https://dubailand.gov.ae/en/');
      expect(launched!.query, isEmpty);
    });

    test('never hands an unsafe address to the platform', () async {
      var calls = 0;
      final launcher = UaeLinkLauncher(launch: (uri) async {
        calls++;
        return true;
      });
      for (final url in [
        'http://dubailand.gov.ae/',
        'javascript:alert(1)',
        'https://evil.example.com/',
        '',
      ]) {
        expect(await launcher.open(url), UaeLinkOpenResult.rejected,
            reason: url);
      }
      expect(calls, 0);
    });

    test('reports a failed launch and a throwing platform as failed', () async {
      expect(
        await UaeLinkLauncher(launch: (_) async => false)
            .open('https://dubailand.gov.ae/en/'),
        UaeLinkOpenResult.failed,
      );
      expect(
        await UaeLinkLauncher(launch: (_) async => throw StateError('no app'))
            .open('https://dubailand.gov.ae/en/'),
        UaeLinkOpenResult.failed,
      );
    });
  });

  group('search normalisation and aliases', () {
    test('folds Arabic spelling variants and digits', () {
      expect(UaeLinksSearch.normalize('إيجاري'),
          UaeLinksSearch.normalize('ايجاري'));
      expect(UaeLinksSearch.normalize('أبوظبي'),
          UaeLinksSearch.normalize('ابوظبي'));
      expect(UaeLinksSearch.normalize('الشارقة'),
          UaeLinksSearch.normalize('الشارقه'));
      expect(UaeLinksSearch.normalize('الفجيرة'),
          UaeLinksSearch.normalize('الفجيره'));
      expect(UaeLinksSearch.normalize('تَصْدِيق'),
          UaeLinksSearch.normalize('تصديق'));
      expect(UaeLinksSearch.normalize('Ejari!'), 'ejari');
      expect(UaeLinksSearch.normalize('٢٠٢٦'), '2026');
      expect(UaeLinksSearch.normalize('  A  -  B '), 'a b');
    });

    test('every alias the owner named finds its service', () {
      final expected = <String, String>{
        'Ejari': 'dubai-ejari-register-renew',
        'إيجاري': 'dubai-ejari-register-renew',
        'ايجاري': 'dubai-ejari-register-renew',
        'Tasdeeq': 'ajman-tasdeeq-home',
        'تصديق': 'ajman-tasdeeq-home',
        'Tawtheeq': 'abudhabi-tawtheeq-register',
        'توثيق': 'abudhabi-tawtheeq-register',
        'Aqari': 'sharjah-digital',
        'عقاري': 'sharjah-digital',
        'DLD': 'dubai-dld-home',
        'Dubai Land Department': 'dubai-dld-home',
        'ADREC': 'abudhabi-adrec-home',
        'RERA': 'dubai-rental-index',
        'SRERD': 'sharjah-srerd-home',
        'Trakheesi': 'dubai-real-estate-ad-permit',
        'ترخيصي': 'dubai-real-estate-ad-permit',
        'Madhmoun': 'abudhabi-madhmoun-permit',
        'مضمون': 'abudhabi-madhmoun-permit',
        'Oqood': 'dubai-oqood',
        'Mollak': 'dubai-mollak',
        'DEWA': 'dubai-dewa-move-in',
        'SEWA': 'sharjah-sewa-home',
        'EtihadWE': 'northern-etihadwe-activation',
        'Ejaar': 'fujairah-ejaar',
        'UAE PASS': 'uae-uae-pass',
        'Noqodi': 'dubai-noqodi',
        'Dubai REST': 'dubai-rest',
        'TAMM': 'abudhabi-tamm',
        'DARI': 'abudhabi-dari-home',
      };
      expected.forEach((query, id) {
        final found = UaeLinksSearch.filter(all, query: query);
        expect(ids(found), contains(id), reason: query);
      });
    });

    test('searches the Arabic and the English names of agencies and services',
        () {
      expect(ids(UaeLinksSearch.filter(all, query: 'مركز أبوظبي العقاري')),
          contains('abudhabi-adrec-home'));
      expect(ids(UaeLinksSearch.filter(all, query: 'بلدية الفجيرة')),
          contains('fujairah-municipality'));
      expect(ids(UaeLinksSearch.filter(all, query: 'Rental Disputes Centre')),
          contains('dubai-rental-disputes-centre'));
      expect(
          ids(UaeLinksSearch.filter(all,
              query: 'دائرة الأراضي والتنظيم العقاري')),
          contains('ajman-land-home'));
    });

    test('every word must match, and nothing matches gibberish', () {
      final both = UaeLinksSearch.filter(all, query: 'dubai ejari');
      expect(both, isNotEmpty);
      for (final e in both) {
        expect(e.emirates, contains(UaeLinkEmirate.dubai));
      }
      expect(UaeLinksSearch.filter(all, query: 'qzxwv nothing'), isEmpty);
      expect(UaeLinksSearch.filter(all, query: '   ').length, all.length);
    });
  });

  group('filtering and grouping', () {
    test('the emirate filter keeps only that emirate', () {
      final ajman = UaeLinksSearch.filter(all, emirate: UaeLinkEmirate.ajman);
      expect(ajman, isNotEmpty);
      expect(ajman.every((e) => e.emirates.contains(UaeLinkEmirate.ajman)),
          isTrue);
      expect(ids(ajman), contains('northern-etihadwe-activation'));
      final dubai = UaeLinksSearch.filter(all, emirate: UaeLinkEmirate.dubai);
      expect(ids(dubai), isNot(contains('northern-etihadwe-activation')));
    });

    test('Tasdeeq is found under Ajman and not under Sharjah', () {
      expect(
          ids(UaeLinksSearch.filter(all,
              query: 'tasdeeq', emirate: UaeLinkEmirate.ajman)),
          contains('ajman-tasdeeq-home'));
      expect(
          UaeLinksSearch.filter(all,
              query: 'tasdeeq', emirate: UaeLinkEmirate.sharjah),
          isEmpty);
    });

    test('the task filter keeps only that task and combines with the rest', () {
      final utilities = UaeLinksSearch.filter(all, task: UaeLinkTask.utilities);
      expect(utilities, isNotEmpty);
      expect(utilities.every((e) => e.tasks.contains(UaeLinkTask.utilities)),
          isTrue);
      final dubaiUtilities = UaeLinksSearch.filter(all,
          task: UaeLinkTask.utilities, emirate: UaeLinkEmirate.dubai);
      expect(ids(dubaiUtilities), everyElement(startsWith('dubai-')));
    });

    test('without an emirate every service appears once, UAE-wide first', () {
      final groups = UaeLinksSearch.group(all);
      expect(groups.first.emirate, UaeLinkEmirate.uae);
      final shown = groups.expand((g) => g.entries).toList();
      expect(ids(shown).toSet().length, shown.length);
      expect(shown.length, all.length);
      final order = groups.map((g) => g.emirate.index).toList();
      expect([...order]..sort(), order);
    });

    test('an emirate keeps the UAE-wide services visible below it', () {
      final groups = UaeLinksSearch.group(all, emirate: UaeLinkEmirate.dubai);
      expect(groups.map((g) => g.emirate),
          [UaeLinkEmirate.dubai, UaeLinkEmirate.uae]);
      expect(groups.first.entries.every((e) => !e.isFederal), isTrue);
      expect(groups.last.entries.every((e) => e.isFederal), isTrue);
    });

    test('the UAE-wide filter shows only federal services', () {
      final groups = UaeLinksSearch.group(all, emirate: UaeLinkEmirate.uae);
      expect(groups, hasLength(1));
      expect(groups.single.entries.every((e) => e.isFederal), isTrue);
    });

    test('a search that matches nothing gives no groups', () {
      expect(UaeLinksSearch.group(all, query: 'qzxwv'), isEmpty);
    });
  });

  group('broken-link report', () {
    final entry = all.firstWhere((e) => e.id == 'dubai-ejari-register-renew');
    final when = DateTime.utc(2026, 10, 19, 8, 30);

    test('holds the service, authority, URL, issue type and time', () {
      final report = UaeLinkReport.build(
        entry: entry,
        issue: UaeLinkIssue.doesNotOpen,
        reportedAt: when,
      );
      expect(report, contains(entry.titleEn));
      expect(report, contains(entry.id));
      expect(report, contains(entry.authorityEn));
      expect(report, contains(entry.url));
      expect(report, contains('The link does not open'));
      expect(report, contains('2026-10-19T08:30:00.000Z'));
    });

    test('is the same in every language and carries nothing personal', () {
      final report = UaeLinkReport.build(
        entry: entry,
        issue: UaeLinkIssue.wrongAuthorityOrEmirate,
        reportedAt: when,
      );
      expect(RegExp('[؀-ۿ]').hasMatch(report), isFalse);
      for (final word in ['token', 'password', 'user id', 'email', 'phone']) {
        expect(report.toLowerCase().contains(word), isFalse, reason: word);
      }
      expect(report.split('\n').length, 7);
    });

    test('converts a local time to UTC', () {
      final report = UaeLinkReport.build(
        entry: entry,
        issue: UaeLinkIssue.other,
        reportedAt: DateTime.parse('2026-10-19T12:30:00+04:00'),
      );
      expect(report, contains('2026-10-19T08:30:00.000Z'));
    });

    test('every issue type has a label key and wording', () {
      for (final issue in UaeLinkIssue.values) {
        expect(issue.labelKey, startsWith('ulxIssue'));
        expect(issue.reportText, isNotEmpty);
      }
    });
  });
}
