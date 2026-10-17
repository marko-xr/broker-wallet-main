// Reading a record's plan for its Details screen: a separate, non-blocking read
// that never shows an error over a screen that otherwise works, applies only
// the most recent answer, and goes quiet once the screen is gone. Pure.

import 'dart:async';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_details_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_plan_transport.dart';

const _recordId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _mediaId = '11111111-1111-4111-8111-111111111111';
const _otherMediaId = '22222222-2222-4222-8222-222222222222';

PlanAttachmentRef _plan({String id = _mediaId}) => PlanAttachmentRef(
      mediaObjectId: id,
      kind: PlanAttachmentKind.pdf,
      contentType: PlanContentTypes.pdf,
      displayName: 'Plot 14 plan.pdf',
      byteLength: 4096,
    );

/// A transport whose reads are answered by hand, in any order.
class _SteppedTransport extends FakePlanTransport {
  final List<Completer<PlanAttachmentRef?>> pending =
      <Completer<PlanAttachmentRef?>>[];

  @override
  Future<PlanAttachmentRef?> fetchCurrent({
    required PlanParent parent,
    required String parentId,
  }) {
    calls.add('fetch');
    fetched.add((parent, parentId));
    final completer = Completer<PlanAttachmentRef?>();
    pending.add(completer);
    return completer.future;
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakePlanTransport transport;
  late int changes;

  PlanAttachmentDetailsLoader loaderFor(
    FakePlanTransport t, {
    PlanParent parent = PlanParent.offer,
  }) =>
      PlanAttachmentDetailsLoader(
        parent: parent,
        parentId: _recordId,
        transport: t,
        onChanged: () => changes++,
      );

  setUp(() {
    transport = FakePlanTransport();
    changes = 0;
  });

  test('a record with a plan shows it, with the link of the last read',
      () async {
    transport.current = _plan();
    final loader = loaderFor(transport);

    expect(loader.plan, isNull, reason: 'nothing before the first read');
    final done = loader.load();
    expect(loader.isLoading, isTrue);
    expect(changes, 0, reason: 'starting a read does not redraw the screen');
    await done;

    expect(loader.plan?.mediaObjectId, _mediaId);
    expect(loader.plan?.signedUrl, isNotNull);
    expect(loader.isLoading, isFalse);
    expect(loader.loadFailed, isFalse);
    expect(changes, 1);
  });

  test('reads the right record of the right kind', () async {
    await loaderFor(transport, parent: PlanParent.owner).load();
    await loaderFor(transport).load();
    expect(transport.fetched, [
      (PlanParent.owner, _recordId),
      (PlanParent.offer, _recordId),
    ]);
  });

  test('a record without a plan has nothing to draw', () async {
    final loader = loaderFor(transport);
    await loader.load();
    expect(loader.plan, isNull);
    expect(loader.loadFailed, isFalse);
    expect(loader.isLoading, isFalse);
    expect(changes, 1, reason: 'the screen is told the read finished');
  });

  test('a failed read keeps what was known and only flags itself', () async {
    transport.current = _plan();
    final loader = loaderFor(transport);
    await loader.load();
    expect(loader.plan, isNotNull);

    transport.fetchError =
        const PlanAttachmentException(PlanAttachmentFailure.unavailable);
    await loader.load();
    expect(loader.loadFailed, isTrue);
    expect(loader.isLoading, isFalse);
    expect(loader.plan?.mediaObjectId, _mediaId,
        reason: 'the plan last read is still shown');
    expect(changes, 2);

    transport.fetchError = null;
    transport.current = _plan(id: _otherMediaId);
    await loader.load();
    expect(loader.loadFailed, isFalse);
    expect(loader.plan?.mediaObjectId, _otherMediaId);
  });

  test('a plan removed elsewhere disappears on the next read', () async {
    transport.current = _plan();
    final loader = loaderFor(transport);
    await loader.load();
    expect(loader.plan, isNotNull);

    transport.current = null;
    await loader.load();
    expect(loader.plan, isNull);
    expect(loader.loadFailed, isFalse);
  });

  test('only the most recent read is applied, whatever order they finish',
      () async {
    final stepped = _SteppedTransport();
    final loader = loaderFor(stepped);

    final first = loader.load();
    final second = loader.load();
    expect(stepped.pending, hasLength(2));

    // The newer read answers first; the older one answers later.
    stepped.pending[1].complete(_plan(id: _otherMediaId));
    await second;
    stepped.pending[0].complete(_plan());
    await first;

    expect(loader.plan?.mediaObjectId, _otherMediaId,
        reason: 'a slow, older answer never overwrites a newer one');
    expect(loader.isLoading, isFalse);
    expect(changes, 1);
  });

  test('an older read that fails after a newer one succeeded changes nothing',
      () async {
    final stepped = _SteppedTransport();
    final loader = loaderFor(stepped);

    final first = loader.load();
    final second = loader.load();
    stepped.pending[1].complete(_plan());
    await second;
    stepped.pending[0].completeError(
        const PlanAttachmentException(PlanAttachmentFailure.unavailable));
    await first;

    expect(loader.loadFailed, isFalse);
    expect(loader.plan?.mediaObjectId, _mediaId);
    expect(changes, 1);
  });

  test('a read that finishes after the screen is gone does nothing', () async {
    final stepped = _SteppedTransport();
    final loader = loaderFor(stepped);

    final pending = loader.load();
    loader.dispose();
    stepped.pending.single.complete(_plan());
    await pending;
    await _settle();

    expect(changes, 0, reason: 'a disposed screen is never redrawn');
    expect(loader.plan, isNull);
  });

  test('a failure after the screen is gone does nothing either', () async {
    final stepped = _SteppedTransport();
    final loader = loaderFor(stepped);

    final pending = loader.load();
    loader.dispose();
    stepped.pending.single.completeError(
        const PlanAttachmentException(PlanAttachmentFailure.unavailable));
    await pending;

    expect(changes, 0);
    expect(loader.loadFailed, isFalse);
  });

  test('loading a disposed loader does not even ask the server', () async {
    final loader = loaderFor(transport)..dispose();
    await loader.load();
    expect(transport.calls, isEmpty);
    expect(changes, 0);
  });
}
