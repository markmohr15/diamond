import 'package:diamond/src/events/generated/events.dart';

/// What a fielder was playing when she touched the ball: the one answer to
/// *"did she miss a fly or miss a throw?"* (DIA-025).
///
/// The touch type records what her glove did (`dropped`, `missed_catch`).
/// What she was receiving is a fact about the **play**, and the chain
/// already states it, so it is derived here rather than stored a second time
/// in the type, where the two could disagree after an edit.
enum Received {
  /// The catcher taking a pitch: the first touch on a pitch, by the catcher.
  pitch,

  /// A throw: the fielder before her on this play had the ball. Between
  /// pitches, anyone but the catcher who plays the ball first is taking a
  /// throw too, because a pickoff's thrower is never recorded.
  thrownBall,

  /// The ball itself, batted or loose: she was the first to play it, or the
  /// fielder before her never had it.
  liveBall,
}

/// The touch types after which the fielder **had the ball**, so that the
/// next fielder to touch it was taking her throw.
///
/// A boot or a drop leaves the ball at her feet, and the pickup is minted as
/// `fielded` at the moment she throws (§15.1 v0.56), so those arrive here as
/// a `fielded`. A wild throw is the exception that proves the rule: nobody
/// receives it, so whoever plays it next is chasing a loose ball.
const Set<TouchType> _hadTheBall = {
  TouchType.FIELDED,
  TouchType.CAUGHT,
  TouchType.RECEIVED_THROW,
  TouchType.BOBBLED,
  TouchType.TAG_APPLIED,
  TouchType.TAG_MISSED,
};

const int _catcher = 2;

/// What the fielder at [position] was receiving, given the touches made
/// before hers on the same play ([earlier], oldest first) and whether the
/// play hangs off a pitch rather than a batted ball ([anchorIsPitch]).
///
/// Both the rules engine and the entry surface read this, so the error a
/// chip names and the error the box score charges cannot disagree.
Received receivedBy({
  required int position,
  required bool anchorIsPitch,
  required List<({int position, TouchType touchType})> earlier,
}) {
  final previous = earlier.lastOrNull;
  if (previous == null) {
    if (!anchorIsPitch) return Received.liveBall;
    return position == _catcher ? Received.pitch : Received.thrownBall;
  }
  return previous.position != position &&
          _hadTheBall.contains(previous.touchType)
      ? Received.thrownBall
      : Received.liveBall;
}
