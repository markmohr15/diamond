import 'package:diamond/src/events/event_store.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/events/pending_event.dart';
import 'package:diamond/src/game/game_session.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/rules/game_state_projector.dart';
import 'package:diamond/src/rules/official_scoring.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Event types the top-level undo will void — the events the loop itself
/// emits. Structural events (LineupSet, InningHalfStart) are deliberately not
/// undoable from here: voiding one would not reverse a scorer's last action,
/// it would unmake the game.
const _undoableTypes = {
  'PitchThrown',
  'BallInPlay',
  'RunnerOut',
  'RunnerAdvance',
  'FielderTouch',
  'RuleCall',
  'CountCorrection',
};

/// Action roots (§11.3 v0.41): the events a scorer authors directly, one per
/// action. Everything the loop auto-appends after a root — a strikeout's
/// RunnerOut, a walk's forced chain, a D3K resolution — belongs to that
/// root's undo unit. A committed play is one action (§15.5): its BallInPlay
/// leads the atomic batch, so it roots the unit and the play voids whole —
/// without reaching back through it to the pitch, which stays its own action.
const _actionRootTypes = {'PitchThrown', 'BallInPlay', 'CountCorrection'};

/// §15.6 v0.42: reasons a `RunnerAdvance` is a **root** rather than a
/// consequence. The same event type is both — a forced advance after a walk
/// rides the pitch's undo unit, a steal entered on the idle field is its own
/// action — so root-ness cannot key on type alone.
///
/// The vocabularies settle it without a schema change: these reasons never
/// appear inside a play or a forced chain (a walk's chain reads `walk`, a
/// batted ball's reads `batted_ball`), so a reason from this set *is* the
/// claim that a scorer authored it standing between pitches.
const _betweenPitchReasons = {
  'stolen_base',
  'wild_pitch',
  'passed_ball',
  'defensive_indifference',
};

/// The same, for `RunnerOut`: only a between-pitch entry produces these.
const _betweenPitchHows = {'caught_stealing', 'picked_off'};

bool _isActionRoot(GameEvent event) {
  if (_actionRootTypes.contains(event.type)) return true;
  return switch (event.type) {
    'RunnerAdvance' => _betweenPitchReasons.contains(event.payload['reason']),
    'RunnerOut' => _betweenPitchHows.contains(event.payload['how']),
    _ => false,
  };
}

/// The UI's one writer and one reader of the event stream: append an event,
/// re-project [GameState] (§5's pure fold, snapshot-aware via
/// [GameStateProjector]).
///
/// Append-then-refold rather than a Drift watch query, on purpose: the store's
/// API stays append + read (its whole design), the fold is cheap at M1 stream
/// lengths, and every state this exposes is provably `fold(stream)` — there is
/// no second code path that could disagree with it.
class GameController extends AsyncNotifier<GameState> {
  late EventStore _store;
  late GameSession _session;
  late GameStateProjector _projector;

  /// Next envelope `seq` for this device — resumed from the raw stream on
  /// build, so a restart continues the sequence instead of colliding with it.
  late int _nextSeq;

  @override
  Future<GameState> build() async {
    _store = ref.watch(eventStoreProvider);
    _session = ref.watch(gameSessionProvider);
    _projector = GameStateProjector(_store);

    final raw = await _store.readRawStream(_session.gameId);
    _nextSeq = raw.isEmpty
        ? 0
        : raw.map((e) => e.seq).reduce((a, b) => a > b ? a : b) + 1;

    // First launch: seed the M1 half-inning — their lineup, top 1, us in the
    // field. DIA-009's scripted game replaces this with a real bootstrap.
    // Idempotent across restarts by construction: it only fires on an empty
    // stream.
    if (raw.isEmpty) {
      await _append(
        type: 'LineupSet',
        payload: LineupSet(
          teamId: _session.opponentTeamId,
          battingOrder: [for (var i = 1; i <= 9; i++) 'opp-$i'],
        ).toJson(),
      );
      await _append(
        type: 'InningHalfStart',
        payload: InningHalfStart(
          inning: 1,
          half: Half.TOP,
          battingTeamId: _session.opponentTeamId,
        ).toJson(),
      );
    }

    return _projector.project(_session.gameId);
  }

  /// Appends one event and refolds. The only write path the UI has.
  ///
  /// Returns the appended event, envelope included — a correction (§6) needs
  /// the id of what it corrects, and "record last pitch" (§11.1 v0.39) needs
  /// the original payload to correct on top of.
  Future<GameEvent> append({
    required String type,
    required Map<String, dynamic> payload,
    String? corrects,
  }) async {
    final event = await _append(
      type: type,
      payload: payload,
      corrects: corrects,
    );
    state = AsyncData(await _projector.project(_session.gameId));
    return event;
  }

  /// Appends a committed play's whole sequence (§15.5) — one storage
  /// transaction, one refold. Entries arrive in stream order; envelopes
  /// (ids, seqs) are built here, as everywhere, and intra-batch references
  /// (`{"$local": key}` payload values, §4.2–4.3's event-id links) resolve
  /// against the batch's real ids once they exist.
  Future<void> appendAllPending(List<PendingEvent> entries) async {
    final events = [
      for (final entry in entries)
        _buildEvent(type: entry.type, payload: entry.payload),
    ];
    final idsByKey = {
      for (var i = 0; i < entries.length; i++)
        if (entries[i].localKey != null) entries[i].localKey!: events[i].id,
    };
    final resolved = [
      for (final event in events)
        GameEvent(
          id: event.id,
          gameId: event.gameId,
          seq: event.seq,
          deviceId: event.deviceId,
          createdBy: event.createdBy,
          wallClock: event.wallClock,
          type: event.type,
          payload: resolveLocalRefs(event.payload, idsByKey),
          corrects: event.corrects,
        ),
    ];
    await _store.appendAll(resolved);
    state = AsyncData(await _projector.project(_session.gameId));
  }

  /// Top-level undo (§6), **action-scoped** (§11.3 v0.41): one tap reverses
  /// the most recent scorer action — the last action-root event plus
  /// everything the loop auto-appended for it — so a bases-loaded walk
  /// reverses as one unit, not five taps. Unlimited depth: each call peels
  /// one more action.
  ///
  /// When the last action was itself a §6 correction ("record last pitch"),
  /// undo **counter-corrects** instead of voiding: it re-appends the
  /// superseded payload, collapsing the chain back to what it showed before
  /// the action. Voiding would hide the *whole* chain — original included
  /// (see `resolveVisibleLogicalOrder`) — undoing more than the action. Once
  /// a chain is back at its origin there is no further correction to unwind,
  /// so the next undo voids it, removing the underlying entry — which is by
  /// then the most recent action still standing.
  /// §15.6's anchors for a between-pitch entry. Touches recorded between
  /// pitches have no `BallInPlay` to hang from, so they anchor to the pitch
  /// itself (§13.2, the same shape a D3K uses) — and a passed ball already
  /// recorded on that pitch is reused rather than duplicated, so a second
  /// runner moving on the same ball links to the same touch: one PB, one
  /// touch, N advances.
  Future<({String? pitchId, String? passedBallTouchId})>
  betweenPitchAnchors() async {
    final visible = await _store.readStream(_session.gameId);
    String? pitchId;
    for (final event in visible.reversed) {
      if (event.type == 'PitchThrown') {
        pitchId = event.id;
        break;
      }
    }
    if (pitchId == null) return (pitchId: null, passedBallTouchId: null);
    String? touchId;
    for (final event in visible) {
      if (event.type != 'FielderTouch') continue;
      final touch = FielderTouch.fromJson(event.payload);
      if (touch.anchorEventId != pitchId) continue;
      if (!pitchReceivingTouchTypes.contains(touch.touchType)) continue;
      touchId = event.id;
    }
    return (pitchId: pitchId, passedBallTouchId: touchId);
  }

  /// The root the next undo would act on, or null when undo is unavailable
  /// (§11.3, DIA-019f) — so the button can *show* it is unavailable rather
  /// than silently doing nothing when tapped.
  ///
  /// [floorEventId] is the seal (see [undoLast]).
  Future<GameEvent?> undoableRoot({String? floorEventId}) async {
    final visible = await _store.readStream(_session.gameId);
    final root = _undoRoot(visible);
    if (root == null) return null;
    return _undoReaches(visible, root, floorEventId) ? root : null;
  }

  /// Where the current plate appearance starts, as an index into [visible].
  ///
  /// The boundary is a `batterId` change on `PitchThrown` — the same test the
  /// scoring partition uses (`official_scoring.dart`), rather than a second
  /// definition that could drift from it.
  ///
  /// Events *before* her first pitch but after the previous batter's last one
  /// — a steal taken while she stood in — count as hers here. That is one
  /// event's worth of generosity at the boundary and it errs toward letting
  /// the scorer undo something she just did.
  int _currentPaStart(List<GameEvent> visible) {
    String? currentBatter;
    for (final event in visible.reversed) {
      if (event.type != 'PitchThrown') continue;
      currentBatter = PitchThrown.fromJson(event.payload).batterId;
      break;
    }
    if (currentBatter == null) return 0;

    var start = 0;
    for (var i = visible.length - 1; i >= 0; i--) {
      final event = visible[i];
      if (event.type != 'PitchThrown') continue;
      if (PitchThrown.fromJson(event.payload).batterId != currentBatter) {
        start = i + 1;
        break;
      }
    }
    return start;
  }

  /// §11.3 v0.54's floor: undo reaches only what is unsealed.
  ///
  /// Two walls, and a root must clear both. The **plate appearance** — undo
  /// never crosses a `batterId` change, so it can never reach into a batter
  /// whose line is finished. And the **seal**, an explicit event id the
  /// caller carries forward: once the scorer has moved on to the next pitch,
  /// or once an undo has emptied a plate appearance, that id freezes the wall
  /// so the next tap cannot walk through the gap the first one opened.
  bool _undoReaches(
    List<GameEvent> visible,
    GameEvent root,
    String? floorEventId,
  ) {
    final rootIndex = visible.indexWhere((e) => e.id == root.id);
    if (rootIndex < 0) return false;
    if (rootIndex < _currentPaStart(visible)) return false;
    if (floorEventId == null) return true;
    final floorIndex = visible.indexWhere((e) => e.id == floorEventId);
    return floorIndex < 0 || rootIndex > floorIndex;
  }

  /// The event the scorer authored, for the unit the next undo would take.
  GameEvent? _undoRoot(List<GameEvent> visible) {
    final unit = _undoUnit(visible);
    if (unit == null) return null;
    return unit.firstWhere(_isActionRoot);
  }

  /// The batch one undo takes, newest first, or null when there is no
  /// complete action to undo.
  List<GameEvent>? _undoUnit(List<GameEvent> visible) {
    final unit = <GameEvent>[];
    var rooted = false;
    for (final event in visible.reversed) {
      if (!_undoableTypes.contains(event.type)) break;
      // A between-pitch entry is a small batch, and its root is the last
      // event in it — the advance or the out the chips committed. The
      // touches that earned the assist come *before* it, so the walk keeps
      // going through them rather than stopping on the root and orphaning
      // the throw (§15.6: the PB pair included, one tap voids it whole).
      if (rooted && event.type != 'FielderTouch') break;
      unit.add(event);
      if (_isActionRoot(event)) {
        if (event.type != 'RunnerAdvance' && event.type != 'RunnerOut') break;
        rooted = true;
      }
    }
    // No complete action to undo (bootstrap only, or consequences with no
    // root — which the loop never writes): a no-op, not an error.
    if (unit.isEmpty || !unit.any(_isActionRoot)) return null;
    return unit;
  }

  /// Undoes the last action, and returns **the root that was voided** so a
  /// caller can put back what the scorer typed (§11.3, DIA-019b).
  ///
  /// Null when nothing was undone — including when the action is **sealed**
  /// (DIA-019f, see [_undoReaches]) — and null when a *correction* was
  /// unwound rather than voided, since there the original entry still stands
  /// and there is nothing for the loop to reopen.
  Future<GameEvent?> undoLast({String? floorEventId}) async {
    final visible = await _store.readStream(_session.gameId);
    final unit = _undoUnit(visible);
    if (unit == null) return null;

    // The event the scorer authored. For a play that is the batch's first
    // event (BallInPlay/PitchThrown, reached last by the backward walk);
    // for a between-pitch entry it is the advance or out the chips
    // committed, with its touches collected after it.
    final root = unit.firstWhere(_isActionRoot);
    if (!_undoReaches(visible, root, floorEventId)) return null;
    if (root.corrects != null) {
      final raw = await _store.readRawStream(_session.gameId);
      final byId = {for (final e in raw) e.id: e};

      var origin = root;
      while (origin.corrects != null && byId.containsKey(origin.corrects)) {
        origin = byId[origin.corrects]!;
      }

      // A chain already showing its origin's payload has nothing left to
      // unwind — the standing action is the original entry, handled by the
      // void path below. Otherwise, one correction step comes off.
      if (!_deepEquals(root.payload, origin.payload)) {
        final predecessor = byId[root.corrects];
        if (predecessor != null) {
          await _append(
            type: root.type,
            payload: predecessor.payload,
            corrects: root.id,
          );
          state = AsyncData(await _projector.project(_session.gameId));
          return null;
        }
      }
    }

    for (final event in unit) {
      await _append(
        type: 'VoidEvent',
        payload: VoidEvent(targetId: event.id).toJson(),
      );
    }
    state = AsyncData(await _projector.project(_session.gameId));
    return root;
  }

  /// Structural equality for JSON-shaped payloads (maps, lists, scalars).
  bool _deepEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// Raw append: envelope construction + store write, no refold. `build`
  /// uses this directly because assigning state mid-build is not allowed.
  Future<GameEvent> _append({
    required String type,
    required Map<String, dynamic> payload,
    String? corrects,
  }) async {
    final event = _buildEvent(type: type, payload: payload, corrects: corrects);
    await _store.append(event);
    return event;
  }

  /// Envelope construction alone — consumes the next seq, writes nothing.
  GameEvent _buildEvent({
    required String type,
    required Map<String, dynamic> payload,
    String? corrects,
  }) {
    final seq = _nextSeq++;
    return GameEvent(
      // Unique per device: seq strictly increases and survives restarts.
      id: '${_session.deviceId}-$seq',
      gameId: _session.gameId,
      seq: seq,
      deviceId: _session.deviceId,
      createdBy: _session.createdBy,
      wallClock: DateTime.now().toUtc(),
      type: type,
      payload: payload,
      corrects: corrects,
    );
  }
}

final gameControllerProvider = AsyncNotifierProvider<GameController, GameState>(
  GameController.new,
);
