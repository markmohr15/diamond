import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/game_state_fold.dart';
import 'package:diamond/src/rules/pitch_count_effect.dart';

/// The §13.2 misplay vocabulary — the only touch types an official error
/// can ever be charged against, and the single definition the whole app
/// reads (the draft's amber rendering and leg reasons included).
///
/// `tag_missed` is one of them (v0.43): recording a missed tag *is* the
/// claim that she muffed it, and anything worth putting in the play-by-play
/// has to be chargeable. A runner who beats the tag on a great slide is not
/// a missed tag — she is simply safe, and nothing is recorded at all.
/// `deflected` stays out: the ball that hit her with no play to be made is
/// a physical fact, never fault.
const Set<TouchType> misplayTouchTypes = {
  TouchType.DROPPED,
  TouchType.BOBBLED,
  TouchType.BOOTED,
  TouchType.WILD_THROW,
  TouchType.MISSED_CATCH,
  TouchType.TAG_MISSED,
};

/// Failing to receive a *pitch* (§13.2) — one touch type, because receiving
/// a pitch is binary. Whether she got a glove on it or it went straight past
/// her changes nothing that is scored, and the scorer is never asked to say
/// which: the question at entry is "passed ball?", yes or no. `missed_catch`
/// is the spelling precisely because it claims less than `dropped`, which
/// would assert she had it and lost it.
///
/// A misplay of this type anchored to a `PitchThrown` rather than a
/// `BallInPlay` is a passed ball — its own statistic, and never an official
/// error; a wild pitch is the same moment with no touch recorded at all.
/// Two misplays that *can* anchor to a pitch stay chargeable: `wild_throw`,
/// because a throw is a thrown ball (the catcher who airmails first base on
/// a dropped third strike is still charged, §14 play #5), and `tag_missed`,
/// because muffing a tag on the batter-runner is a play on her rather than a
/// failure to receive.
const Set<TouchType> pitchReceivingTouchTypes = {TouchType.MISSED_CATCH};

/// Official-scoring category of a charged error, derived from the physical
/// touch type — never entered by the scorer (spec §13.1).
enum OfficialErrorKind {
  fielding('fielding'),
  throwing('throwing'),
  catching('catching'),

  /// Catcher's interference (§4.1 v0.43): an error by rule — E2 with no
  /// misplay touch behind it.
  interference('interference');

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

/// Which half of §13.2's WP/PB pair a pitch that got away was.
enum PitchGetawayKind {
  /// The pitcher's doing — the ball was so high, wide, or low that no
  /// catcher controls it with ordinary effort. Physically, an uncaught
  /// pitch with no catcher misplay touch against it.
  wildPitch('wild_pitch'),

  /// The catcher's doing — a pitch she should have held. Physically, an
  /// ordinary-effort catcher misplay touch against the pitch.
  passedBall('passed_ball');

  const PitchGetawayKind(this.wire);

  /// The string form fixtures and serialized output use.
  final String wire;
}

/// One pitch that got away and let somebody move (§13.2, rule 9.13).
///
/// Charged exactly once per pitch however many runners advance on it, and
/// never charged at all when nobody does — a ball in the dirt the catcher
/// blocks and keeps in front of her is not a wild pitch. This is the same
/// consequence test official errors use, applied to the battery instead of
/// the glove, and it is what §13.3's earned-run reconstruction reads when
/// it replays the inning "as if errors and passed balls hadn't happened."
class PitchGetaway {
  const PitchGetaway({
    required this.pitchEventId,
    required this.kind,
    required this.pitcherId,
    required this.advanceEventIds,
    this.touchEventId,
    this.position,
  });

  final String pitchEventId;
  final PitchGetawayKind kind;

  /// Charged to the pitcher on a wild pitch; carried on a passed ball too,
  /// since the run it lets in is still scored against her.
  final String pitcherId;

  /// Every advance this one pitch enabled — `N` runners, one charge.
  final List<String> advanceEventIds;

  /// The catcher's misplay touch, on a passed ball. Null on a wild pitch:
  /// the absence of a touch is precisely what makes it one.
  final String? touchEventId;

  /// The misplaying fielder on a passed ball (2 in every real game). Null
  /// on a wild pitch.
  final int? position;
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
    this.atBat = true,
  });

  final String batterId;

  /// 'out', 'single'..'home_run', 'reached_on_error', or the wire form of
  /// a non-batted reach reason ('walk', 'dropped_third_strike', ...).
  final String scoring;
  final bool hit;
  final int rbi;

  /// Whether this plate appearance is charged as an at-bat. Walks, HBP,
  /// catcher's interference and obstruction awards are plate appearances
  /// but not at-bats (§13, v0.43) — the distinction batting average turns
  /// on. Sacrifices (§13.6) are the other exclusion: a sac bunt is the
  /// scorer's judgment on the batted ball, a sac fly derives.
  final bool atBat;
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
    required this.pitchGetaways,
    required this.unearnedConditions,
  });

  final List<OfficialError> errors;
  final List<MisplayRecord> misplays;
  final List<BatterOutcome> batterOutcomes;
  final Map<int, int> putoutsByPosition;
  final Map<int, int> assistsByPosition;
  final Map<String, int> strikeoutsByPitcher;

  /// §13.2's wild pitches and passed balls, in stream order — one entry
  /// per pitch that got away and let somebody move.
  final List<PitchGetaway> pitchGetaways;

  /// WP charged to each pitcher, the counterpart to [strikeoutsByPitcher].
  Map<String, int> get wildPitchesByPitcher {
    final counts = <String, int>{};
    for (final g in pitchGetaways) {
      if (g.kind != PitchGetawayKind.wildPitch) continue;
      counts.update(g.pitcherId, (v) => v + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  /// PB charged to the catcher. Team-level rather than per-player: a
  /// passed ball is charged to whoever was catching, and `fielderId` has
  /// no writer yet (there is no roster for our own defense).
  int get passedBalls => pitchGetaways
      .where((g) => g.kind == PitchGetawayKind.passedBall)
      .length;

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

/// One plate appearance: a batter, and **the slice of the stream that
/// happened while she stood at the plate**.
///
/// The unit of official scoring is the plate appearance, not the batter
/// (§13). Before this existed, `_batterOutcome` was handed the whole game's
/// advances and outs plus a `batterId` and had to re-establish its own scope
/// at every read — six reads across two functions using three different
/// rules, three of which did no time scoping at all. A guard repeated at
/// every read site is a bug waiting for the site somebody forgets, and three
/// of the six had already forgotten.
///
/// Carrying the slice removes the question rather than answering it
/// repeatedly: out-of-scope events are not filtered out, they are *absent*,
/// and no call site can omit a guard it never has to write. `batterId`
/// becomes what it should always have been — a label for attributing the
/// finished line, and a way to tell the batter from the runners already
/// aboard — never a key for searching game-wide collections.
class _PlateAppearance {
  _PlateAppearance(this.batterId);

  final String batterId;

  /// Everything that happened while she was up, **by any runner** — a
  /// teammate's steal belongs to this PA as surely as her own single does,
  /// which is what makes RBI scoping fall out for free.
  final List<_AdvanceRecord> advances = [];
  final List<_OutRecord> outs = [];

  /// Her batted ball, if she put one in play, and the outs when she hit it.
  String? battedBallId;
  int? outsAtContact;
}

class _AdvanceRecord {
  _AdvanceRecord(this.eventId, this.payload, this.pitchAtTime);

  final String eventId;
  final RunnerAdvance payload;

  // No `batterAtTime` here, deliberately. It existed so that reads over the
  // whole game's advances could ask "did this happen in my plate
  // appearance" — the scope filter the partition removes. Deleting the field
  // is what keeps it removed: re-introducing that question means putting the
  // field back, which is a visible change rather than a quiet `continue`.

  /// The pitch this advance happened on, for §13.2's WP/PB derivation: a
  /// wild pitch has no touch to link back to, so the ball that got away
  /// can only be identified by which pitch was in the air.
  final String? pitchAtTime;
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
  // Which anchors are pitches rather than batted balls — the hinge §13.2
  // charges WP/PB on rather than an error.
  final pitchEventIds = <String>{};
  final pitcherOfPitch = <String, String>{};
  final touches = <_TouchRecord>[];
  final advances = <_AdvanceRecord>[];
  final outs = <_OutRecord>[];

  // The most recent catcher's-interference ⚖, anchoring the E2 charge
  // (§4.1 v0.43): the award follows its call in the stream.
  String? latestCatcherInterferenceCallId;
  final callsById = <String, RuleCall>{};
  final strikeouts = <String, int>{};

  // The partition. A new plate appearance opens when the batter changes, and
  // an inning boundary closes whichever is open — without that second rule a
  // batter interrupted by a third out made on the bases would continue her
  // old PA next inning, when by rule she starts a fresh one and the
  // interrupted one was never a plate appearance at all.
  final plateAppearances = <_PlateAppearance>[];
  _PlateAppearance? openPa;

  var state = startingFrom;
  var batterOfRecord = startingFrom.currentBatterId;
  String? pitchOfRecord;

  for (final event in visibleLogicalOrder) {
    switch (event.type) {
      case 'PitchThrown':
        final pitch = PitchThrown.fromJson(event.payload);
        pitchEventIds.add(event.id);
        pitchOfRecord = event.id;
        pitcherOfPitch[event.id] = pitch.pitcherId;
        batterOfRecord = pitch.batterId;
        if (openPa == null || openPa.batterId != pitch.batterId) {
          openPa = _PlateAppearance(pitch.batterId);
          plateAppearances.add(openPa);
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
        openPa
          ?..battedBallId = event.id
          ..outsAtContact = state.outs;
      case 'FielderTouch':
        touches.add(
          _TouchRecord(
            event.id,
            FielderTouch.fromJson(event.payload),
            batterOfRecord,
          ),
        );
      case 'RunnerAdvance':
        final advance = _AdvanceRecord(
          event.id,
          RunnerAdvance.fromJson(event.payload),
          pitchOfRecord,
        );
        advances.add(advance);
        openPa?.advances.add(advance);
      case 'RunnerOut':
        final out = _OutRecord(event.id, RunnerOut.fromJson(event.payload));
        outs.add(out);
        openPa?.outs.add(out);
      case 'InningHalfStart':
      case 'InningHalfEnd':
        // Close the open PA. See the partition note above: the batter who was
        // up when the side was retired starts a new plate appearance, not a
        // continuation of the one that never finished.
        openPa = null;
      case 'RuleCall':
        final call = RuleCall.fromJson(event.payload);
        if (call.callType == CallType.INTERFERENCE_CATCHER) {
          latestCatcherInterferenceCallId = event.id;
        }
        callsById[event.id] = call;
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

    final resolvedEffort =
        t.ordinaryEffort ?? defaultOrdinaryEffort(t.touchType);
    misplays.add(
      MisplayRecord(
        touchEventId: touch.eventId,
        position: t.position,
        touchType: t.touchType,
        ordinaryEffort: resolvedEffort,
      ),
    );
    if (resolvedEffort != true) continue;

    // §13.2: a passed ball is not an error — they are two separate
    // statistics. A pitch that gets away from the catcher is charged to
    // the battery as a WP/PB; only a play on a *batted or thrown* ball can
    // become an E. The misplay above still stands: the physical record is
    // layer 1 and does not depend on what official scoring makes of it.
    if (pitchReceivingTouchTypes.contains(t.touchType) &&
        pitchEventIds.contains(t.ballInPlayEventId)) {
      continue;
    }

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

  final pitchGetaways = _pitchGetaways(
    touches: touches,
    advances: advances,
    pitchEventIds: pitchEventIds,
    pitcherOfPitch: pitcherOfPitch,
  );

  // Catcher's interference is an error by rule (§4.1 v0.43): E2, charged
  // with no misplay touch behind it — anchored to the ⚖ when one was
  // recorded, else to the award itself.
  for (final advance in advances) {
    final a = advance.payload;
    if (a.reason == RunnerAdvanceReason.CATCHER_INTERFERENCE && a.from == 0) {
      errors.add(
        OfficialError(
          touchEventId: latestCatcherInterferenceCallId ?? advance.eventId,
          position: 2,
          kind: OfficialErrorKind.interference,
          basis: OfficialErrorBasis.reached,
        ),
      );
    }
  }

  // Obstruction on the batter-runner (§13.2 v0.43): she was awarded a base
  // she never earned, so the fielder who obstructed her is charged a
  // fielding error — the second error with no misplay touch behind it,
  // anchored to the ⚖ that named her.
  for (final advance in advances) {
    final a = advance.payload;
    if (a.reason != RunnerAdvanceReason.OBSTRUCTION || a.from != 0) continue;
    final callId = a.enabledByCallId;
    final against = callId == null ? null : callsById[callId]?.againstPosition;
    if (against == null) continue; // no fielder named: nothing to charge
    errors.add(
      OfficialError(
        touchEventId: callId!,
        position: against,
        kind: OfficialErrorKind.fielding,
        basis: OfficialErrorBasis.reached,
      ),
    );
  }

  final chargedTouchIds = {for (final e in errors) e.touchEventId};

  // Pass C: batter outcomes, RBIs, putouts/assists, unearned conditions —
  // everything that needs to know which errors were actually charged.
  final batterOutcomes = <BatterOutcome>[
    for (final pa in plateAppearances)
      _batterOutcome(
        pa,
        chargedTouchIds,
        sacrifice: _sacrificeFor(
          pa,
          battedBall: pa.battedBallId == null
              ? null
              : ballInPlayById[pa.battedBallId],
          anyChargedError: errors.isNotEmpty,
        ),
      ),
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
    pitchGetaways: pitchGetaways,
    unearnedConditions: unearned,
  );
}

/// Advances that mean the pitch itself got away (§4.3). The dropped third
/// strike is one of them: the batter reaching on an uncaught strike three
/// is charged as a wild pitch or a passed ball like any other advance.
const _getawayReasons = {
  RunnerAdvanceReason.WILD_PITCH,
  RunnerAdvanceReason.PASSED_BALL,
  RunnerAdvanceReason.DROPPED_THIRD_STRIKE,
};

/// §13.2's WP/PB derivation, charged per rule 9.13's consequence test: a
/// pitch that gets away counts only when it lets somebody move, and counts
/// once however many runners move on it.
///
/// Which of the two it is comes from physics, never from the advance's
/// label — an ordinary-effort catcher misplay against the pitch makes it a
/// passed ball, and the absence of one makes it the pitcher's wild pitch.
/// A `passed_ball`-labeled advance with no such touch is therefore scored
/// a wild pitch; §15.6's entry path always emits the touch alongside the
/// chip, so the two only diverge in hand-authored streams.
List<PitchGetaway> _pitchGetaways({
  required List<_TouchRecord> touches,
  required List<_AdvanceRecord> advances,
  required Set<String> pitchEventIds,
  required Map<String, String> pitcherOfPitch,
}) {
  final touchById = {for (final t in touches) t.eventId: t};

  // The catcher misplay against each pitch, if any.
  final misplayOnPitch = <String, _TouchRecord>{};
  for (final touch in touches) {
    final t = touch.payload;
    if (!pitchReceivingTouchTypes.contains(t.touchType)) continue;
    if (!pitchEventIds.contains(t.ballInPlayEventId)) continue;
    final effort = t.ordinaryEffort ?? defaultOrdinaryEffort(t.touchType);
    if (effort != true) continue;
    misplayOnPitch.putIfAbsent(t.ballInPlayEventId, () => touch);
  }

  // Group the advances by the pitch that got away. A linked touch names
  // its own pitch; a wild pitch has none, so it falls back to whichever
  // pitch was in the air.
  final movedOn = <String, List<String>>{};
  for (final advance in advances) {
    if (!_getawayReasons.contains(advance.payload.reason)) continue;
    final linked = touchById[advance.payload.enabledByTouchId];

    // `dropped_third_strike` names the batter's *entitlement to run*, not
    // what happened to the ball, so it is the one getaway reason that can
    // be false. A reach claimed by some other misplay — the catcher blocks
    // strike three, keeps it in front of her, then throws it away — is a
    // reach on that error, not on a ball that got away: no WP, no PB, and
    // never both an error and a passed ball for the same advance. Only a
    // reach linked to a *receiving* misplay (a passed ball) or to nothing
    // at all (a wild pitch) means the pitch itself got past her.
    if (advance.payload.reason == RunnerAdvanceReason.DROPPED_THIRD_STRIKE &&
        linked != null &&
        !pitchReceivingTouchTypes.contains(linked.payload.touchType)) {
      continue;
    }

    final pitchId =
        (linked != null &&
            pitchEventIds.contains(linked.payload.ballInPlayEventId))
        ? linked.payload.ballInPlayEventId
        : advance.pitchAtTime;
    if (pitchId == null) continue;
    movedOn.putIfAbsent(pitchId, () => []).add(advance.eventId);
  }

  return [
    for (final MapEntry(key: pitchId, value: advanceIds) in movedOn.entries)
      if (pitcherOfPitch[pitchId] case final pitcherId?)
        if (misplayOnPitch[pitchId] case final touch?)
          PitchGetaway(
            pitchEventId: pitchId,
            kind: PitchGetawayKind.passedBall,
            pitcherId: pitcherId,
            advanceEventIds: advanceIds,
            touchEventId: touch.eventId,
            position: touch.payload.position,
          )
        else
          PitchGetaway(
            pitchEventId: pitchId,
            kind: PitchGetawayKind.wildPitch,
            pitcherId: pitcherId,
            advanceEventIds: advanceIds,
          ),
  ];
}

/// §13.2 defaults: `booted`, `missed_catch`, `dropped` resolve true when
/// the scorer recorded no judgment. Everything else stays null —
/// "prompt the scorer" — and is never charged until resolved.
/// §13.2's `ordinaryEffort` inference — the single definition, read both
/// here (when a touch carries no explicit judgment) and by the play draft
/// at commit, so the two can never drift.
///
/// v0.43 adds `tag_missed`: recording a missed tag is itself the claim that
/// she should have made it. `wild_throw` deliberately stays a judgment call
/// — a throw can sail and cost nothing, the runner ending up exactly where
/// a good throw would have left her. Null means "prompt" — unresolved, and
/// never charged while it stays that way.
bool? defaultOrdinaryEffort(TouchType type) {
  switch (type) {
    case TouchType.BOOTED:
    case TouchType.MISSED_CATCH:
    case TouchType.DROPPED:
    case TouchType.TAG_MISSED:
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
    // A muffed tag is a fielding error: she had the ball and failed to
    // apply it (§13.2 v0.43).
    case TouchType.TAG_MISSED:
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

/// Reasons whose runs credit the batter an RBI (§13): the hit itself, and
/// the ground-rule award that is a hit by another name.
const _rbiReasons = {
  RunnerAdvanceReason.BATTED_BALL,
  RunnerAdvanceReason.GROUND_RULE,
};

const _nonBattedReachReasons = {
  RunnerAdvanceReason.WALK,
  RunnerAdvanceReason.HBP,
  RunnerAdvanceReason.DROPPED_THIRD_STRIKE,
  RunnerAdvanceReason.FIELDERS_CHOICE,
  RunnerAdvanceReason.CATCHER_INTERFERENCE,
  // v0.43: a batter-runner awarded first on obstruction did not hit her
  // way there. Rare — obstruction usually happens at the other bases,
  // which never reaches this derivation — but it is not a single.
  RunnerAdvanceReason.OBSTRUCTION,
};

/// Reaches that are plate appearances but not at-bats (§13 v0.43).
const _nonAtBatReachReasons = {
  RunnerAdvanceReason.WALK,
  RunnerAdvanceReason.HBP,
  RunnerAdvanceReason.CATCHER_INTERFERENCE,
  RunnerAdvanceReason.OBSTRUCTION,
};

/// §13.6 (v0.43): was this plate appearance a sacrifice? The bunt is the
/// scorer's judgment, stored on the batted ball because nothing physical
/// distinguishes it. The fly *derives*: any ball caught in the air (fly,
/// pop-up, or line drive), fewer than two outs, the batter retired, a
/// runner scoring from third on the ball —
/// and no error anywhere on the play, since a run that needed a misplay was
/// not the sacrifice's doing. An explicit flag overrides the derivation
/// either way.
String? _sacrificeFor(
  _PlateAppearance pa, {
  required BallInPlay? battedBall,
  required bool anyChargedError,
}) {
  if (battedBall == null) return null;
  final bunt = battedBall.trajectory == Trajectory.BUNT;
  // Scoped by construction: `pa.outs` holds only what happened while she was
  // up, so this can no longer report a batter retired three innings ago.
  final wasOut = pa.outs.any((o) => o.payload.runnerId == pa.batterId);

  final judged = battedBall.sacrifice;
  if (judged ?? false) return bunt ? 'sacrifice_bunt' : 'sacrifice_fly';
  // Judged *not* a sacrifice, or a bunt nobody judged: no derivation
  // exists for a bunt, so it stands as an ordinary at-bat.
  if (judged != null || bunt) return null;

  // Any ball caught in the air qualifies — a line drive included, which is
  // the rulebook's wording and the same set the entry surface treats as
  // airborne.
  final airborne =
      battedBall.trajectory == Trajectory.FLY ||
      battedBall.trajectory == Trajectory.POPUP ||
      battedBall.trajectory == Trajectory.LINE;
  if (!airborne || !battedBall.landingIsCaught) return null;
  if (!wasOut || anyChargedError) return null;
  if ((pa.outsAtContact ?? 0) >= 2) return null;

  final scoredFromThird = pa.advances.any(
    (a) =>
        a.payload.runnerId != pa.batterId &&
        a.payload.from == 3 &&
        a.payload.to == 4 &&
        a.payload.reason == RunnerAdvanceReason.BATTED_BALL,
  );
  return scoredFromThird ? 'sacrifice_fly' : null;
}

BatterOutcome _batterOutcome(
  _PlateAppearance pa,
  Set<String> chargedTouchIds, {
  String? sacrifice,
}) {
  final batterId = pa.batterId;
  // A who-filter, not a scope-filter: it asks which of *this* PA's advances
  // are the batter's own, which is a real question about the play. The
  // when-filters this function used to carry are gone — the slice answers
  // them.
  final own = [
    for (final a in pa.advances)
      if (a.payload.runnerId == batterId) a,
  ];
  final reach = own.where((a) => a.payload.from == 0).firstOrNull;

  // RBIs: runs scoring on this batter's play that weren't gifted by a
  // charged error (batted-ball runs, including the batter's own homer).
  // `ground_rule` counts too (v0.43): a ground-rule double that scores a
  // runner drove her in as surely as any other two-base hit.
  var rbi = 0;
  for (final a in pa.advances) {
    if (a.payload.to != 4) continue;
    if (chargedTouchIds.contains(a.payload.enabledByTouchId)) continue;
    if (_rbiReasons.contains(a.payload.reason)) rbi++;
  }

  if (reach == null) {
    final wasOut = pa.outs.any((o) => o.payload.runnerId == batterId);
    return BatterOutcome(
      batterId: batterId,
      scoring: sacrifice ?? (wasOut ? 'out' : 'batting'),
      hit: false,
      rbi: rbi,
      // A sacrifice is a plate appearance, never an at-bat (§13.6).
      atBat: sacrifice == null && wasOut,
    );
  }

  final reason = reach.payload.reason;
  if (_nonBattedReachReasons.contains(reason)) {
    return BatterOutcome(
      batterId: batterId,
      scoring: runnerAdvanceReasonValues.reverse[reason]!,
      hit: false,
      rbi: rbi,
      atBat: !_nonAtBatReachReasons.contains(reason),
    );
  }

  // Hit vs. error (§13.2): the judgment lives on the first touch. If the
  // reach was enabled by a *charged* error the batter reached on it; an
  // uncharged misplay (ordinaryEffort false) means the reach was a hit.
  // Reached on an error: either the enabling touch was charged, or the
  // scorer said `error` with nothing to link — an advance that claims an
  // error is not a hit just because its cause went unrecorded.
  if (chargedTouchIds.contains(reach.payload.enabledByTouchId) ||
      (reason == RunnerAdvanceReason.ERROR &&
          reach.payload.enabledByTouchId == null)) {
    return BatterOutcome(
      batterId: batterId,
      scoring: 'reached_on_error',
      hit: false,
      rbi: rbi,
    );
  }

  // Hit base: the farthest the batter got *on the hit itself* (v0.43). A
  // leg with any enabler — a throw, a misplay, a ⚖ — or a non-batted
  // reason is movement after or apart from the hit and never raises the
  // rank: "took second on the throw" is a single plus an advance, not a
  // double.
  var base = reach.payload.to;
  for (final a in own) {
    if (a.payload.from == 0) continue;
    if (a.payload.enabledByTouchId != null) continue;
    if (a.payload.reason != RunnerAdvanceReason.BATTED_BALL) continue;
    if (a.payload.to > base) base = a.payload.to;
  }
  return BatterOutcome(
    batterId: batterId,
    scoring: _hitByBase[base]!,
    hit: true,
    rbi: rbi,
  );
}
