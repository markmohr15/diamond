import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// DIA-024's partition: the stream grouped into happenings, the pitch as
/// the key. A batted ball hangs off the pitch it was hit on and a
/// between-pitch entry hangs off the pitch that already exists (§15.6
/// v0.45), so one rule covers both and pitch order is chronological order.
void main() {
  test('a batted ball gathers its touches, advances and outs', () {
    final b = EventBuilder();
    final s = foldOfficialScoring([
      b.pitch(
        id: 'p1',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.BALL,
      ),
      b.pitch(
        id: 'p2',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p2'),
      b.fielderTouch(
        id: 't1',
        anchorEventId: 'bip',
        position: 6,
        touchType: TouchType.FIELDED,
      ),
      b.runnerAdvance(
        id: 'a1',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
      b.runnerOut(id: 'o1', runnerId: 'r1', atBase: 2, how: How.FORCE),
    ]);

    expect(s.plays.map((p) => p.pitchEventId), ['p1', 'p2']);
    // The ball pitch is a pitch and not a happening: nothing followed it.
    expect(s.plays.first.isEmpty, isTrue);

    final play = s.plays.last;
    expect(play.ballInPlay?.eventId, 'bip');
    expect(play.touches.map((t) => t.eventId), ['t1']);
    expect(play.advances.map((a) => a.eventId), ['a1']);
    expect(play.outs.map((o) => o.eventId), ['o1']);
    expect(play.isEmpty, isFalse);
  });

  test('a steal is its own happening, on the pitch it was entered against', () {
    final b = EventBuilder();
    final s = foldOfficialScoring([
      b.pitch(
        id: 'p1',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.BALL,
      ),
      // §15.6: entered between pitches, so it hangs off p1.
      b.runnerAdvance(
        id: 'sb',
        runnerId: 'r1',
        from: 1,
        to: 2,
        reason: RunnerAdvanceReason.STOLEN_BASE,
      ),
      b.pitch(
        id: 'p2',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p2'),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
    ]);

    // Two happenings, in the order they happened — which is what lets the
    // log read down the half-inning.
    expect(s.plays.where((p) => !p.isEmpty).map((p) => p.pitchEventId), [
      'p1',
      'p2',
    ]);
    expect(s.plays.first.ballInPlay, isNull);
    expect(
      s.plays.first.advances.single.payload.reason,
      RunnerAdvanceReason.STOLEN_BASE,
    );
    expect(s.plays.last.ballInPlay?.eventId, 'bip');
    expect(s.plays.last.advances.single.eventId, 'reach');
  });

  test('a touch anchored to the pitch rather than a batted ball still lands '
      'on that pitch', () {
    // The between-pitch shape: a catcher's miss on a passed ball anchors to
    // the pitch, because there is no BallInPlay to hang it off.
    final b = EventBuilder();
    final s = foldOfficialScoring([
      b.pitch(
        id: 'p1',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.BALL,
      ),
      b.fielderTouch(
        id: 'pb',
        anchorEventId: 'p1',
        position: 2,
        touchType: TouchType.MISSED_CATCH,
      ),
      b.runnerAdvance(
        id: 'adv',
        runnerId: 'r2',
        from: 2,
        to: 3,
        reason: RunnerAdvanceReason.PASSED_BALL,
        enabledByTouchId: 'pb',
      ),
    ]);

    final play = s.plays.single;
    expect(play.ballInPlay, isNull);
    expect(play.touches.single.eventId, 'pb');
    expect(play.advances.single.eventId, 'adv');
  });

  test('the partition agrees with the outcomes it sits beside', () {
    // The reason this is published rather than recomputed: a consumer that
    // re-derived the grouping could disagree with the rulings. Here every
    // charged error belongs to a touch the partition placed.
    final b = EventBuilder();
    final s = foldOfficialScoring([
      b.pitch(
        id: 'p',
        batterId: 'b1',
        pitcherId: 'pit',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip', pitchEventId: 'p'),
      b.fielderTouch(
        id: 'boot',
        anchorEventId: 'bip',
        position: 6,
        touchType: TouchType.BOOTED,
      ),
      b.runnerAdvance(
        id: 'reach',
        runnerId: 'b1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.ERROR,
        enabledByTouchId: 'boot',
      ),
    ]);

    final placed = {
      for (final p in s.plays)
        for (final t in p.touches) t.eventId,
    };
    expect(s.errors, hasLength(1));
    expect(placed, contains(s.errors.single.touchEventId));
  });
}
