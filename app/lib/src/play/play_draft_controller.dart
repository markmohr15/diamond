import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_journal_store.dart';
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
  Future<void> start({
    required String pitchEventId,
    required String batterId,
  }) async {
    final draft = PlayDraft(pitchEventId: pitchEventId, batterId: batterId);
    await _journal.save(_gameId, draft);
    state = AsyncData(draft);
  }

  /// §15.1's landing gesture, both grips: a tap sets [landing] alone; a
  /// tap-and-drag also sets [retrieved] at release. Passing `retrieved`
  /// null (re-tapping after a drag) clears it — absent ⇒ same as landing.
  Future<void> setLanding(FieldCoord landing, {FieldCoord? retrieved}) {
    return _mutate(
      (draft) => draft.copyWith(landing: landing, retrieved: retrieved),
    );
  }

  Future<void> setTrajectory(Trajectory trajectory) {
    return _mutate((draft) => draft.copyWith(trajectory: trajectory));
  }

  /// The §15.1 fence-spline suggestion, confirmed or withdrawn via its chip.
  Future<void> setOffWall({required bool offWall}) {
    return _mutate((draft) => draft.copyWith(offWall: offWall));
  }

  /// A runner drag released on a base (§15.1), arriving as the dragged move
  /// plus its forced cascade (see [cascadeRunnerMove]) — applied as one
  /// mutation, one journal write. A re-drag of a runner replaces their
  /// target.
  Future<void> moveRunners(List<RunnerMove> moves) {
    return _mutate((draft) {
      var next = draft;
      for (final move in moves) {
        next = next.movingRunner(move.runnerId, from: move.from, to: move.to);
      }
      return next;
    });
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
