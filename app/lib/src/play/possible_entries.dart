import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/official_scoring.dart' show misplayTouchTypes;

/// What the entry surface may offer — the one place that decides it
/// (DIA-019 slice H). The what-happened popup and the chain strip's retype
/// menu each used to keep their own list, and they disagreed: the popup
/// refused "Booted" to a catcher chasing a wild pitch while the strip
/// offered it. Both now read from here, so a menu offers only what this
/// touch could have been.

/// Where the ball was when a fielder played it — the context that decides
/// which verbs are physically possible.
enum BallState {
  /// No batted ball: a pitch that got away, between pitches (§15.6).
  loosePitch,

  /// A batted ball still in the air — nobody but a deflection has touched
  /// it, and no roll has been traced.
  inFlight,

  /// A batted ball on the ground, whatever it was off the bat.
  onGround,
}

const _airborne = {Trajectory.FLY, Trajectory.POPUP, Trajectory.LINE};

/// The ball's state for the next fielder to play it.
///
/// A ball can only be caught while it is still in the air, and it is in the
/// air until somebody touches it — except for a deflection, the one touch
/// that leaves it up. A traced roll is proof it reached the ground: the
/// scorer said it travelled after landing, so nobody is catching it any more.
BallState nextBallState(PlayDraft draft) =>
    _stateAfter(draft, draft.entries.whereType<TouchEntry>().toList());

/// The ball's state when [touch] played it. Recorded types settle it where
/// they can — a catch or a drop was in the air, a boot was on the ground —
/// and only the ambiguous ones fall back to what the draft says now.
BallState ballStateAt(PlayDraft draft, TouchEntry touch) {
  final before = draft.entries
      .takeWhile((entry) => entry.key != touch.key)
      .whereType<TouchEntry>()
      .toList();
  final state = _stateAfter(draft, before);
  if (state == BallState.loosePitch) return state;
  return switch (touch.touchType) {
    TouchType.CAUGHT || TouchType.DROPPED => BallState.inFlight,
    TouchType.BOOTED => BallState.onGround,
    _ => state,
  };
}

BallState _stateAfter(PlayDraft draft, List<TouchEntry> touches) {
  if (!draft.battedBall) return BallState.loosePitch;
  final untouched =
      touches.isEmpty || touches.last.touchType == TouchType.DEFLECTED;
  return _airborne.contains(draft.trajectory) &&
          untouched &&
          draft.rollEnd == null
      ? BallState.inFlight
      : BallState.onGround;
}

/// §15.1's what-happened popup: everything a fielder at [position] could
/// have done to the ball in [state], in the order offered. `null` is
/// *Missed it* — she never touched the ball, so nothing is recorded.
List<TouchType?> ballPlayChoices(
  BallState state, {
  required int position,
  required Trajectory? trajectory,
}) => switch (state) {
  // §15.6: no batted ball, so the batted-ball verbs do not apply. A catcher
  // cannot *boot* a pitch — booting is a ground ball off the bat played with
  // the foot — and nothing caromed off anybody, so there is no deflection
  // either. `bobbled` rather than `dropped`: she never had it to drop.
  BallState.loosePitch => const [TouchType.FIELDED, TouchType.BOBBLED, null],
  BallState.inFlight => [
    TouchType.CAUGHT,
    TouchType.DROPPED,
    // Only a liner caroms, and only in the infield. Mark, 2026-09-04:
    // *"outfielders can't deflect, they can only miss"* — a ball off an
    // outfielder is a play she did not make, not a carom another fielder is
    // standing there to pick up. A pop-up one fielder touches and another
    // catches is likewise two fielders on one ball.
    if (trajectory == Trajectory.LINE && isInfield(position))
      TouchType.DEFLECTED,
    null,
    TouchType.FIELDED,
  ],
  BallState.onGround => [
    TouchType.FIELDED,
    TouchType.BOOTED,
    // It hit her and caromed away with no play to be made: a physical fact,
    // never an error candidate (§13.2), and the ball stays loose. Infield
    // only — see the liner above.
    if (isInfield(position)) TouchType.DEFLECTED,
    null,
  ],
};

/// The fielder whose throw [touch] received, if it is a reception — the one
/// a wild throw belongs to (§15.3).
///
/// A reception is a receiving type *and* somebody else touched the ball
/// first. `dropped` and `missed_catch` describe muffing a throw *or* a ball
/// off the bat or a pitch, and the type alone cannot tell them apart; who
/// had it before can.
TouchEntry? throwerInto(PlayDraft draft, TouchEntry touch) {
  if (!_receivingTypes.contains(touch.touchType)) return null;
  return draft.entries
      .takeWhile((entry) => entry.key != touch.key)
      .whereType<TouchEntry>()
      .where((earlier) => earlier.position != touch.position)
      .lastOrNull;
}

/// What a throw arriving can have been (Mark, 2026-10-23): *caught*,
/// *dropped* — it hit her glove and fell at her feet, so she still has it —
/// *missed* — it went past her — or *missed tag*. And *bad*, which belongs
/// to the thrower and is said with "The throw was wild". Dropped and missed
/// score alike (§13.2's catching error); what differs is where the ball is.
const _receivingTypes = {
  TouchType.RECEIVED_THROW,
  TouchType.DROPPED,
  TouchType.MISSED_CATCH,
};

/// Types after which she had the ball, and so could have missed a tag.
const _heldTypes = {
  TouchType.FIELDED,
  TouchType.CAUGHT,
  TouchType.RECEIVED_THROW,
  TouchType.TAG_APPLIED,
};

/// §15.3's retype menu on a touch node: the misplays this touch could have
/// been, plus `deflected` where a deflection was possible. Derived from the
/// same [ballPlayChoices] as the popup, so the two cannot disagree.
///
/// `wild_throw` is never offered: a throw goes bad on its way to somebody,
/// and "The throw was wild" on her node says so and charges the thrower. The
/// node's own type is always included, so a node already retyped shows what
/// it is.
List<TouchType> retypeChoices(PlayDraft draft, TouchEntry touch) {
  final List<TouchType> choices;
  if (throwerInto(draft, touch) != null) {
    choices = const [
      TouchType.DROPPED,
      TouchType.MISSED_CATCH,
      TouchType.TAG_MISSED,
    ];
  } else if (touch.touchType == TouchType.TAG_APPLIED ||
      touch.touchType == TouchType.TAG_MISSED) {
    choices = const [TouchType.TAG_MISSED];
  } else if (touch.touchType == TouchType.WILD_THROW) {
    choices = const [];
  } else {
    final possible = ballPlayChoices(
      ballStateAt(draft, touch),
      position: touch.position,
      trajectory: draft.trajectory,
    );
    choices = [
      for (final type in possible)
        if (type != null &&
            (misplayTouchTypes.contains(type) || type == TouchType.DEFLECTED))
          type,
      if (_heldTypes.contains(touch.touchType)) TouchType.TAG_MISSED,
    ];
  }
  return [
    if (!choices.contains(touch.touchType) &&
        (misplayTouchTypes.contains(touch.touchType) ||
            touch.touchType == TouchType.DEFLECTED))
      touch.touchType,
    ...choices,
  ];
}

/// The `how` values physically possible for [runnerId] out at [atBase]
/// (§4.3), likeliest first, as `(id, label, how)`. The OUT dialog and the
/// chain strip's out sheet both offer exactly these, so neither can propose
/// an out that couldn't have happened. [bases] is where the play found
/// everyone.
///
/// - A **force** needs the runner headed for the very next base *and* the
///   chain of occupied bases behind her (origin bases, with the batter
///   always running on `in_play`). A runner from second with first empty is
///   forced nowhere: thrown out at home, she was tagged.
/// - A **catch removes every force** — the batter is out in the air, so
///   nobody is compelled to advance and the runners owe a retouch instead.
/// - A **fly out** is the batter's alone; the **appeal** is a runner's
///   alone, and only against a catch.
///
/// [editingKey] is the out being edited, when there is one: only outs
/// entered *before* it can have removed her force. On a 6-4-3 the batter's
/// out at first comes after the force at second, and counting it would take
/// *Force* off the first out of every double play.
List<(String, String, How)> possibleHows(
  PlayDraft draft,
  String runnerId,
  int atBase,
  BaseState bases, {
  int? editingKey,
}) {
  final origin = _originBase(draft, runnerId, bases);
  final caught = draft.caughtInFlight;
  final isBatter = origin == 0;
  // An infield fly removes every force the way a catch does, caught or not
  // — the batter is out by the call. Retiring her already breaks the chain
  // below; this says why in the one place a reader looks.
  final forced =
      !caught &&
      !draft.infieldFlyDeclared &&
      atBase == origin + 1 &&
      _forceChainLive(draft, origin, bases, editingKey: editingKey);
  // Order is load-bearing: the OUT dialog preselects `.first`, so moving an
  // entry changes what the scorer is offered by default. That is invisible
  // from reading the list, hence this note.
  //
  // §15.6: between pitches she was running on her own, so the play's
  // vocabulary does not apply — no force without a batter, no fly out
  // without a batted ball.
  //
  // Leaving early and the look-back rule are rules at every level (Mark,
  // 2026-09-03), so no `RuleSet` gates them — whether a crew calls them
  // varies by crew, and the scorer records what was called. Both are dead
  // ball, no pitch, which is why they are offered only here: neither can
  // happen alongside a batted ball.
  if (!draft.battedBall) {
    return const [
      ('caught_stealing', 'Caught stealing', How.CAUGHT_STEALING),
      ('picked_off', 'Picked off', How.PICKED_OFF),
      ('tag', 'Tag', How.TAG),
      ('left_early', 'Left early', How.LEFT_EARLY),
      ('look_back', 'Look-back', How.LOOK_BACK_RULE),
    ];
  }
  return [
    if (caught && isBatter) ('fly_out', 'Fly out', How.FLY_OUT),
    if (forced) ('force', 'Force', How.FORCE),
    // No tag on the batter when the ball was caught: she is out *by the
    // catch*, and there is no tag to apply.
    if (!caught || !isBatter) ('tag', 'Tag', How.TAG),
    if (caught && !isBatter) ('appeal', "Didn't tag up", How.APPEAL),
  ];
}

/// The base the play found this runner on — force logic reads this, never a
/// mid-play draft position.
int _originBase(PlayDraft draft, String runnerId, BaseState bases) {
  if (runnerId == draft.batterId) return 0;
  if (runnerId == bases.first) return 1;
  if (runnerId == bases.second) return 2;
  return 3;
}

/// Whether every base behind [origin] is still occupied by a runner who has
/// to move — which is what keeps a force alive.
///
/// **Outs already recorded on this play count.** A force is removed when the
/// runner behind is retired: grounder to the first baseman, she steps on the
/// bag, then throws to second — that runner has to be **tagged**. Pre-pitch
/// occupancy alone cannot see that, because the out happened after the
/// pitch.
bool _forceChainLive(
  PlayDraft draft,
  int origin,
  BaseState bases, {
  int? editingKey,
}) {
  final retired = {
    for (final entry in draft.entries.takeWhile((e) => e.key != editingKey))
      if (entry is OutEntry) entry.runnerId,
  };

  String? runnerOn(int base) => switch (base) {
    1 => bases.first,
    2 => bases.second,
    3 => bases.third,
    // Not a base. The old `_` arm silently read third here, so an
    // out-of-range value answered a question about a base that does not
    // exist.
    _ => null,
  };

  for (var base = origin - 1; base >= 1; base--) {
    final runner = runnerOn(base);
    if (runner == null || retired.contains(runner)) return false;
  }

  // The batter's box pushes only while she is still live: `in_play` means
  // she is running, but not once she has been retired on this same play.
  return origin == 0 || !retired.contains(draft.batterId);
}

/// Whether the ball's landing node offers *Infield fly* (§15.3): a fair fly
/// or pop-up — never a liner or a bunt — with fewer than two out and runners
/// on first and second, once it has come down somewhere. The rule is the
/// same at every level, so no `RuleSet` gates it. Not offered once
/// declared, nor once the batter is out some other way than the catch it
/// would replace.
bool offersInfieldFly(
  PlayDraft draft, {
  required int outs,
  required BaseState bases,
}) {
  if (!draft.battedBall || draft.landing == null) return false;
  if (draft.trajectory != Trajectory.FLY &&
      draft.trajectory != Trajectory.POPUP) {
    return false;
  }
  if (outs >= 2 || bases.first == null || bases.second == null) return false;
  if (draft.infieldFlyDeclared) return false;
  return !draft.entries.any(
    (entry) =>
        entry is OutEntry &&
        entry.runnerId == draft.batterId &&
        entry.how != How.FLY_OUT,
  );
}
