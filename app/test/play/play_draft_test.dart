import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/events/pending_event.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = PlayDraft(pitchEventId: 'pitch-1', batterId: 'opp-1');
  final landed = base.copyWith(
    landing: FieldCoord(x: -45, y: 120),
    trajectory: Trajectory.LINE,
  );

  group('ballAt and rollEnd — one answer for where the ball is', () {
    test('the second tap wins, then the last touch, then the landing', () {
      final landed = base.copyWith(
        landing: FieldCoord(x: 0, y: 200),
        trajectory: Trajectory.LINE,
      );
      // Nothing moved it: the ball is where it came down, and there is no
      // streak to draw.
      expect(landed.ballAt?.y, 200);
      expect(landed.rollEnd, isNull, reason: 'a zero-length roll is no roll');

      // The scorer traced it into the corner.
      final traced = landed.copyWith(endedAt: FieldCoord(x: -110, y: 190));
      expect(traced.ballAt?.x, -110);
      expect(traced.rollEnd?.x, -110);

      // A boot leaves the ball at the booter's feet, and that is where the
      // next fielder over has to go — not back to the landing.
      final booted = landed.addingTouch(
        7,
        TouchType.BOOTED,
        location: FieldCoord(x: -60, y: 210),
      );
      expect(booted.ballAt?.x, -60);
    });

    test('a home run has a landing and no roll', () {
      // It does not travel after landing; it arrives. Which is also why the
      // field behind `rollEnd` is absent on every one of them.
      final homer = base.copyWith(
        landing: FieldCoord(x: 20, y: 260),
        trajectory: Trajectory.FLY,
      );
      expect(homer.rollEnd, isNull);
    });
  });

  group('invitesSacrifice (§13.6) — the two calls only a scorer can make', () {
    PlayDraft flyScoring({required bool caught, int to = 4}) {
      var draft = base.copyWith(
        landing: FieldCoord(x: 0, y: 240),
        trajectory: Trajectory.FLY,
      );
      if (caught) draft = draft.addingTouch(8, TouchType.CAUGHT);
      return draft.addingLeg('r3', from: 3, to: to);
    }

    test('a dropped fly that scores a runner asks — clause (2)', () {
      // The rule credits a sac fly on either of two clauses, and the second —
      // dropped, with a runner scoring who could have scored had it been
      // caught — is judgment. Nothing in the record says whether she would
      // have made it, so without this question clause (2) has no way in.
      expect(flyScoring(caught: false).invitesSacrifice, isTrue);
    });

    test('a caught fly does not ask — clause (1) derives', () {
      // Caught with a runner scoring has no judgment in it, so asking would
      // be a question with a known answer.
      expect(flyScoring(caught: true).invitesSacrifice, isFalse);
    });

    test('a dropped fly with nobody scoring does not ask', () {
      // A runner merely advancing is not the clause: it turns on a run.
      expect(flyScoring(caught: false, to: 3).invitesSacrifice, isFalse);
    });

    test('a ground ball never asks, caught or not', () {
      final grounder = base
          .copyWith(
            landing: FieldCoord(x: 0, y: 90),
            trajectory: Trajectory.GROUND,
          )
          .addingLeg('r3', from: 3, to: 4);
      expect(grounder.invitesSacrifice, isFalse);
    });

    test('a bunt still asks on any runner moved up, not only a run', () {
      // The bunt case is unchanged and deliberately wider: moving a runner
      // along is the whole point of a sacrifice bunt.
      final bunt = base
          .copyWith(
            landing: FieldCoord(x: -18, y: 24),
            trajectory: Trajectory.BUNT,
          )
          .addingLeg('r1', from: 1, to: 2);
      expect(bunt.invitesSacrifice, isTrue);
    });
  });

  group('PlayDraft JSON (the §15.5 journal format)', () {
    test('round-trips a full chain', () {
      final draft = landed
          .copyWith(endedAt: FieldCoord(x: -80, y: 180), offWall: true)
          .addingTouch(6, TouchType.BOOTED)
          .addingLeg('opp-1', from: 0, to: 1)
          .addingRuleCall(CallType.OBSTRUCTION)
          .addingOut('opp-9', atBase: 3, how: How.TAG, putoutKey: 0);

      final back = PlayDraft.fromJson(draft.toJson());
      expect(back.pitchEventId, 'pitch-1');
      expect(back.landing!.x, -45);
      expect(back.endedAt!.y, 180);
      expect(back.offWall, isTrue);
      expect(back.nextKey, 4);
      expect(back.entries, hasLength(4));
      final touch = back.entries[0] as TouchEntry;
      expect(touch.touchType, TouchType.BOOTED);
      final leg = back.entries[1] as LegEntry;
      expect(leg.enabledByKey, 0);
      expect((back.entries[2] as RuleCallEntry).callType, CallType.OBSTRUCTION);
      final out = back.entries[3] as OutEntry;
      expect(out.how, How.TAG);
      expect(out.putoutKey, 0);
    });

    test('round-trips the empty draft the surface opens with', () {
      final back = PlayDraft.fromJson(base.toJson());
      expect(back.landing, isNull);
      expect(back.entries, isEmpty);
      expect(back.nextKey, 0);
    });
  });

  group('chain mechanics', () {
    test('legs auto-attribute to the latest misplay or ⚖, never to clean '
        'touches (§13.4, §15.3)', () {
      var draft = landed
          .addingTouch(9, TouchType.FIELDED)
          .addingLeg('opp-1', from: 0, to: 1);
      expect((draft.entries[1] as LegEntry).enabledByKey, isNull);

      draft = draft
          .addingTouch(6, TouchType.WILD_THROW)
          .addingLeg('opp-1', from: 1, to: 2);
      expect((draft.entries[3] as LegEntry).enabledByKey, 2);

      draft = draft
          .addingRuleCall(CallType.OBSTRUCTION)
          .addingLeg('opp-1', from: 2, to: 3);
      expect((draft.entries[5] as LegEntry).enabledByKey, 4);
    });

    test('cascade pushes stay unattributed', () {
      final draft = landed
          .addingTouch(6, TouchType.BOOTED)
          .addingLeg('opp-1', from: 0, to: 1)
          .addingLeg('opp-9', from: 1, to: 2, attribute: false);
      expect((draft.entries[1] as LegEntry).enabledByKey, 0);
      expect((draft.entries[2] as LegEntry).enabledByKey, isNull);
    });

    test('displayBase follows legs; isOut follows outs', () {
      final draft = landed
          .addingLeg('opp-1', from: 0, to: 1)
          .addingLeg('opp-1', from: 1, to: 3)
          .addingOut('opp-9', atBase: 3, how: How.TAG);
      expect(draft.displayBase('opp-1', 0), 3);
      expect(draft.displayBase('opp-2', 1), 1);
      expect(draft.isOut('opp-9'), isTrue);
      expect(draft.isOut('opp-1'), isFalse);
    });

    test('securedTouch: held after a clean touch, loose after a misplay or '
        'a throw away', () {
      final held = landed.addingTouch(6, TouchType.FIELDED);
      expect(held.securedTouch!.key, 0);

      // The ball got away: nobody holds it until someone plays it again.
      expect(held.addingTouch(6, TouchType.WILD_THROW).securedTouch, isNull);
      expect(landed.addingTouch(6, TouchType.BOOTED).securedTouch, isNull);
      expect(landed.addingTouch(8, TouchType.DROPPED).securedTouch, isNull);
    });

    test('removing an entry orphans links to it, never retargets', () {
      final draft = landed
          .addingTouch(6, TouchType.BOOTED)
          .addingLeg('opp-1', from: 0, to: 1)
          .addingOut('opp-9', atBase: 2, how: How.FORCE, putoutKey: 0)
          .removingEntry(0);
      expect(draft.entries, hasLength(2));
      expect((draft.entries[0] as LegEntry).enabledByKey, isNull);
      expect((draft.entries[1] as OutEntry).putoutKey, isNull);
    });

    test('landingIsCaught is the first touch, chips flip it (§4.2)', () {
      expect(landed.landingIsCaught, isFalse);
      final caught = landed.addingTouch(8, TouchType.CAUGHT);
      expect(caught.landingIsCaught, isTrue);
      final dropped = caught.updatingEntry(
        0,
        (e) => (e as TouchEntry).copyWith(touchType: TouchType.DROPPED),
      );
      expect(dropped.landingIsCaught, isFalse);
    });
  });

  group('recordingFielderPlay (§15.1 v0.43: the fielder drag)', () {
    final spot = FieldCoord(x: 30, y: 160);

    test('assumes the landing at her spot only when no path was drawn', () {
      final assumed = base
          .copyWith(trajectory: Trajectory.FLY)
          .recordingFielderPlay(8, spot: spot, touchType: TouchType.CAUGHT);
      expect(assumed.landing!.x, 30);
      expect(assumed.movedFielders[8]!.y, 160);
      final touch = assumed.entries.whereType<TouchEntry>().single;
      expect(touch.touchType, TouchType.CAUGHT);
      expect(touch.location!.x, 30);

      final drawn = landed.recordingFielderPlay(
        6,
        spot: spot,
        touchType: TouchType.FIELDED,
      );
      expect(drawn.landing!.x, -45, reason: 'the drawn path wins');
    });

    test('"missed it" moves her and places the ball, but records no touch', () {
      final missed = base
          .copyWith(trajectory: Trajectory.GROUND)
          .recordingFielderPlay(4, spot: spot);
      expect(missed.entries, isEmpty);
      expect(missed.landing!.x, 30);
      expect(missed.movedFielders[4], isNotNull);
    });

    test('round-trips movedFielders and touch locations through JSON', () {
      final draft = base
          .copyWith(trajectory: Trajectory.FLY)
          .recordingFielderPlay(8, spot: spot, touchType: TouchType.DROPPED);
      final back = PlayDraft.fromJson(draft.toJson());
      expect(back.movedFielders[8]!.x, 30);
      expect((back.entries.single as TouchEntry).location!.y, 160);
    });
  });

  group('the batter runs on contact (§15.1 v0.43)', () {
    // The walk-up as the surface actually builds it (§15.1): the leg plus
    // the count that marks it provisional. Without the count nothing can
    // tell her presumed reach from one the scorer authored.
    final walkedUp = landed
        .addingLeg('opp-1', from: 0, to: 1, attribute: false)
        .copyWith(openingLegCount: 1);

    test('an out at the reached base absorbs the leg — no phantom advance', () {
      final draft = walkedUp.addingOut('opp-1', atBase: 1, how: How.FORCE);
      expect(draft.entries.whereType<LegEntry>(), isEmpty);
      expect((draft.entries.single as OutEntry).atBase, 1);
    });

    test('an out at a farther base keeps the legs — play 03 stretching', () {
      final draft = walkedUp.addingOut('opp-1', atBase: 2, how: How.TAG);
      expect(draft.entries.whereType<LegEntry>(), hasLength(1));
    });

    test('a caught first touch voids the walk-up and records the fly out', () {
      final draft = walkedUp
          .addingLeg('r1', from: 1, to: 2, attribute: false) // the push
          .copyWith(trajectory: Trajectory.FLY)
          .recordingFielderPlay(
            8,
            spot: FieldCoord(x: 0, y: 150),
            touchType: TouchType.CAUGHT,
          );
      expect(draft.entries.whereType<LegEntry>(), isEmpty);
      final out = draft.entries.whereType<OutEntry>().single;
      expect(out.how, How.FLY_OUT);
      expect(out.putoutKey, draft.entries.whereType<TouchEntry>().single.key);
      expect(draft.landingIsCaught, isTrue);
    });

    test('a misplay first touch raises the reach question, it does not '
        'answer it (§13.2 v0.56)', () {
      final draft = walkedUp.recordingFielderPlay(
        6,
        spot: FieldCoord(x: -50, y: 95),
        touchType: TouchType.BOOTED,
      );
      expect(draft.entries, hasLength(2));
      final reach = draft.entries.whereType<LegEntry>().single;
      // Untouched: claiming it here derived hit-vs-error from an answer the
      // scorer never gave, and destroyed the clean single a later misplay
      // only added to.
      expect(reach.enabledByKey, isNull);
      expect(draft.reachNeedsAnswer, isTrue);
    });

    test('resolvingReach links the reach to the first-touch misplay, in '
        'narrative order (§13.2 v0.56)', () {
      final draft = walkedUp
          .recordingFielderPlay(
            6,
            spot: FieldCoord(x: -50, y: 95),
            touchType: TouchType.BOOTED,
          )
          .resolvingReach(earned: false);

      final touch = draft.entries[0] as TouchEntry;
      expect(touch.touchType, TouchType.BOOTED);
      // The touch, then the reach it explains — never the other way round.
      final reach = draft.entries[1] as LegEntry;
      expect(reach.enabledByKey, touch.key);
      expect(draft.reachNeedsAnswer, isFalse);

      final events = draft.toEvents();
      expect(events.map((e) => e.type), [
        'BallInPlay',
        'FielderTouch',
        'RunnerAdvance',
      ]);
      expect(events[2].payload['reason'], 'error');
    });

    test('resolvingReach with the base earned leaves the reach a hit '
        '(§13.2 v0.56)', () {
      final draft = walkedUp
          .recordingFielderPlay(
            6,
            spot: FieldCoord(x: -50, y: 95),
            touchType: TouchType.BOOTED,
          )
          .resolvingReach(earned: true);

      final reach = draft.entries.whereType<LegEntry>().single;
      expect(reach.enabledByKey, isNull);
      expect(draft.reachNeedsAnswer, isFalse);
      // A misplay nobody linked to anything charges nothing and the hit
      // stands — the pair one boolean could never express.
      expect(draft.toEvents()[2].payload['reason'], 'batted_ball');
    });

    test('a clean first touch leaves the reach alone — the hit stands', () {
      final draft = walkedUp.recordingFielderPlay(
        9,
        spot: FieldCoord(x: 110, y: 180),
        touchType: TouchType.FIELDED,
      );
      final reach = draft.entries.whereType<LegEntry>().single;
      expect(reach.enabledByKey, isNull);
    });
  });

  group('affirmingSafe (§15.1 v0.43)', () {
    test('an answered SAFE re-authors the walk-up: same base, no longer a '
        'presumption', () {
      final walkedUp = landed
          .addingLeg('opp-1', from: 0, to: 1, attribute: false)
          .copyWith(openingLegCount: 1);
      expect(walkedUp.isProvisional('opp-1'), isTrue);

      final settled = walkedUp.affirmingSafe('opp-1');
      expect(settled.isProvisional('opp-1'), isFalse);
      final leg = settled.entries.whereType<LegEntry>().single;
      expect(leg.from, 0);
      expect(leg.to, 1);
      expect(settled.displayBase('opp-1', 0), 1);
    });

    test('a runner the scorer already resolved is left alone', () {
      final resolved = landed.addingLeg('opp-1', from: 0, to: 2);
      expect(resolved.affirmingSafe('opp-1').entries, hasLength(1));
    });
  });

  group('beyond the fence (§16.3)', () {
    const origins = <RunnerSlot>[
      (runnerId: 'opp-1', base: 0),
      (runnerId: 'r1', base: 1),
      (runnerId: 'r3', base: 3),
    ];

    test('a home run scores everyone aboard, replacing the walk-up', () {
      final draft = landed
          .addingLeg('opp-1', from: 0, to: 1, attribute: false)
          .addingLeg('r1', from: 1, to: 2, attribute: false)
          .copyWith(offWall: true)
          .resolvingHomeRun(origins);

      final legs = draft.entries.whereType<LegEntry>().toList();
      expect(legs, hasLength(3));
      expect(legs.every((leg) => leg.to == 4), isTrue);
      // Lead runner first, per §11.3's forced-chain ordering.
      expect(legs.map((leg) => leg.from), [3, 1, 0]);
      expect(
        draft.offWall,
        isFalse,
        reason: 'a ball that went over never hit the wall',
      );

      final events = draft.toEvents();
      final advances = events.where((e) => e.type == 'RunnerAdvance');
      expect(advances, hasLength(3));
      expect(
        advances.every((e) => e.payload['reason'] == 'batted_ball'),
        isTrue,
        reason:
            'the hit itself: the batter derives home_run and every run '
            'aboard is an RBI',
      );
    });

    test('the ground-rule sibling awards two bases apiece, capped at home', () {
      final draft = landed.resolvingGroundRuleDouble(origins);
      final legs = draft.entries.whereType<LegEntry>().toList();
      expect(
        legs.map((leg) => (leg.runnerId, leg.from, leg.to)),
        containsAll([('opp-1', 0, 2), ('r1', 1, 3), ('r3', 3, 4)]),
      );
      expect(draft.toEvents().last.payload['reason'], 'ground_rule');
    });

    test('touches survive the award — she can play it at the wall and still '
        'watch it go', () {
      final draft = landed
          .addingTouch(8, TouchType.FIELDED)
          .resolvingHomeRun(origins);
      expect(draft.entries.whereType<TouchEntry>(), hasLength(1));
    });
  });

  group('attachingRuleCall (§15.3 v0.43: ⚖ on the consequence)', () {
    test('inserts before a leg and re-attributes it — reason derives', () {
      final draft = landed
          .addingLeg('opp-1', from: 0, to: 2)
          .attachingRuleCall(0, CallType.OBSTRUCTION);
      expect(draft.entries, hasLength(2));
      final call = draft.entries[0] as RuleCallEntry;
      expect(call.callType, CallType.OBSTRUCTION);
      final leg = draft.entries[1] as LegEntry;
      expect(leg.enabledByKey, call.key);

      final events = draft.toEvents();
      expect(events.map((e) => e.type), [
        'BallInPlay',
        'RuleCall',
        'RunnerAdvance',
      ]);
      expect(events[2].payload['reason'], 'obstruction');
    });

    test('inserts before an out and its how becomes interference', () {
      final draft = landed
          .addingOut('opp-1', atBase: 2, how: How.TAG)
          .attachingRuleCall(0, CallType.INTERFERENCE_RUNNER);
      final out = draft.entries[1] as OutEntry;
      expect(out.how, How.INTERFERENCE);
      expect(draft.entries[0], isA<RuleCallEntry>());
    });
  });

  group('cascadeRunnerMove: runners never pass each other', () {
    test('bases-loaded single: the whole chain walks up, run included', () {
      final moves = cascadeRunnerMove(
        [
          (runnerId: 'b', base: 0),
          (runnerId: 'r1', base: 1),
          (runnerId: 'r2', base: 2),
          (runnerId: 'r3', base: 3),
        ],
        movedId: 'b',
        to: 1,
      );
      expect(moves, [
        (runnerId: 'b', from: 0, to: 1),
        (runnerId: 'r1', from: 1, to: 2),
        (runnerId: 'r2', from: 2, to: 3),
        (runnerId: 'r3', from: 3, to: 4),
      ]);
    });

    test('double with R1: the batter passing first pushes R1 to third', () {
      final moves = cascadeRunnerMove(
        [(runnerId: 'b', base: 0), (runnerId: 'r1', base: 1)],
        movedId: 'b',
        to: 2,
      );
      expect(moves, [
        (runnerId: 'b', from: 0, to: 2),
        (runnerId: 'r1', from: 1, to: 3),
      ]);
    });

    test('no force, no push: R2 holds on a single behind her', () {
      final moves = cascadeRunnerMove(
        [(runnerId: 'b', base: 0), (runnerId: 'r2', base: 2)],
        movedId: 'b',
        to: 1,
      );
      expect(moves, [(runnerId: 'b', from: 0, to: 1)]);
    });

    test('a scored leader is out of the way; a mid-draft leader ahead '
        'absorbs the chain', () {
      expect(
        cascadeRunnerMove(
          [(runnerId: 'b', base: 0), (runnerId: 'r1', base: 4)],
          movedId: 'b',
          to: 1,
        ),
        hasLength(1),
      );
      expect(
        cascadeRunnerMove(
          [(runnerId: 'b', base: 0), (runnerId: 'r1', base: 3)],
          movedId: 'b',
          to: 1,
        ),
        hasLength(1),
      );
    });

    test('trailing runners never move automatically', () {
      final moves = cascadeRunnerMove(
        [(runnerId: 'b', base: 0), (runnerId: 'r1', base: 1)],
        movedId: 'r1',
        to: 3,
      );
      expect(moves, [(runnerId: 'r1', from: 1, to: 3)]);
    });
  });

  group('toEvents (§15.5 atomic commit, §13 derivations)', () {
    test('refuses an incomplete draft — the ✓ should never have fired', () {
      expect(base.toEvents, throwsStateError);
      expect(base.committable, isFalse);
      expect(landed.committable, isTrue);
    });

    test('play 01 shape: dropped liner, out anyway — order, links, and the '
        '§13.2 OE default', () {
      final draft = landed
          .addingTouch(6, TouchType.FIELDED)
          .updatingEntry(
            0,
            (e) => (e as TouchEntry).copyWith(touchType: TouchType.DROPPED),
          )
          .addingTouch(6, TouchType.FIELDED)
          .addingTouch(3, TouchType.RECEIVED_THROW)
          .addingOut('opp-1', atBase: 1, how: How.FORCE, putoutKey: 2);

      final events = draft.toEvents();
      expect(events.map((e) => e.type), [
        'BallInPlay',
        'FielderTouch',
        'FielderTouch',
        'FielderTouch',
        'RunnerOut',
      ]);
      expect(events[0].payload['landingIsCaught'], isFalse);
      expect(events[1].payload['touchType'], 'dropped');
      expect(events[1].payload['anchorEventId'], localRef('bip'));
      expect(events[4].payload['how'], 'force');
      expect(events[4].payload['putoutTouchId'], localRef('e2'));
    });

    test('play 02 shape: boot then wild throw — leg reasons derive from '
        'their enablers, mechanically', () {
      final draft = base
          .copyWith(
            landing: FieldCoord(x: -50, y: 95),
            trajectory: Trajectory.GROUND,
          )
          .addingTouch(6, TouchType.BOOTED)
          .addingLeg('opp-1', from: 0, to: 1)
          .addingTouch(6, TouchType.WILD_THROW)
          .addingLeg('opp-1', from: 1, to: 3);

      final events = draft.toEvents();
      expect(events.map((e) => e.type), [
        'BallInPlay',
        'FielderTouch',
        'RunnerAdvance',
        'FielderTouch',
        'RunnerAdvance',
      ]);
      expect(events[2].payload['reason'], 'error');
      expect(events[2].payload['enabledByTouchId'], localRef('e0'));
      expect(events[4].payload['reason'], 'wild_throw');
      expect(events[4].payload['enabledByTouchId'], localRef('e2'));
    });

    test('obstruction legs carry their reason without a touch link', () {
      final draft = landed
          .addingTouch(6, TouchType.BOOTED)
          .addingRuleCall(CallType.OBSTRUCTION)
          .addingLeg('opp-1', from: 0, to: 2);

      final events = draft.toEvents();
      expect(events[2].payload['callType'], 'obstruction');
      expect(events[3].payload['reason'], 'obstruction');
      expect(events[3].payload['enabledByTouchId'], isNull);
    });

    test('caught first touch: landingIsCaught true on the wire', () {
      final draft = base
          .copyWith(
            landing: FieldCoord(x: 0, y: 150),
            trajectory: Trajectory.FLY,
          )
          .addingTouch(8, TouchType.CAUGHT)
          .addingOut('opp-1', atBase: 1, how: How.FLY_OUT, putoutKey: 0);
      final events = draft.toEvents();
      expect(events[0].payload['landingIsCaught'], isTrue);
      expect(events[2].payload['how'], 'fly_out');
    });
  });
}
