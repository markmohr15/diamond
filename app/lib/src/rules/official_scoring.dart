import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/game_state_fold.dart';
import 'package:diamond/src/rules/pitch_count_effect.dart';

/// The §13.2 misplay vocabulary — the only touch types an official error
/// can ever be charged against. `deflected` and `tag_missed` are physical
/// facts but not error candidates.
const Set<TouchType> misplayTouchTypes = {
  TouchType.DROPPED,
  TouchType.BOBBLED,
  TouchType.BOOTED,
  TouchType.WILD_THROW,
  TouchType.MISSED_CATCH,
};

/// Official-scoring category of a charged error, derived from the physical
/// touch type — never entered by the scorer (spec §13.1).
enum OfficialErrorKind {
  fielding('fielding'),
  throwing('throwing'),
  catching('catching');

  const OfficialErrorKind(this.wire);

  /// The string form fixtures and serialized output use.
  final String wire;
}

/// Why the misplay had a consequence (§13.2's clause (b)) — which of the
/// three consequence tests charged this error.
enum OfficialErrorBasis {
  reached('reached'),
  advance('advance'),
  runnerSurvived('runner_survived'),
  prolongedAtBat('prolonged_at_bat');

  const OfficialErrorBasis(this.wire);

  /// The string form fixtures and serialized output use.
  final String wire;
}

/// One charged official error (projection output, spec §13.2).
class OfficialError {
  const OfficialError({
    required this.touchEventId,
    required this.position,
    required this.kind,
    required this.basis,
  });

  final String touchEventId;
  final int position;
  final OfficialErrorKind kind;
  final OfficialErrorBasis basis;
}

/// One misplay for the development ledger (§13.1 layer 1) — logged whether
/// or not an official error was charged.
class MisplayRecord {
  const MisplayRecord({
    required this.touchEventId,
    required this.position,
    required this.touchType,
    required this.ordinaryEffort,
  });

  final String touchEventId;
  final int position;
  final TouchType touchType;

  /// Resolved judgment: the explicit flag if recorded, else the §13.2
  /// default (`booted`/`missed_catch`/`dropped` -> true), else null —
  /// "prompt the scorer", unresolved, and never charged while null.
  final bool? ordinaryEffort;
}

/// The batter's official result for one plate appearance.
class BatterOutcome {
  const BatterOutcome({
    required this.batterId,
    required this.scoring,
    required this.hit,
    required this.rbi,
  });

  final String batterId;

  /// 'out', 'single'..'home_run', 'reached_on_error', or the wire form of
  /// a non-batted reach reason ('walk', 'dropped_third_strike', ...).
  final String scoring;
  final bool hit;
  final int rbi;
}

/// Official scoring derived from a play/half-inning stream (spec §13):
/// errors, misplay ledger, batter results, putouts/assists, pitcher
/// strikeouts, and conditional unearned-run flags. Pure projection — the
/// scorer records physics; everything here is recomputable forever.
class OfficialScoring {
  const OfficialScoring({
    required this.errors,
    required this.misplays,
    required this.batterOutcomes,
    required this.putoutsByPosition,
    required this.assistsByPosition,
    required this.strikeoutsByPitcher,
    required this.unearnedConditions,
  });

  final List<OfficialError> errors;
  final List<MisplayRecord> misplays;
  final List<BatterOutcome> batterOutcomes;
  final Map<int, int> putoutsByPosition;
  final Map<int, int> assistsByPosition;
  final Map<String, int> strikeoutsByPitcher;

  /// runnerId -> conditional flag consumed by §13.3 and surfaced in the
  /// UI: 'unearned_if_scores' (reach enabled by a charged error) or
  /// 'unearned_if_scores_this_pa' (at-bat prolonged by a charged error).
  final Map<String, String> unearnedConditions;

  /// Test-only: not used by production code, only by test assertions.
  BatterOutcome? outcomeFor(String batterId) {
    for (final o in batterOutcomes) {
      if (o.batterId == batterId) return o;
    }
    return null;
  }
}

class _AdvanceRecord {
  _AdvanceRecord(this.eventId, this.payload, this.batterAtTime);

  final String eventId;
  final RunnerAdvance payload;
  final String? batterAtTime;
}

class _OutRecord {
  _OutRecord(this.eventId, this.payload);

  final String eventId;
  final RunnerOut payload;
}

class _TouchRecord {
  _TouchRecord(this.eventId, this.payload, this.batterAtTime);

  final String eventId;
  final FielderTouch payload;
  final String? batterAtTime;
}

/// Derives [OfficialScoring] from the visible, logically-ordered stream.
/// [startingFrom] carries the pre-play count/outs context (fixture setups,
/// mid-inning starts); pass the same state given to [foldGameState].
///
/// Touch chains are grouped by `FielderTouch.ballInPlayEventId` treated as
/// an *opaque* anchor key — it may reference a BallInPlay, a PitchThrown
/// (D3K sequences, §14 play 5), or a not-yet-modeled anchor like a pickoff
/// (§14 play 6). Chains never require the anchor to resolve.
OfficialScoring foldOfficialScoring(
  List<GameEvent> visibleLogicalOrder, {
  GameState startingFrom = GameState.initial,
}) {
  // Pass A: one event-ordered sweep collecting typed records plus the
  // per-event batter context ("whose play is this"). The batter of record
  // is the most recent pitch's batterId — deliberately NOT
  // GameState.currentBatterId, which nulls the moment a PA ends while the
  // resulting play (throws, outs, advances) is still unfolding.
  final ballInPlayById = <String, BallInPlay>{};
  final touches = <_TouchRecord>[];
  final advances = <_AdvanceRecord>[];
  final outs = <_OutRecord>[];
  final batterOrder = <String>[];
  final strikeouts = <String, int>{};

  var state = startingFrom;
  var batterOfRecord = startingFrom.currentBatterId;

  for (final event in visibleLogicalOrder) {
    switch (event.type) {
      case 'PitchThrown':
        final pitch = PitchThrown.fromJson(event.payload);
        batterOfRecord = pitch.batterId;
        if (batterOrder.isEmpty || batterOrder.last != pitch.batterId) {
          batterOrder.add(pitch.batterId);
        }
        if (pitch.outcome != Outcome.UNKNOWN &&
            pitch.outcome != Outcome.NO_PITCH) {
          // Count context comes from the running GameState fold, so this
          // stays correct across CountCorrection checkpoints.
          final effect = applyPitchCountEffect(
            state.balls,
            state.strikes,
            pitch.outcome,
          );
          if (effect.endsPlateAppearance && effect.strikesAdvanced) {
            strikeouts.update(pitch.pitcherId, (v) => v + 1, ifAbsent: () => 1);
          }
        }
      case 'BallInPlay':
        ballInPlayById[event.id] = BallInPlay.fromJson(event.payload);
      case 'FielderTouch':
        touches.add(
          _TouchRecord(
            event.id,
            FielderTouch.fromJson(event.payload),
            batterOfRecord,
          ),
        );
      case 'RunnerAdvance':
        advances.add(
          _AdvanceRecord(
            event.id,
            RunnerAdvance.fromJson(event.payload),
            batterOfRecord,
          ),
        );
      case 'RunnerOut':
        outs.add(_OutRecord(event.id, RunnerOut.fromJson(event.payload)));
    }
    state = foldGameState([event], startingFrom: state);
  }

  // Pass B: misplay ledger, then §13.2 error charging: ordinaryEffort
  // resolves true AND the misplay had a consequence.
  final misplays = <MisplayRecord>[];
  final errors = <OfficialError>[];

  for (final touch in touches) {
    final t = touch.payload;
    if (!misplayTouchTypes.contains(t.touchType)) continue;

    final resolvedEffort = t.ordinaryEffort ?? _defaultOrdinaryEffort(t);
    misplays.add(
      MisplayRecord(
        touchEventId: touch.eventId,
        position: t.position,
        touchType: t.touchType,
        ordinaryEffort: resolvedEffort,
      ),
    );
    if (resolvedEffort != true) continue;

    final basis = _consequenceBasis(touch, advances, ballInPlayById);
    if (basis == null) continue; // misplay without consequence: no error

    errors.add(
      OfficialError(
        touchEventId: touch.eventId,
        position: t.position,
        kind: _kindOf(t.touchType),
        basis: basis,
      ),
    );
  }

  final chargedTouchIds = {for (final e in errors) e.touchEventId};

  // Pass C: batter outcomes, RBIs, putouts/assists, unearned conditions —
  // everything that needs to know which errors were actually charged.
  final batterOutcomes = <BatterOutcome>[
    for (final batterId in batterOrder)
      _batterOutcome(batterId, advances, outs, chargedTouchIds),
  ];

  final putouts = <int, int>{};
  final assists = <int, int>{};
  final touchById = {for (final t in touches) t.eventId: t.payload};
  for (final out in outs) {
    final putoutTouch = touchById[out.payload.putoutTouchId];
    if (putoutTouch == null) continue; // no touch data (e.g. strikeout)
    putouts.update(putoutTouch.position, (v) => v + 1, ifAbsent: () => 1);
    final credited = <int>{};
    for (final t in touches) {
      if (t.eventId == out.payload.putoutTouchId) break;
      final p = t.payload;
      if (p.ballInPlayEventId != putoutTouch.ballInPlayEventId) continue;
      if (p.position == putoutTouch.position) continue;
      if (misplayTouchTypes.contains(p.touchType)) continue;
      credited.add(p.position);
    }
    for (final position in credited) {
      assists.update(position, (v) => v + 1, ifAbsent: () => 1);
    }
  }

  final unearned = <String, String>{};
  for (final advance in advances) {
    final a = advance.payload;
    if (a.from == 0 && chargedTouchIds.contains(a.enabledByTouchId)) {
      unearned[a.runnerId] = 'unearned_if_scores';
    }
  }
  for (final error in errors) {
    if (error.basis != OfficialErrorBasis.prolongedAtBat) continue;
    final touch = touches.firstWhere((t) => t.eventId == error.touchEventId);
    final batter = touch.batterAtTime;
    if (batter != null && !unearned.containsKey(batter)) {
      unearned[batter] = 'unearned_if_scores_this_pa';
    }
  }

  return OfficialScoring(
    errors: errors,
    misplays: misplays,
    batterOutcomes: batterOutcomes,
    putoutsByPosition: putouts,
    assistsByPosition: assists,
    strikeoutsByPitcher: strikeouts,
    unearnedConditions: unearned,
  );
}

/// §13.2 defaults: `booted`, `missed_catch`, `dropped` resolve true when
/// the scorer recorded no judgment. Everything else stays null —
/// "prompt the scorer" — and is never charged until resolved.
bool? _defaultOrdinaryEffort(FielderTouch touch) {
  switch (touch.touchType) {
    case TouchType.BOOTED:
    case TouchType.MISSED_CATCH:
    case TouchType.DROPPED:
      return true;
    // ignore: no_default_cases - the misplay set is filtered before this.
    default:
      return null;
  }
}

OfficialErrorKind _kindOf(TouchType type) {
  switch (type) {
    case TouchType.BOOTED:
    case TouchType.BOBBLED:
      return OfficialErrorKind.fielding;
    case TouchType.WILD_THROW:
      return OfficialErrorKind.throwing;
    case TouchType.DROPPED:
    case TouchType.MISSED_CATCH:
      return OfficialErrorKind.catching;
    // ignore: no_default_cases - the misplay set is filtered before this.
    default:
      throw ArgumentError('not a misplay touch type: $type');
  }
}

/// §13.2 clause (b): did the misplay have a consequence? The first
/// `enabledByTouchId`-linked advance decides the basis (reach, ordinary
/// advance, or a from==to rundown survival); with no linked advance, a
/// dropped foul ball prolonged the at-bat.
OfficialErrorBasis? _consequenceBasis(
  _TouchRecord touch,
  List<_AdvanceRecord> advances,
  Map<String, BallInPlay> ballInPlayById,
) {
  for (final advance in advances) {
    final a = advance.payload;
    if (a.enabledByTouchId != touch.eventId) continue;
    if (a.from == 0) return OfficialErrorBasis.reached;
    if (a.from == a.to) return OfficialErrorBasis.runnerSurvived;
    return OfficialErrorBasis.advance;
  }
  if (touch.payload.touchType == TouchType.DROPPED) {
    final anchor = ballInPlayById[touch.payload.ballInPlayEventId];
    if (anchor != null && !anchor.fair) {
      return OfficialErrorBasis.prolongedAtBat;
    }
  }
  return null;
}

const _hitByBase = {1: 'single', 2: 'double', 3: 'triple', 4: 'home_run'};

const _nonBattedReachReasons = {
  RunnerAdvanceReason.WALK,
  RunnerAdvanceReason.HBP,
  RunnerAdvanceReason.DROPPED_THIRD_STRIKE,
  RunnerAdvanceReason.FIELDERS_CHOICE,
  RunnerAdvanceReason.CATCHER_INTERFERENCE,
};

BatterOutcome _batterOutcome(
  String batterId,
  List<_AdvanceRecord> advances,
  List<_OutRecord> outs,
  Set<String> chargedTouchIds,
) {
  final own = [
    for (final a in advances)
      if (a.payload.runnerId == batterId) a,
  ];
  final reach = own.where((a) => a.payload.from == 0).firstOrNull;

  // RBIs: runs scoring on this batter's play that weren't gifted by a
  // charged error (batted-ball runs, including the batter's own homer).
  var rbi = 0;
  for (final a in advances) {
    if (a.batterAtTime != batterId) continue;
    if (a.payload.to != 4) continue;
    if (chargedTouchIds.contains(a.payload.enabledByTouchId)) continue;
    if (a.payload.reason == RunnerAdvanceReason.BATTED_BALL) rbi++;
  }

  if (reach == null) {
    final wasOut = outs.any((o) => o.payload.runnerId == batterId);
    return BatterOutcome(
      batterId: batterId,
      scoring: wasOut ? 'out' : 'batting',
      hit: false,
      rbi: rbi,
    );
  }

  final reason = reach.payload.reason;
  if (_nonBattedReachReasons.contains(reason)) {
    return BatterOutcome(
      batterId: batterId,
      scoring: runnerAdvanceReasonValues.reverse[reason]!,
      hit: false,
      rbi: rbi,
    );
  }

  // Hit vs. error (§13.2): the judgment lives on the first touch. If the
  // reach was enabled by a *charged* error the batter reached on it; an
  // uncharged misplay (ordinaryEffort false) means the reach was a hit.
  if (chargedTouchIds.contains(reach.payload.enabledByTouchId)) {
    return BatterOutcome(
      batterId: batterId,
      scoring: 'reached_on_error',
      hit: false,
      rbi: rbi,
    );
  }

  // Hit base: the farthest the batter got without a charged error's help.
  var base = reach.payload.to;
  for (final a in own) {
    if (a.payload.from == 0) continue;
    if (chargedTouchIds.contains(a.payload.enabledByTouchId)) continue;
    if (a.payload.to > base) base = a.payload.to;
  }
  return BatterOutcome(
    batterId: batterId,
    scoring: _hitByBase[base]!,
    hit: true,
    rbi: rbi,
  );
}
