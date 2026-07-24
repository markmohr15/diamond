// GENERATED FILE — DO NOT EDIT.
// Source of truth: schema/ (envelope.schema.json + schema/events/*.schema.json).
// Regenerate with `npm run codegen` from the repo root. See tools/codegen/README.md.

// To parse this data:
//
//   import { Convert, GameEvent, BallInPlay, CountCorrection, FielderTouch, InningHalfEnd, InningHalfStart, LineupSet, PitchThrown, RuleCall, RunnerAdvance, RunnerOut, VoidEvent } from "./events";
//
//   const gameEvent = Convert.toGameEvent(json);
//   const ballInPlay = Convert.toBallInPlay(json);
//   const countCorrection = Convert.toCountCorrection(json);
//   const fielderTouch = Convert.toFielderTouch(json);
//   const inningHalfEnd = Convert.toInningHalfEnd(json);
//   const inningHalfStart = Convert.toInningHalfStart(json);
//   const lineupSet = Convert.toLineupSet(json);
//   const pitchThrown = Convert.toPitchThrown(json);
//   const ruleCall = Convert.toRuleCall(json);
//   const runnerAdvance = Convert.toRunnerAdvance(json);
//   const runnerOut = Convert.toRunnerOut(json);
//   const voidEvent = Convert.toVoidEvent(json);
//
// These functions will throw an error if the JSON doesn't
// match the expected interface, even if the JSON is valid.

/**
 * Envelope shared by every event (spec §2). Append-only. Ordering: (wallClock, deviceId,
 * seq).
 */
export interface GameEvent {
    /**
     * id of the event this supersedes (§6)
     */
    corrects?: string;
    /**
     * userId of the scorer
     */
    createdBy: string;
    deviceId:  string;
    /**
     * id of the event this logically follows, when recorded later than it happened (§6 insert)
     * — e.g. a stolen base noticed two pitches late. Projections fold in this logical order,
     * not recording order.
     */
    effectiveAfter?: string;
    gameId:          string;
    /**
     * UUIDv7, generated on device
     */
    id:      string;
    payload: { [key: string]: unknown };
    /**
     * monotonic per-device
     */
    seq: number;
    /**
     * discriminant; matches an events/ *.schema.json title
     */
    type:      string;
    wallClock: Date;
}

/**
 * Batted ball incl. fouls with coordinates (spec §4.2, §3.2).
 */
export interface BallInPlay {
    contactQuality?: ContactQuality;
    fair:            boolean;
    /**
     * first contact: where it landed, hit the wall, or met a glove (§15.1)
     */
    landing:         FieldCoord;
    landingIsCaught: boolean;
    /**
     * hit the fence on the fly (§15.1, §16.2)
     */
    offWall?:     boolean;
    pitchEventId: string;
    /**
     * where a fielder finally gained possession, when meaningfully different from landing
     * (§15.1). Absent = same as landing.
     */
    retrieved?: FieldCoord;
    trajectory: Trajectory;
}

export type ContactQuality = "weak" | "average" | "hard";

/**
 * first contact: where it landed, hit the wall, or met a glove (§15.1)
 *
 * Field coordinate in absolute FEET (spec §3.2). Home plate = (0,0); +y toward second
 * base/CF; bearing theta = atan2(x, y), negative = third-base side; |theta| > 45deg is foul
 * territory (never clamp).
 *
 * where a fielder finally gained possession, when meaningfully different from landing
 * (§15.1). Absent = same as landing.
 */
export interface FieldCoord {
    x: number;
    y: number;
}

export type Trajectory = "ground" | "line" | "fly" | "popup" | "bunt";

/**
 * Authoritative count checkpoint (spec §12.5). Projection treats as override; back-infers
 * unknown pitches where the math allows, marks inferences as such.
 */
export interface CountCorrection {
    balls:   number;
    strikes: number;
}

/**
 * Physical touch vocabulary — never official-scoring language (spec §4.2, §13). Official
 * errors are DERIVED.
 */
export interface FielderTouch {
    ballInPlayEventId: string;
    /**
     * optional for opponents
     */
    fielderId?: string;
    location?:  FieldCoord;
    /**
     * scorer judgment on misplays; inferred default, overridable post-hoc (§13.2)
     */
    ordinaryEffort?: boolean;
    position:        number;
    /**
     * how a received_throw arrived (§13, §22.1). Default clean; purely developmental, never
     * affects official scoring.
     */
    receivedQuality?: ReceivedQuality;
    touchType:        TouchType;
}

/**
 * how a received_throw arrived (§13, §22.1). Default clean; purely developmental, never
 * affects official scoring.
 */
export type ReceivedQuality = "clean" | "short_hop" | "high" | "wide";

export type TouchType = "fielded" | "caught" | "received_throw" | "deflected" | "dropped" | "bobbled" | "booted" | "wild_throw" | "missed_catch" | "tag_applied" | "tag_missed";

/**
 * Explicit half-inning close (spec §4.4). 'three_outs' is auto-implied by the fold once
 * outs reach 3 and doesn't require this event to appear. Any other reason is authoritative
 * and closes the half even with fewer than 3 outs.
 */
export interface InningHalfEnd {
    reason: InningHalfEndReason;
}

export type InningHalfEndReason = "three_outs" | "run_cap" | "time_limit" | "walkoff" | "mercy" | "coach_agreement" | "suspended" | "other";

/**
 * Derived state checkpoint boundary (spec §4.4, §7). Marks the start of a half-inning;
 * count/outs/bases always reset to empty here. The optional snapshot is a performance cache
 * of cumulative state — never truth, always reproducible by folding from genesis.
 */
export interface InningHalfStart {
    battingTeamId: string;
    half:          Half;
    inning:        number;
    snapshot?:     GameStateSnapshot;
}

export type Half = "top" | "bottom";

/**
 * Cumulative game state carried into a half-inning (spec §7). Cache only — always
 * reproducible by folding from genesis. Per-half state (count, outs, bases) is deliberately
 * excluded: it always resets to empty at a half-inning boundary, so caching it would be
 * redundant.
 */
export interface GameStateSnapshot {
    /**
     * pitch event id -> count effect that a CountCorrection's back-inference resolved uniquely
     * (spec §12.5). Cumulative across halves like the other fields; empty when no inference has
     * occurred.
     */
    inferredPitchEffects: { [key: string]: InferredPitchEffect };
    /**
     * teamId -> index into that team's LineupSet.battingOrder for the next batter due
     */
    nextBatterIndexByTeam: { [key: string]: number };
    /**
     * pitcherId -> total pitches thrown so far this game
     */
    pitchCountByPitcher: { [key: string]: number };
    /**
     * teamId -> runs scored so far
     */
    runsByTeam: { [key: string]: number };
}

export type InferredPitchEffect = "ball" | "strike_effect";

/**
 * Initial batting order for one team (spec §4.4). Batter-due is derived from this plus
 * completed-plate-appearance counts on every fold — never cached positionally — so
 * BattingOrderAdjusted (M2) slots in without refactor.
 */
export interface LineupSet {
    /**
     * playerIds in batting order
     */
    battingOrder: [string, ...string[]];
    teamId:       string;
}

/**
 * One per pitch, always (spec §4.1). intended* = the call; actual* = reality.
 * actualLocation required only when location capture is ON (§12.4).
 */
export interface PitchThrown {
    actualLocation?: ZoneCoord;
    actualType?:     string;
    /**
     * observed offensive posture on this pitch, orthogonal to outcome (§4.1, §11.1). Absent =
     * conventional AB posture.
     */
    batterAction?: BatterAction;
    batterId:      string;
    batterSide:    BatterSide;
    /**
     * set when the pitch hit the dirt before reaching the catcher (§3.3); mutually exclusive
     * with an observed actualLocation. Actual only — never a call.
     */
    bounceLocation?:   BounceCoord;
    intendedLocation?: ZoneCoord;
    /**
     * PitchTypeId (team-configured)
     */
    intendedType?: string;
    /**
     * CallZone id (§10.1)
     */
    intendedZoneId?: string;
    outcome:         Outcome;
    pitcherId:       string;
    /**
     * mph, optional
     */
    velocity?: number;
}

/**
 * Strike-zone coordinate, catcher's perspective, normalized to the batter's zone (spec
 * §3.1). x: 0=middle of plate, -1/+1 = zone edges (negative = third-base side, absolute;
 * flip by handedness at render). y: 0=bottom of zone, 1=top. Values outside [-1,1]/[0,1]
 * are valid out-of-zone locations. Never clamp.
 */
export interface ZoneCoord {
    x: number;
    y: number;
}

/**
 * observed offensive posture on this pitch, orthogonal to outcome (§4.1, §11.1). Absent =
 * conventional AB posture.
 */
export type BatterAction = "showed_bunt" | "pulled_bunt" | "slap" | "fake_slap" | "slash";

export type BatterSide = "L" | "R";

/**
 * set when the pitch hit the dirt before reaching the catcher (§3.3); mutually exclusive
 * with an observed actualLocation. Actual only — never a call.
 *
 * Landing spot of a pitch that hit the dirt before reaching the catcher, whether it bounced
 * in front of the plate or between the plate and the catcher (spec §3.3). Only ever an
 * actual location, never a call (intendedLocation stays a ZoneCoord).
 */
export interface BounceCoord {
    /**
     * Absolute FEET from the front edge of the plate. Positive = toward the pitcher (bounced
     * out front); 0 = front edge; negative = behind the front edge toward the catcher (a short
     * hop between the plate and the catcher, or skipped past the back). Absolute feet, not
     * normalized, because ground geometry does not vary with batter height. Never clamp.
     */
    depth: number;
    /**
     * SAME normalized lateral axis as ZoneCoord.x: absolute, catcher's view, flip by handedness
     * at render.
     */
    x: number;
}

export type Outcome = "ball" | "called_strike" | "swinging_strike" | "swinging_strike_blocked" | "foul" | "foul_tip" | "foul_bunt" | "in_play" | "hit_by_pitch" | "ball_intentional" | "illegal_pitch" | "no_pitch" | "unknown";

/**
 * Umpire rulings as first-class events — the judicial sibling of FielderTouch (spec §4.5).
 */
export interface RuleCall {
    againstPosition?: number;
    callType:         CallType;
    location?:        FieldCoord;
    note?:            string;
    runnerId?:        string;
}

export type CallType = "interference_batter" | "interference_runner" | "interference_catcher" | "interference_spectator" | "obstruction" | "infield_fly" | "ground_rule" | "dead_ball_award" | "look_back_violation" | "illegal_pitch_ruling" | "umpire_reversal";

/**
 * spec §4.3. from 0 = batter's box; to 4 = scored. from==to records surviving a play (e.g.,
 * rundown) attributed to a misplay.
 */
export interface RunnerAdvance {
    /**
     * RuleCall that awarded this advance (§4.5)
     */
    enabledByCallId?: string;
    /**
     * FielderTouch that enabled this advance (§13.1)
     */
    enabledByTouchId?: string;
    from:              number;
    reason:            RunnerAdvanceReason;
    runnerId:          string;
    to:                number;
}

export type RunnerAdvanceReason = "batted_ball" | "walk" | "hbp" | "stolen_base" | "wild_pitch" | "passed_ball" | "balk" | "illegal_pitch" | "error" | "fielders_choice" | "defensive_indifference" | "dropped_third_strike" | "catcher_interference" | "obstruction" | "wild_throw" | "ground_rule" | "awarded";

/**
 * spec §4.3.
 */
export interface RunnerOut {
    atBase:           number;
    enabledByCallId?: string;
    how:              How;
    /**
     * FielderTouch credited with the putout
     */
    putoutTouchId?: string;
    runnerId:       string;
}

export type How = "force" | "tag" | "caught_stealing" | "picked_off" | "fly_out" | "strikeout" | "strikeout_d3k_throw" | "appeal" | "interference" | "batted_ball_contact" | "left_early" | "look_back_rule" | "abandoned" | "infield_fly" | "batter_out_of_box";

/**
 * Undo (spec §6): appending this voids targetId. Unlimited depth. When a committed play was
 * emitted atomically, the UI voids the whole sequence.
 */
export interface VoidEvent {
    targetId: string;
}

// Converts JSON strings to/from your types
// and asserts the results of JSON.parse at runtime
export class Convert {
    public static toGameEvent(json: string): GameEvent {
        return cast(JSON.parse(json), r("GameEvent"));
    }

    public static gameEventToJson(value: GameEvent): string {
        return JSON.stringify(uncast(value, r("GameEvent")), null, 2);
    }

    public static toBallInPlay(json: string): BallInPlay {
        return cast(JSON.parse(json), r("BallInPlay"));
    }

    public static ballInPlayToJson(value: BallInPlay): string {
        return JSON.stringify(uncast(value, r("BallInPlay")), null, 2);
    }

    public static toCountCorrection(json: string): CountCorrection {
        return cast(JSON.parse(json), r("CountCorrection"));
    }

    public static countCorrectionToJson(value: CountCorrection): string {
        return JSON.stringify(uncast(value, r("CountCorrection")), null, 2);
    }

    public static toFielderTouch(json: string): FielderTouch {
        return cast(JSON.parse(json), r("FielderTouch"));
    }

    public static fielderTouchToJson(value: FielderTouch): string {
        return JSON.stringify(uncast(value, r("FielderTouch")), null, 2);
    }

    public static toInningHalfEnd(json: string): InningHalfEnd {
        return cast(JSON.parse(json), r("InningHalfEnd"));
    }

    public static inningHalfEndToJson(value: InningHalfEnd): string {
        return JSON.stringify(uncast(value, r("InningHalfEnd")), null, 2);
    }

    public static toInningHalfStart(json: string): InningHalfStart {
        return cast(JSON.parse(json), r("InningHalfStart"));
    }

    public static inningHalfStartToJson(value: InningHalfStart): string {
        return JSON.stringify(uncast(value, r("InningHalfStart")), null, 2);
    }

    public static toLineupSet(json: string): LineupSet {
        return cast(JSON.parse(json), r("LineupSet"));
    }

    public static lineupSetToJson(value: LineupSet): string {
        return JSON.stringify(uncast(value, r("LineupSet")), null, 2);
    }

    public static toPitchThrown(json: string): PitchThrown {
        return cast(JSON.parse(json), r("PitchThrown"));
    }

    public static pitchThrownToJson(value: PitchThrown): string {
        return JSON.stringify(uncast(value, r("PitchThrown")), null, 2);
    }

    public static toRuleCall(json: string): RuleCall {
        return cast(JSON.parse(json), r("RuleCall"));
    }

    public static ruleCallToJson(value: RuleCall): string {
        return JSON.stringify(uncast(value, r("RuleCall")), null, 2);
    }

    public static toRunnerAdvance(json: string): RunnerAdvance {
        return cast(JSON.parse(json), r("RunnerAdvance"));
    }

    public static runnerAdvanceToJson(value: RunnerAdvance): string {
        return JSON.stringify(uncast(value, r("RunnerAdvance")), null, 2);
    }

    public static toRunnerOut(json: string): RunnerOut {
        return cast(JSON.parse(json), r("RunnerOut"));
    }

    public static runnerOutToJson(value: RunnerOut): string {
        return JSON.stringify(uncast(value, r("RunnerOut")), null, 2);
    }

    public static toVoidEvent(json: string): VoidEvent {
        return cast(JSON.parse(json), r("VoidEvent"));
    }

    public static voidEventToJson(value: VoidEvent): string {
        return JSON.stringify(uncast(value, r("VoidEvent")), null, 2);
    }
}

function invalidValue(typ: any, val: any, key: any, parent: any = ''): never {
    const prettyTyp = prettyTypeName(typ);
    const parentText = parent ? ` on ${parent}` : '';
    const keyText = key ? ` for key "${key}"` : '';
    throw Error(`Invalid value${keyText}${parentText}. Expected ${prettyTyp} but got ${JSON.stringify(val)}`);
}

function prettyTypeName(typ: any): string {
    if (Array.isArray(typ)) {
        if (typ.length === 2 && typ[0] === undefined) {
            return `an optional ${prettyTypeName(typ[1])}`;
        } else {
            return `one of [${typ.map(a => { return prettyTypeName(a); }).join(", ")}]`;
        }
    } else if (typeof typ === "object" && typ.literal !== undefined) {
        return typ.literal;
    } else {
        return typeof typ;
    }
}

function jsonToJSProps(typ: any): any {
    if (typ.jsonToJS === undefined) {
        const map: any = {};
        typ.props.forEach((p: any) => map[p.json] = { key: p.js, typ: p.typ });
        typ.jsonToJS = map;
    }
    return typ.jsonToJS;
}

function jsToJSONProps(typ: any): any {
    if (typ.jsToJSON === undefined) {
        const map: any = {};
        typ.props.forEach((p: any) => map[p.js] = { key: p.json, typ: p.typ });
        typ.jsToJSON = map;
    }
    return typ.jsToJSON;
}

function transform(val: any, typ: any, getProps: any, key: any = '', parent: any = ''): any {
    function transformPrimitive(typ: string, val: any): any {
        if (typeof typ === typeof val) return val;
        return invalidValue(typ, val, key, parent);
    }

    function transformUnion(typs: any[], val: any): any {
        // val must validate against one typ in typs
        const l = typs.length;
        for (let i = 0; i < l; i++) {
            const typ = typs[i];
            try {
                return transform(val, typ, getProps);
            } catch (_) {}
        }
        return invalidValue(typs, val, key, parent);
    }

    function transformEnum(cases: string[], val: any): any {
        if (cases.indexOf(val) !== -1) return val;
        return invalidValue(cases.map(a => { return l(a); }), val, key, parent);
    }

    function transformArray(typ: any, val: any): any {
        // val must be an array with no invalid elements
        if (!Array.isArray(val)) return invalidValue(l("array"), val, key, parent);
        return val.map(el => transform(el, typ, getProps));
    }

    function transformDate(val: any): any {
        if (val === null) {
            return null;
        }
        const d = new Date(val);
        if (isNaN(d.valueOf())) {
            return invalidValue(l("Date"), val, key, parent);
        }
        return d;
    }

    function transformObject(props: { [k: string]: any }, additional: any, val: any): any {
        if (val === null || typeof val !== "object" || Array.isArray(val)) {
            return invalidValue(l(ref || "object"), val, key, parent);
        }
        const result: any = {};
        Object.getOwnPropertyNames(props).forEach(key => {
            const prop = props[key];
            const v = Object.prototype.hasOwnProperty.call(val, key) ? val[key] : undefined;
            result[prop.key] = transform(v, prop.typ, getProps, key, ref);
        });
        Object.getOwnPropertyNames(val).forEach(key => {
            if (!Object.prototype.hasOwnProperty.call(props, key)) {
                result[key] = transform(val[key], additional, getProps, key, ref);
            }
        });
        return result;
    }

    if (typ === "any") return val;
    if (typ === null) {
        if (val === null) return val;
        return invalidValue(typ, val, key, parent);
    }
    if (typ === false) return invalidValue(typ, val, key, parent);
    let ref: any = undefined;
    while (typeof typ === "object" && typ.ref !== undefined) {
        ref = typ.ref;
        typ = typeMap[typ.ref];
    }
    if (Array.isArray(typ)) return transformEnum(typ, val);
    if (typeof typ === "object") {
        return typ.hasOwnProperty("unionMembers") ? transformUnion(typ.unionMembers, val)
            : typ.hasOwnProperty("arrayItems")    ? transformArray(typ.arrayItems, val)
            : typ.hasOwnProperty("props")         ? transformObject(getProps(typ), typ.additional, val)
            : invalidValue(typ, val, key, parent);
    }
    // Numbers can be parsed by Date but shouldn't be.
    if (typ === Date && typeof val !== "number") return transformDate(val);
    return transformPrimitive(typ, val);
}

function cast<T>(val: any, typ: any): T {
    return transform(val, typ, jsonToJSProps);
}

function uncast<T>(val: T, typ: any): any {
    return transform(val, typ, jsToJSONProps);
}

function l(typ: any) {
    return { literal: typ };
}

function a(typ: any) {
    return { arrayItems: typ };
}

function u(...typs: any[]) {
    return { unionMembers: typs };
}

function o(props: any[], additional: any) {
    return { props, additional };
}

function m(additional: any) {
    return { props: [], additional };
}

function r(name: string) {
    return { ref: name };
}

const typeMap: any = {
    "GameEvent": o([
        { json: "corrects", js: "corrects", typ: u(undefined, "") },
        { json: "createdBy", js: "createdBy", typ: "" },
        { json: "deviceId", js: "deviceId", typ: "" },
        { json: "effectiveAfter", js: "effectiveAfter", typ: u(undefined, "") },
        { json: "gameId", js: "gameId", typ: "" },
        { json: "id", js: "id", typ: "" },
        { json: "payload", js: "payload", typ: m("any") },
        { json: "seq", js: "seq", typ: 0 },
        { json: "type", js: "type", typ: "" },
        { json: "wallClock", js: "wallClock", typ: Date },
    ], false),
    "BallInPlay": o([
        { json: "contactQuality", js: "contactQuality", typ: u(undefined, r("ContactQuality")) },
        { json: "fair", js: "fair", typ: true },
        { json: "landing", js: "landing", typ: r("FieldCoord") },
        { json: "landingIsCaught", js: "landingIsCaught", typ: true },
        { json: "offWall", js: "offWall", typ: u(undefined, true) },
        { json: "pitchEventId", js: "pitchEventId", typ: "" },
        { json: "retrieved", js: "retrieved", typ: u(undefined, r("FieldCoord")) },
        { json: "trajectory", js: "trajectory", typ: r("Trajectory") },
    ], false),
    "FieldCoord": o([
        { json: "x", js: "x", typ: 3.14 },
        { json: "y", js: "y", typ: 3.14 },
    ], false),
    "CountCorrection": o([
        { json: "balls", js: "balls", typ: 0 },
        { json: "strikes", js: "strikes", typ: 0 },
    ], false),
    "FielderTouch": o([
        { json: "ballInPlayEventId", js: "ballInPlayEventId", typ: "" },
        { json: "fielderId", js: "fielderId", typ: u(undefined, "") },
        { json: "location", js: "location", typ: u(undefined, r("FieldCoord")) },
        { json: "ordinaryEffort", js: "ordinaryEffort", typ: u(undefined, true) },
        { json: "position", js: "position", typ: 0 },
        { json: "receivedQuality", js: "receivedQuality", typ: u(undefined, r("ReceivedQuality")) },
        { json: "touchType", js: "touchType", typ: r("TouchType") },
    ], false),
    "InningHalfEnd": o([
        { json: "reason", js: "reason", typ: r("InningHalfEndReason") },
    ], false),
    "InningHalfStart": o([
        { json: "battingTeamId", js: "battingTeamId", typ: "" },
        { json: "half", js: "half", typ: r("Half") },
        { json: "inning", js: "inning", typ: 0 },
        { json: "snapshot", js: "snapshot", typ: u(undefined, r("GameStateSnapshot")) },
    ], false),
    "GameStateSnapshot": o([
        { json: "inferredPitchEffects", js: "inferredPitchEffects", typ: m(r("InferredPitchEffect")) },
        { json: "nextBatterIndexByTeam", js: "nextBatterIndexByTeam", typ: m(0) },
        { json: "pitchCountByPitcher", js: "pitchCountByPitcher", typ: m(0) },
        { json: "runsByTeam", js: "runsByTeam", typ: m(0) },
    ], false),
    "LineupSet": o([
        { json: "battingOrder", js: "battingOrder", typ: a("") },
        { json: "teamId", js: "teamId", typ: "" },
    ], false),
    "PitchThrown": o([
        { json: "actualLocation", js: "actualLocation", typ: u(undefined, r("ZoneCoord")) },
        { json: "actualType", js: "actualType", typ: u(undefined, "") },
        { json: "batterAction", js: "batterAction", typ: u(undefined, r("BatterAction")) },
        { json: "batterId", js: "batterId", typ: "" },
        { json: "batterSide", js: "batterSide", typ: r("BatterSide") },
        { json: "bounceLocation", js: "bounceLocation", typ: u(undefined, r("BounceCoord")) },
        { json: "intendedLocation", js: "intendedLocation", typ: u(undefined, r("ZoneCoord")) },
        { json: "intendedType", js: "intendedType", typ: u(undefined, "") },
        { json: "intendedZoneId", js: "intendedZoneId", typ: u(undefined, "") },
        { json: "outcome", js: "outcome", typ: r("Outcome") },
        { json: "pitcherId", js: "pitcherId", typ: "" },
        { json: "velocity", js: "velocity", typ: u(undefined, 3.14) },
    ], false),
    "ZoneCoord": o([
        { json: "x", js: "x", typ: 3.14 },
        { json: "y", js: "y", typ: 3.14 },
    ], false),
    "BounceCoord": o([
        { json: "depth", js: "depth", typ: 3.14 },
        { json: "x", js: "x", typ: 3.14 },
    ], false),
    "RuleCall": o([
        { json: "againstPosition", js: "againstPosition", typ: u(undefined, 0) },
        { json: "callType", js: "callType", typ: r("CallType") },
        { json: "location", js: "location", typ: u(undefined, r("FieldCoord")) },
        { json: "note", js: "note", typ: u(undefined, "") },
        { json: "runnerId", js: "runnerId", typ: u(undefined, "") },
    ], false),
    "RunnerAdvance": o([
        { json: "enabledByCallId", js: "enabledByCallId", typ: u(undefined, "") },
        { json: "enabledByTouchId", js: "enabledByTouchId", typ: u(undefined, "") },
        { json: "from", js: "from", typ: 0 },
        { json: "reason", js: "reason", typ: r("RunnerAdvanceReason") },
        { json: "runnerId", js: "runnerId", typ: "" },
        { json: "to", js: "to", typ: 0 },
    ], false),
    "RunnerOut": o([
        { json: "atBase", js: "atBase", typ: 0 },
        { json: "enabledByCallId", js: "enabledByCallId", typ: u(undefined, "") },
        { json: "how", js: "how", typ: r("How") },
        { json: "putoutTouchId", js: "putoutTouchId", typ: u(undefined, "") },
        { json: "runnerId", js: "runnerId", typ: "" },
    ], false),
    "VoidEvent": o([
        { json: "targetId", js: "targetId", typ: "" },
    ], false),
    "ContactQuality": [
        "average",
        "hard",
        "weak",
    ],
    "Trajectory": [
        "bunt",
        "fly",
        "ground",
        "line",
        "popup",
    ],
    "ReceivedQuality": [
        "clean",
        "high",
        "short_hop",
        "wide",
    ],
    "TouchType": [
        "bobbled",
        "booted",
        "caught",
        "deflected",
        "dropped",
        "fielded",
        "missed_catch",
        "received_throw",
        "tag_applied",
        "tag_missed",
        "wild_throw",
    ],
    "InningHalfEndReason": [
        "coach_agreement",
        "mercy",
        "other",
        "run_cap",
        "suspended",
        "three_outs",
        "time_limit",
        "walkoff",
    ],
    "Half": [
        "bottom",
        "top",
    ],
    "InferredPitchEffect": [
        "ball",
        "strike_effect",
    ],
    "BatterAction": [
        "fake_slap",
        "pulled_bunt",
        "showed_bunt",
        "slap",
        "slash",
    ],
    "BatterSide": [
        "L",
        "R",
    ],
    "Outcome": [
        "ball",
        "ball_intentional",
        "called_strike",
        "foul",
        "foul_bunt",
        "foul_tip",
        "hit_by_pitch",
        "illegal_pitch",
        "in_play",
        "no_pitch",
        "swinging_strike",
        "swinging_strike_blocked",
        "unknown",
    ],
    "CallType": [
        "dead_ball_award",
        "ground_rule",
        "illegal_pitch_ruling",
        "infield_fly",
        "interference_batter",
        "interference_catcher",
        "interference_runner",
        "interference_spectator",
        "look_back_violation",
        "obstruction",
        "umpire_reversal",
    ],
    "RunnerAdvanceReason": [
        "awarded",
        "balk",
        "batted_ball",
        "catcher_interference",
        "defensive_indifference",
        "dropped_third_strike",
        "error",
        "fielders_choice",
        "ground_rule",
        "hbp",
        "illegal_pitch",
        "obstruction",
        "passed_ball",
        "stolen_base",
        "walk",
        "wild_pitch",
        "wild_throw",
    ],
    "How": [
        "abandoned",
        "appeal",
        "batted_ball_contact",
        "batter_out_of_box",
        "caught_stealing",
        "fly_out",
        "force",
        "infield_fly",
        "interference",
        "left_early",
        "look_back_rule",
        "picked_off",
        "strikeout",
        "strikeout_d3k_throw",
        "tag",
    ],
};
