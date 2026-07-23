import 'package:diamond/src/events/generated/events.dart';

/// Occupied bases, keyed by runner. Cleared/moved only by [RunnerOut] and
/// [RunnerAdvance] — never inferred from a [PitchThrown] outcome.
class BaseState {
  const BaseState({this.first, this.second, this.third});

  static const empty = BaseState();

  final String? first;
  final String? second;
  final String? third;

  BaseState copyWith({
    Object? first = _unset,
    Object? second = _unset,
    Object? third = _unset,
  }) {
    return BaseState(
      first: first == _unset ? this.first : first as String?,
      second: second == _unset ? this.second : second as String?,
      third: third == _unset ? this.third : third as String?,
    );
  }

  /// Removes [runnerId] from whichever base they occupy, if any. A no-op
  /// when the runner isn't on base — e.g. a strikeout's [RunnerOut] never
  /// occupied a base to begin with.
  BaseState removingRunner(String runnerId) {
    return BaseState(
      first: first == runnerId ? null : first,
      second: second == runnerId ? null : second,
      third: third == runnerId ? null : third,
    );
  }

  /// Field-by-field comparison — not `operator ==`, so this class doesn't
  /// need an `@immutable` annotation (and the `meta` dependency that'd add).
  /// Test-only: not used by production code, only by projector assertions.
  bool sameAs(BaseState other) =>
      first == other.first && second == other.second && third == other.third;

  @override
  String toString() =>
      'BaseState(first: $first, second: $second, third: $third)';
}

const _unset = Object();

/// Pure projection of the event stream (spec §5): count, outs, half-inning,
/// bases, score, batter due, pitch counts. Every field here is a fold
/// output — nothing is a positional cache, so BattingOrderAdjusted (M2) will
/// slot in without a redesign.
class GameState {
  const GameState({
    this.balls = 0,
    this.strikes = 0,
    this.uncertainCount = false,
    this.pendingSpanEvents = const [],
    this.spanStartBalls = 0,
    this.spanStartStrikes = 0,
    this.inferredPitchEffects = const {},
    this.outs = 0,
    this.inning = 1,
    this.half,
    this.battingTeamId,
    this.bases = BaseState.empty,
    this.halfEnded = false,
    this.halfEndReason,
    this.currentBatterId,
    this.currentPitcherId,
    this.battingOrderByTeam = const {},
    this.runsByTeam = const {},
    this.nextBatterIndexByTeam = const {},
    this.pitchCountByPitcher = const {},
  });

  /// The state before any event has been folded.
  static const initial = GameState();

  final int balls;
  final int strikes;
  final bool uncertainCount;

  /// Every PitchThrown event (known and unknown outcomes alike) since the
  /// last certain state — AB start or the last CountCorrection in this AB
  /// — in order. The span back-inference replays against (spec §12.5);
  /// cleared at the next AB boundary or CountCorrection either way.
  final List<GameEvent> pendingSpanEvents;

  /// The certain count at the start of [pendingSpanEvents]: 0-0 at an AB
  /// boundary, the checkpoint's values after a CountCorrection. Back-
  /// inference must replay the span from here — not from [balls]/[strikes],
  /// which already include every known pitch in the span, so replaying
  /// from them would apply those knowns twice.
  final int spanStartBalls;
  final int spanStartStrikes;

  /// Pitch event ids a CountCorrection's back-inference resolved uniquely,
  /// to the schema-defined [InferredPitchEffect] (spec §12.5). Never a
  /// fabricated [PitchThrown] outcome — we don't claim to know whether it
  /// was a called strike, a swinging strike, or a foul, only which side of
  /// the count it moved.
  final Map<String, InferredPitchEffect> inferredPitchEffects;

  final int outs;
  final int inning;
  final Half? half;
  final String? battingTeamId;
  final BaseState bases;

  /// True once outs reach 3 or an explicit InningHalfEnd is folded, per
  /// §4.4. Folding never stops or rejects further events once this is set
  /// — it's a signal for the UI to have moved on, not a guard the
  /// projection enforces itself.
  final bool halfEnded;
  final InningHalfEndReason? halfEndReason;

  final String? currentBatterId;
  final String? currentPitcherId;

  final Map<String, List<String>> battingOrderByTeam;
  final Map<String, int> runsByTeam;
  final Map<String, int> nextBatterIndexByTeam;
  final Map<String, int> pitchCountByPitcher;

  /// The playerId due up for [teamId], derived from that team's LineupSet
  /// and how many plate appearances it has completed — never cached
  /// positionally (spec §4.4 design constraint).
  String? batterDue(String teamId) {
    final order = battingOrderByTeam[teamId];
    if (order == null || order.isEmpty) return null;
    final index = nextBatterIndexByTeam[teamId] ?? 0;
    return order[index % order.length];
  }

  GameState copyWith({
    int? balls,
    int? strikes,
    bool? uncertainCount,
    List<GameEvent>? pendingSpanEvents,
    int? spanStartBalls,
    int? spanStartStrikes,
    Map<String, InferredPitchEffect>? inferredPitchEffects,
    int? outs,
    int? inning,
    Object? half = _unset,
    Object? battingTeamId = _unset,
    BaseState? bases,
    bool? halfEnded,
    Object? halfEndReason = _unset,
    Object? currentBatterId = _unset,
    Object? currentPitcherId = _unset,
    Map<String, List<String>>? battingOrderByTeam,
    Map<String, int>? runsByTeam,
    Map<String, int>? nextBatterIndexByTeam,
    Map<String, int>? pitchCountByPitcher,
  }) {
    return GameState(
      balls: balls ?? this.balls,
      strikes: strikes ?? this.strikes,
      uncertainCount: uncertainCount ?? this.uncertainCount,
      pendingSpanEvents: pendingSpanEvents ?? this.pendingSpanEvents,
      spanStartBalls: spanStartBalls ?? this.spanStartBalls,
      spanStartStrikes: spanStartStrikes ?? this.spanStartStrikes,
      inferredPitchEffects: inferredPitchEffects ?? this.inferredPitchEffects,
      outs: outs ?? this.outs,
      inning: inning ?? this.inning,
      half: half == _unset ? this.half : half as Half?,
      battingTeamId: battingTeamId == _unset
          ? this.battingTeamId
          : battingTeamId as String?,
      bases: bases ?? this.bases,
      halfEnded: halfEnded ?? this.halfEnded,
      halfEndReason: halfEndReason == _unset
          ? this.halfEndReason
          : halfEndReason as InningHalfEndReason?,
      currentBatterId: currentBatterId == _unset
          ? this.currentBatterId
          : currentBatterId as String?,
      currentPitcherId: currentPitcherId == _unset
          ? this.currentPitcherId
          : currentPitcherId as String?,
      battingOrderByTeam: battingOrderByTeam ?? this.battingOrderByTeam,
      runsByTeam: runsByTeam ?? this.runsByTeam,
      nextBatterIndexByTeam:
          nextBatterIndexByTeam ?? this.nextBatterIndexByTeam,
      pitchCountByPitcher: pitchCountByPitcher ?? this.pitchCountByPitcher,
    );
  }
}
