import 'package:diamond/src/game/game_controller.dart';
import 'package:diamond/src/play/play_draft_controller.dart';
import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
import 'package:diamond/src/ui/field_canvas/field_entry_surface.dart';
import 'package:diamond/src/ui/loop/bailout_step.dart';
import 'package:diamond/src/ui/loop/count_hud.dart';
import 'package:diamond/src/ui/loop/outcome_step.dart';
import 'package:diamond/src/ui/loop/pitch_flow.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys the widget tests resolve against. Production code has no reason to
/// look them up.
@visibleForTesting
const Key recordLastPitchKey = Key('recordLastPitch');
@visibleForTesting
const Key dismissLastPitchKey = Key('dismissLastPitch');
@visibleForTesting
const Key openIdleFieldKey = Key('openIdleField');
@visibleForTesting
const Key d3kOutThrowKey = Key('d3kOutThrow');
@visibleForTesting
const Key d3kOutTagKey = Key('d3kOutTag');
@visibleForTesting
const Key d3kSafeWpKey = Key('d3kSafeWp');
@visibleForTesting
const Key d3kSafePbKey = Key('d3kSafePb');
@visibleForTesting
const Key d3kFieldKey = Key('d3kField');
@visibleForTesting
const Key d3kDismissKey = Key('d3kDismiss');

/// The per-pitch loop (§11.1), DIA-007a's core: count HUD on top — the
/// invariant that is never wrong stays on screen through every step — and the
/// active step's surface below it.
///
/// This is the **primary's** loop (§12.2, v0.39): in M1's combined mode its
/// one operator is the scorer, who also calls. The step seams are where M2's
/// duty split cuts, which is why each step is its own surface handed callbacks
/// by this page rather than reaching into the flow itself.
class PitchLoopPage extends ConsumerWidget {
  const PitchLoopPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(pitchFlowProvider);
    final controller = ref.read(pitchFlowProvider.notifier);
    final batterSide = ref.watch(batterSideProvider);

    // The outcome presents as a sheet over the location canvas — the same
    // popup design as the field surface's what-happened sheet, so every
    // "several options, pick one" moment reads the same. Dismissing it
    // without choosing returns to the location step; nothing commits.
    ref.listen<PitchFlowState>(pitchFlowProvider, (previous, next) {
      if (next.step == PitchStep.outcome &&
          previous?.step != PitchStep.outcome) {
        _showOutcomeSheet(context, ref, next);
      }
    });

    // An uncommitted play owns the screen (§15.5), however it got here —
    // the pitch flow on `in_play`, or the crash journal on relaunch. It sits
    // outside the two-finger detector on purpose: bailout simplifies *pitch*
    // entry, and the pitch under this play is already committed.
    final draft = ref.watch(playDraftProvider).valueOrNull;
    // §15.6 v0.42: the same screen with no ball in play. One entity — a
    // ball in play is a *state* of the draft (`battedBall`), not a
    // different surface — so there is nothing extra to check here.
    if (draft != null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const CountHud(),
              Expanded(child: FieldEntrySurface(draft: draft)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const CountHud(),
            Expanded(
              // §11.2's two-finger swipe wraps every step surface, so bailout
              // is reachable from anywhere in the pitch — a Listener, not a
              // gesture-arena participant, so it can never steal a tap, a
              // long-press, or the reroll drag from the surfaces beneath it.
              child: _TwoFingerSwipeDetector(
                onSwipe: controller.bailout,
                child: switch (flow.step) {
                  // The pitch-happened checkmark lives beside the code, inside
                  // the call screen's own top strip (§10.3, v0.40) — no page
                  // chrome of this page's own beyond the standing offer below.
                  PitchStep.call => Column(
                    children: [
                      // §11.1 v0.39: the offer to locate the pitch that just
                      // committed unlocated. It blocks nothing — the loop
                      // moving on is itself the dismissal, and starting the
                      // next call IS moving on: the first type tap removes it.
                      if (flow.lastPitchOffer != null &&
                          ref.watch(callDraftProvider).pitchTypeId == null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              key: recordLastPitchKey,
                              onPressed: controller.takeLastPitchOffer,
                              icon: const Icon(Icons.my_location),
                              label: const Text('Record last pitch'),
                            ),
                            IconButton(
                              key: dismissLastPitchKey,
                              onPressed: controller.dismissLastPitchOffer,
                              icon: const Icon(Icons.close),
                              tooltip: 'Keep unlocated',
                            ),
                          ],
                        ),
                      // §11.3's D3K resolution. The loop already recorded
                      // the strikeout, so this blocks nothing and dies by
                      // being ignored — but the everyday ending is one tap
                      // and it fixes real credit: a strikeout thrown out at
                      // first is 2-3, which the recorded out does not say.
                      if (flow.d3kOffer != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('Uncaught 3rd strike?'),
                              FilledButton(
                                key: d3kOutThrowKey,
                                onPressed: controller.d3kOutOnThrow,
                                child: const Text('Out at first'),
                              ),
                              OutlinedButton(
                                key: d3kOutTagKey,
                                onPressed: controller.d3kOutOnTag,
                                child: const Text('Out (tag)'),
                              ),
                              OutlinedButton(
                                key: d3kSafeWpKey,
                                onPressed: controller.d3kSafeWildPitch,
                                child: const Text('Safe (wild pitch)'),
                              ),
                              OutlinedButton(
                                key: d3kSafePbKey,
                                onPressed: controller.d3kSafePassedBall,
                                child: const Text('Safe (passed ball)'),
                              ),
                              OutlinedButton(
                                key: d3kFieldKey,
                                onPressed: controller.d3kToField,
                                child: const Text('Go to field'),
                              ),
                              IconButton(
                                key: d3kDismissKey,
                                onPressed: controller.dismissD3kOffer,
                                icon: const Icon(Icons.close),
                                tooltip: 'She was out on the strikeout',
                              ),
                            ],
                          ),
                        ),
                      // §15.6: the way to the field with nothing in play —
                      // a steal, a runner taking a base on a passed ball.
                      // Deliberately a plain affordance rather than a step
                      // in the flow: it interrupts nothing, and if the field
                      // ever becomes the loop's home surface this is the
                      // only line that changes.
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: TextButton.icon(
                            key: openIdleFieldKey,
                            onPressed: () async {
                              final anchors = await ref
                                  .read(gameControllerProvider.notifier)
                                  .betweenPitchAnchors();
                              final pitchId = anchors.pitchId;
                              if (pitchId == null) return;
                              await ref
                                  .read(playDraftProvider.notifier)
                                  .startBetweenPitches(pitchEventId: pitchId);
                            },
                            icon: const Icon(Icons.sports_baseball),
                            label: const Text('Go to field'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: CallScreen(
                          batterSide: batterSide,
                          onSkipCall: controller.skipCall,
                          onPitchThrown: controller.pitchThrown,
                        ),
                      ),
                    ],
                  ),
                  PitchStep.actual => ZoneCanvas(
                    mode: ZoneCanvasIntent.actual,
                    value: flow.actual,
                    bounceValue: flow.bounce,
                    batterSide: batterSide,
                    ballKind: BallKind.softball,
                    onCommit: controller.actualCommitted,
                    onCommitBounce: controller.bounceCommitted,
                    onSkip: controller.skipLocation,
                    onCancel: controller.backToCall,
                  ),
                  // The outcome sheet (shown by the listener above) floats
                  // over the location canvas the scorer just used — context
                  // behind the scrim, choices in front.
                  PitchStep.outcome => ZoneCanvas(
                    mode: ZoneCanvasIntent.actual,
                    value: flow.actual,
                    bounceValue: flow.bounce,
                    batterSide: batterSide,
                    ballKind: BallKind.softball,
                    onCommit: (_) {},
                    onSkip: () {},
                    onCancel: () {},
                  ),
                  // Location entry for the already-committed pitch (§11.1
                  // v0.39). Same canvas, same gesture; only what the release
                  // writes differs — a §6 correction rather than a new event.
                  // No bounce hinge: the offer exists only for in-play pitches.
                  PitchStep.recordLast => ZoneCanvas(
                    mode: ZoneCanvasIntent.actual,
                    value: null,
                    batterSide: batterSide,
                    ballKind: BallKind.softball,
                    onCommit: controller.recordLastLocation,
                    skipLabel: 'Keep unlocated',
                    onSkip: controller.dismissLastPitchOffer,
                    onCancel: controller.cancelRecordLast,
                  ),
                  PitchStep.bailout => BailoutStep(
                    onChosen: controller.commitOutcome,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// §11.1's outcome, as the same popup design the field surface uses for
  /// its what-happened sheet: suggestion + full override row over a scrim,
  /// with the just-placed location visible behind it. Barrier dismiss →
  /// back to the location step; the ump's call still requires a tap, so
  /// nothing here commits without one.
  Future<void> _showOutcomeSheet(
    BuildContext context,
    WidgetRef ref,
    PitchFlowState flow,
  ) async {
    final chosen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: OutcomeStep(
            suggestion: suggestOutcome(
              actual: flow.actual,
              bounce: flow.bounce,
            ),
            onChosen: (outcome) {
              Navigator.pop(dialogContext, true);
              ref.read(pitchFlowProvider.notifier).commitOutcome(outcome);
            },
          ),
        ),
      ),
    );
    if (chosen != true) {
      ref.read(pitchFlowProvider.notifier).backToActual();
    }
  }
}

/// §11.2's two-finger swipe, as a [Listener] rather than a gesture-arena
/// recognizer — deliberately: the surfaces underneath already use taps,
/// long-presses, and a horizontal drag (the reroll), and an arena participant
/// spanning all of them would compete for every one of those. A Listener only
/// watches; it can't win or lose anything.
///
/// Fires once per touch: both pointers down together, both moved downward
/// past the threshold, dominant axis vertical. Resets when the screen clears.
class _TwoFingerSwipeDetector extends StatefulWidget {
  const _TwoFingerSwipeDetector({required this.onSwipe, required this.child});

  final VoidCallback onSwipe;
  final Widget child;

  @override
  State<_TwoFingerSwipeDetector> createState() =>
      _TwoFingerSwipeDetectorState();
}

class _TwoFingerSwipeDetectorState extends State<_TwoFingerSwipeDetector> {
  static const double _threshold = 48;

  final Map<int, Offset> _start = {};
  final Map<int, Offset> _current = {};
  bool _fired = false;

  bool get _twoFingersSwipedDown {
    if (_start.length != 2) return false;
    for (final pointer in _start.keys) {
      final delta = _current[pointer]! - _start[pointer]!;
      if (delta.dy < _threshold || delta.dy.abs() < delta.dx.abs()) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _start[event.pointer] = event.position;
        _current[event.pointer] = event.position;
      },
      onPointerMove: (event) {
        _current[event.pointer] = event.position;
        if (!_fired && _twoFingersSwipedDown) {
          _fired = true;
          widget.onSwipe();
        }
      },
      onPointerUp: (event) {
        _start.remove(event.pointer);
        _current.remove(event.pointer);
        if (_start.isEmpty) _fired = false;
      },
      onPointerCancel: (event) {
        _start.remove(event.pointer);
        _current.remove(event.pointer);
        if (_start.isEmpty) _fired = false;
      },
      child: widget.child,
    );
  }
}
