import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_plan.dart';

CombineSource source(String id, int pages, {int size = 1000}) => CombineSource(
      id: id,
      path: '/x/$id.pdf',
      displayName: '$id.pdf',
      size: size,
      pageCount: pages,
    );

/// "A1 A2 B1" style labels of the plan's pages, with rotation as "A1+1".
List<String> labels(CombinePlan plan) => [
      for (final page in plan.pages)
        '${page.sourceId}${page.pageIndex + 1}'
            '${page.quarterTurns == 0 ? '' : '+${page.quarterTurns}'}',
    ];

void main() {
  late CombinePlan plan;

  setUp(() {
    plan = CombinePlan();
    plan.addSource(source('A', 3));
    plan.addSource(source('B', 2));
  });

  test('adding files adds every page in order and counts them', () {
    expect(labels(plan), ['A1', 'A2', 'A3', 'B1', 'B2']);
    expect(plan.totalPages, 5);
    expect(plan.sources.map((s) => s.id), ['A', 'B']);
    expect(plan.selectedCount('A'), 3);
  });

  test('the same file is not added twice', () {
    expect(plan.addSource(source('A', 3)), isFalse);
    expect(plan.sources, hasLength(2));
    expect(plan.totalPages, 5);
  });

  test('moving a file moves its pages as a block', () {
    plan.moveSource(1, 0);
    expect(plan.sources.map((s) => s.id), ['B', 'A']);
    expect(labels(plan), ['B1', 'B2', 'A1', 'A2', 'A3']);
    plan.moveSource(0, 1);
    expect(labels(plan), ['A1', 'A2', 'A3', 'B1', 'B2']);
    // Out of range moves change nothing.
    plan.moveSource(5, 0);
    expect(labels(plan), ['A1', 'A2', 'A3', 'B1', 'B2']);
  });

  test('a page range keeps only those pages and keeps their rotation', () {
    plan.rotatePage(1, 1); // A2
    plan.selectRange('A', 2, 3);
    expect(labels(plan), ['A2+1', 'A3', 'B1', 'B2']);
    expect(plan.selectedCount('A'), 2);
    expect(plan.totalPages, 4);
    // Widening the range brings back pages unrotated.
    plan.selectRange('A', 1, 3);
    expect(labels(plan), ['A1', 'A2+1', 'A3', 'B1', 'B2']);
  });

  test('a range outside the file is refused and changes nothing', () {
    expect(() => plan.selectRange('A', 0, 2), throwsRangeError);
    expect(() => plan.selectRange('A', 2, 9), throwsRangeError);
    expect(() => plan.selectRange('A', 3, 2), throwsRangeError);
    expect(labels(plan), ['A1', 'A2', 'A3', 'B1', 'B2']);
  });

  test('removed pages can be brought back with "use all pages"', () {
    plan.removePage(0);
    plan.removePage(0);
    expect(labels(plan), ['A3', 'B1', 'B2']);
    plan.useAllPages('A');
    expect(labels(plan), ['A1', 'A2', 'A3', 'B1', 'B2']);
  });

  test('pages can be reordered, also from one file into another', () {
    plan.movePage(4, 0); // B2 to the front
    expect(labels(plan), ['B2', 'A1', 'A2', 'A3', 'B1']);
    plan.movePage(0, 3); // B2 to final position 3 (after A3)
    expect(labels(plan), ['A1', 'A2', 'A3', 'B2', 'B1']);
    plan.movePage(1, 4);
    expect(labels(plan), ['A1', 'A3', 'B2', 'B1', 'A2']);
    plan.movePage(9, 0);
    expect(labels(plan), ['A1', 'A3', 'B2', 'B1', 'A2']);
  });

  test('moving a file after interleaving regroups that plan by file', () {
    plan.movePage(4, 1); // A1 B2 A2 A3 B1
    expect(labels(plan), ['A1', 'B2', 'A2', 'A3', 'B1']);
    plan.moveSource(0, 1);
    expect(labels(plan), ['B2', 'B1', 'A1', 'A2', 'A3']);
  });

  test('rotation turns a quarter at a time, in both directions, and wraps', () {
    plan.rotatePage(0, 1);
    expect(plan.pages[0].quarterTurns, 1);
    plan.rotatePage(0, 3);
    expect(plan.pages[0].quarterTurns, 0);
    plan.rotatePage(0, -1);
    expect(plan.pages[0].quarterTurns, 3);
    plan.rotatePage(40, 1); // no such page
    expect(plan.totalPages, 5);
  });

  test('removing a file removes exactly its pages', () {
    plan.removeSource('A');
    expect(labels(plan), ['B1', 'B2']);
    expect(plan.sources.map((s) => s.id), ['B']);
  });

  test('what blocks a combine, in order of importance', () {
    expect(plan.blocker, isNull);
    plan.removeSource('B');
    expect(plan.blocker, CombinePdfFailure.tooFewFiles);
    plan.addSource(source('B', 2));
    // A file with every page removed would silently contribute nothing.
    plan.removePage(3);
    plan.removePage(3);
    expect(plan.blocker, CombinePdfFailure.fileHasNoPages);
    expect(plan.firstEmptySourceId, 'B');
    plan.useAllPages('B');
    expect(plan.blocker, isNull);
    plan.clear();
    expect(plan.blocker, CombinePdfFailure.tooFewFiles);
    expect(plan.isEmpty, isTrue);
  });

  test('a selection too big for the phone is blocked before any work', () {
    final big = CombinePlan()
      ..addSource(source('A', CombineLimits.maxTotalPages))
      ..addSource(source('B', 1));
    expect(big.blocker, CombinePdfFailure.selectionTooLarge);
    final heavy = CombinePlan()
      ..addSource(source('A', 1, size: CombineLimits.maxTotalSourceBytes))
      ..addSource(source('B', 1, size: 1));
    expect(heavy.blocker, CombinePdfFailure.selectionTooLarge);
    final many = CombinePlan();
    for (var i = 0; i <= CombineLimits.maxSources; i++) {
      many.addSource(source('F$i', 1));
    }
    expect(many.blocker, CombinePdfFailure.selectionTooLarge);
  });
}
