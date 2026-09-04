/// The uncommitted play (§15.5): everything the field canvas has gathered
/// since the in-play pitch, held *outside* the event stream until the ✓.
///
/// Deliberately not an event and never one: commit translates the draft into
/// the atomic sequence (`BallInPlay`, then the chain in entry order) in one
/// append, so a half-entered play can't corrupt game state — and the same
/// JSON round-trip that keeps the draft immutable is what the crash journal
/// persists.
///
/// DIA-008b: the chain is an ordered list of [PlayEntry] — fielder touches,
/// runner legs, outs, rule calls — each with a stable [PlayEntry.key] so
/// links (`enabledBy`, `putout`) survive removals. Official-scoring language
/// never appears here (§13): the draft records physics; the chips record
/// physics; `error`-the-reason is derived mechanically from the enabling
/// touch's type at commit.
library;

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/events/pending_event.dart';
import 'package:diamond/src/rules/official_scoring.dart'
    show OfficialErrorKind, misplayTouchTypes, officialErrorKindOf;
import 'package:flutter/foundation.dart';

/// One node of the play chain. [key] is stable for the draft's lifetime —
/// links point at keys, never at list positions, so removing an entry can
/// orphan a link (nulled) but never silently retarget it.
@immutable
sealed class PlayEntry {
  const PlayEntry({required this.key});

  final int key;

  Map<String, dynamic> toJson();

  static PlayEntry fromJson(Map<String, dynamic> json) {
    return switch (json['kind']) {
      'touch' => TouchEntry(
        key: json['key'] as int,
        position: json['position'] as int,
        touchType: touchTypeValues.map[json['touchType']]!,
        receivedQuality: receivedQualityValues.map[json['receivedQuality']],
        location: json['location'] == null
            ? null
            : FieldCoord.fromJson(json['location'] as Map<String, dynamic>),
      ),
      'leg' => LegEntry(
        key: json['key'] as int,
        runnerId: json['runnerId'] as String,
        from: json['from'] as int,
        to: json['to'] as int,
        enabledByKey: json['enabledByKey'] as int?,
        reasonOverride: runnerAdvanceReasonValues.map[json['reasonOverride']],
      ),
      'out' => OutEntry(
        key: json['key'] as int,
        runnerId: json['runnerId'] as String,
        atBase: json['atBase'] as int,
        how: howValues.map[json['how']]!,
        putoutKey: json['putoutKey'] as int?,
        enabledByCallKey: json['enabledByCallKey'] as int?,
      ),
      'ruleCall' => RuleCallEntry(
        key: json['key'] as int,
        callType: callTypeValues.map[json['callType']]!,
        againstPosition: json['againstPosition'] as int?,
      ),
      _ => throw StateError('unknown play entry kind: ${json['kind']}'),
    };
  }
}

/// A fielder touched the ball (§4.2). Type starts as the surface's
/// inference; the chip converts it (dropped/booted/… §15.3) in place — one
/// node, retyped, never a second node.
class TouchEntry extends PlayEntry {
  const TouchEntry({
    required super.key,
    required this.position,
    required this.touchType,
    this.receivedQuality,
    this.location,
  });

  final int position;
  final TouchType touchType;

  /// Arrival quality on receiving touches (§4.2) — developmental only.
  final ReceivedQuality? receivedQuality;

  /// Where the touch happened (§4.2) — set by the fielder drag: where she
  /// was dropped is where she played it.
  final FieldCoord? location;

  bool get isMisplay => misplayTouchTypes.contains(touchType);

  TouchEntry copyWith({
    TouchType? touchType,
    Object? receivedQuality = _unset,
  }) {
    return TouchEntry(
      key: key,
      position: position,
      touchType: touchType ?? this.touchType,
      receivedQuality: receivedQuality == _unset
          ? this.receivedQuality
          : receivedQuality as ReceivedQuality?,
      location: location,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'touch',
    'key': key,
    'position': position,
    'touchType': touchTypeValues.reverse[touchType],
    'receivedQuality': receivedQualityValues.reverse[receivedQuality],
    'location': location?.toJson(),
  };
}

/// One runner's movement between two bases (§4.3). A runner's journey is a
/// sequence of legs, each attributable to its own enabler (§13.4).
class LegEntry extends PlayEntry {
  const LegEntry({
    required super.key,
    required this.runnerId,
    required this.from,
    required this.to,
    this.enabledByKey,
    this.reasonOverride,
  });

  final String runnerId;
  final int from;
  final int to;

  /// The [TouchEntry] or [RuleCallEntry] that enabled this leg; null =
  /// plain batted-ball movement (including cascade pushes).
  final int? enabledByKey;

  /// An explicit §4.3 reason from the SAFE classification (v0.43) — e.g.
  /// `fielders_choice`, or `error` when no misplay touch exists yet to
  /// link. Null = derive from the enabler at commit.
  final RunnerAdvanceReason? reasonOverride;

  LegEntry copyWith({Object? enabledByKey = _unset}) => LegEntry(
    key: key,
    runnerId: runnerId,
    from: from,
    to: to,
    enabledByKey: enabledByKey == _unset
        ? this.enabledByKey
        : enabledByKey as int?,
    reasonOverride: reasonOverride,
  );

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'leg',
    'key': key,
    'runnerId': runnerId,
    'from': from,
    'to': to,
    'enabledByKey': enabledByKey,
    'reasonOverride': runnerAdvanceReasonValues.reverse[reasonOverride],
  };
}

/// A runner retired (§4.3). [how] is stored as inferred by the surface
/// (force/tag/fly_out from context, §15.1) and overridable from the node.
class OutEntry extends PlayEntry {
  const OutEntry({
    required super.key,
    required this.runnerId,
    required this.atBase,
    required this.how,
    this.putoutKey,
    this.enabledByCallKey,
  });

  final String runnerId;
  final int atBase;
  final How how;

  /// The [TouchEntry] credited with the putout.
  final int? putoutKey;

  /// The [RuleCallEntry] that produced this out — an interference call
  /// (§4.3's `enabledByCallId`), so the committed stream keeps the link
  /// rather than only the resulting `how`.
  final int? enabledByCallKey;

  OutEntry copyWith({
    How? how,
    Object? putoutKey = _unset,
    Object? enabledByCallKey = _unset,
  }) => OutEntry(
    key: key,
    runnerId: runnerId,
    atBase: atBase,
    how: how ?? this.how,
    putoutKey: putoutKey == _unset ? this.putoutKey : putoutKey as int?,
    enabledByCallKey: enabledByCallKey == _unset
        ? this.enabledByCallKey
        : enabledByCallKey as int?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'out',
    'key': key,
    'runnerId': runnerId,
    'atBase': atBase,
    'how': howValues.reverse[how],
    'putoutKey': putoutKey,
    'enabledByCallKey': enabledByCallKey,
  };
}

/// An umpire ruling in the chain (§4.5, §15.3's ⚖ node). M1 subset:
/// obstruction and runner interference.
class RuleCallEntry extends PlayEntry {
  const RuleCallEntry({
    required super.key,
    required this.callType,
    this.againstPosition,
  });

  final CallType callType;

  /// The fielder the call is against (§4.5) — obstruction is charged to
  /// her (§13.2 v0.43), so the surface asks who before recording it.
  final int? againstPosition;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'ruleCall',
    'key': key,
    'callType': callTypeValues.reverse[callType],
    'againstPosition': againstPosition,
  };
}

/// The SAFE popup's classification vocabulary (§15.1 v0.43): what got the
/// runner there. Encodes to §4.3 reasons and touch links — physics and
/// linkage, never rulings.
/// What got a runner where she ended up. The first five are a play's
/// vocabulary (§15.1 v0.43); the last four are §15.6's, offered only
/// between pitches. Disjoint by construction — nothing is stolen on a
/// batted ball, and nothing comes "on the hit" when there was no hit — so
/// the popup shows one set or the other and never both.
enum SafeResolution {
  onTheHit,
  onTheThrow,
  onError,
  fieldersChoice,
  obstruction,
  stolenBase,
  wildPitch,
  passedBall,
  defensiveIndifference,
}

/// The leg reason each between-pitch resolution writes.
const _betweenPitchReasons = <SafeResolution, RunnerAdvanceReason>{
  SafeResolution.stolenBase: RunnerAdvanceReason.STOLEN_BASE,
  SafeResolution.wildPitch: RunnerAdvanceReason.WILD_PITCH,
  SafeResolution.passedBall: RunnerAdvanceReason.PASSED_BALL,
  SafeResolution.defensiveIndifference:
      RunnerAdvanceReason.DEFENSIVE_INDIFFERENCE,
};

/// One occupied spot as the forced cascade sees it: who and where they
/// currently stand in the draft.
typedef RunnerSlot = ({String runnerId, int base});

/// The dragged move as `(runnerId, from, to)` triples: the drag itself plus
/// its forced pushes. See [cascadeRunnerMove].
typedef CascadedMove = ({String runnerId, int from, int to});

/// A runner drag with the rulebook's geometry applied: **runners never pass
/// one another**, so releasing a runner on or past a leader's base pushes
/// that leader forward, cascading — the bases-loaded single walks everyone
/// up, run included, in the same spirit as §11.3's forced walk chain.
/// Trailing runners never move automatically, a scored leader (base 4) is
/// out of the way, and every pushed token stays draggable, so an over-push
/// costs one corrective drag.
///
/// Returns the dragged move plus every push, trailing-to-leading; each
/// `from` is the runner's *current* draft base — these become [LegEntry]s.
List<CascadedMove> cascadeRunnerMove(
  List<RunnerSlot> slots, {
  required String movedId,
  required int to,
}) {
  final moved = slots.firstWhere((s) => s.runnerId == movedId);
  final moves = <CascadedMove>[(runnerId: movedId, from: moved.base, to: to)];
  var floor = to;
  final ahead = [...slots.where((s) => s.base > moved.base)]
    ..sort((a, b) => a.base.compareTo(b.base));
  for (final slot in ahead) {
    if (slot.runnerId == movedId || slot.base >= 4) continue;
    if (slot.base > floor) {
      // Strictly ahead already; the chain (if any) restarts behind them.
      floor = slot.base;
      continue;
    }
    final pushed = floor + 1 > 4 ? 4 : floor + 1;
    moves.add((runnerId: slot.runnerId, from: slot.base, to: pushed));
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
    this.endedAt,
    this.trajectory,
    this.offWall = false,
    this.sacrifice = false,
    this.entries = const [],
    this.movedFielders = const {},
    this.openingLegCount = 0,
    this.nextKey = 0,
    this.battedBall = true,
    this.heldBy,
  });

  factory PlayDraft.fromJson(Map<String, dynamic> json) => PlayDraft(
    pitchEventId: json['pitchEventId'] as String,
    batterId: json['batterId'] as String,
    landing: json['landing'] == null
        ? null
        : FieldCoord.fromJson(json['landing'] as Map<String, dynamic>),
    endedAt: json['endedAt'] == null
        ? null
        : FieldCoord.fromJson(json['endedAt'] as Map<String, dynamic>),
    trajectory: trajectoryValues.map[json['trajectory']],
    offWall: json['offWall'] as bool? ?? false,
    sacrifice: json['sacrifice'] as bool? ?? false,
    entries: [
      for (final entry in (json['entries'] as List<dynamic>? ?? []))
        PlayEntry.fromJson(entry as Map<String, dynamic>),
    ],
    movedFielders: {
      for (final entry
          in (json['movedFielders'] as Map<String, dynamic>? ?? {}).entries)
        int.parse(entry.key): FieldCoord.fromJson(
          entry.value as Map<String, dynamic>,
        ),
    },
    openingLegCount: json['openingLegCount'] as int? ?? 0,
    nextKey: json['nextKey'] as int? ?? 0,
    battedBall: json['battedBall'] as bool? ?? true,
    heldBy: json['heldBy'] as int?,
  );

  /// The committed `PitchThrown` this play hangs off (§4.2's link).
  final String pitchEventId;

  /// The batter-runner: rendered at the plate, dragged like any runner but
  /// starting from the batter's box.
  final String batterId;

  final FieldCoord? landing;

  /// §15.1's tap-and-drag second grip; null ⇒ same as landing.
  final FieldCoord? endedAt;

  /// Whether a ball was hit (§15.5) or this is a **between-pitch** entry
  /// (§15.6) — a steal, a runner taking a base on a passed ball, a D3K
  /// resolution. The two are the same structure with a different anchor:
  /// a play hangs its chain off the `BallInPlay` it mints, a between-pitch
  /// entry hangs it off the pitch that already exists. Everything else —
  /// touches, legs, outs, chips, the ✓ — is identical, deliberately: the
  /// scorer should not have two grammars to learn, and official scoring
  /// should not have two shapes to read.
  final bool battedBall;

  /// Who holds the ball before any touch says so. Between pitches that is
  /// the catcher, true after every pitch in both sports; null means the
  /// ball is loose — the pitch got past her. Ignored once a touch secures
  /// it, which is why [holderPosition] prefers [securedTouch].
  final int? heldBy;

  /// **Where the ball is** — the one answer, so nothing has to guess twice.
  ///
  /// A fielder placed on a loose ball snaps here, and the painter draws the
  /// roll segment to here, which is what stops the streak and the fielder from
  /// disagreeing about the same fact.
  ///
  /// In order: where the scorer said it ended up; else wherever the last touch
  /// left it, since a boot drops the ball at the booter's feet and the next
  /// fielder over goes to *that* spot rather than back to the landing; else the
  /// landing, which is where a ball stays when nothing moved it.
  FieldCoord? get ballAt {
    if (endedAt != null) return endedAt;
    final lastTouch = entries.whereType<TouchEntry>().lastOrNull;
    return lastTouch?.location ?? landing;
  }

  /// The roll segment's far end, or null when the ball never moved after
  /// landing — a home run, or anything fielded on the spot.
  ///
  /// Generated types carry no value equality, so this compares coordinates
  /// rather than instances: `ballAt` falls back to `landing` and would
  /// otherwise draw a zero-length streak on every play that has one.
  FieldCoord? get rollEnd {
    final at = ballAt;
    final from = landing;
    if (at == null || from == null) return null;
    return (at.x == from.x && at.y == from.y) ? null : at;
  }

  /// Who has the ball right now, seed included.
  int? get holderPosition => securedTouch?.position ?? heldBy;

  final Trajectory? trajectory;

  /// §15.1: auto-suggested when the landing sits on the fence spline; the
  /// scorer confirms via a chip.
  final bool offWall;

  /// §13's second judgment flag (v0.43): she was giving herself up. Only
  /// the scorer knows — no physical record separates a bunt to move the
  /// runner from a bunt for a hit — so the surface asks on any bunt that
  /// moved somebody. A sac fly needs no flag; it derives.
  final bool sacrifice;

  /// The chain, in entry order — which is stream order at commit.
  final List<PlayEntry> entries;

  /// Where the fielder drag left each dragged fielder this play — render
  /// state for this canvas only. Deliberately never an event: per-play
  /// repositioning is where she made *this* play, not §16.4 alignment data,
  /// and the touch's own `location` carries the analytic value.
  final Map<int, FieldCoord> movedFielders;

  /// Next [PlayEntry.key]; monotonic for the draft's lifetime.
  /// How many entries the draft opened with (the batter-runs-on-contact
  /// walk-up): everything past this count is scorer-authored, which is what
  /// locks the drawn path (see [pathLocked]).
  final int openingLegCount;

  final int nextKey;

  /// Caught in the air *at the landing coordinate* (§4.2's wire field):
  /// true iff the chain's first touch is `caught`. A ball deflected and
  /// then caught was not caught where it landed, so this stays false — see
  /// [caughtInFlight] for the question the rules actually ask.
  bool get landingIsCaught {
    final first = entries.whereType<TouchEntry>().firstOrNull;
    return first?.touchType == TouchType.CAUGHT;
  }

  /// Whether anybody has actually thrown the ball — evidence being a
  /// reception or a throw that got away. "She went on the throw" is only
  /// an answer when a throw happened.
  bool get hasThrow => entries.whereType<TouchEntry>().any(
    (touch) =>
        touch.touchType == TouchType.RECEIVED_THROW ||
        touch.touchType == TouchType.WILD_THROW,
  );

  /// Whether anyone caught this ball in the air. This is what the rules
  /// turn on — a catch retires the batter and removes every force, whether
  /// or not it happened where the ball first came down.
  bool get caughtInFlight => entries.whereType<TouchEntry>().any(
    (touch) => touch.touchType == TouchType.CAUGHT,
  );

  /// Whether this play needs §13.6's sacrifice judgment — the two cases only
  /// the scorer can settle.
  ///
  /// **A bunt that moved a runner up.** No derivation exists for a bunt:
  /// whether she was giving herself up or bunting for a hit looks identical in
  /// the physical record, so the surface has to ask.
  ///
  /// **A fly that was *not* caught, with a runner scoring.** This is the sac
  /// fly's second clause — dropped, and a runner scores who in the scorer's
  /// judgment could have scored had it been caught. It is judgment for the
  /// same reason: nothing in the record says whether the runner would have
  /// made it.
  ///
  /// Clause (1) — caught, and a runner scores — is deliberately absent. That
  /// one derives with no judgment in it, so asking there would be a question
  /// with a known answer.
  bool get invitesSacrifice {
    bool movedARunner(bool Function(LegEntry) reached) => entries.any(
      (entry) =>
          entry is LegEntry && entry.runnerId != batterId && reached(entry),
    );

    if (trajectory == Trajectory.BUNT) {
      return movedARunner((leg) => leg.to > leg.from);
    }

    const airborne = {Trajectory.FLY, Trajectory.POPUP, Trajectory.LINE};
    if (!airborne.contains(trajectory) || caughtInFlight) return false;
    return movedARunner((leg) => leg.to == 4);
  }

  /// A committable draft has the two facts §11.1 always collects — but only
  /// a batted ball has them. A between-pitch entry (§15.6) has no landing
  /// and no trajectory; what makes it committable is that something is on
  /// the chain to commit.
  bool get committable =>
      battedBall ? landing != null && trajectory != null : entries.isNotEmpty;

  /// Whether the drawn path is frozen (§15.1 v0.43): once anything beyond
  /// the opening walk-up has been entered, the ball's path stops being
  /// editable — changing it after plays hang off it would silently rewrite
  /// what those plays meant. The way out is the full play reset.
  bool get pathLocked => entries.length > openingLegCount;

  /// The last touch this fielder made in this play, if any — a re-drag of
  /// a fielder who already played the ball adjusts, never duplicates.
  TouchEntry? latestTouchBy(int position) {
    for (final entry in entries.reversed) {
      if (entry is TouchEntry && entry.position == position) return entry;
    }
    return null;
  }

  /// A re-drag of a fielder who already played the ball (§15.1 v0.43):
  /// she repositions and her play's location follows — one play, adjusted,
  /// never a second touch. When the landing was assumed from that touch,
  /// it moves with her.
  PlayDraft adjustingFielderPlay(int position, {required FieldCoord spot}) {
    final touch = latestTouchBy(position);
    if (touch == null) return this;
    final landingWasAssumed =
        landing != null &&
        touch.location != null &&
        landing!.x == touch.location!.x &&
        landing!.y == touch.location!.y;
    final moved = TouchEntry(
      key: touch.key,
      position: touch.position,
      touchType: touch.touchType,
      receivedQuality: touch.receivedQuality,
      location: spot,
    );
    return copyWith(
      landing: landingWasAssumed ? spot : null,
      movedFielders: {...movedFielders, position: spot},
      entries: [
        for (final entry in entries)
          if (entry.key == touch.key) moved else entry,
      ],
    );
  }

  PlayEntry? entryByKey(int key) {
    for (final entry in entries) {
      if (entry.key == key) return entry;
    }
    return null;
  }

  /// Where [runnerId] currently stands: their last leg's target, or
  /// [origin] untouched.
  int displayBase(String runnerId, int origin) {
    var base = origin;
    for (final entry in entries) {
      if (entry is LegEntry && entry.runnerId == runnerId) base = entry.to;
    }
    return base;
  }

  /// Whether this runner's position is still the opening presumption (the
  /// walk-up on contact) rather than something the scorer resolved. The
  /// canvas renders these in motion — she is running, not arrived.
  bool isProvisional(String runnerId) {
    for (final entry in entries.reversed) {
      if (entry is LegEntry && entry.runnerId == runnerId) {
        return entry.key < openingLegCount;
      }
    }
    return false;
  }

  /// Whether [runnerId] has been retired in this draft.
  bool isOut(String runnerId) =>
      entries.any((e) => e is OutEntry && e.runnerId == runnerId);

  PlayDraft copyWith({
    FieldCoord? landing,
    Object? endedAt = _unset,
    Trajectory? trajectory,
    bool? offWall,
    bool? sacrifice,
    List<PlayEntry>? entries,
    Map<int, FieldCoord>? movedFielders,
    int? openingLegCount,
    int? nextKey,
    Object? heldBy = _unset,
  }) {
    return PlayDraft(
      pitchEventId: pitchEventId,
      batterId: batterId,
      landing: landing ?? this.landing,
      endedAt: endedAt == _unset ? this.endedAt : endedAt as FieldCoord?,
      trajectory: trajectory ?? this.trajectory,
      offWall: offWall ?? this.offWall,
      sacrifice: sacrifice ?? this.sacrifice,
      entries: entries ?? this.entries,
      movedFielders: movedFielders ?? this.movedFielders,
      openingLegCount: openingLegCount ?? this.openingLegCount,
      nextKey: nextKey ?? this.nextKey,
      battedBall: battedBall,
      heldBy: heldBy == _unset ? this.heldBy : heldBy as int?,
    );
  }

  PlayDraft _appending(PlayEntry Function(int key) build) =>
      copyWith(entries: [...entries, build(nextKey)], nextKey: nextKey + 1);

  /// The default attribution target for the next runner leg: the most
  /// recent misplay touch (§13.4) or ⚖ rule call (§15.3: drags after an
  /// insertion link to it). Clean touches never auto-claim an advance — a
  /// single past a diving shortstop isn't "enabled by" her touch.
  int? get latestEnablerKey {
    for (final entry in entries.reversed) {
      if (entry is RuleCallEntry) return entry.key;
      if (entry is TouchEntry && entry.isMisplay) return entry.key;
    }
    return null;
  }

  /// The touch types that leave the ball *in hand* — a tap on another
  /// fielder while one of these is the latest touch is a throw. After a
  /// drop, a boot, a missed catch, or a throw away, the ball is loose and
  /// the next fielder interaction is a play on the ball, not a reception.
  static const _securingTypes = {
    TouchType.FIELDED,
    TouchType.CAUGHT,
    TouchType.RECEIVED_THROW,
    TouchType.TAG_APPLIED,
    TouchType.BOBBLED, // momentary misplay, ball stays with the fielder
  };

  /// Who holds the ball right now: the chain's last touch when it secured
  /// the ball, null when the ball is loose (or untouched). The accent ring
  /// and the tap-to-throw grammar key on this.
  TouchEntry? get securedTouch {
    for (final entry in entries.reversed) {
      if (entry is TouchEntry) {
        return _securingTypes.contains(entry.touchType) ? entry : null;
      }
    }
    return null;
  }

  PlayDraft addingTouch(
    int position,
    TouchType touchType, {
    FieldCoord? location,
  }) => _appending(
    (key) => TouchEntry(
      key: key,
      position: position,
      touchType: touchType,
      location: location,
    ),
  );

  /// The fielder drag's full effect in one value (§15.1 v0.43): she stands
  /// where she was dropped, the ball is assumed there when no path was
  /// drawn, and — unless the popup said she never touched it — the touch
  /// goes on the chain with its location.
  ///
  /// A *first* touch carries two more consequences:
  /// - **Caught** voids the running presumption: every unattributed leg
  ///   (the walk-up [PlayDraft] opened with) comes off, and the batter is
  ///   out in the air, putout to this touch.
  /// A misplay first touch does **not** touch her reach (§13.2 v0.56). It
  /// raises the hit-vs-error question rather than answering it: see
  /// [reachNeedsAnswer] and [resolvingReach].
  PlayDraft recordingFielderPlay(
    int position, {
    required FieldCoord spot,
    TouchType? touchType,
  }) {
    var next = copyWith(
      landing: landing ?? spot,
      movedFielders: {...movedFielders, position: spot},
    );
    if (touchType == null) return next;

    final before = next.entries.whereType<TouchEntry>().toList();
    final isFirstTouch = before.isEmpty;
    // A deflection is the one touch that leaves the ball airborne, so a
    // liner off the pitcher's glove can still be caught by the shortstop —
    // and that catch retires the batter exactly like any other.
    final wasInFlight =
        isFirstTouch || before.last.touchType == TouchType.DEFLECTED;
    next = next.addingTouch(position, touchType, location: spot);
    final touchKey = next.entries.last.key;

    if (touchType == TouchType.CAUGHT && wasInFlight) {
      next = next.copyWith(
        entries: [
          for (final entry in next.entries)
            if (entry is! LegEntry || entry.enabledByKey != null) entry,
        ],
      );
      return next.addingOut(
        batterId,
        atBase: 1,
        how: How.FLY_OUT,
        putoutKey: touchKey,
      );
    }

    return next;
  }

  /// §15.3 v0.43: a ⚖ attached to a runner consequence — inserted into the
  /// chain just before it, and linked: a leg re-attributes to the call
  /// (obstruction's reason derives from it); an out's `how` becomes
  /// `interference`.
  PlayDraft attachingRuleCall(
    int consequenceKey,
    CallType callType, {
    int? againstPosition,
  }) {
    final callKey = nextKey;
    final entries = <PlayEntry>[];
    for (final entry in this.entries) {
      if (entry.key == consequenceKey) {
        entries
          ..add(
            RuleCallEntry(
              key: callKey,
              callType: callType,
              againstPosition: againstPosition,
            ),
          )
          ..add(switch (entry) {
            LegEntry() => entry.copyWith(enabledByKey: callKey),
            OutEntry() => entry.copyWith(
              how: How.INTERFERENCE,
              enabledByCallKey: callKey,
            ),
            _ => entry,
          });
      } else {
        entries.add(entry);
      }
    }
    return copyWith(entries: entries, nextKey: callKey + 1);
  }

  /// Appends one leg. [attribute] = the default: link to [latestEnablerKey]
  /// (cascade pushes pass false — geometry moved them, not the ball). An
  /// explicit [enabledByKey] or [reason] wins over both — the SAFE
  /// classification's vocabulary (v0.43).
  PlayDraft addingLeg(
    String runnerId, {
    required int from,
    required int to,
    bool attribute = true,
    int? enabledByKey,
    RunnerAdvanceReason? reason,
  }) => _appending(
    (key) => LegEntry(
      key: key,
      runnerId: runnerId,
      from: from,
      to: to,
      enabledByKey: enabledByKey ?? (attribute ? latestEnablerKey : null),
      reasonOverride: reason,
    ),
  );

  /// The catcher's missed-catch touch on this chain, if one is already
  /// there — so a second runner advancing on the same passed ball links to
  /// it rather than minting a second one (§15.6).
  int? get passedBallTouchKey {
    for (final entry in entries) {
      if (entry is TouchEntry &&
          entry.position == 2 &&
          entry.touchType == TouchType.MISSED_CATCH) {
        return entry.key;
      }
    }
    return null;
  }

  /// The most recent touch of any kind — "on the throw" links here.
  int? get latestTouchKey {
    for (final entry in entries.reversed) {
      if (entry is TouchEntry) return entry.key;
    }
    return null;
  }

  /// The most recent misplay *touch* (never a ⚖) — "on an error" links
  /// here.
  int? get latestMisplayTouchKey {
    for (final entry in entries.reversed) {
      if (entry is TouchEntry && entry.isMisplay) return entry.key;
    }
    return null;
  }

  /// §16.3's beyond-the-fence award: the ball left the yard, so bases are
  /// granted rather than run. Every leg already on the chain is replaced —
  /// a home run is not a reach plus pushes, it is four bases for everyone
  /// aboard — and `offWall` comes off, since a ball that went over never
  /// hit the wall. Touches and ⚖ calls stay: a fielder can have played it
  /// at the fence and still watched it go.
  PlayDraft _awardingBases(
    List<RunnerSlot> origins, {
    required int bases,
    RunnerAdvanceReason? reason,
  }) {
    var next = copyWith(
      entries: [
        for (final entry in entries)
          if (entry is! LegEntry) entry,
      ],
      offWall: false,
      // The opening walk-up is superseded: every leg below is authored, so
      // nothing here is provisional and no force play can be pending.
      openingLegCount: 0,
    );
    // Lead runner first, matching §11.3's forced-chain ordering.
    final ordered = [...origins]..sort((a, b) => b.base.compareTo(a.base));
    for (final slot in ordered) {
      final to = slot.base + bases > 4 ? 4 : slot.base + bases;
      next = next.addingLeg(
        slot.runnerId,
        from: slot.base,
        to: to,
        attribute: false,
        reason: reason,
      );
    }
    return next;
  }

  /// Home run (§16.3): four bases for everyone — the batter's own leg to
  /// 4 derives `home_run` and every run aboard is an RBI (§13).
  PlayDraft resolvingHomeRun(List<RunnerSlot> origins) =>
      _awardingBases(origins, bases: 4);

  /// The beyond-the-fence sibling (§16.3): two bases for everyone, the
  /// batter's reach deriving `double` (a ground-rule double is a hit).
  PlayDraft resolvingGroundRuleDouble(List<RunnerSlot> origins) =>
      _awardingBases(
        origins,
        bases: 2,
        reason: RunnerAdvanceReason.GROUND_RULE,
      );

  /// The scorer answered SAFE on a force play (§15.1 v0.43): her
  /// provisional leg becomes an authored one at the same base. Nothing
  /// about the play changes except that it is no longer a presumption —
  /// she stops rendering in motion and stands on the bag.
  PlayDraft affirmingSafe(String runnerId) {
    LegEntry? provisional;
    for (final entry in entries.reversed) {
      if (entry is LegEntry && entry.runnerId == runnerId) {
        if (entry.key < openingLegCount) provisional = entry;
        break;
      }
    }
    final leg = provisional;
    if (leg == null) return this;
    return copyWith(
      entries: [
        for (final entry in entries)
          if (entry.key != leg.key) entry,
      ],
    ).addingLeg(runnerId, from: leg.from, to: leg.to, attribute: false);
  }

  /// The misplays a reach or an advance can be charged to (§13.2 v0.56),
  /// one per kind-and-fielder, in chain order.
  ///
  /// The scorer picks from these by name — "on the throwing error" — which
  /// is what lets the engine stop guessing *which* misplay explains a base.
  /// Guessing was wrong both ways round: the first touch charges the boot on
  /// a play where she recovered and then threw it away, and the latest touch
  /// charges the throw on a play where the boot is what put the batter on.
  /// Neither is derivable from the physical record, because both plays
  /// record the same touches.
  List<TouchEntry> get chargeableMisplays {
    final byLabel = <(OfficialErrorKind, int), TouchEntry>{};
    for (final entry in entries) {
      if (entry is! TouchEntry || !entry.isMisplay) continue;
      // Two boots by the same fielder are one answer, not two identical
      // chips; the later one is nearer the consequence.
      byLabel[(officialErrorKindOf(entry.touchType), entry.position)] = entry;
    }
    return byLabel.values.toList()..sort((a, b) => a.key.compareTo(b.key));
  }

  /// Whether the batter's reach to first is a question nobody has answered
  /// (§13.2 v0.56): some misplay on the play could explain it, she is still
  /// standing on the walk-up rather than on an authored leg, and she was not
  /// retired. Until v0.56 the first-touch misplay simply claimed the reach;
  /// deriving hit-vs-error from an answer the scorer never gave was wrong in
  /// both directions, so the question is now asked — on the SAFE popup when
  /// she is resolved there, at the ✓ otherwise.
  bool get reachNeedsAnswer =>
      battedBall &&
      chargeableMisplays.isNotEmpty &&
      provisionalReach != null &&
      !isOut(batterId);

  /// Her walk-up leg to first while it is still a presumption (§15.1).
  ///
  /// Deliberately *not* [isProvisional], which reports on a runner's most
  /// recent leg: once she is dragged to third her last leg is authored, and
  /// the reach behind it can still be an unanswered question. Reading the
  /// last leg made the ✓ commit that question silently.
  LegEntry? get provisionalReach {
    for (final entry in entries) {
      if (entry is LegEntry && entry.runnerId == batterId) {
        return entry.key < openingLegCount && entry.to == 1 ? entry : null;
      }
    }
    return null;
  }

  /// The hit-vs-error answer applied to the reach (§13.2 v0.56). [earned]
  /// true: she beat it out and no misplay cost her anything here — the leg
  /// becomes an authored, unattributed reach, which derives a hit. False:
  /// [misplayKey] gave her the base, so the leg links to that touch and
  /// `reached_on_error` derives. The scorer names the touch (§13.2's
  /// [chargeableMisplays]); nothing here infers it.
  ///
  /// Replaces the provisional leg rather than editing it, exactly as
  /// [affirmingSafe] does — a presumption becoming an answer is a new leg,
  /// and keeping the old key would leave it looking provisional forever.
  PlayDraft resolvingReach({required bool earned, int? misplayKey}) {
    misplayKey ??= latestMisplayTouchKey;
    final leg = provisionalReach;
    if (leg == null || misplayKey == null) return this;
    final resolved = LegEntry(
      key: nextKey,
      runnerId: batterId,
      from: leg.from,
      to: leg.to,
      enabledByKey: earned ? null : misplayKey,
    );
    // Narrative order: the touch that opened the play, then the reach it
    // does or does not explain, then whatever she did afterwards. Appending
    // would leave her reach *behind* legs she took later — the strip
    // reading 1→3 above 0→1, which is the ordering complaint the old
    // auto-claim also produced, from the other direction.
    final next = <PlayEntry>[];
    var placed = false;
    for (final entry in entries) {
      if (entry.key == leg.key) continue;
      next.add(entry);
      if (!placed && entry.key == misplayKey) {
        next.add(resolved);
        placed = true;
      }
    }
    if (!placed) next.add(resolved);
    return copyWith(entries: next, nextKey: nextKey + 1);
  }

  /// The SAFE popup's answer applied (§15.1 v0.43): the dragged leg carries
  /// the classification — the hit itself (no enabler; raises hit rank), on
  /// the throw (linked to the latest touch; officially an advance, not more
  /// hit), on an error (linked to the latest misplay, or explicit `error`
  /// when none is entered yet), a fielder's choice, or obstruction (⚖
  /// inserted and linked). Cascade pushes stay plain forced movement.
  ///
  /// [earnedThrough] (v0.56) splits the dragged leg when the scorer says she
  /// earned part of it: *double, then third on the boot* is 1→2 unattributed
  /// plus 2→3 linked, not one 1→3 leg that has to be all hit or all error.
  /// Only meaningful with [SafeResolution.onError], and only strictly
  /// between the move's ends.
  PlayDraft resolvingSafe(
    List<CascadedMove> moves,
    SafeResolution how, {
    int? againstPosition,
    int? earnedThrough,
    int? errorTouchKey,
  }) {
    var next = this;
    for (var i = 0; i < moves.length; i++) {
      final move = moves[i];
      if (i > 0) {
        next = next.addingLeg(
          move.runnerId,
          from: move.from,
          to: move.to,
          attribute: false,
        );
        continue;
      }
      next = switch (how) {
        SafeResolution.onTheHit => next.addingLeg(
          move.runnerId,
          from: move.from,
          to: move.to,
          attribute: false,
        ),
        SafeResolution.onTheThrow => next.addingLeg(
          move.runnerId,
          from: move.from,
          to: move.to,
          attribute: false,
          enabledByKey: next.latestTouchKey,
        ),
        SafeResolution.onError =>
          next.latestMisplayTouchKey != null
              ? () {
                  // The bases she earned come off the front of the move as
                  // their own unattributed leg; the misplay is charged only
                  // with what is left (v0.56).
                  final earned = earnedThrough;
                  var withEarned = next;
                  var from = move.from;
                  if (earned != null &&
                      earned > move.from &&
                      earned < move.to) {
                    withEarned = next.addingLeg(
                      move.runnerId,
                      from: move.from,
                      to: earned,
                      attribute: false,
                    );
                    from = earned;
                  }
                  return withEarned.addingLeg(
                    move.runnerId,
                    from: from,
                    to: move.to,
                    attribute: false,
                    // The misplay the scorer named, or the most recent when
                    // this answer carried no name (a runner's advance, where
                    // the chip is still the plain "on an error").
                    enabledByKey:
                        errorTouchKey ?? withEarned.latestMisplayTouchKey,
                  );
                }()
              : next.addingLeg(
                  move.runnerId,
                  from: move.from,
                  to: move.to,
                  attribute: false,
                  reason: RunnerAdvanceReason.ERROR,
                ),
        SafeResolution.fieldersChoice => next.addingLeg(
          move.runnerId,
          from: move.from,
          to: move.to,
          attribute: false,
          reason: RunnerAdvanceReason.FIELDERS_CHOICE,
        ),
        SafeResolution.obstruction => () {
          final withLeg = next.addingLeg(
            move.runnerId,
            from: move.from,
            to: move.to,
            attribute: false,
          );
          return withLeg.attachingRuleCall(
            withLeg.entries.last.key,
            CallType.OBSTRUCTION,
            againstPosition: againstPosition,
          );
        }(),
        // §13.2's pair: a passed ball is physics, so the catcher's miss is
        // recorded and the advance links to it. A second runner moving on
        // the same ball reuses that touch — one PB, one touch, N advances.
        SafeResolution.passedBall => () {
          var withTouch = next;
          var touchKey = next.passedBallTouchKey;
          if (touchKey == null) {
            withTouch = next.addingTouch(2, TouchType.MISSED_CATCH);
            touchKey = withTouch.entries.last.key;
          }
          return withTouch.addingLeg(
            move.runnerId,
            from: move.from,
            to: move.to,
            attribute: false,
            enabledByKey: touchKey,
            reason: RunnerAdvanceReason.PASSED_BALL,
          );
        }(),
        // A wild pitch is the advance alone — the absence of the catcher's
        // touch is what makes it one (§13.2).
        _ => next.addingLeg(
          move.runnerId,
          from: move.from,
          to: move.to,
          attribute: false,
          reason: _betweenPitchReasons[how],
        ),
      };
    }
    return next;
  }

  /// Appends an out. If the runner's last leg reached exactly [atBase],
  /// that leg comes off first — she never made it; the provisional advance
  /// *resolves into* the out rather than committing alongside it as a
  /// phantom `RunnerAdvance`.
  PlayDraft addingOut(
    String runnerId, {
    required int atBase,
    required How how,
    int? putoutKey,
  }) {
    LegEntry? last;
    for (final entry in entries) {
      if (entry is LegEntry && entry.runnerId == runnerId) last = entry;
    }
    final resolved = last;
    final next = resolved != null && resolved.to == atBase
        ? copyWith(
            entries: [
              for (final entry in entries)
                if (entry.key != resolved.key) entry,
            ],
          )
        : this;
    return next._appending(
      (key) => OutEntry(
        key: key,
        runnerId: runnerId,
        atBase: atBase,
        how: how,
        putoutKey: putoutKey,
      ),
    );
  }

  /// Appends a bare ⚖ at the chain's end. Used only by the test suite —
  /// production ⚖ entry goes through [attachingRuleCall], which inserts
  /// before the consequence it explains.
  PlayDraft addingRuleCall(CallType callType) =>
      _appending((key) => RuleCallEntry(key: key, callType: callType));

  PlayDraft updatingEntry(int key, PlayEntry Function(PlayEntry) change) =>
      copyWith(
        entries: [
          for (final entry in entries)
            if (entry.key == key) change(entry) else entry,
        ],
      );

  /// Removes an entry. Links pointing at it are orphaned to null — never
  /// silently retargeted.
  PlayDraft removingEntry(int key) => copyWith(
    entries: [
      for (final entry in entries)
        if (entry.key != key)
          switch (entry) {
            LegEntry(enabledByKey: final e) when e == key => entry.copyWith(
              enabledByKey: null,
            ),
            OutEntry(putoutKey: final p) when p == key => entry.copyWith(
              putoutKey: null,
            ),
            _ => entry,
          },
    ],
  );

  Map<String, dynamic> toJson() => {
    'pitchEventId': pitchEventId,
    'batterId': batterId,
    'landing': landing?.toJson(),
    'endedAt': endedAt?.toJson(),
    'trajectory': trajectoryValues.reverse[trajectory],
    'offWall': offWall,
    'sacrifice': sacrifice,
    'entries': [for (final entry in entries) entry.toJson()],
    'movedFielders': {
      for (final entry in movedFielders.entries)
        '${entry.key}': entry.value.toJson(),
    },
    'openingLegCount': openingLegCount,
    'nextKey': nextKey,
    'battedBall': battedBall,
    'heldBy': heldBy,
  };

  /// The atomic commit sequence (§15.5): `BallInPlay` first, then the chain
  /// in entry order, with §4.2–4.3's id links expressed as intra-batch
  /// local refs. Throws [StateError] when not [committable] — the ✓ is
  /// disabled until then, so reaching this any other way is a bug.
  ///
  /// Commit-time derivations, all mechanical (§13):
  /// - leg `reason` from the enabling entry — misplay touch → `error`
  ///   (`wild_throw` keeps its own reason), obstruction call →
  ///   `obstruction`, otherwise `batted_ball`;
  /// - `landingIsCaught` from the chain's first touch;
  /// - `fair` is always true — the outcome that opens this surface is
  ///   `in_play`, and foul field taps are out of DIA-008's scope.
  List<PendingEvent> toEvents() {
    final landing = this.landing;
    final trajectory = this.trajectory;
    if (battedBall && (landing == null || trajectory == null)) {
      throw StateError('draft is not committable: landing/trajectory missing');
    }
    const bipKey = 'bip';
    String entryKey(int key) => 'e$key';

    return [
      // A between-pitch entry mints no BallInPlay — nothing was hit. Its
      // touches anchor to the pitch itself, which is already in the stream,
      // so they carry a real id rather than a batch-local reference.
      if (battedBall)
        PendingEvent(
          type: 'BallInPlay',
          localKey: bipKey,
          payload: BallInPlay(
            pitchEventId: pitchEventId,
            fair: true,
            trajectory: trajectory!,
            landing: landing!,
            endedAt: endedAt,
            landingIsCaught: landingIsCaught,
            offWall: offWall ? true : null,
            sacrifice: sacrifice ? true : null,
          ).toJson(),
        ),
      for (final entry in entries)
        switch (entry) {
          TouchEntry() => PendingEvent(
            type: 'FielderTouch',
            localKey: entryKey(entry.key),
            payload:
                FielderTouch(
                    anchorEventId: '',
                    position: entry.position,
                    touchType: entry.touchType,
                    receivedQuality: entry.receivedQuality,
                    location: entry.location,
                  ).toJson()
                  ..['anchorEventId'] = battedBall
                      ? localRef(bipKey)
                      : pitchEventId,
          ),
          LegEntry() => PendingEvent(
            type: 'RunnerAdvance',
            localKey: entryKey(entry.key),
            payload: () {
              final enabler = entry.enabledByKey == null
                  ? null
                  : entryByKey(entry.enabledByKey!);
              final payload = RunnerAdvance(
                runnerId: entry.runnerId,
                from: entry.from,
                to: entry.to,
                reason: entry.reasonOverride ?? _legReason(enabler),
              ).toJson();
              if (enabler is TouchEntry) {
                payload['enabledByTouchId'] = localRef(entryKey(enabler.key));
              } else if (enabler is RuleCallEntry) {
                // §4.3's `enabledByCallId`: the call that caused the
                // movement, not merely the reason it implies.
                payload['enabledByCallId'] = localRef(entryKey(enabler.key));
              }
              return payload;
            }(),
          ),
          OutEntry() => PendingEvent(
            type: 'RunnerOut',
            localKey: entryKey(entry.key),
            payload:
                RunnerOut(
                  runnerId: entry.runnerId,
                  atBase: entry.atBase,
                  how: entry.how,
                ).toJson()..addAll({
                  if (entry.putoutKey != null)
                    'putoutTouchId': localRef(entryKey(entry.putoutKey!)),
                  if (entry.enabledByCallKey != null)
                    'enabledByCallId': localRef(
                      entryKey(entry.enabledByCallKey!),
                    ),
                }),
          ),
          RuleCallEntry() => PendingEvent(
            type: 'RuleCall',
            localKey: entryKey(entry.key),
            payload: RuleCall(
              callType: entry.callType,
              againstPosition: entry.againstPosition,
            ).toJson(),
          ),
        },
    ];
  }

  /// Leg reason from its enabler (§13's derivation, mechanical): the reason
  /// is physics-adjacent vocabulary, and hit-vs-error is *never* decided
  /// here — official scoring reads the charged touch, not this field.
  RunnerAdvanceReason _legReason(PlayEntry? enabler) {
    return switch (enabler) {
      TouchEntry(touchType: TouchType.WILD_THROW) =>
        RunnerAdvanceReason.WILD_THROW,
      TouchEntry(isMisplay: true) => RunnerAdvanceReason.ERROR,
      RuleCallEntry(callType: CallType.OBSTRUCTION) =>
        RunnerAdvanceReason.OBSTRUCTION,
      _ => RunnerAdvanceReason.BATTED_BALL,
    };
  }
}

const _unset = Object();
