// GENERATED FILE — DO NOT EDIT.
// Source of truth: schema/ (envelope.schema.json + schema/events/*.schema.json).
// Regenerate with `npm run codegen` from the repo root. See tools/codegen/README.md.

// To parse this JSON data, do
//
//     final gameEvent = gameEventFromJson(jsonString);
//     final ballInPlay = ballInPlayFromJson(jsonString);
//     final countCorrection = countCorrectionFromJson(jsonString);
//     final fielderTouch = fielderTouchFromJson(jsonString);
//     final inningHalfEnd = inningHalfEndFromJson(jsonString);
//     final inningHalfStart = inningHalfStartFromJson(jsonString);
//     final lineupSet = lineupSetFromJson(jsonString);
//     final pitchThrown = pitchThrownFromJson(jsonString);
//     final ruleCall = ruleCallFromJson(jsonString);
//     final runnerAdvance = runnerAdvanceFromJson(jsonString);
//     final runnerOut = runnerOutFromJson(jsonString);
//     final voidEvent = voidEventFromJson(jsonString);

import 'dart:convert';

GameEvent gameEventFromJson(String str) => GameEvent.fromJson(json.decode(str));

String gameEventToJson(GameEvent data) => json.encode(data.toJson());

BallInPlay ballInPlayFromJson(String str) => BallInPlay.fromJson(json.decode(str));

String ballInPlayToJson(BallInPlay data) => json.encode(data.toJson());

CountCorrection countCorrectionFromJson(String str) => CountCorrection.fromJson(json.decode(str));

String countCorrectionToJson(CountCorrection data) => json.encode(data.toJson());

FielderTouch fielderTouchFromJson(String str) => FielderTouch.fromJson(json.decode(str));

String fielderTouchToJson(FielderTouch data) => json.encode(data.toJson());

InningHalfEnd inningHalfEndFromJson(String str) => InningHalfEnd.fromJson(json.decode(str));

String inningHalfEndToJson(InningHalfEnd data) => json.encode(data.toJson());

InningHalfStart inningHalfStartFromJson(String str) => InningHalfStart.fromJson(json.decode(str));

String inningHalfStartToJson(InningHalfStart data) => json.encode(data.toJson());

LineupSet lineupSetFromJson(String str) => LineupSet.fromJson(json.decode(str));

String lineupSetToJson(LineupSet data) => json.encode(data.toJson());

PitchThrown pitchThrownFromJson(String str) => PitchThrown.fromJson(json.decode(str));

String pitchThrownToJson(PitchThrown data) => json.encode(data.toJson());

RuleCall ruleCallFromJson(String str) => RuleCall.fromJson(json.decode(str));

String ruleCallToJson(RuleCall data) => json.encode(data.toJson());

RunnerAdvance runnerAdvanceFromJson(String str) => RunnerAdvance.fromJson(json.decode(str));

String runnerAdvanceToJson(RunnerAdvance data) => json.encode(data.toJson());

RunnerOut runnerOutFromJson(String str) => RunnerOut.fromJson(json.decode(str));

String runnerOutToJson(RunnerOut data) => json.encode(data.toJson());

VoidEvent voidEventFromJson(String str) => VoidEvent.fromJson(json.decode(str));

String voidEventToJson(VoidEvent data) => json.encode(data.toJson());


///Envelope shared by every event (spec §2). Append-only. Ordering: (wallClock, deviceId,
///seq).
class GameEvent {
    
    ///id of the event this supersedes (§6)
    final String? corrects;
    
    ///userId of the scorer
    final String createdBy;
    final String deviceId;
    
    ///id of the event this logically follows, when recorded later than it happened (§6 insert)
    ///— e.g. a stolen base noticed two pitches late. Projections fold in this logical order,
    ///not recording order.
    final String? effectiveAfter;
    final String gameId;
    
    ///UUIDv7, generated on device
    final String id;
    final Map<String, dynamic> payload;
    
    ///monotonic per-device
    final int seq;
    
    ///discriminant; matches an events/*.schema.json title
    final String type;
    final DateTime wallClock;

    GameEvent({
        this.corrects,
        required this.createdBy,
        required this.deviceId,
        this.effectiveAfter,
        required this.gameId,
        required this.id,
        required this.payload,
        required this.seq,
        required this.type,
        required this.wallClock,
    });

    factory GameEvent.fromJson(Map<String, dynamic> json) => GameEvent(
        corrects: json["corrects"],
        createdBy: json["createdBy"],
        deviceId: json["deviceId"],
        effectiveAfter: json["effectiveAfter"],
        gameId: json["gameId"],
        id: json["id"],
        payload: Map.from(json["payload"]).map((k, v) => MapEntry<String, dynamic>(k, v)),
        seq: json["seq"],
        type: json["type"],
        wallClock: DateTime.parse(json["wallClock"]),
    );

    Map<String, dynamic> toJson() => {
        "corrects": corrects,
        "createdBy": createdBy,
        "deviceId": deviceId,
        "effectiveAfter": effectiveAfter,
        "gameId": gameId,
        "id": id,
        "payload": Map.from(payload).map((k, v) => MapEntry<String, dynamic>(k, v)),
        "seq": seq,
        "type": type,
        "wallClock": wallClock.toIso8601String(),
    };
}


///Batted ball incl. fouls with coordinates (spec §4.2, §3.2).
class BallInPlay {
    final ContactQuality? contactQuality;
    final bool fair;
    
    ///first contact: where it landed, hit the wall, or met a glove (§15.1)
    final FieldCoord landing;
    final bool landingIsCaught;
    
    ///hit the fence on the fly (§15.1, §16.2)
    final bool? offWall;
    final String pitchEventId;
    
    ///where a fielder finally gained possession, when meaningfully different from landing
    ///(§15.1). Absent = same as landing.
    final FieldCoord? retrieved;
    
    ///scorer judgment (§13, v0.43): this batted ball was a sacrifice. Required for a sac bunt —
    ///no physical record distinguishes bunting to advance a runner from bunting for a hit — and
    ///optional for a sac fly, which derives (§13.6) and which this overrides when present.
    ///Plate appearance, not an at-bat.
    final bool? sacrifice;
    final Trajectory trajectory;

    BallInPlay({
        this.contactQuality,
        required this.fair,
        required this.landing,
        required this.landingIsCaught,
        this.offWall,
        required this.pitchEventId,
        this.retrieved,
        this.sacrifice,
        required this.trajectory,
    });

    factory BallInPlay.fromJson(Map<String, dynamic> json) => BallInPlay(
        contactQuality: contactQualityValues.map[json["contactQuality"]],
        fair: json["fair"],
        landing: FieldCoord.fromJson(json["landing"]),
        landingIsCaught: json["landingIsCaught"],
        offWall: json["offWall"],
        pitchEventId: json["pitchEventId"],
        retrieved: json["retrieved"] == null ? null : FieldCoord.fromJson(json["retrieved"]),
        sacrifice: json["sacrifice"],
        trajectory: trajectoryValues.map[json["trajectory"]]!,
    );

    Map<String, dynamic> toJson() => {
        "contactQuality": contactQualityValues.reverse[contactQuality],
        "fair": fair,
        "landing": landing.toJson(),
        "landingIsCaught": landingIsCaught,
        "offWall": offWall,
        "pitchEventId": pitchEventId,
        "retrieved": retrieved?.toJson(),
        "sacrifice": sacrifice,
        "trajectory": trajectoryValues.reverse[trajectory],
    };
}

enum ContactQuality {
    AVERAGE,
    HARD,
    WEAK
}

final contactQualityValues = EnumValues({
    "average": ContactQuality.AVERAGE,
    "hard": ContactQuality.HARD,
    "weak": ContactQuality.WEAK
});


///first contact: where it landed, hit the wall, or met a glove (§15.1)
///
///Field coordinate in absolute FEET (spec §3.2). Home plate = (0,0); +y toward second
///base/CF; bearing theta = atan2(x, y), negative = third-base side; |theta| > 45deg is foul
///territory (never clamp).
///
///where a fielder finally gained possession, when meaningfully different from landing
///(§15.1). Absent = same as landing.
class FieldCoord {
    final double x;
    final double y;

    FieldCoord({
        required this.x,
        required this.y,
    });

    factory FieldCoord.fromJson(Map<String, dynamic> json) => FieldCoord(
        x: json["x"]?.toDouble(),
        y: json["y"]?.toDouble(),
    );

    Map<String, dynamic> toJson() => {
        "x": x,
        "y": y,
    };
}

enum Trajectory {
    BUNT,
    FLY,
    GROUND,
    LINE,
    POPUP
}

final trajectoryValues = EnumValues({
    "bunt": Trajectory.BUNT,
    "fly": Trajectory.FLY,
    "ground": Trajectory.GROUND,
    "line": Trajectory.LINE,
    "popup": Trajectory.POPUP
});


///Authoritative count checkpoint (spec §12.5). Projection treats as override; back-infers
///unknown pitches where the math allows, marks inferences as such.
class CountCorrection {
    final int balls;
    final int strikes;

    CountCorrection({
        required this.balls,
        required this.strikes,
    });

    factory CountCorrection.fromJson(Map<String, dynamic> json) => CountCorrection(
        balls: json["balls"],
        strikes: json["strikes"],
    );

    Map<String, dynamic> toJson() => {
        "balls": balls,
        "strikes": strikes,
    };
}


///Physical touch vocabulary — never official-scoring language (spec §4.2, §13). Official
///errors are DERIVED.
class FielderTouch {
    final String ballInPlayEventId;
    
    ///optional for opponents
    final String? fielderId;
    final FieldCoord? location;
    
    ///scorer judgment on misplays; inferred default, overridable post-hoc (§13.2)
    final bool? ordinaryEffort;
    final int position;
    
    ///how a received_throw arrived (§13, §22.1). Default clean; purely developmental, never
    ///affects official scoring.
    final ReceivedQuality? receivedQuality;
    final TouchType touchType;

    FielderTouch({
        required this.ballInPlayEventId,
        this.fielderId,
        this.location,
        this.ordinaryEffort,
        required this.position,
        this.receivedQuality,
        required this.touchType,
    });

    factory FielderTouch.fromJson(Map<String, dynamic> json) => FielderTouch(
        ballInPlayEventId: json["ballInPlayEventId"],
        fielderId: json["fielderId"],
        location: json["location"] == null ? null : FieldCoord.fromJson(json["location"]),
        ordinaryEffort: json["ordinaryEffort"],
        position: json["position"],
        receivedQuality: receivedQualityValues.map[json["receivedQuality"]],
        touchType: touchTypeValues.map[json["touchType"]]!,
    );

    Map<String, dynamic> toJson() => {
        "ballInPlayEventId": ballInPlayEventId,
        "fielderId": fielderId,
        "location": location?.toJson(),
        "ordinaryEffort": ordinaryEffort,
        "position": position,
        "receivedQuality": receivedQualityValues.reverse[receivedQuality],
        "touchType": touchTypeValues.reverse[touchType],
    };
}


///how a received_throw arrived (§13, §22.1). Default clean; purely developmental, never
///affects official scoring.
enum ReceivedQuality {
    CLEAN,
    HIGH,
    SHORT_HOP,
    WIDE
}

final receivedQualityValues = EnumValues({
    "clean": ReceivedQuality.CLEAN,
    "high": ReceivedQuality.HIGH,
    "short_hop": ReceivedQuality.SHORT_HOP,
    "wide": ReceivedQuality.WIDE
});

enum TouchType {
    BOBBLED,
    BOOTED,
    CAUGHT,
    DEFLECTED,
    DROPPED,
    FIELDED,
    MISSED_CATCH,
    RECEIVED_THROW,
    TAG_APPLIED,
    TAG_MISSED,
    WILD_THROW
}

final touchTypeValues = EnumValues({
    "bobbled": TouchType.BOBBLED,
    "booted": TouchType.BOOTED,
    "caught": TouchType.CAUGHT,
    "deflected": TouchType.DEFLECTED,
    "dropped": TouchType.DROPPED,
    "fielded": TouchType.FIELDED,
    "missed_catch": TouchType.MISSED_CATCH,
    "received_throw": TouchType.RECEIVED_THROW,
    "tag_applied": TouchType.TAG_APPLIED,
    "tag_missed": TouchType.TAG_MISSED,
    "wild_throw": TouchType.WILD_THROW
});


///Explicit half-inning close (spec §4.4). 'three_outs' is auto-implied by the fold once
///outs reach 3 and doesn't require this event to appear. Any other reason is authoritative
///and closes the half even with fewer than 3 outs.
class InningHalfEnd {
    final InningHalfEndReason reason;

    InningHalfEnd({
        required this.reason,
    });

    factory InningHalfEnd.fromJson(Map<String, dynamic> json) => InningHalfEnd(
        reason: inningHalfEndReasonValues.map[json["reason"]]!,
    );

    Map<String, dynamic> toJson() => {
        "reason": inningHalfEndReasonValues.reverse[reason],
    };
}

enum InningHalfEndReason {
    COACH_AGREEMENT,
    MERCY,
    OTHER,
    RUN_CAP,
    SUSPENDED,
    THREE_OUTS,
    TIME_LIMIT,
    WALKOFF
}

final inningHalfEndReasonValues = EnumValues({
    "coach_agreement": InningHalfEndReason.COACH_AGREEMENT,
    "mercy": InningHalfEndReason.MERCY,
    "other": InningHalfEndReason.OTHER,
    "run_cap": InningHalfEndReason.RUN_CAP,
    "suspended": InningHalfEndReason.SUSPENDED,
    "three_outs": InningHalfEndReason.THREE_OUTS,
    "time_limit": InningHalfEndReason.TIME_LIMIT,
    "walkoff": InningHalfEndReason.WALKOFF
});


///Derived state checkpoint boundary (spec §4.4, §7). Marks the start of a half-inning;
///count/outs/bases always reset to empty here. The optional snapshot is a performance cache
///of cumulative state — never truth, always reproducible by folding from genesis.
class InningHalfStart {
    final String battingTeamId;
    final Half half;
    final int inning;
    final GameStateSnapshot? snapshot;

    InningHalfStart({
        required this.battingTeamId,
        required this.half,
        required this.inning,
        this.snapshot,
    });

    factory InningHalfStart.fromJson(Map<String, dynamic> json) => InningHalfStart(
        battingTeamId: json["battingTeamId"],
        half: halfValues.map[json["half"]]!,
        inning: json["inning"],
        snapshot: json["snapshot"] == null ? null : GameStateSnapshot.fromJson(json["snapshot"]),
    );

    Map<String, dynamic> toJson() => {
        "battingTeamId": battingTeamId,
        "half": halfValues.reverse[half],
        "inning": inning,
        "snapshot": snapshot?.toJson(),
    };
}

enum Half {
    BOTTOM,
    TOP
}

final halfValues = EnumValues({
    "bottom": Half.BOTTOM,
    "top": Half.TOP
});


///Cumulative game state carried into a half-inning (spec §7). Cache only — always
///reproducible by folding from genesis. Per-half state (count, outs, bases) is deliberately
///excluded: it always resets to empty at a half-inning boundary, so caching it would be
///redundant.
class GameStateSnapshot {
    
    ///pitch event id -> count effect that a CountCorrection's back-inference resolved uniquely
    ///(spec §12.5). Cumulative across halves like the other fields; empty when no inference has
    ///occurred.
    final Map<String, InferredPitchEffect> inferredPitchEffects;
    
    ///teamId -> index into that team's LineupSet.battingOrder for the next batter due
    final Map<String, int> nextBatterIndexByTeam;
    
    ///pitcherId -> total pitches thrown so far this game
    final Map<String, int> pitchCountByPitcher;
    
    ///teamId -> runs scored so far
    final Map<String, int> runsByTeam;

    GameStateSnapshot({
        required this.inferredPitchEffects,
        required this.nextBatterIndexByTeam,
        required this.pitchCountByPitcher,
        required this.runsByTeam,
    });

    factory GameStateSnapshot.fromJson(Map<String, dynamic> json) => GameStateSnapshot(
        inferredPitchEffects: Map.from(json["inferredPitchEffects"]).map((k, v) => MapEntry<String, InferredPitchEffect>(k, inferredPitchEffectValues.map[v]!)),
        nextBatterIndexByTeam: Map.from(json["nextBatterIndexByTeam"]).map((k, v) => MapEntry<String, int>(k, v)),
        pitchCountByPitcher: Map.from(json["pitchCountByPitcher"]).map((k, v) => MapEntry<String, int>(k, v)),
        runsByTeam: Map.from(json["runsByTeam"]).map((k, v) => MapEntry<String, int>(k, v)),
    );

    Map<String, dynamic> toJson() => {
        "inferredPitchEffects": Map.from(inferredPitchEffects).map((k, v) => MapEntry<String, dynamic>(k, inferredPitchEffectValues.reverse[v])),
        "nextBatterIndexByTeam": Map.from(nextBatterIndexByTeam).map((k, v) => MapEntry<String, dynamic>(k, v)),
        "pitchCountByPitcher": Map.from(pitchCountByPitcher).map((k, v) => MapEntry<String, dynamic>(k, v)),
        "runsByTeam": Map.from(runsByTeam).map((k, v) => MapEntry<String, dynamic>(k, v)),
    };
}

enum InferredPitchEffect {
    BALL,
    STRIKE_EFFECT
}

final inferredPitchEffectValues = EnumValues({
    "ball": InferredPitchEffect.BALL,
    "strike_effect": InferredPitchEffect.STRIKE_EFFECT
});


///Initial batting order for one team (spec §4.4). Batter-due is derived from this plus
///completed-plate-appearance counts on every fold — never cached positionally — so
///BattingOrderAdjusted (M2) slots in without refactor.
class LineupSet {
    
    ///playerIds in batting order
    final List<String> battingOrder;
    final String teamId;

    LineupSet({
        required this.battingOrder,
        required this.teamId,
    });

    factory LineupSet.fromJson(Map<String, dynamic> json) => LineupSet(
        battingOrder: List<String>.from(json["battingOrder"].map((x) => x)),
        teamId: json["teamId"],
    );

    Map<String, dynamic> toJson() => {
        "battingOrder": List<dynamic>.from(battingOrder.map((x) => x)),
        "teamId": teamId,
    };
}


///One per pitch, always (spec §4.1). intended* = the call; actual* = reality.
///actualLocation required only when location capture is ON (§12.4).
class PitchThrown {
    final ZoneCoord? actualLocation;
    final String? actualType;
    
    ///observed offensive posture on this pitch, orthogonal to outcome (§4.1, §11.1). Absent =
    ///conventional AB posture.
    final BatterAction? batterAction;
    final String batterId;
    final BatterSide batterSide;
    
    ///set when the pitch hit the dirt before reaching the catcher (§3.3); mutually exclusive
    ///with an observed actualLocation. Actual only — never a call.
    final BounceCoord? bounceLocation;
    final ZoneCoord? intendedLocation;
    
    ///PitchTypeId (team-configured)
    final String? intendedType;
    
    ///CallZone id (§10.1)
    final String? intendedZoneId;
    
    ///strike_unspecified (§4.1, §11.2 bailout): a strike of unknown kind — called, swinging, or
    ///possibly an uncaught foul; the count advanced and the scorer doesn't know how. Full count
    ///effect (strike three at two strikes); excluded from swing/contact analytics. At two
    ///strikes FOUL vs STRIKE is a read of whether the at-bat ended, not a judgment about the
    ///pitch. catcher_interference (§4.1 v0.43): dead ball, no count effect, plate appearance
    ///ends, batter awarded first with the forced chain — structurally the hit_by_pitch pattern;
    ///scored E2 by derivation (§13.2).
    final Outcome outcome;
    final String pitcherId;
    
    ///mph, optional
    final double? velocity;

    PitchThrown({
        this.actualLocation,
        this.actualType,
        this.batterAction,
        required this.batterId,
        required this.batterSide,
        this.bounceLocation,
        this.intendedLocation,
        this.intendedType,
        this.intendedZoneId,
        required this.outcome,
        required this.pitcherId,
        this.velocity,
    });

    factory PitchThrown.fromJson(Map<String, dynamic> json) => PitchThrown(
        actualLocation: json["actualLocation"] == null ? null : ZoneCoord.fromJson(json["actualLocation"]),
        actualType: json["actualType"],
        batterAction: batterActionValues.map[json["batterAction"]],
        batterId: json["batterId"],
        batterSide: batterSideValues.map[json["batterSide"]]!,
        bounceLocation: json["bounceLocation"] == null ? null : BounceCoord.fromJson(json["bounceLocation"]),
        intendedLocation: json["intendedLocation"] == null ? null : ZoneCoord.fromJson(json["intendedLocation"]),
        intendedType: json["intendedType"],
        intendedZoneId: json["intendedZoneId"],
        outcome: outcomeValues.map[json["outcome"]]!,
        pitcherId: json["pitcherId"],
        velocity: json["velocity"]?.toDouble(),
    );

    Map<String, dynamic> toJson() => {
        "actualLocation": actualLocation?.toJson(),
        "actualType": actualType,
        "batterAction": batterActionValues.reverse[batterAction],
        "batterId": batterId,
        "batterSide": batterSideValues.reverse[batterSide],
        "bounceLocation": bounceLocation?.toJson(),
        "intendedLocation": intendedLocation?.toJson(),
        "intendedType": intendedType,
        "intendedZoneId": intendedZoneId,
        "outcome": outcomeValues.reverse[outcome],
        "pitcherId": pitcherId,
        "velocity": velocity,
    };
}


///Strike-zone coordinate, catcher's perspective, normalized to the batter's zone (spec
///§3.1). x: 0=middle of plate, -1/+1 = zone edges (negative = third-base side, absolute;
///flip by handedness at render). y: 0=bottom of zone, 1=top. Values outside [-1,1]/[0,1]
///are valid out-of-zone locations. Never clamp.
class ZoneCoord {
    final double x;
    final double y;

    ZoneCoord({
        required this.x,
        required this.y,
    });

    factory ZoneCoord.fromJson(Map<String, dynamic> json) => ZoneCoord(
        x: json["x"]?.toDouble(),
        y: json["y"]?.toDouble(),
    );

    Map<String, dynamic> toJson() => {
        "x": x,
        "y": y,
    };
}


///observed offensive posture on this pitch, orthogonal to outcome (§4.1, §11.1). Absent =
///conventional AB posture.
enum BatterAction {
    FAKE_SLAP,
    PULLED_BUNT,
    SHOWED_BUNT,
    SLAP,
    SLASH
}

final batterActionValues = EnumValues({
    "fake_slap": BatterAction.FAKE_SLAP,
    "pulled_bunt": BatterAction.PULLED_BUNT,
    "showed_bunt": BatterAction.SHOWED_BUNT,
    "slap": BatterAction.SLAP,
    "slash": BatterAction.SLASH
});

enum BatterSide {
    L,
    R
}

final batterSideValues = EnumValues({
    "L": BatterSide.L,
    "R": BatterSide.R
});


///set when the pitch hit the dirt before reaching the catcher (§3.3); mutually exclusive
///with an observed actualLocation. Actual only — never a call.
///
///Landing spot of a pitch that hit the dirt before reaching the catcher, whether it bounced
///in front of the plate or between the plate and the catcher (spec §3.3). Only ever an
///actual location, never a call (intendedLocation stays a ZoneCoord).
class BounceCoord {
    
    ///Absolute FEET from the front edge of the plate. Positive = toward the pitcher (bounced
    ///out front); 0 = front edge; negative = behind the front edge toward the catcher (a short
    ///hop between the plate and the catcher, or skipped past the back). Absolute feet, not
    ///normalized, because ground geometry does not vary with batter height. Never clamp.
    ///OPTIONAL: absent means the pitch is known to have hit the dirt but its depth was not
    ///captured (§11.1's hinge skipped, §11.2's mode ladder) — x alone is still a real
    ///observation, and both consumers of a bounce that do not need depth (§4.1's conventional
    ///y_ground coordinate, §17.4's bounced-is-uncompetitive) read fine without it. Absent is
    ///never 0.
    final double? depth;
    
    ///SAME normalized lateral axis as ZoneCoord.x: absolute, catcher's view, flip by handedness
    ///at render.
    final double x;

    BounceCoord({
        this.depth,
        required this.x,
    });

    factory BounceCoord.fromJson(Map<String, dynamic> json) => BounceCoord(
        depth: json["depth"]?.toDouble(),
        x: json["x"]?.toDouble(),
    );

    Map<String, dynamic> toJson() => {
        "depth": depth,
        "x": x,
    };
}


///strike_unspecified (§4.1, §11.2 bailout): a strike of unknown kind — called, swinging, or
///possibly an uncaught foul; the count advanced and the scorer doesn't know how. Full count
///effect (strike three at two strikes); excluded from swing/contact analytics. At two
///strikes FOUL vs STRIKE is a read of whether the at-bat ended, not a judgment about the
///pitch. catcher_interference (§4.1 v0.43): dead ball, no count effect, plate appearance
///ends, batter awarded first with the forced chain — structurally the hit_by_pitch pattern;
///scored E2 by derivation (§13.2).
enum Outcome {
    BALL,
    BALL_INTENTIONAL,
    CALLED_STRIKE,
    CATCHER_INTERFERENCE,
    FOUL,
    FOUL_BUNT,
    FOUL_TIP,
    HIT_BY_PITCH,
    ILLEGAL_PITCH,
    IN_PLAY,
    NO_PITCH,
    STRIKE_UNSPECIFIED,
    SWINGING_STRIKE,
    UNKNOWN
}

final outcomeValues = EnumValues({
    "ball": Outcome.BALL,
    "ball_intentional": Outcome.BALL_INTENTIONAL,
    "called_strike": Outcome.CALLED_STRIKE,
    "catcher_interference": Outcome.CATCHER_INTERFERENCE,
    "foul": Outcome.FOUL,
    "foul_bunt": Outcome.FOUL_BUNT,
    "foul_tip": Outcome.FOUL_TIP,
    "hit_by_pitch": Outcome.HIT_BY_PITCH,
    "illegal_pitch": Outcome.ILLEGAL_PITCH,
    "in_play": Outcome.IN_PLAY,
    "no_pitch": Outcome.NO_PITCH,
    "strike_unspecified": Outcome.STRIKE_UNSPECIFIED,
    "swinging_strike": Outcome.SWINGING_STRIKE,
    "unknown": Outcome.UNKNOWN
});


///Umpire rulings as first-class events — the judicial sibling of FielderTouch (spec §4.5).
class RuleCall {
    final int? againstPosition;
    final CallType callType;
    final FieldCoord? location;
    final String? note;
    final String? runnerId;

    RuleCall({
        this.againstPosition,
        required this.callType,
        this.location,
        this.note,
        this.runnerId,
    });

    factory RuleCall.fromJson(Map<String, dynamic> json) => RuleCall(
        againstPosition: json["againstPosition"],
        callType: callTypeValues.map[json["callType"]]!,
        location: json["location"] == null ? null : FieldCoord.fromJson(json["location"]),
        note: json["note"],
        runnerId: json["runnerId"],
    );

    Map<String, dynamic> toJson() => {
        "againstPosition": againstPosition,
        "callType": callTypeValues.reverse[callType],
        "location": location?.toJson(),
        "note": note,
        "runnerId": runnerId,
    };
}

enum CallType {
    DEAD_BALL_AWARD,
    GROUND_RULE,
    ILLEGAL_PITCH_RULING,
    INFIELD_FLY,
    INTERFERENCE_BATTER,
    INTERFERENCE_CATCHER,
    INTERFERENCE_RUNNER,
    INTERFERENCE_SPECTATOR,
    LOOK_BACK_VIOLATION,
    OBSTRUCTION,
    UMPIRE_REVERSAL
}

final callTypeValues = EnumValues({
    "dead_ball_award": CallType.DEAD_BALL_AWARD,
    "ground_rule": CallType.GROUND_RULE,
    "illegal_pitch_ruling": CallType.ILLEGAL_PITCH_RULING,
    "infield_fly": CallType.INFIELD_FLY,
    "interference_batter": CallType.INTERFERENCE_BATTER,
    "interference_catcher": CallType.INTERFERENCE_CATCHER,
    "interference_runner": CallType.INTERFERENCE_RUNNER,
    "interference_spectator": CallType.INTERFERENCE_SPECTATOR,
    "look_back_violation": CallType.LOOK_BACK_VIOLATION,
    "obstruction": CallType.OBSTRUCTION,
    "umpire_reversal": CallType.UMPIRE_REVERSAL
});


///spec §4.3. from 0 = batter's box; to 4 = scored. from==to records surviving a play (e.g.,
///rundown) attributed to a misplay.
class RunnerAdvance {
    
    ///RuleCall that awarded this advance (§4.5)
    final String? enabledByCallId;
    
    ///FielderTouch that enabled this advance (§13.1)
    final String? enabledByTouchId;
    final int from;
    final RunnerAdvanceReason reason;
    final String runnerId;
    final int to;

    RunnerAdvance({
        this.enabledByCallId,
        this.enabledByTouchId,
        required this.from,
        required this.reason,
        required this.runnerId,
        required this.to,
    });

    factory RunnerAdvance.fromJson(Map<String, dynamic> json) => RunnerAdvance(
        enabledByCallId: json["enabledByCallId"],
        enabledByTouchId: json["enabledByTouchId"],
        from: json["from"],
        reason: runnerAdvanceReasonValues.map[json["reason"]]!,
        runnerId: json["runnerId"],
        to: json["to"],
    );

    Map<String, dynamic> toJson() => {
        "enabledByCallId": enabledByCallId,
        "enabledByTouchId": enabledByTouchId,
        "from": from,
        "reason": runnerAdvanceReasonValues.reverse[reason],
        "runnerId": runnerId,
        "to": to,
    };
}

enum RunnerAdvanceReason {
    AWARDED,
    BALK,
    BATTED_BALL,
    CATCHER_INTERFERENCE,
    DEFENSIVE_INDIFFERENCE,
    DROPPED_THIRD_STRIKE,
    ERROR,
    FIELDERS_CHOICE,
    GROUND_RULE,
    HBP,
    ILLEGAL_PITCH,
    OBSTRUCTION,
    PASSED_BALL,
    STOLEN_BASE,
    WALK,
    WILD_PITCH,
    WILD_THROW
}

final runnerAdvanceReasonValues = EnumValues({
    "awarded": RunnerAdvanceReason.AWARDED,
    "balk": RunnerAdvanceReason.BALK,
    "batted_ball": RunnerAdvanceReason.BATTED_BALL,
    "catcher_interference": RunnerAdvanceReason.CATCHER_INTERFERENCE,
    "defensive_indifference": RunnerAdvanceReason.DEFENSIVE_INDIFFERENCE,
    "dropped_third_strike": RunnerAdvanceReason.DROPPED_THIRD_STRIKE,
    "error": RunnerAdvanceReason.ERROR,
    "fielders_choice": RunnerAdvanceReason.FIELDERS_CHOICE,
    "ground_rule": RunnerAdvanceReason.GROUND_RULE,
    "hbp": RunnerAdvanceReason.HBP,
    "illegal_pitch": RunnerAdvanceReason.ILLEGAL_PITCH,
    "obstruction": RunnerAdvanceReason.OBSTRUCTION,
    "passed_ball": RunnerAdvanceReason.PASSED_BALL,
    "stolen_base": RunnerAdvanceReason.STOLEN_BASE,
    "walk": RunnerAdvanceReason.WALK,
    "wild_pitch": RunnerAdvanceReason.WILD_PITCH,
    "wild_throw": RunnerAdvanceReason.WILD_THROW
});


///spec §4.3.
class RunnerOut {
    final int atBase;
    final String? enabledByCallId;
    final How how;
    
    ///FielderTouch credited with the putout
    final String? putoutTouchId;
    final String runnerId;

    RunnerOut({
        required this.atBase,
        this.enabledByCallId,
        required this.how,
        this.putoutTouchId,
        required this.runnerId,
    });

    factory RunnerOut.fromJson(Map<String, dynamic> json) => RunnerOut(
        atBase: json["atBase"],
        enabledByCallId: json["enabledByCallId"],
        how: howValues.map[json["how"]]!,
        putoutTouchId: json["putoutTouchId"],
        runnerId: json["runnerId"],
    );

    Map<String, dynamic> toJson() => {
        "atBase": atBase,
        "enabledByCallId": enabledByCallId,
        "how": howValues.reverse[how],
        "putoutTouchId": putoutTouchId,
        "runnerId": runnerId,
    };
}

enum How {
    ABANDONED,
    APPEAL,
    BATTED_BALL_CONTACT,
    BATTER_OUT_OF_BOX,
    CAUGHT_STEALING,
    FLY_OUT,
    FORCE,
    INFIELD_FLY,
    INTERFERENCE,
    LEFT_EARLY,
    LOOK_BACK_RULE,
    PICKED_OFF,
    STRIKEOUT,
    STRIKEOUT_D3_K_THROW,
    TAG
}

final howValues = EnumValues({
    "abandoned": How.ABANDONED,
    "appeal": How.APPEAL,
    "batted_ball_contact": How.BATTED_BALL_CONTACT,
    "batter_out_of_box": How.BATTER_OUT_OF_BOX,
    "caught_stealing": How.CAUGHT_STEALING,
    "fly_out": How.FLY_OUT,
    "force": How.FORCE,
    "infield_fly": How.INFIELD_FLY,
    "interference": How.INTERFERENCE,
    "left_early": How.LEFT_EARLY,
    "look_back_rule": How.LOOK_BACK_RULE,
    "picked_off": How.PICKED_OFF,
    "strikeout": How.STRIKEOUT,
    "strikeout_d3k_throw": How.STRIKEOUT_D3_K_THROW,
    "tag": How.TAG
});


///Undo (spec §6): appending this voids targetId. Unlimited depth. When a committed play was
///emitted atomically, the UI voids the whole sequence.
class VoidEvent {
    final String targetId;

    VoidEvent({
        required this.targetId,
    });

    factory VoidEvent.fromJson(Map<String, dynamic> json) => VoidEvent(
        targetId: json["targetId"],
    );

    Map<String, dynamic> toJson() => {
        "targetId": targetId,
    };
}

class EnumValues<T> {
    Map<String, T> map;
    late Map<T, String> reverseMap;

    EnumValues(this.map);

    Map<T, String> get reverse {
            reverseMap = map.map((k, v) => MapEntry(v, k));
            return reverseMap;
    }
}
