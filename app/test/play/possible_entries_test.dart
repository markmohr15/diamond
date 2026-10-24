import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/possible_entries.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// DIA-019 slice H: a menu offers only what this touch could have been,
/// derived in one place. These are the rows of the table the slice was
/// approved against.
void main() {
  PlayDraft batted(Trajectory trajectory) => const PlayDraft(
    pitchEventId: 'p',
    batterId: 'b',
  ).copyWith(landing: FieldCoord(x: -50, y: 95), trajectory: trajectory);

  const betweenPitches = PlayDraft(
    pitchEventId: 'p',
    batterId: '',
    battedBall: false,
  );

  TouchEntry last(PlayDraft draft) =>
      draft.entries.whereType<TouchEntry>().last;

  group('retypeChoices', () {
    test('a reception: dropped, missed, or missed tag — never a wild throw '
        'of her own', () {
      final draft = batted(Trajectory.GROUND)
          .addingTouch(6, TouchType.FIELDED)
          .addingTouch(3, TouchType.RECEIVED_THROW);
      expect(retypeChoices(draft, last(draft)), [
        TouchType.DROPPED,
        TouchType.MISSED_CATCH,
        TouchType.TAG_MISSED,
      ]);
      expect(throwerInto(draft, last(draft))?.position, 6);
    });

    test(
      'a grounder fielded in the infield: booted, deflected, missed tag',
      () {
        final draft = batted(
          Trajectory.GROUND,
        ).addingTouch(6, TouchType.FIELDED);
        expect(retypeChoices(draft, last(draft)), [
          TouchType.BOOTED,
          TouchType.DEFLECTED,
          TouchType.TAG_MISSED,
        ]);
      },
    );

    test('an outfielder cannot deflect', () {
      final draft = batted(Trajectory.GROUND).addingTouch(8, TouchType.FIELDED);
      expect(
        retypeChoices(draft, last(draft)),
        isNot(contains(TouchType.DEFLECTED)),
      );
    });

    test('a fly caught in flight: dropped and missed tag, and a pop-up '
        'never caroms', () {
      final draft = batted(Trajectory.POPUP).addingTouch(6, TouchType.CAUGHT);
      expect(retypeChoices(draft, last(draft)), [
        TouchType.DROPPED,
        TouchType.TAG_MISSED,
      ]);
    });

    test('an infield liner can carom', () {
      final draft = batted(Trajectory.LINE).addingTouch(5, TouchType.CAUGHT);
      expect(retypeChoices(draft, last(draft)), contains(TouchType.DEFLECTED));
    });

    test('between pitches the catcher cannot be retyped to booted', () {
      final draft = betweenPitches.addingTouch(2, TouchType.FIELDED);
      expect(retypeChoices(draft, last(draft)), [
        TouchType.BOBBLED,
        TouchType.TAG_MISSED,
      ]);
    });

    test('a node already a wild throw shows only what it is', () {
      final draft = batted(
        Trajectory.GROUND,
      ).addingTouch(6, TouchType.WILD_THROW);
      expect(retypeChoices(draft, last(draft)), [TouchType.WILD_THROW]);
    });

    test('the node keeps its own type on the menu once retyped', () {
      final draft = batted(Trajectory.GROUND).addingTouch(6, TouchType.BOOTED);
      expect(retypeChoices(draft, last(draft)), [
        TouchType.BOOTED,
        TouchType.DEFLECTED,
      ]);
    });
  });

  group('one vocabulary, two surfaces', () {
    test('every misplay the popup offers in a state, the retype menu '
        'offers for a touch made in it', () {
      final cases = <(PlayDraft, TouchType, BallState)>[
        (batted(Trajectory.GROUND), TouchType.FIELDED, BallState.onGround),
        (batted(Trajectory.LINE), TouchType.CAUGHT, BallState.inFlight),
        (batted(Trajectory.FLY), TouchType.CAUGHT, BallState.inFlight),
        (betweenPitches, TouchType.FIELDED, BallState.loosePitch),
      ];
      for (final (base, type, state) in cases) {
        for (var position = 1; position <= 10; position++) {
          final draft = base.addingTouch(position, type);
          expect(ballStateAt(draft, last(draft)), state);
          final popupMisplays =
              ballPlayChoices(
                state,
                position: position,
                trajectory: draft.trajectory,
              ).where(
                (t) =>
                    t != null &&
                    t != TouchType.CAUGHT &&
                    t != TouchType.FIELDED,
              );
          expect(
            retypeChoices(draft, last(draft)).toSet(),
            containsAll(popupMisplays),
            reason: '$state at $position',
          );
          expect(
            retypeChoices(
              draft,
              last(draft),
            ).toSet().difference({...popupMisplays, TouchType.TAG_MISSED}),
            isEmpty,
            reason:
                'nothing the popup could not have entered, $state at '
                '$position',
          );
        }
      }
    });
  });

  group('possibleHows', () {
    List<How> hows(
      PlayDraft draft,
      String runnerId,
      int atBase,
      BaseState bases, {
      int? editingKey,
    }) => [
      for (final (_, _, how) in possibleHows(
        draft,
        runnerId,
        atBase,
        bases,
        editingKey: editingKey,
      ))
        how,
    ];

    const r1OnFirst = BaseState(first: 'r1');

    test('between pitches: never a force, and the two dead-ball outs', () {
      expect(hows(betweenPitches, 'r1', 2, r1OnFirst), [
        How.CAUGHT_STEALING,
        How.PICKED_OFF,
        How.TAG,
        How.LEFT_EARLY,
        How.LOOK_BACK_RULE,
      ]);
    });

    test('a runner after a catch owes a retouch: no force', () {
      final draft = batted(Trajectory.FLY).addingTouch(8, TouchType.CAUGHT);
      expect(hows(draft, 'r1', 2, r1OnFirst), [How.TAG, How.APPEAL]);
    });

    test('6-4-3: the force at second stays a force although the batter is '
        'retired after it', () {
      final draft = batted(Trajectory.GROUND)
          .addingTouch(6, TouchType.FIELDED)
          .addingTouch(4, TouchType.RECEIVED_THROW)
          .addingOut('r1', atBase: 2, how: How.FORCE)
          .addingTouch(3, TouchType.RECEIVED_THROW)
          .addingOut('b', atBase: 1, how: How.FORCE);
      final forceAtSecond = draft.entries.whereType<OutEntry>().first;
      expect(
        hows(draft, 'r1', 2, r1OnFirst, editingKey: forceAtSecond.key),
        contains(How.FORCE),
      );
      // Without the ordering rule, the later out removes it.
      expect(hows(draft, 'r1', 2, r1OnFirst), isNot(contains(How.FORCE)));
    });

    test('3-6: the batter retired first takes the force off second', () {
      final draft = batted(Trajectory.GROUND)
          .addingTouch(3, TouchType.FIELDED)
          .addingOut('b', atBase: 1, how: How.FORCE);
      expect(hows(draft, 'r1', 2, r1OnFirst), [How.TAG]);
    });
  });

  group('infield fly (DIA-019 H2)', () {
    const r1r2 = BaseState(first: 'r1', second: 'r2');
    final pop = batted(Trajectory.POPUP);

    test('offered for a fly or pop-up, under two out, first and second '
        'occupied, once it has come down', () {
      expect(offersInfieldFly(pop, outs: 0, bases: r1r2), isTrue);
      expect(
        offersInfieldFly(batted(Trajectory.FLY), outs: 1, bases: r1r2),
        isTrue,
      );
      expect(
        offersInfieldFly(batted(Trajectory.LINE), outs: 0, bases: r1r2),
        isFalse,
        reason: 'never a liner',
      );
      expect(
        offersInfieldFly(batted(Trajectory.BUNT), outs: 0, bases: r1r2),
        isFalse,
        reason: 'never a bunt',
      );
      expect(offersInfieldFly(pop, outs: 2, bases: r1r2), isFalse);
      expect(
        offersInfieldFly(pop, outs: 0, bases: const BaseState(first: 'r1')),
        isFalse,
      );
      expect(
        offersInfieldFly(
          const PlayDraft(
            pitchEventId: 'p',
            batterId: 'b',
          ).copyWith(trajectory: Trajectory.POPUP),
          outs: 0,
          bases: r1r2,
        ),
        isFalse,
        reason: 'no landing yet',
      );
      expect(
        offersInfieldFly(pop.declaringInfieldFly(), outs: 0, bases: r1r2),
        isFalse,
        reason: 'already declared',
      );
    });

    test('declaring it retires the batter by the call and takes the walk-up '
        'off — and with it every force', () {
      final declared = pop
          .addingLeg('b', from: 0, to: 1)
          .addingLeg('r1', from: 1, to: 2)
          .addingLeg('r2', from: 2, to: 3)
          .declaringInfieldFly();

      expect(declared.entries.whereType<LegEntry>(), isEmpty);
      final call = declared.entries.whereType<RuleCallEntry>().single;
      expect(call.callType, CallType.INFIELD_FLY);
      final out = declared.entries.whereType<OutEntry>().single;
      expect(out.runnerId, 'b');
      expect(out.how, How.INFIELD_FLY);
      expect(out.enabledByCallKey, call.key);
      expect(out.putoutKey, isNull, reason: 'nobody has touched it');

      final hows = [
        for (final (_, _, how) in possibleHows(declared, 'r1', 2, r1r2)) how,
      ];
      expect(hows, isNot(contains(How.FORCE)));
    });

    test('caught after the call: one out, putout to the catch', () {
      final caught = pop
          .declaringInfieldFly()
          .recordingFielderPlay(
            6,
            spot: FieldCoord(x: -25, y: 95),
            touchType: TouchType.CAUGHT,
          )
          .withInfieldFlyPutout();
      final out = caught.entries.whereType<OutEntry>().single;
      expect(out.how, How.INFIELD_FLY);
      expect(caught.entryByKey(out.putoutKey!), isA<TouchEntry>());
    });

    test('called after the catch: the fly out becomes the infield fly', () {
      final declared = pop
          .recordingFielderPlay(
            6,
            spot: FieldCoord(x: -25, y: 95),
            touchType: TouchType.CAUGHT,
          )
          .declaringInfieldFly();
      final out = declared.entries.whereType<OutEntry>().single;
      expect(out.how, How.INFIELD_FLY);
      expect(
        out.putoutKey,
        declared.entries.whereType<TouchEntry>().single.key,
      );
    });

    test('dropped: the putout is hers — she is who would have caught it', () {
      final dropped = pop
          .declaringInfieldFly()
          .recordingFielderPlay(
            4,
            spot: FieldCoord(x: 20, y: 70),
            touchType: TouchType.DROPPED,
          )
          .withInfieldFlyPutout();
      final out = dropped.entries.whereType<OutEntry>().single;
      final putout = dropped.entryByKey(out.putoutKey!)! as TouchEntry;
      expect(putout.position, 4);
    });

    test('removing the call takes its out off, or gives the catch back its '
        'fly out', () {
      final uncaught = pop.declaringInfieldFly();
      final call = uncaught.entries.whereType<RuleCallEntry>().single;
      expect(
        uncaught.removingEntry(call.key).entries.whereType<OutEntry>(),
        isEmpty,
      );

      final caught = pop
          .recordingFielderPlay(
            6,
            spot: FieldCoord(x: -25, y: 95),
            touchType: TouchType.CAUGHT,
          )
          .declaringInfieldFly();
      final caughtCall = caught.entries.whereType<RuleCallEntry>().single;
      final out = caught
          .removingEntry(caughtCall.key)
          .entries
          .whereType<OutEntry>()
          .single;
      expect(out.how, How.FLY_OUT);
      expect(out.enabledByCallKey, isNull);
    });
  });

  test('infield is 1–6, and the fourth outfielder is an outfielder', () {
    expect(
      [for (var p = 1; p <= 10; p++) isInfield(p)],
      [...List.filled(6, true), ...List.filled(4, false)],
    );
  });
}
