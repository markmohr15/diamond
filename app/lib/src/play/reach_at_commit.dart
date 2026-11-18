import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/rules/game_state.dart';

/// What the ✓ does with a batter still standing on her walk-up to first
/// (§13.2 v0.56): settle it itself, or ask.
enum ReachAtCommit {
  /// A runner her contact pushed up was retired, which *is* the defense
  /// choosing her over the batter (§15.1 v0.56).
  fieldersChoice,

  /// Nothing on the play could explain the reach except the hit: one
  /// possible answer is not a question.
  single,

  /// The record leaves the reach open, so "Safe at 1B — how?" asks.
  ask,
}

/// How the ✓ will resolve the batter's reach, or null when there is nothing
/// to resolve: she was retired, or the scorer already answered for her.
///
/// [before] is the fold's base state ahead of the play. The ✓ and the
/// result in words beside it (DIA-018b-2) both read this, so what the line
/// says the play scores as is what the ✓ saves.
ReachAtCommit? reachAtCommit(PlayDraft draft, BaseState before) {
  if (!draft.reachNeedsAnswer) return null;
  if (outOnPushedRunner(draft, before)) return ReachAtCommit.fieldersChoice;
  final open =
      draft.chargeableMisplays.isNotEmpty ||
      draft.lastThrow != null ||
      threwElsewhere(draft, before);
  return open ? ReachAtCommit.ask : ReachAtCommit.single;
}

/// The draft with the ✓'s own answer to the reach applied, when it has one
/// and nothing would be asked; otherwise the draft unchanged.
PlayDraft withReachSettled(PlayDraft draft, BaseState before) {
  return switch (reachAtCommit(draft, before)) {
    ReachAtCommit.fieldersChoice => draft.resolvingReach(
      earned: true,
      reason: RunnerAdvanceReason.FIELDERS_CHOICE,
    ),
    ReachAtCommit.single => draft.resolvingReach(earned: true),
    ReachAtCommit.ask || null => draft,
  };
}

/// An out on a runner the batter's contact pushed — retired at the base
/// she started from, or one beyond it (§15.1 v0.56).
///
/// This *is* the defense choosing her over the batter, so the reach is a
/// fielder's choice and nothing is asked. Mark, 2026-09-04: the deciding
/// factor is "did we get an out on a runner attempting to move up one
/// base". Two bases is a different play — a runner going first to third on
/// a ball through the infield is running on her own, and the batter
/// standing on first got there on the hit.
bool outOnPushedRunner(PlayDraft draft, BaseState before) {
  final origins = <String, int>{
    if (before.first != null) before.first!: 1,
    if (before.second != null) before.second!: 2,
    if (before.third != null) before.third!: 3,
  };
  for (final entry in draft.entries) {
    if (entry is! OutEntry || entry.runnerId == draft.batterId) continue;
    final origin = origins[entry.runnerId];
    if (origin != null && entry.atBase - origin <= 1) return true;
  }
  return false;
}

/// Somebody threw it, so a fielder's choice is on the table even though
/// nobody was retired.
///
/// Deliberately *any* throw rather than one taken away from first. Where
/// the throw was going is not recorded, and marking a throw wild deletes
/// the reception that used to imply it — so keying on that made the answer
/// set depend on whether a **different** answer had eaten its own
/// evidence. Bases loaded, grounder to short, throw home and away: the
/// textbook fielder's choice, and it was offering *single* only. Mark's
/// test is the scorer's anyway — "a single if there really was no play to
/// be made, or a FC if they could have gotten an out elsewhere" — which is
/// a judgment, not something the record settles.
///
/// **And somebody else was on base.** A throw alone was necessary but not
/// sufficient: bases empty, grounder to short, throw to first, batter safe
/// — and fielder's choice was offered with nobody to choose against
/// (DIA-019 H). An out recorded on another runner this play needs her on
/// base too, so this one condition covers both.
bool threwElsewhere(PlayDraft draft, BaseState before) {
  final someoneOn =
      before.first != null || before.second != null || before.third != null;
  return draft.hasThrow && someoneOn;
}
