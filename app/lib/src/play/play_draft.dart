/// The uncommitted play (§15.5): everything the field canvas has gathered
/// since the in-play pitch, held *outside* the event stream until the ✓.
///
/// Deliberately not an event and never one: commit translates the draft into
/// the atomic sequence (`BallInPlay`, then consequences) in one append, so a
/// half-entered play can't corrupt game state — and the same JSON round-trip
/// that keeps the draft immutable is what the crash journal persists.
///
/// DIA-008a scope: landing (+retrieved), trajectory, offWall, and runner
/// advances. Fielder touches, outs, rule calls, and per-leg advance
/// attribution are DIA-008b, which will grow this model rather than replace
/// it.
library;

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/events/pending_event.dart';
import 'package:flutter/foundation.dart';

/// Where one runner ends up, relative to where the play found them.
///
/// One move per runner, holding the *net* advance (`from` = the base the
/// play started them on, `to` = the latest drag target). DIA-008b splits
/// this into per-leg advances when legs need distinct reasons and touch
/// attribution (§13.4); a clean single needs only the net.
@immutable
class RunnerMove {
  const RunnerMove({
    required this.runnerId,
    required this.from,
    required this.to,
  });

  factory RunnerMove.fromJson(Map<String, dynamic> json) => RunnerMove(
    runnerId: json['runnerId'] as String,
    from: json['from'] as int,
    to: json['to'] as int,
  );

  final String runnerId;

  /// 0 = batter's box, 1–3 bases (§4.3).
  final int from;

  /// 1–3 bases, 4 = scored (§4.3).
  final int to;

  Map<String, dynamic> toJson() => {
    'runnerId': runnerId,
    'from': from,
    'to': to,
  };
}

/// One occupied spot as the forced cascade sees it: who, the base the play
/// found them on (`origin`; 0 = batter's box), and where they currently
/// stand in the draft (`base`).
typedef RunnerSlot = ({String runnerId, int origin, int base});

/// A runner drag with the rulebook's geometry applied: **runners never pass
/// one another**, so releasing a trailing runner on or past a leading
/// runner's base pushes that leader forward, cascading — the bases-loaded
/// single walks everyone up, run included, in the same spirit as §11.3's
/// auto-applied walk chain. Trailing runners never move automatically, a
/// scored leader (base 4) is out of the way, and every pushed token stays
/// draggable, so an over-push costs one corrective drag.
///
/// Returns the dragged move plus every push, trailing-to-leading.
List<RunnerMove> cascadeRunnerMove(
  List<RunnerSlot> slots, {
  required String movedId,
  required int to,
}) {
  final moved = slots.firstWhere((s) => s.runnerId == movedId);
  final moves = [RunnerMove(runnerId: movedId, from: moved.origin, to: to)];
  var floor = to;
  final ahead = [...slots.where((s) => s.origin > moved.origin)]
    ..sort((a, b) => a.origin.compareTo(b.origin));
  for (final slot in ahead) {
    if (slot.base >= 4) continue; // scored — nobody left to displace
    if (slot.base > floor) {
      // Strictly ahead already; the chain (if any) restarts behind them.
      floor = slot.base;
      continue;
    }
    final pushed = floor + 1 > 4 ? 4 : floor + 1;
    moves.add(
      RunnerMove(runnerId: slot.runnerId, from: slot.origin, to: pushed),
    );
    floor = pushed;
  }
  return moves;
}

@immutable
class PlayDraft {
  const PlayDraft({
    required this.pitchEventId,
    required this.batterId,
    this.landing,
    this.retrieved,
    this.trajectory,
    this.landingIsCaught = false,
    this.offWall = false,
    this.runnerMoves = const [],
  });

  factory PlayDraft.fromJson(Map<String, dynamic> json) => PlayDraft(
    pitchEventId: json['pitchEventId'] as String,
    batterId: json['batterId'] as String,
    landing: json['landing'] == null
        ? null
        : FieldCoord.fromJson(json['landing'] as Map<String, dynamic>),
    retrieved: json['retrieved'] == null
        ? null
        : FieldCoord.fromJson(json['retrieved'] as Map<String, dynamic>),
    trajectory: trajectoryValues.map[json['trajectory']],
    landingIsCaught: json['landingIsCaught'] as bool? ?? false,
    offWall: json['offWall'] as bool? ?? false,
    runnerMoves: [
      for (final move in (json['runnerMoves'] as List<dynamic>? ?? []))
        RunnerMove.fromJson(move as Map<String, dynamic>),
    ],
  );

  /// The committed `PitchThrown` this play hangs off (§4.2's link).
  final String pitchEventId;

  /// The batter-runner: rendered at the plate, dragged like any runner but
  /// starting `from: 0`.
  final String batterId;

  final FieldCoord? landing;

  /// §15.1's tap-and-drag second grip; null ⇒ same as landing.
  final FieldCoord? retrieved;

  final Trajectory? trajectory;

  /// Caught in the air at the landing coordinate (§4.2). Always false in
  /// DIA-008a — marking the catch arrives with fielder touches (008b) —
  /// carried so the journal format doesn't change under 008b.
  final bool landingIsCaught;

  /// §15.1: auto-suggested when the landing sits on the fence spline; the
  /// scorer confirms via a chip.
  final bool offWall;

  /// Ordered by first entry; at most one move per runner (see [RunnerMove]).
  final List<RunnerMove> runnerMoves;

  /// A committable draft has the two facts §11.1 always collects: where and
  /// how it came off the bat.
  bool get committable => landing != null && trajectory != null;

  PlayDraft copyWith({
    FieldCoord? landing,
    Object? retrieved = _unset,
    Trajectory? trajectory,
    bool? landingIsCaught,
    bool? offWall,
    List<RunnerMove>? runnerMoves,
  }) {
    return PlayDraft(
      pitchEventId: pitchEventId,
      batterId: batterId,
      landing: landing ?? this.landing,
      retrieved: retrieved == _unset
          ? this.retrieved
          : retrieved as FieldCoord?,
      trajectory: trajectory ?? this.trajectory,
      landingIsCaught: landingIsCaught ?? this.landingIsCaught,
      offWall: offWall ?? this.offWall,
      runnerMoves: runnerMoves ?? this.runnerMoves,
    );
  }

  /// Sets or replaces this runner's move; a re-drag updates `to`, keeping
  /// the original `from` and entry order.
  PlayDraft movingRunner(
    String runnerId, {
    required int from,
    required int to,
  }) {
    final moves = [...runnerMoves];
    final existing = moves.indexWhere((m) => m.runnerId == runnerId);
    if (existing >= 0) {
      moves[existing] = RunnerMove(
        runnerId: runnerId,
        from: moves[existing].from,
        to: to,
      );
    } else {
      moves.add(RunnerMove(runnerId: runnerId, from: from, to: to));
    }
    return copyWith(runnerMoves: moves);
  }

  Map<String, dynamic> toJson() => {
    'pitchEventId': pitchEventId,
    'batterId': batterId,
    'landing': landing?.toJson(),
    'retrieved': retrieved?.toJson(),
    'trajectory': trajectoryValues.reverse[trajectory],
    'landingIsCaught': landingIsCaught,
    'offWall': offWall,
    'runnerMoves': [for (final move in runnerMoves) move.toJson()],
  };

  /// The atomic commit sequence (§15.5): `BallInPlay` first, then runner
  /// consequences in entry order. Throws [StateError] when not [committable]
  /// — the ✓ is disabled until then, so reaching this any other way is a
  /// bug, not an input.
  ///
  /// DIA-008a: every advance is `batted_ball` — misplay reasons and
  /// `enabledByTouchId` links need touches, which don't exist yet. `fair` is
  /// always true: the outcome that opens this surface is `in_play`, and foul
  /// field taps are out of DIA-008's scope.
  List<PendingEvent> toEvents() {
    final landing = this.landing;
    final trajectory = this.trajectory;
    if (landing == null || trajectory == null) {
      throw StateError('draft is not committable: landing/trajectory missing');
    }
    return [
      PendingEvent(
        type: 'BallInPlay',
        payload: BallInPlay(
          pitchEventId: pitchEventId,
          fair: true,
          trajectory: trajectory,
          landing: landing,
          retrieved: retrieved,
          landingIsCaught: landingIsCaught,
          offWall: offWall ? true : null,
        ).toJson(),
      ),
      for (final move in runnerMoves)
        PendingEvent(
          type: 'RunnerAdvance',
          payload: RunnerAdvance(
            runnerId: move.runnerId,
            from: move.from,
            to: move.to,
            reason: RunnerAdvanceReason.BATTED_BALL,
          ).toJson(),
        ),
    ];
  }
}

const _unset = Object();
