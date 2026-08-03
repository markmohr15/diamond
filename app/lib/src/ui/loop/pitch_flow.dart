import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/rules/pitch_count_effect.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which step of §11.1's loop is on screen.
enum PitchStep { call, actual, outcome }

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
  });

  final PitchStep step;

  /// Null when the call was skipped (§11.2's per-pitch Scorer mode).
  final CallIntent? intent;

  /// Mutually exclusive with [bounce], as on the event (§4.1).
  final ZoneCoord? actual;
  final BounceCoord? bounce;
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

    await game.append(
      type: 'PitchThrown',
      payload: PitchThrown(
        batterId: batterId,
        batterSide: side,
        pitcherId: session.pitcherId,
        intendedType: intent?.pitchTypeId,
        intendedZoneId: intent?.zoneId,
        intendedLocation: zone?.absoluteCentroid(side),
        actualLocation: state.actual,
        bounceLocation: state.bounce,
        outcome: outcome,
      ).toJson(),
    );

    // Strike three: the loop records the out itself — automatic state, §11.3.
    // Except when D3K is live (uncaught third strike with first open or two
    // outs): then assuming the out would be wrong, and the runner-resolution
    // prompt is DIA-007b. `unknown` never reaches here: no known outcome, no
    // consequence.
    if (outcome != Outcome.UNKNOWN) {
      final effect = applyPitchCountEffect(gs.balls, gs.strikes, outcome);
      final struckOut = effect.endsPlateAppearance && effect.strikes >= 3;
      final d3kLive =
          outcome == Outcome.SWINGING_STRIKE_BLOCKED &&
          (gs.bases.first == null || gs.outs == 2);
      if (struckOut && !d3kLive) {
        await game.append(
          type: 'RunnerOut',
          payload: RunnerOut(
            runnerId: batterId,
            atBase: 1,
            how: How.STRIKEOUT,
          ).toJson(),
        );
      }
    }

    // Loop closes: the flow resets and the call screen gets its arsenal back.
    ref.read(callDraftProvider.notifier).clear();
    state = const PitchFlowState();
  }
}

final pitchFlowProvider = NotifierProvider<PitchFlowController, PitchFlowState>(
  PitchFlowController.new,
);
