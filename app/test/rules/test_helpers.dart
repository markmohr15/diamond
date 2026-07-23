import 'package:diamond/src/events/generated/events.dart';

/// Builds [GameEvent]s for tests with monotonically increasing
/// `(wallClock, seq)` in call order — i.e. call order is *recording*
/// order, which is deliberately not always the same as logical order
/// (that's the whole point of the `effectiveAfter` tests).
class EventBuilder {
  EventBuilder({this.gameId = 'game-1', this.deviceId = 'device-1'});

  final String gameId;
  final String deviceId;
  final DateTime _base = DateTime.utc(2026, 4, 2);
  int _seq = 0;

  GameEvent make({
    required String id,
    required String type,
    required Map<String, dynamic> payload,
    String? corrects,
    String? effectiveAfter,
  }) {
    final event = GameEvent(
      id: id,
      gameId: gameId,
      seq: _seq,
      deviceId: deviceId,
      createdBy: 'scorer-1',
      wallClock: _base.add(Duration(seconds: _seq)),
      type: type,
      payload: payload,
      corrects: corrects,
      effectiveAfter: effectiveAfter,
    );
    _seq++;
    return event;
  }

  GameEvent pitch({
    required String id,
    required String batterId,
    required String pitcherId,
    required Outcome outcome,
    BatterSide batterSide = BatterSide.R,
    String? corrects,
    String? effectiveAfter,
  }) {
    return make(
      id: id,
      type: 'PitchThrown',
      payload: PitchThrown(
        pitcherId: pitcherId,
        batterId: batterId,
        batterSide: batterSide,
        outcome: outcome,
      ).toJson(),
      corrects: corrects,
      effectiveAfter: effectiveAfter,
    );
  }

  GameEvent countCorrection({
    required String id,
    required int balls,
    required int strikes,
    String? corrects,
    String? effectiveAfter,
  }) {
    return make(
      id: id,
      type: 'CountCorrection',
      payload: CountCorrection(balls: balls, strikes: strikes).toJson(),
      corrects: corrects,
      effectiveAfter: effectiveAfter,
    );
  }

  GameEvent runnerAdvance({
    required String id,
    required String runnerId,
    required int from,
    required int to,
    required RunnerAdvanceReason reason,
    String? enabledByTouchId,
    String? corrects,
    String? effectiveAfter,
  }) {
    return make(
      id: id,
      type: 'RunnerAdvance',
      payload: RunnerAdvance(
        runnerId: runnerId,
        from: from,
        to: to,
        reason: reason,
        enabledByTouchId: enabledByTouchId,
      ).toJson(),
      corrects: corrects,
      effectiveAfter: effectiveAfter,
    );
  }

  GameEvent runnerOut({
    required String id,
    required String runnerId,
    required int atBase,
    required How how,
    String? corrects,
    String? effectiveAfter,
  }) {
    return make(
      id: id,
      type: 'RunnerOut',
      payload: RunnerOut(runnerId: runnerId, atBase: atBase, how: how).toJson(),
      corrects: corrects,
      effectiveAfter: effectiveAfter,
    );
  }

  GameEvent ballInPlay({
    required String id,
    required String pitchEventId,
    bool fair = true,
    Trajectory trajectory = Trajectory.GROUND,
    FieldCoord? landing,
    bool landingIsCaught = false,
  }) {
    return make(
      id: id,
      type: 'BallInPlay',
      payload: BallInPlay(
        pitchEventId: pitchEventId,
        fair: fair,
        trajectory: trajectory,
        landing: landing ?? FieldCoord(x: 0, y: 100),
        landingIsCaught: landingIsCaught,
      ).toJson(),
    );
  }

  GameEvent fielderTouch({
    required String id,
    required String anchorEventId,
    required int position,
    required TouchType touchType,
    bool? ordinaryEffort,
  }) {
    return make(
      id: id,
      type: 'FielderTouch',
      payload: FielderTouch(
        ballInPlayEventId: anchorEventId,
        position: position,
        touchType: touchType,
        ordinaryEffort: ordinaryEffort,
      ).toJson(),
    );
  }

  GameEvent lineupSet({
    required String id,
    required String teamId,
    required List<String> battingOrder,
  }) {
    return make(
      id: id,
      type: 'LineupSet',
      payload: LineupSet(teamId: teamId, battingOrder: battingOrder).toJson(),
    );
  }

  GameEvent inningHalfStart({
    required String id,
    required int inning,
    required Half half,
    required String battingTeamId,
    GameStateSnapshot? snapshot,
  }) {
    return make(
      id: id,
      type: 'InningHalfStart',
      payload: InningHalfStart(
        inning: inning,
        half: half,
        battingTeamId: battingTeamId,
        snapshot: snapshot,
      ).toJson(),
    );
  }

  GameEvent inningHalfEnd({
    required String id,
    required InningHalfEndReason reason,
  }) {
    return make(
      id: id,
      type: 'InningHalfEnd',
      payload: InningHalfEnd(reason: reason).toJson(),
    );
  }

  GameEvent voidEvent({required String id, required String targetId}) {
    return make(
      id: id,
      type: 'VoidEvent',
      payload: VoidEvent(targetId: targetId).toJson(),
    );
  }
}
