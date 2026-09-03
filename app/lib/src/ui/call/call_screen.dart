import 'package:diamond/src/call/team_config.dart';
import 'package:diamond/src/call/wristband_card.dart';
import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/call/pending_call.dart';
import 'package:diamond/src/ui/theme/brand_metrics.dart';
import 'package:diamond/src/ui/theme/brand_type.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys the widget tests resolve against. Production code has no reason to look
/// them up.
@visibleForTesting
const Key callScreenCodeKey = Key('callScreenCode');
@visibleForTesting
const Key callScreenTypeRowKey = Key('callScreenTypeRow');
@visibleForTesting
const Key callScreenPitchThrownKey = Key('callScreenPitchThrown');

/// Height reserved for the code, whether or not one is showing.
///
/// §10.3 wants it at 120pt+; `height: 1` on the style makes the line box that
/// tall exactly, so the constant and the font size move together.
// Deliberately not a slot on the type scale (§23.5). The code is the one
// thing the pitcher reads from across the circle, and 120 is a purpose-built
// size for that job rather than a step in a ladder — the scale tops out at 44,
// which is a headline, not a signal. `_codeSlotHeight` derives from it, so it
// is load-bearing for layout too.
const double _codeFontSize = 120;
const double _codeSlotHeight = _codeFontSize;

/// Height of the pitch-type row, fixed rather than sized to its text.
///
/// The canvas begins directly below this strip, so anything that lets the
/// strip's height float — a font whose line height differs by a pixel, a
/// longer pitch name, a larger text scale — moves the whole canvas and every
/// landmark on it. Pinning it keeps the drawing area in one place no matter
/// what the chips contain.
const double _typeRowHeight = 66;

/// The call screen (§10.3): tap a pitch type, tap a zone, yell the code.
///
/// The call grid is drawn *on* the canvas (§11.4, v0.38); the code and the
/// pitch chips sit in a strip above it, outside the drawing area, so they never
/// cover the top call zones or compete with a location tap.
///
/// Three states, and the pointer rule differs between them:
///
/// 1. **No type chosen** — the whole arsenal is on screen and takes taps. Zone
///    taps do nothing, because type precedes zone (§10.1).
/// 2. **Type chosen** — the others go away so the coach can see what they
///    picked, and the surviving chip stops taking taps. It is a *label* now,
///    and §11.4's rule for the batter silhouette applies: anything that
///    swallows taps makes the region it covers uncapturable.
/// 3. **Zone chosen** — the code appears above the chip, also pass-through. The
///    grid stays live underneath, because tapping a new zone replaces the
///    pending call (§10.3's shake-off reality).
///
/// Which zones may be tapped depends on `TeamCallConfig.usesWristbands`: the
/// card bounds it when they are on, the layout when they are off, and with them
/// off there is no code to show.
///
/// Cancel lives in the canvas's control strip, *below* the drawing area, where
/// it structurally cannot compete with a location tap.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    this.batterSide = BatterSide.R,
    this.fidelity = CanvasFidelity.restrained,
    this.showBatterSilhouette = false,
    this.onSkipCall,
    this.onPitchThrown,
    super.key,
  });

  /// Which box the batter stands in. Moves the *labels* on the grid, never the
  /// geometry — "In" is negative x for a righty (§10.1, §11.4).
  final BatterSide batterSide;

  /// Passed through to the canvas so the dev harness can flip treatments on a
  /// real tablet (§11.4).
  final CanvasFidelity fidelity;

  final bool showBatterSilhouette;

  /// §11.2's per-pitch Scorer mode: this pitch gets no recorded intent. Wired
  /// to the control strip's skip affordance, relabeled "Skip call" here —
  /// skipping on this screen skips the whole call, not just a location. Null
  /// (the DIA-006 harness and tests) leaves the affordance inert.
  final VoidCallback? onSkipCall;

  /// §10.3's pitch-happened checkmark (v0.40): confirms the pending call was
  /// used and advances the loop to actual-location entry. Rendered beside the
  /// code — or alone in the code's slot when the team calls verbally and has
  /// no code (§10.2) — and only once a pending call exists: a half-made call
  /// has nothing to confirm. Null hides the checkmark entirely.
  final VoidCallback? onPitchThrown;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(teamCallConfigProvider);
    final card = ref.watch(wristbandCardProvider);
    final draft = ref.watch(callDraftProvider);
    final pending = draft.pending;
    final typeId = draft.pitchTypeId;

    // With wristbands on, the *card* decides what may be offered — a code the
    // coach yells has to be a code the pitcher can look up (§10.1). With them
    // off there is no card to consult, so the layout decides and no code is
    // shown.
    final callableIds = typeId == null
        ? <String>{}
        : {
            for (final zone in config.callableZones(typeId))
              if (!config.usesWristbands ||
                  card.canExpress(Call(pitchTypeId: typeId, zoneId: zone.id)))
                zone.id,
          };

    return ZoneCanvas(
      mode: ZoneCanvasIntent.call,
      value: null,
      batterSide: widget.batterSide,
      fidelity: widget.fidelity,
      showBatterSilhouette: widget.showBatterSilhouette,
      // Always set, so the grid is on screen from the first frame and the
      // freeform marker layer stays suppressed. What gates state 1 is
      // [onZoneSelected] being null — the grid is visible but inert until a
      // pitch is chosen, rather than absent and then appearing.
      callLayout: config.layout,
      // Empty until a pitch is chosen, so nothing reads as available while
      // taps are still inert — green is a promise that a zone can be touched.
      callableZoneIds: callableIds,
      selectedZoneId: pending?.zoneId,
      onZoneSelected: typeId == null
          ? null
          : (zone) => ref.read(callDraftProvider.notifier).selectZone(zone.id),
      onReroll: pending == null
          ? null
          : () => ref.read(callDraftProvider.notifier).reroll(),
      topStrip: _CallOverlay(
        arsenal: config.arsenal,
        selectedTypeId: typeId,
        onTypeSelected: (id) =>
            ref.read(callDraftProvider.notifier).selectType(id),
        pending: pending,
        // §10.2: the code exists only when a card does. The checkmark keys
        // off the pending call instead, so verbal-calling teams still get it.
        showCode: config.usesWristbands,
        onPitchThrown: widget.onPitchThrown,
      ),
      // Freeform capture is unreachable in grid-calling mode, so onCommit
      // never fires here.
      onCommit: (_) {},
      skipLabel: 'Skip call',
      onSkip: widget.onSkipCall ?? () {},
      onCancel: () => ref.read(callDraftProvider.notifier).clear(),
    );
  }
}

class _CallOverlay extends StatelessWidget {
  const _CallOverlay({
    required this.arsenal,
    required this.selectedTypeId,
    required this.onTypeSelected,
    required this.pending,
    required this.showCode,
    required this.onPitchThrown,
  });

  final List<PitchType> arsenal;
  final String? selectedTypeId;
  final ValueChanged<String> onTypeSelected;

  /// Null until a zone is chosen. Everything in the code slot keys off this:
  /// the code (when [showCode]) and the checkmark both exist only for a
  /// completed call.
  final PendingCall? pending;

  /// Whether the code is displayed (§10.2, wristbands on). Verbal-calling
  /// teams have a pending call — and a checkmark — but no code to read out.
  final bool showCode;

  final VoidCallback? onPitchThrown;

  @override
  Widget build(BuildContext context) {
    // Code above the pitch, both at the top: the code is what the coach says
    // out loud, so it leads. Nothing spells the call out in words — the chip
    // names the pitch and the accent marks the zone, so a third statement of
    // the same fact is ink without information (§23.1.1).
    return Align(
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The slot is always this tall, empty or not. If it grew when the
          // code appeared, the canvas below would shrink and every landmark on
          // it — the plate above all — would jump at the exact moment the coach
          // is reading a number off the screen.
          SizedBox(
            height: _codeSlotHeight,
            child: pending == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showCode) _CodeDisplay(pending: pending!),
                      // The pitch-happened checkmark (§10.3, v0.40). A real
                      // control, unlike everything else up here — allowed
                      // because the strip is outside the drawing area, so it
                      // can never shadow a zone tap (§11.4).
                      if (onPitchThrown != null)
                        Padding(
                          padding: EdgeInsets.only(left: showCode ? 20 : 0),
                          child: FilledButton(
                            key: callScreenPitchThrownKey,
                            onPressed: onPitchThrown,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(76, 76),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Icon(Icons.check, size: 46),
                          ),
                        ),
                    ],
                  ),
          ),
          _PitchTypeRow(
            arsenal: arsenal,
            selectedTypeId: selectedTypeId,
            onTypeSelected: onTypeSelected,
          ),
        ],
      ),
    );
  }
}

/// The arsenal, above the zone rect. No per-type color (§10.3, v0.38) — the
/// accent marks the *selected* type and nothing else (§23.1.2, §23.1.3).
///
/// Collapses to the chosen chip once a type is picked, and that chip stops
/// taking taps so the chase-high zones under it stay callable.
class _PitchTypeRow extends StatelessWidget {
  const _PitchTypeRow({
    required this.arsenal,
    required this.selectedTypeId,
    required this.onTypeSelected,
  });

  final List<PitchType> arsenal;
  final String? selectedTypeId;
  final ValueChanged<String> onTypeSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = selectedTypeId;
    final shown = selected == null
        ? arsenal
        : arsenal.where((type) => type.id == selected).toList();

    final row = Container(
      key: callScreenTypeRowKey,
      height: _typeRowHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in shown)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: selected == null ? () => onTypeSelected(type.id) : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: type.id == selected
                        ? scheme.primary
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: BrandMetrics.spaceMd,
                    ),
                    child: Text(
                      type.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: type.id == selected
                                ? scheme.onPrimary
                                : scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // A choice takes taps; a label must not (§11.4). Cancel — in the control
    // strip below the canvas — is how the coach gets the arsenal back.
    return selected == null ? row : IgnorePointer(child: row);
  }
}

/// The code, huge (§10.3): readable at arm's length in sunlight, with the call
/// echoed small underneath.
///
/// Pass-through, like every other label on this surface. Re-roll is a
/// horizontal drag anywhere on the canvas rather than a swipe on the code
/// itself, precisely so the grid underneath stays tappable.
class _CodeDisplay extends StatelessWidget {
  const _CodeDisplay({required this.pending});

  final PendingCall pending;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        pending.code ?? '—',
        key: callScreenCodeKey,
        // A wristband code is the type specimen for the mono rule (§23.5):
        // three digits looked up on a band, read one at a time, never read as
        // a word.
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: _codeFontSize,
          fontWeight: FontWeight.bold,
          height: 1,
        ).code,
      ),
    );
  }
}
