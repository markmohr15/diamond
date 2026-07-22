// GENERATED FILE — DO NOT EDIT.
// Source of truth: schema/ (envelope.schema.json + schema/events/*.schema.json).
// Regenerate with `npm run codegen` from the repo root. See tools/codegen/README.md.

// To parse this JSON data, do
//
//     final gameEvent = gameEventFromJson(jsonString);
//     final ballInPlay = ballInPlayFromJson(jsonString);
//     final countCorrection = countCorrectionFromJson(jsonString);
//     final fielderTouch = fielderTouchFromJson(jsonString);
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
    final Trajectory trajectory;

    BallInPlay({
        this.contactQuality,
        required this.fair,
        required this.landing,
        required this.landingIsCaught,
        this.offWall,
        required this.pitchEventId,
        this.retrieved,
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
    final ZoneCoord? intendedLocation;
    
    ///PitchTypeId (team-configured)
    final String? intendedType;
    
    ///CallZone id (§10.1)
    final String? intendedZoneId;
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

enum Outcome {
    BALL,
    BALL_INTENTIONAL,
    CALLED_STRIKE,
    FOUL,
    FOUL_BUNT,
    FOUL_TIP,
    HIT_BY_PITCH,
    ILLEGAL_PITCH,
    IN_PLAY,
    NO_PITCH,
    SWINGING_STRIKE,
    SWINGING_STRIKE_BLOCKED,
    UNKNOWN
}

final outcomeValues = EnumValues({
    "ball": Outcome.BALL,
    "ball_intentional": Outcome.BALL_INTENTIONAL,
    "called_strike": Outcome.CALLED_STRIKE,
    "foul": Outcome.FOUL,
    "foul_bunt": Outcome.FOUL_BUNT,
    "foul_tip": Outcome.FOUL_TIP,
    "hit_by_pitch": Outcome.HIT_BY_PITCH,
    "illegal_pitch": Outcome.ILLEGAL_PITCH,
    "in_play": Outcome.IN_PLAY,
    "no_pitch": Outcome.NO_PITCH,
    "swinging_strike": Outcome.SWINGING_STRIKE,
    "swinging_strike_blocked": Outcome.SWINGING_STRIKE_BLOCKED,
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
    final Reason reason;
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
        reason: reasonValues.map[json["reason"]]!,
        runnerId: json["runnerId"],
        to: json["to"],
    );

    Map<String, dynamic> toJson() => {
        "enabledByCallId": enabledByCallId,
        "enabledByTouchId": enabledByTouchId,
        "from": from,
        "reason": reasonValues.reverse[reason],
        "runnerId": runnerId,
        "to": to,
    };
}

enum Reason {
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

final reasonValues = EnumValues({
    "awarded": Reason.AWARDED,
    "balk": Reason.BALK,
    "batted_ball": Reason.BATTED_BALL,
    "catcher_interference": Reason.CATCHER_INTERFERENCE,
    "defensive_indifference": Reason.DEFENSIVE_INDIFFERENCE,
    "dropped_third_strike": Reason.DROPPED_THIRD_STRIKE,
    "error": Reason.ERROR,
    "fielders_choice": Reason.FIELDERS_CHOICE,
    "ground_rule": Reason.GROUND_RULE,
    "hbp": Reason.HBP,
    "illegal_pitch": Reason.ILLEGAL_PITCH,
    "obstruction": Reason.OBSTRUCTION,
    "passed_ball": Reason.PASSED_BALL,
    "stolen_base": Reason.STOLEN_BASE,
    "walk": Reason.WALK,
    "wild_pitch": Reason.WILD_PITCH,
    "wild_throw": Reason.WILD_THROW
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
