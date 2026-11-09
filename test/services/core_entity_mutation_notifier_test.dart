// Q-1b: a mutation signal may say which kind of record it changed. Listeners
// of every change (the six lists, Home counts, Search, Map) still get every
// signal; a listener of one kind gets that kind and any signal that does not
// say what it changed.
import 'package:broker_wallet/src/services/core_entity_mutation_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every change still reaches the listeners of all changes', () async {
    var seen = 0;
    final sub = CoreEntityMutationNotifier.changes.listen((_) => seen++);
    addTearDown(sub.cancel);
    for (final kind in CoreEntityKind.values) {
      CoreEntityMutationNotifier.notify(kind);
    }
    CoreEntityMutationNotifier.notify();
    expect(seen, CoreEntityKind.values.length + 1);
  });

  test('a listener of Quotations gets Quotation and unknown changes only',
      () async {
    var seen = 0;
    final sub = CoreEntityMutationNotifier.changesTo(CoreEntityKind.quotation)
        .listen((_) => seen++);
    addTearDown(sub.cancel);
    for (final kind in CoreEntityKind.values) {
      if (kind != CoreEntityKind.quotation) {
        CoreEntityMutationNotifier.notify(kind);
      }
    }
    expect(seen, 0);
    CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
    expect(seen, 1);
    CoreEntityMutationNotifier.notify();
    expect(seen, 2, reason: 'unknown ⇒ possibly a Quotation');
  });

  test('the same holds for any one kind', () async {
    var seen = 0;
    final sub = CoreEntityMutationNotifier.changesTo(CoreEntityKind.owner)
        .listen((_) => seen++);
    addTearDown(sub.cancel);
    CoreEntityMutationNotifier.notify(CoreEntityKind.offer);
    CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
    CoreEntityMutationNotifier.notify(CoreEntityKind.owner);
    expect(seen, 1);
  });

  test('delivery is synchronous, so a read starts before notify returns', () {
    var seen = false;
    final sub = CoreEntityMutationNotifier.changesTo(CoreEntityKind.quotation)
        .listen((_) => seen = true);
    addTearDown(sub.cancel);
    CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
    expect(seen, isTrue);
  });

  test('a cancelled listener gets nothing more', () async {
    var seen = 0;
    final sub = CoreEntityMutationNotifier.changesTo(CoreEntityKind.quotation)
        .listen((_) => seen++);
    await sub.cancel();
    CoreEntityMutationNotifier.notify(CoreEntityKind.quotation);
    CoreEntityMutationNotifier.notify();
    expect(seen, 0);
  });
}
