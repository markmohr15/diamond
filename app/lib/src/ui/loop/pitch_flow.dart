import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/events/pending_event.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/pitch_count_effect.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which step of §11.1's loop is on screen.
///
/// [call], [actual], and [outcome] are the loop proper. [recordLast] is the
/// v0.39 location backfill for the pitch just committed, and [bailout] is
/// §11.2's bottom rung: outcome only, reached by two-finger swipe from any
/// entry step. A dropped third strike is **not** a step here (v0.46): it is
/// declared on the outcome sheet like any other outcome, and its two
/// questions are dialogs over that sheet rather than states of the loop.
enum PitchStep { call, actual, outcome, recordLast, bailout }

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
    this.lastPitchOffer,
    this.getawayOffer,
    this.droppedThirdStrike,
  });

  final PitchStep step;

  /// Null when the call was skipped (§11.2's per-pitch Scorer mode).
  final CallIntent? intent;

  /// Mutually exclusive with [bounce], as on the event (§4.1).
  final ZoneCoord? actual;
  final BounceCoord? bounce;

  /// Set while an offer to locate the previous pitch stands (§11.1 v0.39).
  /// Survives the idle call screen and dies the moment the loop moves on —
  /// which is exactly "dismisses by simply proceeding."
  final RecordLastPitchOffer? lastPitchOffer;

  /// Set between declaring a dropped third strike and saying what happened
  /// to her (§11.3 v0.46) — the two steps of one decision, not an offer
  /// standing over an already-recorded strikeout. Nothing has been written
  /// for the batter yet, so there is nothing to void or dismiss.
  final DroppedThirdStrike? droppedThirdStrike;

  /// Set when the scorer marked a getaway and there are runners it could have
  /// moved (§13.2). The advance is a prompt, never automatic — see
  /// [PitchGetawayOffer].
  final PitchGetawayOffer? getawayOffer;
}

/// A dropped third strike the scorer has declared, waiting on its ending.
/// Carries what the resolution needs: the pitch its touches anchor to —
/// there is no `BallInPlay`, nothing was hit — and who is running.
/// A pitch the scorer said got away, with runners aboard to be moved by it.
///
/// §11.3's rule is automatic where the rules leave no doubt and a prompt where
/// they don't, and this is squarely the second: a runner on third often holds
/// on a ball that only trickled away. So the advance is **one tap, not zero** —
/// and the correction is action-scoped undo rather than a confirmation dialog,
/// because confirming every common case costs more taps over a game than
/// undoing the rare wrong one.
class PitchGetawayOffer {
  const PitchGetawayOffer({
    required this.pitchEventId,
    required this.cause,
    required this.occupied,
  });

  final String pitchEventId;
  final Cause cause;

  /// Occupied bases, lead runner first — the order the advances must be
  /// written in so no runner is ever momentarily on an occupied bag.
  final List<(int, String)> occupied;
}

class DroppedThirdStrike {
  const DroppedThirdStrike({
    required this.pitchEventId,
    required this.batterId,
  });

  final String pitchEventId;
  final String batterId;
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

  /// Dismissing the outcome sheet without a choice: back to the location
  /// step with everything gathered intact — nothing committed, nothing
  /// lost. The placed location stays on the canvas; re-placing or
  /// re-confirming reopens the sheet.
  void backToActual() {
    state = PitchFlowState(
      step: PitchStep.actual,
      intent: state.intent,
      actual: state.actual,
      bounce: state.bounce,
      lastPitchOffer: state.lastPitchOffer,
    );
  }

  /// The one write of the loop: `PitchThrown`, plus the strikeout's
  /// `RunnerOut` when the loop itself is sure of it (§11.3).
  /// [uncaughtThirdStrike] is the scorer declaring, with the pitch, that
  /// she is running — §11.3's equivalent of putting the ball in play. The
  /// automatic strikeout out is not written when it is set.
  Future<void> commitOutcome(
    Outcome outcome, {
    bool uncaughtThirdStrike = false,
    BatterAction? batterAction,
    Cause? getaway,
  }) async {
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
      // §4.1: what she was doing, orthogonal to what the pitch did. Absent is
      // the conventional posture and is the overwhelming majority.
      batterAction: batterAction,
    ).toJson();
    // Lead runner first, so the batch never puts a runner on an occupied bag.
    final occupied = <(int, String)>[
      if (gs.bases.third case final r?) (3, r),
      if (gs.bases.second case final r?) (2, r),
      if (gs.bases.first case final r?) (1, r),
    ];
    final event = await game.append(type: 'PitchThrown', payload: payload);

    // The call draft clears on every path out of here — the pitch happened,
    // so the call is spent whatever comes next.
    ref.read(callDraftProvider.notifier).clear();

    // Consequences (§11.3) — automatic where the rules leave no doubt,
    // a prompt where they don't. `unknown` never reaches any of them: no
    // known outcome, no consequence.
    DroppedThirdStrike? d3k;
    if (outcome != Outcome.UNKNOWN) {
      final effect = applyPitchCountEffect(gs.balls, gs.strikes, outcome);
      final struckOut = effect.endsPlateAppearance && effect.strikes >= 3;

      // Strike three: the loop records the out itself (§11.3). A real D3K —
      // uncaught, batter runs — is reversed with one action-scoped undo (the
      // pitch and this out, one unit) until DIA-008's resolution flow lands.
      // Arming that flow keys on the catch, not the pitch (§11.3 v0.41): a
      // blocked ball and a dropped clean strike are equally live, and the
      // catcher-misplay entry that detects the second is DIA-008's play
      // chain, so no per-outcome guard here could be honest.
      // §11.3 v0.46: an uncaught third strike is declared with the pitch,
      // not corrected afterwards — it is the equivalent of a ball put in
      // play (Mark), an outcome that opens a surface rather than a note on
      // a strikeout. Declaring it up front means the automatic out is
      // never written, so there is nothing to void and no phantom out in
      // the stream.
      if (struckOut && uncaughtThirdStrike) {
        d3k = DroppedThirdStrike(pitchEventId: event.id, batterId: batterId);
      } else if (struckOut) {
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
      if (walked ||
          outcome == Outcome.HIT_BY_PITCH ||
          outcome == Outcome.CATCHER_INTERFERENCE) {
        // Catcher's interference carries its ⚖ (§4.5) ahead of the award —
        // the judicial fact the E2 derivation reads (§13.2 v0.43).
        if (outcome == Outcome.CATCHER_INTERFERENCE) {
          await game.append(
            type: 'RuleCall',
            payload: RuleCall(
              callType: CallType.INTERFERENCE_CATCHER,
              againstPosition: 2,
            ).toJson(),
          );
        }
        final reason = switch (outcome) {
          Outcome.HIT_BY_PITCH => RunnerAdvanceReason.HBP,
          Outcome.CATCHER_INTERFERENCE =>
            RunnerAdvanceReason.CATCHER_INTERFERENCE,
          _ => RunnerAdvanceReason.WALK,
        };
        for (final advance in forcedAdvances(gs.bases, batterId, reason)) {
          await game.append(type: 'RunnerAdvance', payload: advance.toJson());
        }
      }
    }

    // In play: open the field surface (§15.1, DIA-008) for the play that is
    // now unfolding. The draft owns the screen from here — the loop page
    // switches on its presence — and the flow state below still resets, so
    // the call surface (and the standing offer) is what commit/discard
    // returns to.
    if (outcome == Outcome.IN_PLAY) {
      await ref
          .read(playDraftProvider.notifier)
          .start(pitchEventId: event.id, batterId: batterId);
    }

    // Loop closes. A pitch that went unlocated gets the standing offer to fix
    // that (§11.1 v0.39) — it blocks nothing and dies the moment the loop
    // moves on.
    //
    // Two outcomes arm it, for one reason (v0.53): the scorer's attention
    // left the zone. On contact that is obvious; on an uncaught third strike
    // it is the same — the batter is running. Everything else does not
    // qualify, and arming this for *every* unlocated pitch would put the
    // affordance on nearly every call screen of a scorer who skips location
    // routinely.
    state = PitchFlowState(
      lastPitchOffer:
          (outcome == Outcome.IN_PLAY || d3k != null) &&
              state.actual == null &&
              state.bounce == null
          ? RecordLastPitchOffer(eventId: event.id, payload: payload)
          : null,
      droppedThirdStrike: d3k,
      // Only when somebody could have moved: rule 9.13 charges a getaway on
      // its consequence, so with the bases empty there is nothing to offer.
      getawayOffer: (getaway != null && d3k == null && occupied.isNotEmpty)
          ? PitchGetawayOffer(
              pitchEventId: event.id,
              cause: getaway,
              occupied: occupied,
            )
          : null,
    );
  }

  /// The whole play, the overwhelming majority of the time: everybody up one.
  ///
  /// Written lead runner first so no runner is ever momentarily standing on an
  /// occupied bag, and as one batch so a single action-scoped undo takes the
  /// advances off without touching the pitch beneath them. A passed ball also
  /// mints the catcher's misplay touch and links every advance to it — §13.2's
  /// pair, the same shape the D3K resolution writes.
  Future<void> getawayAdvanceAll() async {
    final offer = state.getawayOffer;
    if (offer == null) return;
    state = PitchFlowState(lastPitchOffer: state.lastPitchOffer);

    final passedBall = offer.cause == Cause.PASSED_BALL;
    final reason = passedBall ? 'passed_ball' : 'wild_pitch';
    await ref.read(gameControllerProvider.notifier).appendAllPending([
      if (passedBall)
        PendingEvent(
          type: 'FielderTouch',
          localKey: 'pb',
          payload: FielderTouch(
            anchorEventId: offer.pitchEventId,
            position: 2,
            touchType: TouchType.MISSED_CATCH,
            ordinaryEffort: true,
          ).toJson(),
        ),
      for (final (base, runnerId) in offer.occupied)
        PendingEvent(
          type: 'RunnerAdvance',
          payload: {
            'runnerId': runnerId,
            'from': base,
            'to': base + 1,
            'reason': reason,
            if (passedBall) 'enabledByTouchId': localRef('pb'),
          },
        ),
    ]);
  }

  /// Anything else — she held, or somebody was thrown out. Opens §15.6's
  /// surface with the ball **loose**: a wild pitch's physics is the *absence*
  /// of a touch (§13.2), so there is nothing on the pitch to read and seeding
  /// the catcher would assert something that did not happen.
  Future<void> getawayToField() async {
    final offer = state.getawayOffer;
    if (offer == null) return;
    state = PitchFlowState(lastPitchOffer: state.lastPitchOffer);
    await ref
        .read(playDraftProvider.notifier)
        .startBetweenPitches(pitchEventId: offer.pitchEventId, heldBy: null);
  }

  /// §11.3's D3K resolution, written as one batch and one undo unit.
  ///
  /// Nothing needs undoing first: declaring the dropped third strike with
  /// the pitch means the automatic strikeout out was never appended, so
  /// this only ever *adds* what happened. Clearing the state before the
  /// append is what keeps a second tap from writing the ending twice.
  Future<void> _resolveD3k(
    List<PendingEvent> Function(DroppedThirdStrike) build,
  ) async {
    final offer = state.droppedThirdStrike;
    if (offer == null) return;
    state = PitchFlowState(lastPitchOffer: state.lastPitchOffer);
    await ref
        .read(gameControllerProvider.notifier)
        .appendAllPending(build(offer));
  }

  /// Thrown out at first — the everyday ending. She is out either way,
  /// which makes a bare strikeout look sufficient; it is not, because it
  /// credits nobody, and throwing runners out is most of what a catcher's
  /// line is made of. So the throw is recorded as a real chain and the out
  /// names who made it: putout 3, assist 2.
  Future<void> d3kOutOnThrow() => _resolveD3k(
    (offer) => [
      PendingEvent(
        type: 'FielderTouch',
        localKey: 'c',
        payload: FielderTouch(
          anchorEventId: offer.pitchEventId,
          position: 2,
          touchType: TouchType.FIELDED,
        ).toJson(),
      ),
      PendingEvent(
        type: 'FielderTouch',
        localKey: 'f',
        payload: FielderTouch(
          anchorEventId: offer.pitchEventId,
          position: 3,
          touchType: TouchType.RECEIVED_THROW,
        ).toJson(),
      ),
      PendingEvent(
        type: 'RunnerOut',
        payload: {
          'runnerId': offer.batterId,
          'atBase': 1,
          'how': 'strikeout_d3k_throw',
          'putoutTouchId': localRef('f'),
        },
      ),
    ],
  );

  /// Tagged by the catcher, who never had to throw.
  Future<void> d3kOutOnTag() => _resolveD3k(
    (offer) => [
      PendingEvent(
        type: 'FielderTouch',
        localKey: 'c',
        payload: FielderTouch(
          anchorEventId: offer.pitchEventId,
          position: 2,
          touchType: TouchType.TAG_APPLIED,
        ).toJson(),
      ),
      PendingEvent(
        type: 'RunnerOut',
        payload: {
          'runnerId': offer.batterId,
          'atBase': 1,
          'how': 'tag',
          'putoutTouchId': localRef('c'),
        },
      ),
    ],
  );

  /// Safe, and the ball was the pitcher's doing.
  ///
  /// `reason` stays `dropped_third_strike` — that is why she was *entitled* to
  /// run, and the batting line reads it — while `cause` says what happened to
  /// the ball (§13.2 v0.50). The two used to be one field, so this said only
  /// the first and the projection inferred the second from whether a touch
  /// existed.
  Future<void> d3kSafeWildPitch() => _resolveD3k(
    (offer) => [
      PendingEvent(
        type: 'RunnerAdvance',
        payload: {
          'runnerId': offer.batterId,
          'from': 0,
          'to': 1,
          'reason': 'dropped_third_strike',
          'cause': 'wild_pitch',
        },
      ),
    ],
  );

  /// Safe, and the catcher should have had it: the §13.2 pair.
  Future<void> d3kSafePassedBall() => _resolveD3k(
    (offer) => [
      PendingEvent(
        type: 'FielderTouch',
        localKey: 'pb',
        payload: FielderTouch(
          anchorEventId: offer.pitchEventId,
          position: 2,
          touchType: TouchType.MISSED_CATCH,
          ordinaryEffort: true,
        ).toJson(),
      ),
      PendingEvent(
        type: 'RunnerAdvance',
        payload: {
          'runnerId': offer.batterId,
          'from': 0,
          'to': 1,
          'reason': 'dropped_third_strike',
          'cause': 'passed_ball',
          'enabledByTouchId': localRef('pb'),
        },
      ),
    ],
  );

  /// Anything else — play #5's throw into right field, a runner moving on
  /// the same ball. Opens the field, where a dropped third strike is just a
  /// pitch-anchored draft with the batter running (§15.6 v0.45): nothing on
  /// that surface is D3K-specific, so play #5 is entered with the ordinary
  /// play grammar.
  Future<void> d3kToField() async {
    final offer = state.droppedThirdStrike;
    if (offer == null) return;
    state = PitchFlowState(lastPitchOffer: state.lastPitchOffer);
    await ref
        .read(playDraftProvider.notifier)
        .startBetweenPitches(
          pitchEventId: offer.pitchEventId,
          batterId: offer.batterId,
        );
  }

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
  Future<void> recordLastLocation(ZoneCoord coord) =>
      _backfill('actualLocation', coord.toJson());

  /// The same correction for a pitch that bounced (§4.1's other field).
  ///
  /// The canvas offers the hinge because a dropped third strike is most often
  /// a ball in the dirt (v0.53) — an offer that could only record a frontal
  /// location would miss the case that motivates it.
  Future<void> recordLastBounce(BounceCoord coord) =>
      _backfill('bounceLocation', coord.toJson());

  /// §4.1's mutual exclusion holds here by construction rather than by check:
  /// the offer only arms when *both* location fields are null, so filling one
  /// in leaves the other null however the scorer answers.
  Future<void> _backfill(String field, Map<String, dynamic> json) async {
    final offer = state.lastPitchOffer;
    if (offer == null) return;
    final corrected = Map<String, dynamic>.from(offer.payload)..[field] = json;
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
  /// Inert on [PitchStep.recordLast]: there the pitch is already committed,
  /// and bailing would strand a §6 correction, not simplify entry.
  void bailout() {
    if (state.step == PitchStep.recordLast) {
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
