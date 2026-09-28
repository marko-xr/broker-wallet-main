import 'dart:io';

import 'package:broker_wallet/src/services/media_parent.dart';
import 'package:broker_wallet/src/services/offer_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Static checks that keep the `confirm_owner_media_upload` migration, its
/// rollback-only validation script, its pgTAP suite, the Media Worker's Owner
/// routes and the app's Owner media rules in agreement.
///
/// These read files; they do not execute SQL or the Worker. The migration's
/// behaviour is proven only by running
/// `supabase/tests/owner_media_confirm_test.sql` (pgTAP) or
/// `supabase/validation/owner_media_confirm_validation.sql` against a
/// database; the Worker's by its own `npm test` suite
/// (`test/owner_media.test.mjs`).

const _migration =
    'supabase/migrations/20260928131828_owner_media_confirm_rpc.sql';
const _offerMigration =
    'supabase/migrations/20260926092220_offer_media_confirm_rpc.sql';
const _pgTap = 'supabase/tests/owner_media_confirm_test.sql';
const _validation = 'supabase/validation/owner_media_confirm_validation.sql';
const _worker = 'cloudflare/workers/r2-profile-upload/worker.js';
const _wrangler = 'cloudflare/workers/r2-profile-upload/wrangler.toml';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// SQL without `--` comments, lower-cased.
String _statements(String path) => _read(path)
    .split('\n')
    .map((line) {
      final comment = line.indexOf('--');
      return comment >= 0 ? line.substring(0, comment) : line;
    })
    .join('\n')
    .toLowerCase();

String _functionBlock(String sql, String name) {
  final start = sql.indexOf('create or replace function public.$name(');
  final end = sql.indexOf(r'$function$;', start);
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return sql.substring(start, end + r'$function$;'.length);
}

List<String> _parameters(String path, String name) {
  final sql = _statements(path);
  final start = sql.indexOf('create or replace function public.$name(');
  final open = sql.indexOf('(', start);
  final close = sql.indexOf(')', open);
  return [
    for (final part in sql.substring(open + 1, close).split(','))
      part.trim().split(RegExp(r'\s+')).first,
  ];
}

/// The Owner entry of the Worker's `MEDIA_PARENTS` table, verbatim.
String _ownerParent(String worker) {
  final start = worker.indexOf('  owner: Object.freeze({');
  final end = worker.indexOf('}),', start);
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return worker.substring(start, end);
}

void main() {
  group('the Owner migration', () {
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
              r'revoke all on function public\.confirm_owner_media_upload\([^;]*\) from '
              '$role;')),
          reason: 'EXECUTE revoked from $role',
        );
      }
      expect(
        sql,
        matches(RegExp(
            r'grant execute on function public\.confirm_owner_media_upload\([^;]*\) to service_role;')),
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

    test('takes exactly the Offer function\'s parameters, for an Owner', () {
      final offer = _parameters(_offerMigration, 'confirm_offer_media_upload');
      final owner = _parameters(_migration, 'confirm_owner_media_upload');
      expect(owner, [
        for (final name in offer)
          name == 'p_offer_id' ? 'p_owner_record_id' : name,
      ]);
    });

    test(
        'locks the Owner row before deciding the limit and the position, '
        'counts only ready media in the same bucket, and accepts only '
        'media under the Owner\'s own key', () {
      final sql = _statements(_migration);
      final lock = sql.indexOf('from public.owners as ow');
      final forUpdate = sql.indexOf('for update', lock);
      final count = sql.indexOf('count(*)');
      final position = sql.indexOf('max(owm.ordinal)');
      expect(lock, greaterThan(0));
      expect(forUpdate, greaterThan(lock));
      expect(count, greaterThan(forUpdate));
      expect(position, greaterThan(count));

      final countQuery = sql.substring(count, sql.indexOf(';', count));
      expect(countQuery, contains('mo.bucket = p_bucket'));
      expect(countQuery, contains("mo.status = 'ready'"));
      expect(sql, contains("'/owners/' || p_owner_record_id::text || '/'"));
      expect(sql, isNot(contains('/offers/')),
          reason: 'an Offer key is never accepted for an Owner');
    });

    test('an attached item is never attached twice', () {
      final sql = _statements(_migration);
      final existing = sql.indexOf('from public.owner_media as owm\n'
          '  where owm.owner_record_id = p_owner_record_id\n'
          '    and owm.media_id = p_media_id');
      final insert = sql.indexOf('insert into public.owner_media');
      expect(existing, greaterThan(0));
      expect(insert, greaterThan(existing));
      expect(sql, contains("'already_attached'"));
    });

    test('the size ceiling is the Offer video limit (owner decision)', () {
      expect(_statements(_migration),
          contains('p_observed_size > ${OfferMediaPolicy.maxVideoBytes}'));
    });
  });

  group('the Media Worker and the Owner function agree', () {
    test('the Worker sends exactly the function\'s parameters', () {
      final worker = _read(_worker);
      expect(
        worker,
        contains("const OWNER_MEDIA_CONFIRM_RPC = "
            "'/rest/v1/rpc/confirm_owner_media_upload';"),
      );
      final owner = _ownerParent(worker);
      expect(owner, contains('confirmRpc: OWNER_MEDIA_CONFIRM_RPC,'));
      expect(owner, contains("table: 'owners',"));
      expect(owner, contains("linkTable: 'owner_media',"));
      expect(owner, contains("linkColumn: 'owner_record_id',"));
      expect(owner, contains("keySegment: 'owners',"));
      expect(owner, contains("idField: '${MediaParent.owner.idField}',"));

      final call = worker.indexOf('parent.confirmRpc,\n');
      final body = worker.substring(call, worker.indexOf('}', call));
      final sent = <String>{
        ...RegExp(r'(p_[a-z_]+):').allMatches(body).map((m) => m.group(1)!),
        if (body.contains('[parent.rpcParentParam]:'))
          RegExp(r"rpcParentParam: '(p_[a-z_]+)'").firstMatch(owner)!.group(1)!,
      };
      expect(
          sent, _parameters(_migration, 'confirm_owner_media_upload').toSet());
    });

    test('the limit the Worker passes is the app\'s Owner limit', () {
      final worker = _read(_worker);
      expect(_ownerParent(worker), contains('maxItems: MAX_MEDIA_PER_OWNER,'));
      expect(
          worker,
          contains(
              'const MAX_MEDIA_PER_OWNER = ${MediaParent.owner.maxItems};'));
    });

    test('the app routes Owner media to the Owner routes', () {
      expect(MediaParent.owner.routePrefix, '/owner-media');
      final worker = _read(_worker);
      for (final route in [
        "path === '/owner-media/authorize'",
        "path === '/owner-media/confirm'",
        "path === '/owner-media'",
        "path === '/owner-media/remove'",
      ]) {
        expect(worker, contains(route));
      }
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
        'owner_not_found',
        'media_not_found',
        'invalid_status',
      });

      final worker = _read(_worker);
      expect(
          _ownerParent(worker), contains("notFoundCode: 'owner_not_found',"));
      expect(_ownerParent(worker),
          contains("limitCode: 'owner_media_limit_reached',"));
      expect(
        OfferMediaRejection.fromWorkerCode('owner_media_limit_reached'),
        OfferMediaRejection.limitReached,
        reason: 'the app shows the Worker\'s Owner limit refusal as the limit',
      );
    });
  });

  group('review artifacts', () {
    test(
        'the validation script installs the exact migration text and '
        'rolls everything back', () {
      final migration = _read(_migration);
      final validation = _read(_validation);
      expect(validation,
          contains(_functionBlock(migration, 'confirm_owner_media_upload')));

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

    test('Owner media cleanup ships switched off in every environment', () {
      final toml = _read(_wrangler);
      final production = toml.substring(toml.indexOf('[vars]'),
          toml.indexOf('[', toml.indexOf('[vars]') + 1));
      final staging = toml.substring(toml.indexOf('[env.staging.vars]'));
      for (final section in [production, staging]) {
        expect(section, contains('OWNER_MEDIA_SWEEP_MODE = "off"'));
      }
      final worker = _read(_worker);
      expect(_ownerParent(worker),
          contains("sweepModeVar: 'OWNER_MEDIA_SWEEP_MODE',"));
      expect(worker, contains('ctx.waitUntil(runOwnerMediaSweeps(env));'));
    });
  });
}
