import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/logical_order.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

GameEvent _ball(EventBuilder b, String id) {
  return b.pitch(
    id: id,
    batterId: 'bat',
    pitcherId: 'p',
    outcome: Outcome.BALL,
  );
}

void main() {
  test('with no effectiveAfter, logical order matches recording order', () {
    final b = EventBuilder();
    final e1 = _ball(b, 'e1');
    final e2 = _ball(b, 'e2');

    final visible = resolveVisibleLogicalOrder([e1, e2]);

    expect(visible.map((e) => e.id).toList(), ['e1', 'e2']);
  });

  test(
    'the stress scenario: a stolen base noticed two pitches late lands '
    'right after the pitch it actually happened during, fixing the '
    'runner state the later pitches see',
    () {
      final b = EventBuilder();
      final pitch1 = _ball(b, 'pitch1');
      final pitch2 = _ball(b, 'pitch2');
      final pitch3 = b.pitch(
        id: 'pitch3',
        batterId: 'bat',
        pitcherId: 'p',
        outcome: Outcome.FOUL,
      );
      // Recorded last, chronologically — the scorer only just noticed it
      // — but it happened right after pitch1.
      final lateSteal = b.runnerAdvance(
        id: 'late-steal',
        runnerId: 'r1',
        from: 1,
        to: 2,
        reason: RunnerAdvanceReason.STOLEN_BASE,
        effectiveAfter: 'pitch1',
      );

      final chronological = [pitch1, pitch2, pitch3, lateSteal];
      final visible = resolveVisibleLogicalOrder(chronological);

      expect(
        visible.map((e) => e.id).toList(),
        ['pitch1', 'late-steal', 'pitch2', 'pitch3'],
        reason: 'the steal is spliced in right after pitch1, not appended '
            'at the end where it was actually recorded',
      );
    },
  );

  test('editing an inserted event keeps its spliced position', () {
    final b = EventBuilder();
    final anchor = _ball(b, 'anchor');
    final after = _ball(b, 'after');
    final insert = b.runnerAdvance(
      id: 'insert',
      runnerId: 'r1',
      from: 1,
      to: 2,
      reason: RunnerAdvanceReason.STOLEN_BASE,
      effectiveAfter: 'anchor',
    );
    // The scorer realizes the runner actually went to third, not second.
    final edit = b.runnerAdvance(
      id: 'edit',
      runnerId: 'r1',
      from: 1,
      to: 3,
      reason: RunnerAdvanceReason.STOLEN_BASE,
      corrects: 'insert',
    );

    final visible = resolveVisibleLogicalOrder([anchor, after, insert, edit]);

    expect(visible.map((e) => e.id).toList(), ['anchor', 'edit', 'after']);
    expect(RunnerAdvance.fromJson(visible[1].payload).to, 3);
  });

  test('voiding an inserted event removes it entirely', () {
    final b = EventBuilder();
    final anchor = _ball(b, 'anchor');
    final after = _ball(b, 'after');
    final insert = b.runnerAdvance(
      id: 'insert',
      runnerId: 'r1',
      from: 1,
      to: 2,
      reason: RunnerAdvanceReason.STOLEN_BASE,
      effectiveAfter: 'anchor',
    );
    final undo = b.voidEvent(id: 'undo', targetId: 'insert');

    final visible = resolveVisibleLogicalOrder([anchor, after, insert, undo]);

    expect(visible.map((e) => e.id).toList(), ['anchor', 'after']);
  });

  test(
    'two inserts anchored to the same event tie-break by their own '
    'recording order',
    () {
      final b = EventBuilder();
      final anchor = _ball(b, 'anchor');
      final firstNoticed = b.runnerAdvance(
        id: 'first-noticed',
        runnerId: 'r1',
        from: 1,
        to: 2,
        reason: RunnerAdvanceReason.STOLEN_BASE,
        effectiveAfter: 'anchor',
      );
      final secondNoticed = b.runnerAdvance(
        id: 'second-noticed',
        runnerId: 'r2',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.WALK,
        effectiveAfter: 'anchor',
      );

      final visible = resolveVisibleLogicalOrder([
        anchor,
        firstNoticed,
        secondNoticed,
      ]);

      expect(
        visible.map((e) => e.id).toList(),
        ['anchor', 'first-noticed', 'second-noticed'],
        reason: 'both anchor to the same event; order matches the order '
            'they were actually recorded in',
      );
    },
  );

  test('an insert anchored to a since-voided event keeps its position', () {
    final b = EventBuilder();
    final before = _ball(b, 'before');
    final anchor = _ball(b, 'anchor');
    final after = _ball(b, 'after');
    final insert = b.runnerAdvance(
      id: 'insert',
      runnerId: 'r1',
      from: 1,
      to: 2,
      reason: RunnerAdvanceReason.STOLEN_BASE,
      effectiveAfter: 'anchor',
    );
    final voidAnchor = b.voidEvent(id: 'void-anchor', targetId: 'anchor');

    final visible = resolveVisibleLogicalOrder([
      before,
      anchor,
      after,
      insert,
      voidAnchor,
    ]);

    expect(
      visible.map((e) => e.id).toList(),
      ['before', 'insert', 'after'],
      reason: 'anchor is hidden (voided), but insert still sits where '
          "anchor's raw position was — not wherever it was recorded",
    );
  });

  test(
    'an insert anchored to a corrected (non-head) event resolves through '
    "the correction chain's root position",
    () {
      final b = EventBuilder();
      final before = _ball(b, 'before');
      final original = _ball(b, 'original');
      final after = _ball(b, 'after');
      final correction = b.pitch(
        id: 'correction',
        batterId: 'bat',
        pitcherId: 'p',
        outcome: Outcome.FOUL,
        corrects: 'original',
      );
      // Anchors to 'original', which is no longer the visible head of its
      // chain — 'correction' is. The insert must still land at the
      // chain's root position (right after 'before'), not wherever
      // 'original' or 'correction' happen to sort.
      final insert = b.runnerAdvance(
        id: 'insert',
        runnerId: 'r1',
        from: 1,
        to: 2,
        reason: RunnerAdvanceReason.STOLEN_BASE,
        effectiveAfter: 'original',
      );

      final visible = resolveVisibleLogicalOrder([
        before,
        original,
        after,
        correction,
        insert,
      ]);

      expect(
        visible.map((e) => e.id).toList(),
        ['before', 'correction', 'insert', 'after'],
      );
    },
  );
}
