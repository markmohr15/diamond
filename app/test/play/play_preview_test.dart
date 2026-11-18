import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_preview.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../rules/test_helpers.dart';

/// The result in words beside the ✓ (§15.5, DIA-018b-2): the play log's own
/// sentence, said for a play that hasn't been committed.
void main() {
  late EventBuilder b;
  setUp(() => b = EventBuilder());

  GameEvent pitch(String id, Outcome outcome) =>
      b.pitch(id: id, batterId: 'b1', pitcherId: 'p1', outcome: outcome);

  test("Mark's popup: single and an error, before it is saved", () {
    final visible = [pitch('p1', Outcome.IN_PLAY)];
    final draft = const PlayDraft(pitchEventId: 'p1', batterId: 'b1')
        .copyWith(
          landing: FieldCoord(x: 36, y: 120),
          trajectory: Trajectory.POPUP,
        )
        .addingTouch(9, TouchType.BOOTED, location: FieldCoord(x: 40, y: 120))
        .addingLeg('b1', from: 0, to: 1, attribute: false);
    final misplay = draft.entries.whereType<TouchEntry>().single.key;
    final played = draft.addingLeg(
      'b1',
      from: 1,
      to: 2,
      attribute: false,
      enabledByKey: misplay,
    );

    expect(
      previewPlayLine(visible, played, before: BaseState.empty, outs: 0),
      'b1 singled to right-center. On a fielding error by the RF, b1 '
      'advanced to second.',
    );
  });

  test('nothing to say until the play can be committed', () {
    final visible = [pitch('p1', Outcome.IN_PLAY)];
    const draft = PlayDraft(pitchEventId: 'p1', batterId: 'b1');
    expect(
      previewPlayLine(visible, draft, before: BaseState.empty, outs: 0),
      isNull,
    );
  });

  test('between pitches it says only what the entry adds', () {
    final visible = [
      b.make(
        id: 'lineup',
        type: 'LineupSet',
        payload: const {
          'teamId': 'opp',
          'battingOrder': ['r1', 'b1'],
        },
      ),
      pitch('p1', Outcome.BALL),
    ];
    final steal =
        const PlayDraft(
          pitchEventId: 'p1',
          batterId: '',
          battedBall: false,
        ).addingLeg(
          'r1',
          from: 1,
          to: 2,
          attribute: false,
          reason: RunnerAdvanceReason.STOLEN_BASE,
        );
    final said = previewPlayLine(
      visible,
      steal,
      before: const BaseState(first: 'r1'),
      outs: 0,
    );
    expect(said, isNotNull);
    expect(said, contains('stole second'));
  });

  group("what the ✓ settles without asking is said before it's pressed", () {
    // r1 singled to first; b1 is up with a runner on.
    List<GameEvent> runnerOnFirst() => [
      b.lineupSet(id: 'lineup', teamId: 'opp', battingOrder: ['r1', 'b1']),
      b.pitch(
        id: 'p0',
        batterId: 'r1',
        pitcherId: 'p1',
        outcome: Outcome.IN_PLAY,
      ),
      b.ballInPlay(id: 'bip0', pitchEventId: 'p0'),
      b.runnerAdvance(
        id: 'adv0',
        runnerId: 'r1',
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.BATTED_BALL,
      ),
      pitch('p1', Outcome.IN_PLAY),
    ];
    const onFirst = BaseState(first: 'r1');

    // The walk-up as the surface builds it: the leg plus the count that
    // marks it a presumption.
    PlayDraft walkedUp() => const PlayDraft(pitchEventId: 'p1', batterId: 'b1')
        .copyWith(
          landing: FieldCoord(x: -20, y: 60),
          trajectory: Trajectory.GROUND,
        )
        .addingLeg('b1', from: 0, to: 1, attribute: false)
        .copyWith(openingLegCount: 1);

    test("Mark's grounder: the lead runner forced at second reads as the "
        "fielder's choice the ✓ will record, with the batter never moved", () {
      final forced = walkedUp()
          .addingTouch(
            6,
            TouchType.FIELDED,
            location: FieldCoord(x: -20, y: 63),
          )
          .addingTouch(4, TouchType.RECEIVED_THROW);
      final putout = forced.entries.whereType<TouchEntry>().last.key;
      final draft = forced.addingOut(
        'r1',
        atBase: 2,
        how: How.FORCE,
        putoutKey: putout,
      );
      expect(draft.provisionalReach, isNotNull, reason: 'batter not moved');

      final said = previewPlayLine(
        runnerOnFirst(),
        draft,
        before: onFirst,
        outs: 0,
      );
      expect(said, contains("fielder's choice"));
      expect(said, isNot(contains('singled')));
    });

    test('a clean single says single: the only possible answer', () {
      final draft = walkedUp().addingTouch(
        8,
        TouchType.FIELDED,
        location: FieldCoord(x: 0, y: 200),
      );
      final said = previewPlayLine(
        [pitch('p1', Outcome.IN_PLAY)],
        draft,
        before: BaseState.empty,
        outs: 0,
      );
      expect(said, contains('singled'));
    });

    test('blank when the ✓ would ask how she reached', () {
      final draft = walkedUp().addingTouch(
        6,
        TouchType.BOOTED,
        location: FieldCoord(x: -20, y: 63),
      );
      expect(
        previewPlayLine(
          [pitch('p1', Outcome.IN_PLAY)],
          draft,
          before: BaseState.empty,
          outs: 0,
        ),
        isNull,
      );
    });
  });
}
