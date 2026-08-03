import 'package:diamond/src/ui/call/call_screen.dart';
import 'package:diamond/src/ui/loop/count_hud.dart';
import 'package:diamond/src/ui/loop/outcome_step.dart';
import 'package:diamond/src/ui/loop/pitch_flow.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const CountHud(),
            Expanded(
              child: switch (flow.step) {
                // The pitch-happened checkmark lives beside the code, inside
                // the call screen's own top strip (§10.3, v0.40) — no page
                // chrome of this page's own.
                PitchStep.call => CallScreen(
                  batterSide: batterSide,
                  onSkipCall: controller.skipCall,
                  onPitchThrown: controller.pitchThrown,
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
                PitchStep.outcome => OutcomeStep(
                  suggestion: suggestOutcome(
                    actual: flow.actual,
                    bounce: flow.bounce,
                  ),
                  onChosen: controller.commitOutcome,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
