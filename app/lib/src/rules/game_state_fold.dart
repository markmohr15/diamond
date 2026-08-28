import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/back_inference.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/pitch_count_effect.dart';

/// Pure fold: the visible, logically-ordered event stream -> [GameState]
/// (spec §5). Pass [startingFrom] to resume on top of a cached
/// GameStateSnapshot (§7) instead of genesis — folding a tail on top of a
/// snapshot must always produce the same result as folding the whole
/// stream from scratch.
GameState foldGameState(
  List<GameEvent> visibleLogicalOrder, {
  GameState startingFrom = GameState.initial,
}) {
  var state = startingFrom;
  for (final event in visibleLogicalOrder) {
    state = _foldOne(state, event);
  }
  return state;
}

GameState _foldOne(GameState state, GameEvent event) {
  switch (event.type) {
    case 'LineupSet':
      return _foldLineupSet(state, event);
    case 'InningHalfStart':
      return _foldInningHalfStart(state, event);
    case 'InningHalfEnd':
      return _foldInningHalfEnd(state, event);
    case 'PitchThrown':
      return _foldPitchThrown(state, event);
    case 'CountCorrection':
      return _foldCountCorrection(state, event);
    case 'RunnerOut':
      return _foldRunnerOut(state, event);
    case 'RunnerAdvance':
      return _foldRunnerAdvance(state, event);
    default:
      return state; // not relevant to GameState (spec §5)
  }
}

GameState _foldLineupSet(GameState state, GameEvent event) {
  final payload = LineupSet.fromJson(event.payload);

  final order = Map<String, List<String>>.from(state.battingOrderByTeam);
  order[payload.teamId] = payload.battingOrder;

  final runs = Map<String, int>.from(state.runsByTeam)
    ..putIfAbsent(payload.teamId, () => 0);

  final nextIndex = Map<String, int>.from(state.nextBatterIndexByTeam)
    ..putIfAbsent(payload.teamId, () => 0);

  return state.copyWith(
    battingOrderByTeam: order,
    runsByTeam: runs,
    nextBatterIndexByTeam: nextIndex,
  );
}

GameState _foldInningHalfStart(GameState state, GameEvent event) {
  final payload = InningHalfStart.fromJson(event.payload);

  var next = state.copyWith(
    balls: 0,
    strikes: 0,
    uncertainCount: false,
    pendingSpanEvents: const [],
    spanStartBalls: 0,
    spanStartStrikes: 0,
    outs: 0,
    inning: payload.inning,
    half: payload.half,
    battingTeamId: payload.battingTeamId,
    bases: BaseState.empty,
    halfEnded: false,
    halfEndReason: null,
    currentBatterId: null,
    currentPitcherId: null,
  );

  // The snapshot is a performance cache of cumulative state (spec §7) —
  // per-half state above is always reset regardless of whether one exists.
  final snapshot = payload.snapshot;
  if (snapshot != null) {
    next = next.copyWith(
      runsByTeam: Map<String, int>.from(snapshot.runsByTeam),
      nextBatterIndexByTeam: Map<String, int>.from(
        snapshot.nextBatterIndexByTeam,
      ),
      pitchCountByPitcher: Map<String, int>.from(snapshot.pitchCountByPitcher),
      inferredPitchEffects: Map<String, InferredPitchEffect>.from(
        snapshot.inferredPitchEffects,
      ),
    );
  }

  return next;
}

GameState _foldInningHalfEnd(GameState state, GameEvent event) {
  if (state.halfEnded) return state; // first cause wins
  final payload = InningHalfEnd.fromJson(event.payload);
  return state.copyWith(halfEnded: true, halfEndReason: payload.reason);
}

GameState _foldPitchThrown(GameState state, GameEvent event) {
  final payload = PitchThrown.fromJson(event.payload);

  var working = state;
  if (working.currentBatterId != payload.batterId) {
    working = working.copyWith(
      balls: 0,
      strikes: 0,
      uncertainCount: false,
      pendingSpanEvents: const [],
      spanStartBalls: 0,
      spanStartStrikes: 0,
      currentBatterId: payload.batterId,
    );
  }
  working = working.copyWith(currentPitcherId: payload.pitcherId);

  // Every recorded pitch counts toward the pitcher's total, unconditionally.
  // `no_pitch` used to be the exception and is gone (v0.51): nothing ever
  // wrote it, so it existed only as three exclusions like this one.
  final counts = Map<String, int>.from(working.pitchCountByPitcher);
  counts[payload.pitcherId] = (counts[payload.pitcherId] ?? 0) + 1;
  working = working.copyWith(pitchCountByPitcher: counts);

  if (payload.outcome == Outcome.UNKNOWN) {
    return working.copyWith(
      uncertainCount: true,
      pendingSpanEvents: [...working.pendingSpanEvents, event],
    );
  }

  final effect = applyPitchCountEffect(
    working.balls,
    working.strikes,
    payload.outcome,
  );
  working = working.copyWith(
    balls: effect.balls,
    strikes: effect.strikes,
    pendingSpanEvents: [...working.pendingSpanEvents, event],
  );

  if (effect.endsPlateAppearance) {
    final team = working.battingTeamId;
    final nextIndex = Map<String, int>.from(working.nextBatterIndexByTeam);
    if (team != null) {
      nextIndex[team] = (nextIndex[team] ?? 0) + 1;
    }
    working = working.copyWith(
      nextBatterIndexByTeam: nextIndex,
      balls: 0,
      strikes: 0,
      uncertainCount: false,
      pendingSpanEvents: const [],
      spanStartBalls: 0,
      spanStartStrikes: 0,
      currentBatterId: null,
    );
  }

  return working;
}

GameState _foldCountCorrection(GameState state, GameEvent event) {
  final payload = CountCorrection.fromJson(event.payload);

  // Replay starts at the span's certain base — state.balls/strikes already
  // include the span's known pitches, which the replay applies itself.
  final inferred = inferBackward(
    span: state.pendingSpanEvents,
    startBalls: state.spanStartBalls,
    startStrikes: state.spanStartStrikes,
    checkpointBalls: payload.balls,
    checkpointStrikes: payload.strikes,
  );

  final effects = inferred == null
      ? state.inferredPitchEffects
      : {...state.inferredPitchEffects, ...inferred};

  return state.copyWith(
    balls: payload.balls,
    strikes: payload.strikes,
    uncertainCount: false,
    pendingSpanEvents: const [],
    spanStartBalls: payload.balls,
    spanStartStrikes: payload.strikes,
    inferredPitchEffects: effects,
  );
}

GameState _foldRunnerOut(GameState state, GameEvent event) {
  final payload = RunnerOut.fromJson(event.payload);
  final outs = state.outs + 1;

  var next = state.copyWith(
    outs: outs,
    bases: state.bases.removingRunner(payload.runnerId),
  );

  if (!next.halfEnded && outs >= 3) {
    next = next.copyWith(
      halfEnded: true,
      halfEndReason: InningHalfEndReason.THREE_OUTS,
    );
  }

  return next;
}

GameState _foldRunnerAdvance(GameState state, GameEvent event) {
  final payload = RunnerAdvance.fromJson(event.payload);

  // "Survived a play" bookkeeping only — no base change (spec §4.3).
  if (payload.from == payload.to) return state;

  var bases = state.bases.removingRunner(payload.runnerId);

  if (payload.to == 4) {
    final team = state.battingTeamId;
    var runs = state.runsByTeam;
    if (team != null) {
      runs = Map<String, int>.from(runs)
        ..update(team, (v) => v + 1, ifAbsent: () => 1);
    }
    return state.copyWith(bases: bases, runsByTeam: runs);
  }

  bases = switch (payload.to) {
    1 => bases.copyWith(first: payload.runnerId),
    2 => bases.copyWith(second: payload.runnerId),
    3 => bases.copyWith(third: payload.runnerId),
    _ => bases,
  };
  return state.copyWith(bases: bases);
}
