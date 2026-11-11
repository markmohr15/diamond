import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/ui/field_canvas/field_controls.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back one names what it removes (§15.5 v0.60), read as the difference
/// between two step snapshots.
void main() {
  const labels = {'b1': 'B', 'r2': '2'};
  const opening = PlayDraft(pitchEventId: 'p1', batterId: 'b1');

  String step(PlayDraft before, PlayDraft after) =>
      describeStep(before: before, after: after, runnerLabels: labels);

  PlayDraft withEntries(List<PlayEntry> entries) => PlayDraft(
    pitchEventId: 'p1',
    batterId: 'b1',
    trajectory: Trajectory.POPUP,
    entries: entries,
  );

  test('the trajectory, by its built label', () {
    expect(step(opening, withEntries(const [])), 'Popup');
  });

  test('a touch: position and what she did — 14A\'s "SS catch"', () {
    expect(
      step(
        withEntries(const []),
        withEntries(const [
          TouchEntry(key: 0, position: 6, touchType: TouchType.CAUGHT),
        ]),
      ),
      'SS catch',
    );
  });

  test('a throw adds a touch and a leg together; the touch names it', () {
    expect(
      step(
        withEntries(const []),
        withEntries(const [
          TouchEntry(key: 0, position: 3, touchType: TouchType.RECEIVED_THROW),
          LegEntry(key: 1, runnerId: 'r2', from: 2, to: 3),
        ]),
      ),
      '1B takes the throw',
    );
  });

  test('a runner leg: 15B\'s "R2 to 3rd"', () {
    expect(
      step(
        withEntries(const []),
        withEntries(const [LegEntry(key: 0, runnerId: 'r2', from: 2, to: 3)]),
      ),
      'R2 to 3rd',
    );
  });

  test('an out names the batter as the batter', () {
    expect(
      step(
        withEntries(const []),
        withEntries(const [
          OutEntry(key: 0, runnerId: 'b1', atBase: 1, how: How.FORCE),
        ]),
      ),
      'Batter out at 1B',
    );
  });

  test('a ball made loose by tapping the holder', () {
    const held = PlayDraft(
      pitchEventId: 'p1',
      batterId: '',
      battedBall: false,
      heldBy: 2,
    );
    const loose = PlayDraft(
      pitchEventId: 'p1',
      batterId: '',
      battedBall: false,
    );
    expect(step(held, loose), 'Ball loose');
  });
}
