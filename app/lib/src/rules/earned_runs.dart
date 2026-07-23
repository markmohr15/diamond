import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/official_scoring.dart';

/// Whether a scored run survives the §13.3 reconstruction.
enum RunRuling { earned, unearned }

/// Earned-run reconstruction (spec §13.3): replays the half-inning as if
/// charged errors and passed balls hadn't happened, and rules each scored
/// run (keyed by its `RunnerAdvance{to: 4}` event id) earned or unearned.
///
/// Removal semantics, strictly per the spec's "removes error-enabled
/// advances and error-prolonged at-bats":
/// - A reach (`from == 0`) enabled by a charged error is removed — the
///   batter would have been out, so the runner is tainted AND the
///   reconstruction counts a hypothetical out.
/// - A reach by a batter whose at-bat was prolonged by a charged error
///   (the dropped foul, §14 play 4) is removed the same way — the at-bat
///   should already have ended in an out.
/// - Any *later* advance enabled by a charged error, or scoring via a
///   passed ball, breaks that runner's chain: with the advance removed the
///   runner never occupied the base they scored from, so the run is ruled
///   unearned. This is deliberately the strict reading — no counterfactual
///   "would they have scored anyway" simulation; if field testing demands
///   the official-scorer benefit-of-the-doubt version, that judgment is
///   exactly what the coming scoring-override events are for.
/// - Runs scoring after the reconstruction reaches three outs are
///   unearned regardless of how the runner got around.
///
/// Wild pitches are the pitcher's own doing and never launder a run.
Map<String, RunRuling> reconstructEarnedRuns(
  List<GameEvent> visibleLogicalOrder, {
  GameState startingFrom = GameState.initial,
  OfficialScoring? scoring,
}) {
  final official =
      scoring ??
      foldOfficialScoring(visibleLogicalOrder, startingFrom: startingFrom);
  final chargedTouchIds = {for (final e in official.errors) e.touchEventId};
  final prolongingTouchIds = {
    for (final e in official.errors)
      if (e.basis == OfficialErrorBasis.prolongedAtBat) e.touchEventId,
  };

  final rulings = <String, RunRuling>{};
  // Runners removed from the reconstruction entirely (their reach was
  // error-enabled): scoring is unearned and their real outs don't count
  // again — the reconstruction already charged their hypothetical out.
  final removedRunners = <String>{};
  // Runners still legitimately aboard but whose base chain was broken by
  // an error-enabled advance: scoring is unearned, outs still real.
  final chainBrokenRunners = <String>{};

  var reconOuts = startingFrom.outs;
  var batterOfRecord = startingFrom.currentBatterId;
  var atBatProlonged = false;

  for (final event in visibleLogicalOrder) {
    switch (event.type) {
      case 'PitchThrown':
        final pitch = PitchThrown.fromJson(event.payload);
        if (pitch.batterId != batterOfRecord) {
          batterOfRecord = pitch.batterId;
          atBatProlonged = false;
        }
      case 'FielderTouch':
        if (prolongingTouchIds.contains(event.id)) {
          atBatProlonged = true;
        }
      case 'RunnerOut':
        final out = RunnerOut.fromJson(event.payload);
        if (!removedRunners.contains(out.runnerId)) {
          reconOuts++;
        }
      case 'RunnerAdvance':
        final advance = RunnerAdvance.fromJson(event.payload);
        final errorEnabled = chargedTouchIds.contains(advance.enabledByTouchId);

        if (advance.from == 0) {
          final prolongedReach =
              atBatProlonged && advance.runnerId == batterOfRecord;
          if (errorEnabled || prolongedReach) {
            removedRunners.add(advance.runnerId);
            reconOuts++; // the out the error erased
          }
          if (advance.to != 4) continue;
        } else if (advance.to != 4) {
          if (errorEnabled) chainBrokenRunners.add(advance.runnerId);
          continue;
        }

        // Scoring advance.
        final unearned =
            removedRunners.contains(advance.runnerId) ||
            chainBrokenRunners.contains(advance.runnerId) ||
            errorEnabled ||
            advance.reason == RunnerAdvanceReason.PASSED_BALL ||
            reconOuts >= 3;
        rulings[event.id] = unearned ? RunRuling.unearned : RunRuling.earned;
    }
  }

  return rulings;
}
