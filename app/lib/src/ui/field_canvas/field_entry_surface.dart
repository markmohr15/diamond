import 'dart:async';

import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/field/field_profile.dart';
import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/play/play_draft.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
import 'package:diamond/src/rules/game_state.dart';
import 'package:diamond/src/ui/field_canvas/field_dialog.dart';
import 'package:diamond/src/ui/field_canvas/field_geometry.dart';
import 'package:diamond/src/ui/field_canvas/field_painter.dart';
import 'package:diamond/src/ui/field_canvas/play_chain_strip.dart';
import 'package:diamond/src/ui/field_canvas/trajectory_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
const Key fieldCommitKey = Key('fieldCommit');
@visibleForTesting
const Key fieldDiscardKey = Key('fieldDiscard');
@visibleForTesting
const Key offWallChipKey = Key('offWallChip');
@visibleForTesting
const Key sacrificeChipKey = Key('sacrificeChip');
@visibleForTesting
const Key fieldDistanceKey = Key('fieldDistance');
@visibleForTesting
const Key fieldCanvasKey = Key('fieldCanvas');
@visibleForTesting
const Key fieldIdleLabelKey = Key('fieldIdleLabel');
@visibleForTesting
const Key fieldIdleCloseKey = Key('fieldIdleClose');
@visibleForTesting
Key betweenPitchChipKey(String reason) => Key('betweenPitch-$reason');


@visibleForTesting
Key fielderPlayKey(String choice) => Key('fielderPlay-$choice');
@visibleForTesting
const Key trajectoryEditKey = Key('trajectoryEdit');
@visibleForTesting
const Key fieldResetKey = Key('fieldReset');
@visibleForTesting
Key beyondFenceKey(String choice) => Key('beyondFence-$choice');
@visibleForTesting
Key safeChipKey(String choice) => Key('safe-$choice');
@visibleForTesting
Key outChipKey(String choice) => Key('out-$choice');

/// How close (px) a release must be to a target — a base, a Safe/Out pill,
/// or a fielder — to hit it. Tuned literal: generous enough for a gloved
/// thumb on a sideline tablet.
const double _snapRadiusPx = 36;

/// How near the fence (ft, either side) a landing suggests `offWall`
/// (§15.1). Tuned literal — the spline is exact, thumbs aren't.
const double _offWallToleranceFt = 6;

/// The DIA-008 field surface (§15.1 v0.43, §15.2–15.4 M1 subset), in the
/// order the grammar demands: trajectory first (it gates the canvas and
/// drives every later option); then the ball — a two-tap drawn path
/// (bounce → ended up, the accent streak) or a fielder dragged to where she
/// made the play, with the what-happened popup; runner drags resolve on
/// Safe/Out targets that appear at the approached base; the play chain
/// strip carries the corrections; ✓ commits atomically (§15.5).
///
/// Reads the *pre-play* base state from the fold — the draft's chain exists
/// only here and in the journal until commit.
/// The field screen (§15.1, §15.6 v0.42) — **one entity whether the ball was
/// hit or not**. A ball in play is a *state* of this screen, not a different
/// screen: same canvas, same fielders, same runner tokens, same throw
/// grammar. What a draft adds is the play chrome (trajectory, chain strip,
/// ✓) and the accumulating chain behind it.
///
/// With [draft] null the surface is **between pitches**: defense and runners
/// visible, no chain strip and no ✓, and a runner drag commits its own event
/// on the reason chip rather than joining a play. The catcher holds the ball
/// — true after every pitch in both sports — so tapping a fielder throws to
/// her exactly as it does inside a play, which is what lets a caught stealing
/// record 2-6 with real putout and assist credit.
class FieldEntrySurface extends ConsumerStatefulWidget {
  const FieldEntrySurface({required this.draft, super.key});

  final PlayDraft draft;

  @override
  ConsumerState<FieldEntrySurface> createState() => _FieldEntrySurfaceState();
}

/// One in-flight gesture, decided at pointer-down by what the finger landed
/// on: a runner token, a fielder, or open field (path entry).
class _ActiveDrag {
  _ActiveDrag({required this.start, this.runnerId, this.fielderPosition})
    : current = start;

  final Offset start;
  Offset current;

  final String? runnerId;
  final int? fielderPosition;

  bool get isPath => runnerId == null && fielderPosition == null;
}

class _FieldEntrySurfaceState extends ConsumerState<FieldEntrySurface> {
  _ActiveDrag? _drag;

  /// A throw just arrived at this base with a runner heading there: the
  /// SAFE/OUT pair is up at the bag, waiting for the tap that resolves the
  /// force play (§15.1 v0.43).
  ({String runnerId, int base})? _pendingForcePlay;

  @override
  void initState() {
    super.initState();
    // §15.1 v0.43: the batted-ball type is the first question, front and
    // center — the modal opens with the surface (unless a restored journal
    // already answered it).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Between pitches there is no batted ball to ask about.
      final draft = widget.draft;
      if (mounted && draft.battedBall && draft.trajectory == null) {
        _showTrajectoryDialog();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draft = widget.draft;
    final controller = ref.read(playDraftProvider.notifier);
    final bases = _foldBases;
    final tokens = _tokens(draft, bases);

    return Column(
      children: [
        if (!draft.battedBall)
          // Between pitches: no trajectory, no chain, nothing to commit —
          // the only chrome is a way back out.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _possessionLabel,
                    key: fieldIdleLabelKey,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                // The same pair the play surface uses, and they mean the
                // same things: ✕ leaves with nothing recorded, ✓ commits
                // what is on the chain. A between-pitch entry accumulates
                // now, so it earns a real commit rather than a "close".
                IconButton(
                  key: fieldIdleCloseKey,
                  onPressed: controller.discard,
                  icon: const Icon(Icons.close),
                  tooltip: 'Leave without recording',
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: fieldCommitKey,
                  onPressed: draft.committable ? controller.commit : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Commit'),
                ),
              ],
            ),
          )
        else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // The chosen batted-ball type; taps reopen the modal for the
              // "line or fly?" second thought.
              ActionChip(
                key: trajectoryEditKey,
                label: Text(
                  draft.trajectory == null
                      ? '…'
                      : trajectoryLabel(draft.trajectory!),
                ),
                onPressed: _showTrajectoryDialog,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  _statusLabel(draft),
                  key: fieldDistanceKey,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              IconButton(
                key: fieldResetKey,
                onPressed: () async {
                  setState(() => _pendingForcePlay = null);
                  await controller.reset();
                  if (mounted) _showTrajectoryDialog();
                },
                icon: const Icon(Icons.replay),
                tooltip: 'Start the play over',
              ),
              IconButton(
                key: fieldDiscardKey,
                onPressed: controller.discard,
                icon: const Icon(Icons.close),
                tooltip: 'Discard play',
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: fieldCommitKey,
                onPressed: draft.committable ? controller.commit : null,
                icon: const Icon(Icons.check),
                label: const Text('Commit play'),
              ),
            ],
          ),
        ),
        // §15.2: the chain above the canvas, once there is a play to chain.
        // Between pitches there is none — §15.6 is a single fact, not a chain.
        if (!draft.battedBall || draft.trajectory != null)
          PlayChainStrip(
            draft: draft,
            runnerLabels: _runnerLabels(draft, bases),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final geometry = FieldGeometry(
                profile: FieldProfile.fastpitch12U,
                size: constraints.biggest,
              );
              return GestureDetector(
                onPanDown: (details) =>
                    _onDown(details.localPosition, geometry, tokens),
                onPanUpdate: (details) => setState(() {
                  _drag?.current = details.localPosition;
                }),
                onPanEnd: (_) => _onUp(geometry, controller, tokens),
                onPanCancel: () => setState(() => _drag = null),
                child: CustomPaint(
                  key: fieldCanvasKey,
                  size: constraints.biggest,
                  painter: FieldPainter(
                    geometry: geometry,
                    ink: scheme.onSurface,
                    accent: scheme.primary,
                    surface: scheme.surface,
                    landing: draft.landing,
                    retrieved: draft.retrieved,
                    tokens: tokens,
                    dragPosition: _drag?.current,
                    dragTokenId: _drag?.runnerId,
                    dragFielderPosition: _drag?.fielderPosition,
                    // Seed included, so the ring is right between pitches
                    // too — and absent once the ball is loose.
                    holderPosition: draft.holderPosition,
                    movedFielders: draft.movedFielders,
                    forcePlayBase: _pendingForcePlay?.base,
                    canRecordOut: _canRecordOut,
                    route: [
                      if (draft.landing != null)
                        draft.retrieved ?? draft.landing!,
                      for (final entry in draft.entries)
                        if (entry is TouchEntry && entry.location != null)
                          entry.location!,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // §13 v0.43: a bunt that moved a runner is the one play where the
        // record is genuinely incomplete without the scorer — nothing
        // physical separates giving herself up from bunting for a hit.
        if (draft.invitesSacrifice)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilterChip(
              key: sacrificeChipKey,
              label: const Text('Sacrifice bunt'),
              selected: draft.sacrifice,
              onSelected: (value) => controller.setSacrifice(sacrifice: value),
            ),
          ),
        if (draft.landing != null && _nearFence(draft.landing!))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilterChip(
              key: offWallChipKey,
              label: const Text('Off the wall'),
              selected: draft.offWall,
              onSelected: (value) => controller.setOffWall(offWall: value),
            ),
          ),
      ],
    );
  }

  /// Outs standing right now: what the fold shows, plus what this play has
  /// already recorded. At three the half is over (§4.4), and a surface that
  /// kept taking outs would fold a fourth — so the OUT half of every pill
  /// goes away. The appeal falls out of the same rule: with two away, the
  /// catch *is* the third out, so there is nothing left to appeal.
  bool get _canRecordOut {
    final folded = ref.read(gameControllerProvider).valueOrNull?.outs ?? 0;
    return folded + _draft.entries.whereType<OutEntry>().length < 3;
  }

  /// Who has the ball, said out loud. The assumption that the catcher holds
  /// it is correct almost every time and costs nothing — but it was silently
  /// wrong on a wild pitch, minting a touch for a catcher who never had the
  /// ball, so it says itself and names the way out. Once anything has
  /// happened the hint drops and the line is just the fact.
  String get _possessionLabel {
    final holder = _draft.holderPosition;
    if (holder == null) return 'Ball is loose — tap the fielder who gets it';
    if (holder == 2 && _draft.entries.isEmpty) {
      return "Catcher has the ball — tap her if she doesn't";
    }
    return '${positionAbbreviations[holder] ?? holder} has the ball';
  }

  PlayDraft get _draft => widget.draft;

  BaseState get _foldBases =>
      ref.watch(gameControllerProvider).valueOrNull?.bases ?? BaseState.empty;

  /// Everyone the canvas shows as draggable: the batter-runner, then the
  /// fold's base runners — each at their draft position, and gone from the
  /// canvas once retired (their out lives on the chain strip).
  List<RunnerToken> _tokens(PlayDraft? draft, BaseState bases) {
    // Between pitches there is no batter-runner and nobody is in motion:
    // everyone stands on the base the fold put them on.
    if (draft == null) {
      return [
        for (final (origin, runnerId) in [
          (1, bases.first),
          (2, bases.second),
          (3, bases.third),
        ])
          if (runnerId != null)
            RunnerToken(runnerId: runnerId, label: '$origin', base: origin),
      ];
    }
    return [
      if (!draft.isOut(draft.batterId))
        RunnerToken(
          runnerId: draft.batterId,
          label: 'B',
          base: draft.displayBase(draft.batterId, 0),
          origin: 0,
          inMotion: draft.isProvisional(draft.batterId),
        ),
      for (final (origin, runnerId) in [
        (1, bases.first),
        (2, bases.second),
        (3, bases.third),
      ])
        if (runnerId != null && !draft.isOut(runnerId))
          RunnerToken(
            runnerId: runnerId,
            label: '$origin',
            base: draft.displayBase(runnerId, origin),
            origin: origin,
            inMotion: draft.isProvisional(runnerId),
          ),
    ];
  }

  Map<String, String> _runnerLabels(PlayDraft draft, BaseState bases) => {
    draft.batterId: 'B',
    if (bases.first != null) bases.first!: '1',
    if (bases.second != null) bases.second!: '2',
    if (bases.third != null) bases.third!: '3',
  };

  /// The base the play found this runner on — force logic and cascade
  /// origins read this, never a mid-play draft position.
  int _originBase(String runnerId, BaseState bases) {
    if (runnerId == _draft.batterId) return 0;
    if (runnerId == bases.first) return 1;
    if (runnerId == bases.second) return 2;
    return 3;
  }

  void _onDown(
    Offset position,
    FieldGeometry geometry,
    List<RunnerToken> tokens,
  ) {
    // Nothing enters before the trajectory (§15.1 v0.43): a touch on the
    // canvas just brings the question back, front and center.
    if (_draft.battedBall && _draft.trajectory == null) {
      _showTrajectoryDialog();
      return;
    }

    // A pending force play consumes taps on its pills before anything else.
    final pending = _pendingForcePlay;
    if (pending != null) {
      final controller = ref.read(playDraftProvider.notifier);
      final pill = geometry.pillAt(pending.base, position);
      if (_canRecordOut && pill == BaseCall.out) {
        controller.addOut(
          pending.runnerId,
          atBase: pending.base,
          how: _inferredHow(pending.runnerId, pending.base, _foldBases),
        );
        setState(() => _pendingForcePlay = null);
        return;
      }
      final baseCenter = pending.base == 4
          ? geometry.plate
          : geometry.baseCenter(pending.base);
      if (pill == BaseCall.safe ||
          (position - baseCenter).distance <= _snapRadiusPx) {
        // Safe: she stays where the walk-up put her, but it is an answer
        // now rather than a presumption — so she stops running and stands
        // on the bag.
        controller.affirmSafe(pending.runnerId);
        setState(() => _pendingForcePlay = null);
        return;
      }
      // Anything else proceeds normally; the question stays up.
    }

    // Nearest target wins between runner tokens and fielders — at first
    // base the batter token and the first baseman stand ~11 ft apart, and
    // category priority there sent throws to the wrong interpreter.
    RunnerToken? bestToken;
    var bestTokenDistance = _snapRadiusPx;
    for (final token in tokens) {
      final d = (position - _tokenCenter(geometry, token)).distance;
      if (d <= bestTokenDistance) {
        bestTokenDistance = d;
        bestToken = token;
      }
    }
    int? bestFielder;
    var bestFielderDistance = _snapRadiusPx;
    final spots = standardFielderSpots(geometry.profile);
    for (final entry in spots.entries) {
      // Grab her where she now stands, in either state of the screen.
      final spot =
          _draft.movedFielders[entry.key] ?? entry.value;
      final d = (position - geometry.toPx(spot)).distance;
      if (d <= bestFielderDistance) {
        bestFielderDistance = d;
        bestFielder = entry.key;
      }
    }
    if (bestToken != null &&
        (bestFielder == null || bestTokenDistance <= bestFielderDistance)) {
      setState(() {
        _drag = _ActiveDrag(start: position, runnerId: bestToken!.runnerId);
      });
      return;
    }
    if (bestFielder != null) {
      setState(() {
        _drag = _ActiveDrag(start: position, fielderPosition: bestFielder);
      });
      return;
    }
    setState(() => _drag = _ActiveDrag(start: position));
  }

  int? _fielderAt(Offset position, FieldGeometry geometry) {
    final spots = standardFielderSpots(geometry.profile);
    for (final entry in spots.entries) {
      final spot = _draft.movedFielders[entry.key] ?? entry.value;
      if ((position - geometry.toPx(spot)).distance <= _snapRadiusPx) {
        return entry.key;
      }
    }
    return null;
  }

  void _onUp(
    FieldGeometry geometry,
    PlayDraftController controller,
    List<RunnerToken> tokens,
  ) {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = null);
    final moved = (drag.current - drag.start).distance > kTouchSlop;

    if (drag.isPath) {
      // The drawn path, two taps (§15.1 v0.43): first tap = first bounce,
      // second tap = where it ended up; later taps adjust the streak's end
      // — until anything hangs off the path, which freezes it. From there
      // the ↺ reset is the only way to redraw.
      if (_draft.pathLocked) return;
      final point = geometry.toField(drag.start);
      final beyondFence =
          FieldGeometry.isFair(point) && geometry.fenceDepthFt(point) < 0;
      final landing = _draft.landing;
      if (landing == null) {
        controller.setLanding(point);
        // §16.3's ball-flight sanity: the canvas knows where the fence is
        // on this field today. It *landed* out there — home run?
        if (beyondFence) _showHomeRunDialog();
      } else {
        controller.setRetrieved(point);
        // It landed in the park and ended up over the fence: the bounced-
        // over ball, which is a ground-rule double.
        if (beyondFence && geometry.fenceDepthFt(landing) >= 0) {
          _showGroundRuleDialog();
        }
      }
      return;
    }

    if (drag.fielderPosition != null) {
      final position = drag.fielderPosition!;
      // Seed included: between pitches the catcher holds it without a
      // touch to prove it (§15.6), and a tap on the holder says she never
      // had it — the pitch got past her.
      final holder = _draft.holderPosition;
      final spot = moved
          ? geometry.toField(drag.current)
          : _currentFielderSpot(position, geometry);
      if (position == holder && !moved) {
        unawaited(controller.setHeldBy(null));
        return;
      }
      // A loose ball falls through to the what-happened popup in BOTH
      // states — she is making a play on it, and "picked it up" versus
      // "booted it" is worth asking behind the plate too.
      // The ball is held and this is a different fielder: a THROW — one
      // tap sends it to her where she stands; a drag places the reception.
      // A throw arriving at a base with a runner heading there raises the
      // SAFE/OUT pair at the bag (§15.1 v0.43): the force play is the
      // question, asked where it happened.
      if (holder != null && position != holder) {
        final forcePlay = _canRecordOut ? _forcePlayFor(spot, geometry) : null;
        controller.receiveThrow(position, spot: spot, moved: moved);
        if (forcePlay != null) {
          setState(() => _pendingForcePlay = forcePlay);
        }
        return;
      }
      if (moved) {
        // The holder dragged onto another fielder also reads as a throw —
        // the aiming gesture from before tap-to-throw existed.
        if (position == holder) {
          final receiver = _fielderAt(drag.current, geometry);
          if (receiver != null && receiver != holder) {
            controller.receiveThrow(
              receiver,
              spot: _currentFielderSpot(receiver, geometry),
            );
            return;
          }
        }
        // Re-dragging a fielder who already played the ball adjusts her
        // play — one play, moved, never a second touch.
        if (_draft.latestTouchBy(position) != null) {
          controller.adjustFielderPlay(position, spot: spot);
          return;
        }
      }
      // Loose or untouched ball: she made a play on it — where she was
      // dropped (or stands, for a tap) is where it happened; the popup
      // says what happened there.
      _showFielderPlaySheet(position, spot);
      return;
    }

    // Runner drag: resolves against the approached base's SAFE/OUT pair
    // (§15.1 v0.43) — the base itself reads as safe. Either way the popup
    // classifies what happened; how this flows is load-bearing. A tap with
    // no movement resolves nothing: the boxes only mean something once a
    // runner has actually been moved.
    if (!moved) return;
    final runnerId = drag.runnerId!;
    final base = geometry.nearestBaseWithin(
      drag.current,
      FieldPainter.approachRadiusPx,
    );
    if (base == null) return;
    // Dropped on the base she is already standing on: that is not a move,
    // it is "safe right there". Settling her says so without minting a
    // from==to leg, which §4.3 reserves for surviving a rundown.
    final standingOn = tokens.firstWhere((t) => t.runnerId == runnerId).base;
    final pill = geometry.pillAt(base, drag.current);
    if (base == standingOn && pill != BaseCall.out) {
      controller.affirmSafe(runnerId);
      return;
    }
    if (pill == BaseCall.out) {
      // No OUT pill is drawn once the half is over, so a release there
      // means nothing: she springs back.
      if (_canRecordOut) _showOutDialog(runnerId, base);
      return;
    }
    final baseCenter = base == 4 ? geometry.plate : geometry.baseCenter(base);
    final onBase = (drag.current - baseCenter).distance;
    if (pill == BaseCall.safe || onBase <= _snapRadiusPx) {
      final slots = [
        for (final token in tokens)
          (runnerId: token.runnerId, base: token.base),
      ];
      _showSafeDialog(
        base,
        isBatter: runnerId == _draft.batterId,
        moves: cascadeRunnerMove(slots, movedId: runnerId, to: base),
      );
    }
  }

  static const _baseLabels = {1: '1B', 2: '2B', 3: '3B', 4: 'home'};
  static const _hitLabels = {
    1: 'Single',
    2: 'Double',
    3: 'Triple',
    4: 'Home run',
  };

  /// The SAFE classification (§15.1 v0.43): what got the runner there.
  /// Safe-only vocabulary — obstruction lives here and never on OUT.
  void _showSafeDialog(
    int base, {
    required bool isBatter,
    required List<CascadedMove> moves,
  }) {
    final controller = ref.read(playDraftProvider.notifier);
    final draft = _draft;
    final caught = draft.caughtInFlight;
    // What could actually have moved her, and nothing else. A caught ball
    // was not hit anywhere she could run on, so the honest answer is that
    // she tagged; there is no fielder's choice once the batter is out in
    // the air; and "on the throw" is only true if somebody threw.
    // Obstruction is not here at all — it lives on the chain node, found
    // when looked for rather than offered on every play.
    // §15.6's vocabulary between pitches — disjoint from a play's, because
    // nothing is stolen on a batted ball and nothing comes "on the hit"
    // when there was no hit. "On an error" is in both: it is how a runner
    // is safe on a missed tag.
    final choices = !draft.battedBall
        ? <(String, String, SafeResolution)>[
            ('stolen_base', 'Stolen base', SafeResolution.stolenBase),
            ('wild_pitch', 'Wild pitch', SafeResolution.wildPitch),
            ('passed_ball', 'Passed ball', SafeResolution.passedBall),
            (
              'defensive_indifference',
              'Defensive indifference',
              SafeResolution.defensiveIndifference,
            ),
            if (draft.latestMisplayTouchKey != null)
              ('error', 'On an error', SafeResolution.onError),
          ]
        : <(String, String, SafeResolution)>[
      (
        'hit',
        isBatter ? _hitLabels[base]! : (caught ? 'Tagged up' : 'On the hit'),
        SafeResolution.onTheHit,
      ),
      if (draft.hasThrow) ('throw', 'On the throw', SafeResolution.onTheThrow),
      // Only offered when there is a misplay to point at: an advance that
      // claims an error but links to nothing derives as a hit (§13.2), so
      // the answer must not exist without its cause.
      if (draft.latestMisplayTouchKey != null)
        ('error', 'On an error', SafeResolution.onError),
      if (!caught) ('fc', "Fielder's choice", SafeResolution.fieldersChoice),
          ];

    // One possible answer is not a question: tagging up on a routine fly
    // costs the gesture that moved her and nothing more.
    if (choices.length == 1) {
      controller.resolveSafe(moves, choices.single.$3);
      return;
    }
    _centeredDialog('Safe at ${_baseLabels[base]} — how?', [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final (id, label, resolution) in choices)
            ActionChip(
              key: safeChipKey(id),
              label: Text(label),
              onPressed: () {
                controller.resolveSafe(moves, resolution);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    ]);
  }

  /// The OUT confirmation (§15.1 v0.43): the inferred `how` leads, the
  /// alternatives follow, and interference — the out-flavored ⚖ — closes
  /// the list. Obstruction never appears here.
  void _showOutDialog(String runnerId, int base) {
    final controller = ref.read(playDraftProvider.notifier);
    final hows = _possibleHows(runnerId, base, _foldBases);
    final inferred = hows.first.$3;
    _centeredDialog('Out at ${_baseLabels[base]} — how?', [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final (id, label, how) in hows)
            ChoiceChip(
              key: outChipKey(id),
              label: Text(label),
              selected: how == inferred,
              onSelected: (_) {
                controller.addOut(runnerId, atBase: base, how: how);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    ]);
  }

  /// A throw arriving at [spot]: which base is it covering, and is a
  /// runner provisionally headed there? Only unresolved walk-up movement
  /// asks — a runner the scorer already classified safe is settled.
  ({String runnerId, int base})? _forcePlayFor(
    FieldCoord spot,
    FieldGeometry geometry,
  ) {
    const coverRadiusFt = 15.0;
    final draft = _draft;
    for (final base in const [1, 2, 3, 4]) {
      final center = geometry.baseCoord(base);
      final dx = spot.x - center.x;
      final dy = spot.y - center.y;
      if (dx * dx + dy * dy > coverRadiusFt * coverRadiusFt) continue;
      for (final entry in draft.entries.reversed) {
        if (entry is LegEntry &&
            entry.to == base &&
            entry.key < draft.openingLegCount &&
            !draft.isOut(entry.runnerId) &&
            draft.displayBase(entry.runnerId, entry.from) == base) {
          return (runnerId: entry.runnerId, base: base);
        }
      }
    }
    return null;
  }

  /// Where a token actually renders — the painter and this hit test must
  /// agree, so both read it from the geometry.
  Offset _tokenCenter(FieldGeometry geometry, RunnerToken token) =>
      geometry.runnerTokenCenter(
        base: token.base,
        origin: token.origin,
        inMotion: token.inMotion,
      );

  FieldCoord _currentFielderSpot(int position, FieldGeometry geometry) =>
      _draft.movedFielders[position] ??
      standardFielderSpots(geometry.profile)[position]!;

  /// Every popup on this surface: a centered dialog, only as big as its
  /// content — front and center, never a bottom drawer. See
  /// [showFieldDialog] for the sizing all of them share.
  void _centeredDialog(String title, List<Widget> children) {
    showFieldDialog<void>(context, title: title, children: (_) => children);
  }

  /// §15.1 v0.43: the batted-ball type, the surface's first question.
  void _showTrajectoryDialog() {
    final controller = ref.read(playDraftProvider.notifier);
    _centeredDialog('How did it come off the bat?', [
      TrajectoryRow(
        selected: _draft.trajectory,
        onChosen: (trajectory) {
          controller.setTrajectory(trajectory);
          Navigator.pop(context);
        },
      ),
    ]);
  }

  /// §16.3: it landed beyond the fence. One question, two answers — No
  /// simply proceeds as a normal play, landing and all.
  void _showHomeRunDialog() {
    final controller = ref.read(playDraftProvider.notifier);
    _yesNoDialog('Home run?', onYes: controller.resolveHomeRun);
  }

  /// §16.3's sibling: it landed in the park and ended up over the fence —
  /// the bounced-over ball, two bases apiece.
  void _showGroundRuleDialog() {
    final controller = ref.read(playDraftProvider.notifier);
    _yesNoDialog(
      'Ground rule double?',
      onYes: controller.resolveGroundRuleDouble,
    );
  }

  void _yesNoDialog(String question, {required VoidCallback onYes}) {
    _centeredDialog(question, [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            key: beyondFenceKey('yes'),
            onPressed: () {
              onYes();
              Navigator.pop(context);
            },
            child: const Text('Yes'),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            key: beyondFenceKey('no'),
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
        ],
      ),
    ]);
  }

  /// §15.1 v0.43's what-happened popup, options driven by the trajectory:
  /// in the air she caught it, dropped it, flat-out missed it, or came over
  /// and picked it up; on the ground she fielded it, booted it, or missed
  /// it. "Missed it" records no touch at all — she never touched the ball,
  /// so there is officially nothing to record (§13) beyond where it went.
  void _showFielderPlaySheet(int position, FieldCoord spot) {
    final airborne =
        _draft.trajectory == Trajectory.FLY ||
        _draft.trajectory == Trajectory.POPUP ||
        _draft.trajectory == Trajectory.LINE;
    // A ball can only be caught while it is still in the air, and it is in
    // the air until somebody touches it — except for a deflection, the one
    // touch that leaves it up. After any other touch it is a ball on the
    // ground, whatever it was off the bat, so the fielder who comes over is
    // fielding it rather than catching it.
    final touches = _draft.entries.whereType<TouchEntry>();
    final inFlight =
        touches.isEmpty || touches.last.touchType == TouchType.DEFLECTED;
    final choices = <(String, String, TouchType?)>[
      if (airborne && inFlight) ...[
        ('caught', 'Caught', TouchType.CAUGHT),
        ('dropped', 'Dropped', TouchType.DROPPED),
        // Only a liner caroms. A pop-up one fielder touches and another
        // catches is two fielders on one ball, not a deflection.
        if (_draft.trajectory == Trajectory.LINE)
          ('deflected', 'Deflected', TouchType.DEFLECTED),
        ('missed', 'Missed it', null),
        ('picked_up', 'Picked it up', TouchType.FIELDED),
      ] else ...[
        ('fielded', 'Fielded', TouchType.FIELDED),
        ('booted', 'Booted', TouchType.BOOTED),
        // It hit her and caromed away with no play to be made: a physical
        // fact, never an error candidate (§13.2), and the ball stays loose.
        ('deflected', 'Deflected', TouchType.DEFLECTED),
        ('missed', 'Missed it', null),
      ],
    ];
    final controller = ref.read(playDraftProvider.notifier);
    _centeredDialog(
      'What happened at ${positionAbbreviations[position] ?? position}?',
      [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final (id, label, touchType) in choices)
              ActionChip(
                key: fielderPlayKey(id),
                label: Text(label),
                onPressed: () {
                  controller.recordFielderPlay(
                    position,
                    spot: spot,
                    touchType: touchType,
                  );
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ],
    );
  }

  /// The `how` values physically possible for this runner at this base
  /// (§4.3), likeliest first — the OUT dialog offers exactly these, so it
  /// can never propose an out that couldn't have happened.
  ///
  /// - A **force** needs the runner headed for the very next base *and* the
  ///   chain of occupied bases behind her (origin bases — where the play
  ///   found everyone, with the batter always running on `in_play`). A
  ///   runner from second with first empty is forced nowhere: thrown out at
  ///   home, she was tagged.
  /// - A **catch removes every force** — the batter is out in the air, so
  ///   nobody is compelled to advance and the runners owe a retouch
  ///   instead.
  /// - A **fly out** is the batter's alone; the **appeal** is a runner's
  ///   alone, and only against a catch.
  List<(String, String, How)> _possibleHows(
    String runnerId,
    int atBase,
    BaseState bases,
  ) {
    final origin = _originBase(runnerId, bases);
    final caught = _draft.caughtInFlight;
    final isBatter = origin == 0;
    final forced =
        !caught && atBase == origin + 1 && _forceChainLive(origin, bases);
    // §15.6: between pitches she was running on her own, so the play's
    // vocabulary does not apply — no force without a batter, no fly out
    // without a batted ball.
    if (!_draft.battedBall) {
      return [
        ('caught_stealing', 'Caught stealing', How.CAUGHT_STEALING),
        ('picked_off', 'Picked off', How.PICKED_OFF),
        ('tag', 'Tag', How.TAG),
      ];
    }
    return [
      if (caught && isBatter) ('fly_out', 'Fly out', How.FLY_OUT),
      if (forced) ('force', 'Force', How.FORCE),
      ('tag', 'Tag', How.TAG),
      if (caught && !isBatter) ('appeal', "Didn't tag up", How.APPEAL),
    ];
  }

  /// §15.1's `how` inference — the likeliest possible out, by construction
  /// the same list the dialog shows.
  How _inferredHow(String runnerId, int atBase, BaseState bases) =>
      _possibleHows(runnerId, atBase, bases).first.$3;

  bool _forceChainLive(int origin, BaseState bases) {
    for (var base = origin - 1; base >= 1; base--) {
      final occupied = switch (base) {
        1 => bases.first != null,
        2 => bases.second != null,
        _ => bases.third != null,
      };
      if (!occupied) return false;
    }
    return true; // batter's box always pushes: in_play means she's running
  }

  bool _nearFence(FieldCoord landing) {
    final geometry = FieldGeometry(
      profile: FieldProfile.fastpitch12U,
      size: const Size(100, 100),
    );
    return geometry.fenceDepthFt(landing).abs() <= _offWallToleranceFt;
  }

  String _statusLabel(PlayDraft draft) {
    final drag = _drag;
    final landing = draft.landing;

    // Mid-gesture: live number under the finger (§16.3).
    if (drag != null && drag.isPath) {
      final geometry = _labelGeometry();
      final at = FieldGeometry.distanceFt(geometry.toField(drag.current));
      return '${at.round()} ft';
    }

    if (draft.trajectory == null) return 'New play';
    if (landing == null) {
      return 'Tap the ball path — or drag the fielder who played it';
    }
    final at = FieldGeometry.distanceFt(landing);
    final retrieved = draft.retrieved;
    if (retrieved == null) return '${at.round()} ft';
    final rolled = FieldGeometry.distanceFt(retrieved).round();
    return '${at.round()} ft → $rolled ft';
  }

  FieldGeometry _labelGeometry() {
    // The label re-derives world coordinates from the gesture's screen
    // points, so it needs the same geometry the canvas used. Rebuilt from
    // the current render box size — cheap, and never stale.
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size ?? const Size(100, 100);
    return FieldGeometry(profile: FieldProfile.fastpitch12U, size: size);
  }
}
