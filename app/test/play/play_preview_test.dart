import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_preview.dart';
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
      previewPlayLine(visible, played),
      'b1 singled to right-center. On a fielding error by the RF, b1 '
      'advanced to second.',
    );
  });

  test('nothing to say until the play can be committed', () {
    final visible = [pitch('p1', Outcome.IN_PLAY)];
    const draft = PlayDraft(pitchEventId: 'p1', batterId: 'b1');
    expect(previewPlayLine(visible, draft), isNull);
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
    final said = previewPlayLine(visible, steal);
    expect(said, isNotNull);
    expect(said, contains('stole second'));
  });
}
