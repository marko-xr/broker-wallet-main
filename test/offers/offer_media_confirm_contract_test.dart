import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Static checks that keep the proposed `confirm_offer_media_upload`
/// migration, its rollback-only validation script, its pgTAP suite and the
/// Media Worker that calls it in agreement.
///
/// These read files; they do not execute SQL. The migration's behaviour is
/// proven only by running `supabase/tests/offer_media_confirm_test.sql`
/// (pgTAP) or `supabase/validation/offer_media_confirm_validation.sql`
/// against a database — neither of which these tests do.

const _migration =
    'supabase/migrations/20260926092220_offer_media_confirm_rpc.sql';
const _pgTap = 'supabase/tests/offer_media_confirm_test.sql';
const _validation = 'supabase/validation/offer_media_confirm_validation.sql';
const _worker = 'cloudflare/workers/r2-profile-upload/worker.js';
const _wrangler = 'cloudflare/workers/r2-profile-upload/wrangler.toml';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// SQL without `--` comments, lower-cased: assertions about statements, not
/// prose. (None of these files has `--` inside a string literal.)
String _statements(String path) => _read(path)
    .split('\n')
    .map((line) {
      final comment = line.indexOf('--');
      return comment >= 0 ? line.substring(0, comment) : line;
    })
    .join('\n')
    .toLowerCase();

/// The `create or replace function ... $function$;` block, verbatim.
String _functionBlock(String sql) {
  final start = sql.indexOf('create or replace function public.'
      'confirm_offer_media_upload(');
  final end = sql.indexOf(r'$function$;', start);
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return sql.substring(start, end + r'$function$;'.length);
}

List<String> _migrationParameters() {
  final sql = _statements(_migration);
  final start = sql
      .indexOf('create or replace function public.confirm_offer_media_upload(');
  final open = sql.indexOf('(', start);
  final close = sql.indexOf(')', open);
  return [
    for (final part in sql.substring(open + 1, close).split(','))
      part.trim().split(RegExp(r'\s+')).first,
  ];
}

void main() {
  group('the proposed migration', () {
    test(
        'is SECURITY DEFINER with an empty search_path and runs for '
        'service_role only', () {
      final sql = _statements(_migration);
      expect(sql, contains('security definer'));
      expect(sql, contains("set search_path = ''"));
      for (final role in ['public', 'anon', 'authenticated']) {
        expect(
          sql,
          matches(RegExp(
              r'revoke all on function public\.confirm_offer_media_upload\([^;]*\) from '
              '$role;')),
          reason: 'EXECUTE revoked from $role',
        );
      }
      expect(
        sql,
        matches(RegExp(
            r'grant execute on function public\.confirm_offer_media_upload\([^;]*\) to service_role;')),
      );
      expect(
        sql,
        isNot(matches(RegExp(r'grant [^;]* to (anon|authenticated|public)\b'))),
      );
    });

    test('changes no table, column, policy, index or trigger', () {
      final sql = _statements(_migration);
      for (final ddl in [
        'create table',
        'alter table',
        'drop table',
        'create policy',
        'alter policy',
        'drop policy',
        'row level security',
        'create index',
        'create trigger',
        'drop trigger',
        'drop function',
        'truncate',
        'delete from',
      ]) {
        expect(sql, isNot(contains(ddl)), reason: ddl);
      }
    });

    test(
        'locks the Offer row before deciding the limit and the position, '
        'and counts only ready media in the same bucket', () {
      final sql = _statements(_migration);
      final lock = sql.indexOf('from public.offers as o');
      final forUpdate = sql.indexOf('for update', lock);
      final count = sql.indexOf('count(*)');
      final position = sql.indexOf('max(om.ordinal)');
      expect(lock, greaterThan(0));
      expect(forUpdate, greaterThan(lock));
      expect(count, greaterThan(forUpdate));
      expect(position, greaterThan(count));

      final countQuery = sql.substring(count, sql.indexOf(';', count));
      expect(countQuery, contains('mo.bucket = p_bucket'));
      expect(countQuery, contains("mo.status = 'ready'"));
    });

    test('an attached item is never attached twice', () {
      final sql = _statements(_migration);
      final existing = sql.indexOf('from public.offer_media as om\n'
          '  where om.offer_id = p_offer_id\n'
          '    and om.media_id = p_media_id');
      final insert = sql.indexOf('insert into public.offer_media');
      expect(existing, greaterThan(0));
      expect(insert, greaterThan(existing),
          reason: 'the existing link is looked for before inserting');
      expect(sql, contains("'already_attached'"));
    });
  });

  group('the Media Worker and the function agree', () {
    test('the Worker sends exactly the function\'s parameters', () {
      final worker = _read(_worker);
      expect(
        worker,
        contains(
            "const OFFER_MEDIA_CONFIRM_RPC = '/rest/v1/rpc/confirm_offer_media_upload';"),
      );
      final call = worker.indexOf('OFFER_MEDIA_CONFIRM_RPC,\n');
      final body = worker.substring(call, worker.indexOf('}', call));
      final sent = RegExp(r'(p_[a-z_]+):')
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();

      expect(sent, _migrationParameters().toSet());
    });

    test('the limit the Worker passes is the app\'s limit', () {
      final worker = _read(_worker);
      expect(worker, contains('p_max_items: MAX_MEDIA_PER_OFFER,'));
      expect(
        worker,
        contains('const MAX_MEDIA_PER_OFFER = '
            '${OfferMediaPolicy.maxItemsPerOffer};'),
      );
    });

    test('every outcome the function can return is handled', () {
      final outcomes = RegExp(r"select '([a-z_]+)'::text")
          .allMatches(_statements(_migration))
          .map((m) => m.group(1)!)
          .toSet();
      expect(outcomes, {
        'attached',
        'already_attached',
        'limit_reached',
        'offer_not_found',
        'media_not_found',
        'invalid_status',
      });

      final worker = _read(_worker);
      final switchStart = worker.indexOf('switch (attach.outcome) {');
      final switchBody =
          worker.substring(switchStart, worker.indexOf('\n  }\n', switchStart));
      for (final handled in [
        'attached',
        'already_attached',
        'limit_reached',
        'offer_not_found',
      ]) {
        expect(switchBody, contains("case '$handled':"));
      }
      // media_not_found and invalid_status: refused, nothing attached.
      expect(switchBody, contains('default:'));
      expect(switchBody, contains("'invalid_state'"));
    });
  });

  group('review artifacts', () {
    test(
        'the validation script installs the exact migration text and '
        'rolls everything back', () {
      final migration = _read(_migration);
      final validation = _read(_validation);
      expect(validation, contains(_functionBlock(migration)));

      final statements = _statements(_validation);
      expect(statements,
          isNot(matches(RegExp(r'^\s*commit\s*;', multiLine: true))));
      final lastStatement = statements
          .split('\n')
          .map((line) => line.trim())
          .lastWhere((line) => line.isNotEmpty);
      expect(lastStatement, 'rollback;');
    });

    test('the pgTAP suite plans exactly the assertions it makes', () {
      final sql = _statements(_pgTap);
      final plan = int.parse(
          RegExp(r'select plan\((\d+)\);').firstMatch(sql)!.group(1)!);
      final made = RegExp(
              r'^\s*select (ok|is|isnt|has_function|throws_ok|lives_ok|results_eq|is_definer|function_privs_are)\(',
              multiLine: true)
          .allMatches(sql)
          .length;
      expect(made, plan);
      expect(sql, contains('select * from finish();'));
      expect(sql.trimRight(), endsWith('rollback;'));
    });

    test('Offer media cleanup ships switched off in every environment', () {
      final toml = _read(_wrangler);
      final production = toml.substring(toml.indexOf('[vars]'),
          toml.indexOf('[', toml.indexOf('[vars]') + 1));
      final staging = toml.substring(toml.indexOf('[env.staging.vars]'));
      for (final section in [production, staging]) {
        expect(section, contains('OFFER_MEDIA_SWEEP_MODE = "off"'));
      }
      expect(_read(_worker), contains("env.OFFER_MEDIA_SWEEP_MODE : 'off'"),
          reason: 'a missing or unknown mode means off');
    });
  });
}
