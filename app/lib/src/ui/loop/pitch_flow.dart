import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/pitch_count_effect.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which step of §11.1's loop is on screen.
///
/// [call], [actual], and [outcome] are the loop proper. The rest are the
/// judgment calls and repairs that interleave with it: [d3k] is §11.3's
/// dropped-third-strike prompt (the one consequence with something to
/// decide — walks auto-apply, v0.41), and [recordLast] the v0.39 location
/// backfill for the pitch just committed. [bailout] is §11.2's bottom rung:
/// outcome only, reached by two-finger swipe from any entry step.
enum PitchStep { call, actual, outcome, d3k, recordLast, bailout }

/// Which box the batter stands in. Session-level stub for M1 — DIA-008/009's
/// lineup work replaces this with per-batter data; the loop already reads it
/// per pitch, so that swap touches only this provider.
final batterSideProvider = StateProvider<BatterSide>((ref) => BatterSide.R);

/// The call as it stood when the pitch left the hand: what `PitchThrown`
/// records as intent (§10.1).
///
/// A snapshot, not a live reference to the call draft — the draft belongs to
/// the call screen and clears when the flow resets, while this has to survive
/// until commit. Always complete (v0.40): the checkmark that freezes it only
/// exists once a zone is chosen, so a half-made call is never captured — the
/// coach finishes it, replaces it, or skips.
@immutable
class CallIntent {
  const CallIntent({required this.pitchTypeId, required this.zoneId});

  final String pitchTypeId;
  final String zoneId;
}

/// §11.1 v0.39's "record last pitch": the in-play pitch that just committed
/// without a location, held so the loop's return can offer to fill it in.
///
/// Carries the original payload because a correction (§6) is a complete
/// replacement, not a patch — the corrected event is the old payload with
/// `actualLocation` set, appended with `corrects` pointing at [eventId].
@immutable
class RecordLastPitchOffer {
  const RecordLastPitchOffer({required this.eventId, required this.payload});

  final String eventId;
  final Map<String, dynamic> payload;
}

/// One pitch's accumulating entry, across the loop's steps.
///
/// Deliberately not an event (§10.3): nothing reaches the store until
/// [PitchFlowController.commitOutcome] writes the one `PitchThrown`.
@immutable
class PitchFlowState {
  const PitchFlowState({
    this.step = PitchStep.call,
    this.intent,
    this.actual,
    this.bounce,
    this.d3kBatterId,
    this.d3kPitchEventId,
    this.lastPitchOffer,
  });

  final PitchStep step;

  /// Null when the call was skipped (§11.2's per-pitch Scorer mode).
  final CallIntent? intent;

  /// Mutually exclusive with [bounce], as on the event (§4.1).
  final ZoneCoord? actual;
  final BounceCoord? bounce;

  /// The batter free to run, while [step] is [PitchStep.d3k] — held here
  /// because the fold already closed the plate appearance, so
  /// `currentBatterId` no longer names her.
  final String? d3kBatterId;

  /// The strike-three pitch's event id, while [step] is [PitchStep.d3k]:
  /// the anchor for a passed ball's catcher-misplay touch (play #5's
  /// convention — a D3K `FielderTouch` references the pitch, since no
  /// `BallInPlay` exists).
  final String? d3kPitchEventId;

  /// Set while an offer to locate the previous pitch stands (§11.1 v0.39).
  /// Survives the idle call screen and dies the moment the loop moves on —
  /// which is exactly "dismisses by simply proceeding."
  final RecordLastPitchOffer? lastPitchOffer;
}

/// §11.3's forced chain for a walk or HBP, lead runner first — ordered so no
/// placement overwrites a base another runner is still leaving.
///
/// Only *forced* runners move: the batter takes first; each runner advances
/// only while the chain of occupied bases behind them reaches first.
List<RunnerAdvance> forcedAdvances(
  BaseState bases,
  String batterId,
  RunnerAdvanceReason reason,
) {
  final first = bases.first;
  final second = bases.second;
  final third = bases.third;
  return [
    if (third != null && second != null && first != null)
      RunnerAdvance(runnerId: third, from: 3, to: 4, reason: reason),
    if (second != null && first != null)
      RunnerAdvance(runnerId: second, from: 2, to: 3, reason: reason),
    if (first != null)
      RunnerAdvance(runnerId: first, from: 1, to: 2, reason: reason),
    RunnerAdvance(runnerId: batterId, from: 0, to: 1, reason: reason),
  ];
}

/// Diamond's suggested outcome for the confirm button (§11.1), or null when
/// there is nothing to suggest from.
///
/// Suggestion ≠ auto-commit: the ump's call is the truth, not the location,
/// so one tap is always required and the override row always shows.
Outcome? suggestOutcome({ZoneCoord? actual, BounceCoord? bounce}) {
  // Bounced before the plate: never a strike by location.
  if (bounce != null) return Outcome.BALL;
  if (actual == null) return null;
  final inZone =
      actual.x >= -1 && actual.x <= 1 && actual.y >= 0 && actual.y <= 1;
  return inZone ? Outcome.CALLED_STRIKE : Outcome.BALL;
}

/// §11.1's state machine: call → actual → outcome → commit → back to call.
///
/// **Outcome is its own step with its own surface, never entangled with
/// location entry.** That seam is deliberate and load-bearing: under §12.2's
/// duty split (v0.39) the caller's device runs call → actual and *stops* —
/// outcome is the scorer's bundle, entered on the primary. M2 cuts the loop
/// along exactly this boundary, so nothing on the call or actual surfaces may
/// ever grow a ball/strike button.
///
/// The controller holds no game state (§5): it reads counts and bases from
/// [gameControllerProvider]'s fold and writes events through it, nothing else.
class PitchFlowController extends Notifier<PitchFlowState> {
  @override
  PitchFlowState build() => const PitchFlowState();

  /// §10.3's checkmark (v0.40): the coach confirmed the pending call was
  /// used. Freeze it as this pitch's intent and move to actual-location
  /// entry. Guarded rather than trusted — the checkmark only renders with a
  /// pending call, but a stale tap must not advance an empty flow. With no
  /// call to confirm, [skipCall] is the way forward.
  void pitchThrown() {
    final pending = ref.read(callDraftProvider).pending;
    if (pending == null) return;
    state = PitchFlowState(
      step: PitchStep.actual,
      intent: CallIntent(
        pitchTypeId: pending.pitchTypeId,
        zoneId: pending.zoneId,
      ),
    );
  }

  /// §11.2's per-pitch Scorer mode: no call captured at all. Clears any
  /// half-made draft — skipping *is* the statement that this pitch has no
  /// recorded intent.
  void skipCall() {
    ref.read(callDraftProvider.notifier).clear();
    state = const PitchFlowState(step: PitchStep.actual);
  }

  void actualCommitted(ZoneCoord coord) {
    state = PitchFlowState(
      step: PitchStep.outcome,
      intent: state.intent,
      actual: coord,
    );
  }

  void bounceCommitted(BounceCoord coord) {
    state = PitchFlowState(
      step: PitchStep.outcome,
      intent: state.intent,
      bounce: coord,
    );
  }

  /// §11.2's skip-location affordance: on to the outcome with no location —
  /// a real choice under pressure, not a failure mode.
  void skipLocation() {
    state = PitchFlowState(step: PitchStep.outcome, intent: state.intent);
  }

  /// Back from the actual step (§11.1: Cancel reverses the step). The pending
  /// call is still on screen when we get there — it persists until the pitch
  /// result is entered (§10.3).
  void backToCall() {
    state = PitchFlowState(intent: state.intent);
  }

  /// The one write of the loop: `PitchThrown`, plus the strikeout's
  /// `RunnerOut` when the loop itself is sure of it (§11.3).
  Future<void> commitOutcome(Outcome outcome) async {
    final game = ref.read(gameControllerProvider.notifier);
    final gs = ref.read(gameControllerProvider).valueOrNull;
    if (gs == null) return; // still bootstrapping; nothing to attribute to

    final session = ref.read(gameSessionProvider);
    final side = ref.read(batterSideProvider);
    final battingTeam = gs.battingTeamId;
    final batterId =
        gs.currentBatterId ??
        (battingTeam == null ? null : gs.batterDue(battingTeam));
    if (batterId == null) return; // no lineup folded yet — same situation

    final intent = state.intent;
    // The one crossing from the batter-relative call frame to the absolute
    // coordinate the event stores (§10.1): mirrored here, at write time.
    final zone = intent == null
        ? null
        : ref.read(teamCallConfigProvider).layout.byId(intent.zoneId);

    final payload = PitchThrown(
      batterId: batterId,
      batterSide: side,
      pitcherId: session.pitcherId,
      intendedType: intent?.pitchTypeId,
      intendedZoneId: intent?.zoneId,
      intendedLocation: zone?.absoluteCentroid(side),
      actualLocation: state.actual,
      bounceLocation: state.bounce,
      outcome: outcome,
    ).toJson();
    final event = await game.append(type: 'PitchThrown', payload: payload);

    // The call draft clears on every path out of here — the pitch happened,
    // so the call is spent whatever comes next.
    ref.read(callDraftProvider.notifier).clear();

    // Consequences (§11.3) — automatic where the rules leave no doubt,
    // a prompt where they don't. `unknown` never reaches any of them: no
    // known outcome, no consequence.
    if (outcome != Outcome.UNKNOWN) {
      final effect = applyPitchCountEffect(gs.balls, gs.strikes, outcome);
      final struckOut = effect.endsPlateAppearance && effect.strikes >= 3;
      final d3kLive =
          outcome == Outcome.SWINGING_STRIKE_BLOCKED &&
          (gs.bases.first == null || gs.outs == 2);

      // D3K: the batter may run, so the out is never assumed — the scorer
      // resolves it (§11.3). Full throw/error sequences are DIA-008; this
      // prompt records only the resolution.
      if (struckOut && d3kLive) {
        state = PitchFlowState(
          step: PitchStep.d3k,
          d3kBatterId: batterId,
          d3kPitchEventId: event.id,
        );
        return;
      }
      if (struckOut) {
        await game.append(
          type: 'RunnerOut',
          payload: RunnerOut(
            runnerId: batterId,
            atBase: 1,
            how: How.STRIKEOUT,
          ).toJson(),
        );
      }

      // Walk / HBP: the forced chain auto-applies (§11.3 v0.41) — rulebook
      // arithmetic with nothing to decide, and the mistapped-outcome error a
      // confirm couldn't catch is what action-scoped undo is for. The chain
      // reads the *pre-advance* bases, which the fold hasn't moved (bases
      // only change on RunnerAdvance, never inferred from an outcome).
      final walked = effect.endsPlateAppearance && effect.balls >= 4;
      if (walked || outcome == Outcome.HIT_BY_PITCH) {
        final reason = outcome == Outcome.HIT_BY_PITCH
            ? RunnerAdvanceReason.HBP
            : RunnerAdvanceReason.WALK;
        for (final advance in forcedAdvances(gs.bases, batterId, reason)) {
          await game.append(
            type: 'RunnerAdvance',
            payload: advance.toJson(),
          );
        }
      }
    }

    // Loop closes. An in-play pitch that went unlocated gets the standing
    // offer to fix that (§11.1 v0.39) — it blocks nothing and dies the moment
    // the loop moves on.
    state = PitchFlowState(
      lastPitchOffer:
          outcome == Outcome.IN_PLAY &&
              state.actual == null &&
              state.bounce == null
          ? RecordLastPitchOffer(eventId: event.id, payload: payload)
          : null,
    );
  }

  /// D3K, tagged: `RunnerOut{atBase: 1, how: tag}` (§11.3 v0.41).
  Future<void> d3kOutTag() => _d3kOut(How.TAG);

  /// D3K, thrown out at first: the schema's own word for it.
  Future<void> d3kOutThrow() => _d3kOut(How.STRIKEOUT_D3_K_THROW);

  Future<void> _d3kOut(How how) async {
    final batter = state.d3kBatterId;
    if (batter == null) return;
    await ref
        .read(gameControllerProvider.notifier)
        .append(
          type: 'RunnerOut',
          payload: RunnerOut(runnerId: batter, atBase: 1, how: how).toJson(),
        );
    state = const PitchFlowState();
  }

  /// D3K, safe on a wild pitch: the advance alone — the ball getting away
  /// was the pitcher's, and there is no catcher misplay to record (§13.2).
  Future<void> d3kSafeWildPitch() async {
    final batter = state.d3kBatterId;
    if (batter == null) return;
    await ref
        .read(gameControllerProvider.notifier)
        .append(
          type: 'RunnerAdvance',
          payload: _d3kAdvance(batter).toJson(),
        );
    state = const PitchFlowState();
  }

  /// D3K, safe on a passed ball: §13 working as designed — the catcher's
  /// misplay is recorded as *physics* (an ordinary-effort drop, anchored to
  /// the pitch event per play #5's convention), and the passed-ball ruling is
  /// derived from it (§13.2), never stored.
  Future<void> d3kSafePassedBall() async {
    final batter = state.d3kBatterId;
    final pitchEventId = state.d3kPitchEventId;
    if (batter == null || pitchEventId == null) return;

    final game = ref.read(gameControllerProvider.notifier);
    final touch = await game.append(
      type: 'FielderTouch',
      payload: FielderTouch(
        ballInPlayEventId: pitchEventId,
        position: 2,
        touchType: TouchType.DROPPED,
        ordinaryEffort: true,
      ).toJson(),
    );
    await game.append(
      type: 'RunnerAdvance',
      payload: _d3kAdvance(batter, enabledByTouchId: touch.id).toJson(),
    );
    state = const PitchFlowState();
  }

  /// Play #5's convention: the batter's D3K advance always carries
  /// `dropped_third_strike`, whatever let the ball get away.
  RunnerAdvance _d3kAdvance(String batter, {String? enabledByTouchId}) =>
      RunnerAdvance(
        runnerId: batter,
        from: 0,
        to: 1,
        reason: RunnerAdvanceReason.DROPPED_THIRD_STRIKE,
        enabledByTouchId: enabledByTouchId,
      );

  /// Take the standing offer (§11.1 v0.39): open location entry for the
  /// pitch that already committed.
  void takeLastPitchOffer() {
    final offer = state.lastPitchOffer;
    if (offer == null) return;
    state = PitchFlowState(step: PitchStep.recordLast, lastPitchOffer: offer);
  }

  /// Back out of location entry without deciding — the offer keeps standing.
  void cancelRecordLast() {
    state = PitchFlowState(lastPitchOffer: state.lastPitchOffer);
  }

  /// Decline for good: the pitch stays honestly unlocated (null means "not
  /// captured", §12.4 — never a fabricated coordinate).
  void dismissLastPitchOffer() {
    state = const PitchFlowState();
  }

  /// The backfill itself: a §6 correction — the committed payload with its
  /// location filled in, `corrects` pointing at the original. The stream
  /// shows the corrected pitch at the original's position; provenance shows
  /// when and by whom the location arrived.
  Future<void> recordLastLocation(ZoneCoord coord) async {
    final offer = state.lastPitchOffer;
    if (offer == null) return;
    final corrected = Map<String, dynamic>.from(offer.payload)
      ..['actualLocation'] = coord.toJson();
    await ref
        .read(gameControllerProvider.notifier)
        .append(
          type: 'PitchThrown',
          payload: corrected,
          corrects: offer.eventId,
        );
    state = const PitchFlowState();
  }

  /// §11.2's two-finger bailout: drop the current pitch to the giant
  /// outcome-only row, keeping whatever was already gathered — a call or a
  /// location entered before the chaos still rides the commit.
  ///
  /// Inert on [PitchStep.d3k] and [PitchStep.recordLast]: there the pitch is
  /// already committed, and bailing would strand a live resolution or a §6
  /// correction, not simplify entry.
  void bailout() {
    if (state.step == PitchStep.d3k || state.step == PitchStep.recordLast) {
      return;
    }
    // Bailing from the call step: the intent snapshot that [pitchThrown]
    // would have taken hasn't happened yet — take it here, so a call made
    // before the chaos still rides the commit.
    var intent = state.intent;
    if (state.step == PitchStep.call) {
      final pending = ref.read(callDraftProvider).pending;
      intent = pending == null
          ? null
          : CallIntent(
              pitchTypeId: pending.pitchTypeId,
              zoneId: pending.zoneId,
            );
    }
    state = PitchFlowState(
      step: PitchStep.bailout,
      intent: intent,
      actual: state.actual,
      bounce: state.bounce,
    );
  }

  /// §12.5's checkpoint: "the scoreboard says this — make it so."
  Future<void> correctCount({required int balls, required int strikes}) async {
    await ref
        .read(gameControllerProvider.notifier)
        .append(
          type: 'CountCorrection',
          payload: CountCorrection(balls: balls, strikes: strikes).toJson(),
        );
  }
}

final pitchFlowProvider = NotifierProvider<PitchFlowController, PitchFlowState>(
  PitchFlowController.new,
);
