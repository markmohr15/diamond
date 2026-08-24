import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_journal_store.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owner of the uncommitted play (§15.5). Null state = no play in flight,
/// which is what the loop page switches on: a draft present shows the field
/// surface, whoever put it there — the pitch flow on `in_play`, or the
/// journal on relaunch (the kill-app-mid-play restore).
///
/// Every mutation persists to the journal before it lands in state, so the
/// journal can never be *behind* what the scorer saw on screen.
class PlayDraftController extends AsyncNotifier<PlayDraft?> {
  late PlayJournalStore _journal;
  late String _gameId;

  @override
  Future<PlayDraft?> build() async {
    _journal = ref.watch(playJournalStoreProvider);
    _gameId = ref.watch(gameSessionProvider).gameId;
    return _journal.load(_gameId);
  }

  /// Opens the field surface for the pitch that just committed `in_play`.
  ///
  /// The ball is in play, so the batter is running (§15.1 v0.43): the draft
  /// opens with her already walked up to first, forced chain cascading —
  /// unattributed legs that later gestures resolve (a caught first touch
  /// voids them; an out at the reached base absorbs one; a misplay first
  /// touch claims the reach).
  Future<void> start({
    required String pitchEventId,
    required String batterId,
  }) async {
    final draft = _openingDraft(pitchEventId: pitchEventId, batterId: batterId);
    await _journal.save(_gameId, draft);
    state = AsyncData(draft);
  }

  /// §15.6's between-pitch entry: the same draft with a different anchor.
  /// No batted ball, so no `BallInPlay` and no trajectory question; no
  /// batter-runner, so no walk-up cascade. The catcher starts with the
  /// ball, which is true after every pitch in both sports.
  ///
  /// Everything after this point is the play grammar unchanged — touches,
  /// throws, legs, outs, chips, the ✓ — deliberately, so a steal with an
  /// error on it is entered the same way a batted ball with one is.
  Future<void> startBetweenPitches({required String pitchEventId}) async {
    final draft = PlayDraft(
      pitchEventId: pitchEventId,
      batterId: '',
      battedBall: false,
      heldBy: 2,
    );
    await _journal.save(_gameId, draft);
    state = AsyncData(draft);
  }

  /// Tapping the holder says she never had it — the pitch got past her.
  /// Reversible; the next fielder tapped then picks up a loose ball
  /// (`fielded`) rather than receiving a throw, per §15.1's loose-ball rule.
  Future<void> setHeldBy(int? position) {
    return _mutate((draft) => draft.copyWith(heldBy: position));
  }

  /// §15.5's escape hatch for a locked path (§15.1 v0.43): the whole play
  /// starts over — trajectory question included — with the committed pitch
  /// untouched. Everything or nothing; there is no partial unpick once
  /// plays hang off the path.
  Future<void> reset() async {
    final draft = state.valueOrNull;
    if (draft == null) return;
    final fresh = _openingDraft(
      pitchEventId: draft.pitchEventId,
      batterId: draft.batterId,
    );
    await _journal.save(_gameId, fresh);
    state = AsyncData(fresh);
  }

  /// Everyone the play found on the field, batter first: the fold's base
  /// state read as origins. The walk-up cascade and §16.3's beyond-the-fence
  /// awards both start here.
  List<RunnerSlot> _origins(String batterId) {
    final bases =
        ref.read(gameControllerProvider).valueOrNull?.bases ?? BaseState.empty;
    return [
      (runnerId: batterId, base: 0),
      if (bases.first != null) (runnerId: bases.first!, base: 1),
      if (bases.second != null) (runnerId: bases.second!, base: 2),
      if (bases.third != null) (runnerId: bases.third!, base: 3),
    ];
  }

  /// §16.3: the landing sat beyond the fence and the scorer said home run —
  /// four bases for everyone aboard, RBIs and all.
  Future<void> resolveHomeRun() {
    return _mutate((draft) => draft.resolvingHomeRun(_origins(draft.batterId)));
  }

  /// The beyond-the-fence sibling (§16.3): two bases for everyone.
  Future<void> resolveGroundRuleDouble() {
    return _mutate(
      (draft) => draft.resolvingGroundRuleDouble(_origins(draft.batterId)),
    );
  }

  PlayDraft _openingDraft({
    required String pitchEventId,
    required String batterId,
  }) {
    var draft = PlayDraft(pitchEventId: pitchEventId, batterId: batterId);
    final slots = _origins(batterId);
    for (final move in cascadeRunnerMove(slots, movedId: batterId, to: 1)) {
      draft = draft.addingLeg(
        move.runnerId,
        from: move.from,
        to: move.to,
        attribute: false,
      );
    }
    return draft.copyWith(openingLegCount: draft.entries.length);
  }

  /// A re-drag of a fielder who already played the ball: adjust her play,
  /// never duplicate it (§15.1 v0.43).
  Future<void> adjustFielderPlay(int position, {required FieldCoord spot}) {
    return _mutate((draft) => draft.adjustingFielderPlay(position, spot: spot));
  }

  /// §15.1 v0.43's drawn path, first tap: where the ball first hit ground
  /// or glove. Re-tapping restarts the streak — the old end is stale.
  Future<void> setLanding(FieldCoord landing, {FieldCoord? retrieved}) {
    return _mutate(
      (draft) => draft.copyWith(landing: landing, retrieved: retrieved),
    );
  }

  /// The streak's second tap: where the ball ended up. Further taps adjust.
  Future<void> setRetrieved(FieldCoord retrieved) {
    return _mutate((draft) => draft.copyWith(retrieved: retrieved));
  }

  /// §15.1 v0.43's fielder drag, popup answered: she stands at [spot], the
  /// ball is assumed there when no path was drawn, and [touchType] null
  /// means "flat out missed it" — she never touched it, so no touch exists
  /// to record (§13: no touch, no chargeable anything).
  Future<void> recordFielderPlay(
    int position, {
    required FieldCoord spot,
    TouchType? touchType,
  }) {
    return _mutate(
      (draft) => draft.recordingFielderPlay(
        position,
        spot: spot,
        touchType: touchType,
      ),
    );
  }

  /// A ⚖ attached to a runner consequence (§15.3 v0.43) — the baserunning
  /// calls live on baserunning nodes, not on a standing button.
  Future<void> attachRuleCall(
    int consequenceKey,
    CallType callType, {
    int? againstPosition,
  }) {
    return _mutate(
      (draft) => draft.attachingRuleCall(
        consequenceKey,
        callType,
        againstPosition: againstPosition,
      ),
    );
  }

  Future<void> setTrajectory(Trajectory trajectory) {
    return _mutate((draft) => draft.copyWith(trajectory: trajectory));
  }

  /// §13's sacrifice judgment (v0.43): she was giving herself up.
  Future<void> setSacrifice({required bool sacrifice}) {
    return _mutate((draft) => draft.copyWith(sacrifice: sacrifice));
  }

  /// The §15.1 fence-spline suggestion, confirmed or withdrawn via its chip.
  Future<void> setOffWall({required bool offWall}) {
    return _mutate((draft) => draft.copyWith(offWall: offWall));
  }

  /// SAFE tapped on a force play (§15.1 v0.43): her provisional walk-up
  /// becomes an answer, so she stands on the base instead of running.
  Future<void> affirmSafe(String runnerId) {
    return _mutate((draft) => draft.affirmingSafe(runnerId));
  }

  /// A runner released SAFE (§15.1 v0.43): the dragged move plus its
  /// forced cascade, with the popup's classification applied to the
  /// dragged leg — one mutation, one journal write.
  Future<void> resolveSafe(
    List<CascadedMove> moves,
    SafeResolution classification, {
    int? againstPosition,
  }) {
    return _mutate(
      (draft) => draft.resolvingSafe(
        moves,
        classification,
        againstPosition: againstPosition,
      ),
    );
  }

  /// A fielder tap (§15.1): touch with the surface's inferred type.
  Future<void> addTouch(int position, TouchType touchType) {
    return _mutate((draft) => draft.addingTouch(position, touchType));
  }

  /// A throw (§15.1 v0.43): the ball is held, and a tap on another fielder
  /// sends it to her — `received_throw` at her spot. A drag instead places
  /// the reception: she moves there and receives there.
  Future<void> receiveThrow(
    int position, {
    required FieldCoord spot,
    bool moved = false,
  }) {
    return _mutate((draft) {
      var next = draft;
      if (moved) {
        next = next.copyWith(
          movedFielders: {...next.movedFielders, position: spot},
        );
      }
      // Between pitches the thrower holds the ball by seed rather than by
      // a touch (§15.6), so she has nothing to be credited an assist on.
      // Mint it here, at the moment a throw proves she had it — not at
      // open, where a surface nobody throws on would record a phantom.
      final seed = next.heldBy;
      if (seed != null && next.securedTouch == null) {
        next = next.addingTouch(
          seed,
          TouchType.FIELDED,
          location: next.movedFielders[seed],
        );
      }
      // Off a loose ball she is making a play on it, not receiving a throw
      // — §15.1's rule, and what makes "the catcher never had it" honest.
      return next.addingTouch(
        position,
        next.holderPosition == null
            ? TouchType.FIELDED
            : TouchType.RECEIVED_THROW,
        location: spot,
      );
    });
  }

  /// A runner released OUT (§15.1 v0.43): out with the popup-confirmed
  /// `how`; a tag auto-emits the `tag_applied` touch first and credits it
  /// with the putout, per fixture 03's pattern. [interference] is the
  /// out-flavored ⚖ (v0.43): the call inserts ahead of the out and the
  /// `how` becomes `interference`.
  Future<void> addOut(
    String runnerId, {
    required int atBase,
    required How how,
    bool interference = false,
    int? againstPosition,
  }) {
    return _mutate((draft) {
      var next = draft;
      if (how == How.TAG && !interference) {
        final holder = next.securedTouch;
        if (holder != null) {
          next = next.addingTouch(holder.position, TouchType.TAG_APPLIED);
          next = next.addingOut(
            runnerId,
            atBase: atBase,
            how: how,
            putoutKey: next.entries.last.key,
          );
          return next;
        }
      }
      next = next.addingOut(
        runnerId,
        atBase: atBase,
        how: how,
        putoutKey: next.securedTouch?.key,
      );
      if (interference) {
        next = next.attachingRuleCall(
          next.entries.last.key,
          CallType.INTERFERENCE_RUNNER,
          againstPosition: againstPosition,
        );
      }
      return next;
    });
  }

  /// A chip on a touch node (§15.3): retype in place. Retyping resets any
  /// explicit ordinary-effort judgment — it was about the old type.
  Future<void> setTouchType(int key, TouchType touchType) {
    return _mutate(
      (draft) => draft.updatingEntry(
        key,
        (entry) => (entry as TouchEntry).copyWith(
          touchType: touchType,
          ordinaryEffort: null,
        ),
      ),
    );
  }

  /// Arrival-quality chip on a receiving node (§15.3) — developmental,
  /// never official scoring.
  Future<void> setReceivedQuality(int key, ReceivedQuality quality) {
    return _mutate(
      (draft) => draft.updatingEntry(
        key,
        (entry) => (entry as TouchEntry).copyWith(receivedQuality: quality),
      ),
    );
  }

  /// The scorer's §13.2 judgment, when made in the moment.
  Future<void> setOrdinaryEffort(int key, {required bool ordinaryEffort}) {
    return _mutate(
      (draft) => draft.updatingEntry(
        key,
        (entry) =>
            (entry as TouchEntry).copyWith(ordinaryEffort: ordinaryEffort),
      ),
    );
  }

  /// Override an out's inferred `how` (§15.1: "confirmable").
  Future<void> setOutHow(int key, How how) {
    return _mutate(
      (draft) => draft.updatingEntry(
        key,
        (entry) => (entry as OutEntry).copyWith(how: how),
      ),
    );
  }

  /// §13.4's two-tap re-attribution: this leg was enabled by that entry.
  Future<void> reattributeLeg(int legKey, int? enablerKey) {
    return _mutate(
      (draft) => draft.updatingEntry(
        legKey,
        (entry) => (entry as LegEntry).copyWith(enabledByKey: enablerKey),
      ),
    );
  }

  /// Remove a chain node; links to it orphan to null, never retarget.
  Future<void> removeEntry(int key) {
    return _mutate((draft) => draft.removingEntry(key));
  }

  /// The ✓ (§15.5): the whole sequence in one atomic append, then the
  /// journal row goes — in that order, so a crash between the two replays
  /// as a duplicate draft to discard, never as a lost play.
  Future<void> commit() async {
    final draft = state.valueOrNull;
    if (draft == null || !draft.committable) return;
    await ref
        .read(gameControllerProvider.notifier)
        .appendAllPending(draft.toEvents());
    await _journal.clear(_gameId);
    state = const AsyncData(null);
  }

  /// Abandons the draft; the committed pitch stands (undo reverses it
  /// separately, §6). The escape hatch for a mistapped `in_play`.
  Future<void> discard() async {
    await _journal.clear(_gameId);
    state = const AsyncData(null);
  }

  Future<void> _mutate(PlayDraft Function(PlayDraft) change) async {
    final draft = state.valueOrNull;
    if (draft == null) return;
    final next = change(draft);
    await _journal.save(_gameId, next);
    state = AsyncData(next);
  }
}

final playDraftProvider =
    AsyncNotifierProvider<PlayDraftController, PlayDraft?>(
      PlayDraftController.new,
    );
