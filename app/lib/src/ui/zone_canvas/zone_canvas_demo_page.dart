import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/zone_canvas/zone_canvas.dart';
import 'package:flutter/material.dart';

/// Dev-only harness for manually exercising [ZoneCanvas] outside of a real
/// game: no event store, no pitcher/batter data, just a simulated one-batter
/// call → actual loop (§11.1) so the widget can be tapped through by hand.
///
/// This page is a placeholder home screen for DIA-005 only. DELETE this file
/// and its wiring in `main.dart` once DIA-007's real pitch loop replaces it
/// as the app's home screen — see DIA-007's Cleanup note. It deliberately
/// stays minimal (e.g. no way to re-edit a committed value from the summary
/// screen) since the real UI, not this harness, is where that belongs.
class ZoneCanvasDemoPage extends StatefulWidget {
  const ZoneCanvasDemoPage({super.key});

  @override
  State<ZoneCanvasDemoPage> createState() => _ZoneCanvasDemoPageState();
}

enum _Step { call, actual, done }

class _ZoneCanvasDemoPageState extends State<ZoneCanvasDemoPage> {
  _Step _step = _Step.call;
  ZoneCoord? _intendedLocation;
  ZoneCoord? _actualLocation;
  BounceCoord? _bounceLocation;
  BallKind _ballKind = BallKind.baseball;

  /// §11.4 makes fidelity a question settled by field test in daylight rather
  /// than by argument, so the harness has to be able to flip between the two
  /// treatments on a real tablet — comparing golden PNGs on a desk is exactly
  /// the thing that section says will not settle it.
  CanvasFidelity _fidelity = CanvasFidelity.restrained;

  /// Off in production while the drawing is provisional (DIA-013), so the only
  /// way to look at the figure on device is to switch it on here.
  bool _showBatterSilhouette = false;

  /// Only the silhouette moves with this — both boxes are always drawn and `x`
  /// is absolute, so the canvas never mirrors coordinates (§3.1). With the
  /// batter switched off this control visibly does nothing, which is correct.
  BatterSide _batterSide = BatterSide.R;

  void _resetForNextPitch() {
    setState(() {
      _step = _Step.call;
      _intendedLocation = null;
      _actualLocation = null;
      _bounceLocation = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ZoneCanvas demo — DIA-005')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Simulated batter: #7 "Dummy" Batter — not wired to a real '
              'game (DIA-007 does that)',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
          // Harness controls live here rather than in the app bar, which
          // overflows once there is more than one of them at phone widths.
          // Wrap so they reflow instead of clipping.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<BallKind>(
                  segments: const [
                    ButtonSegment(
                      value: BallKind.baseball,
                      label: Text('Baseball'),
                    ),
                    ButtonSegment(
                      value: BallKind.softball,
                      label: Text('Softball'),
                    ),
                  ],
                  selected: {_ballKind},
                  onSelectionChanged: (selection) =>
                      setState(() => _ballKind = selection.first),
                ),
                SegmentedButton<CanvasFidelity>(
                  segments: const [
                    ButtonSegment(
                      value: CanvasFidelity.restrained,
                      label: Text('Restrained'),
                    ),
                    ButtonSegment(
                      value: CanvasFidelity.rich,
                      label: Text('Rich'),
                    ),
                  ],
                  selected: {_fidelity},
                  onSelectionChanged: (selection) =>
                      setState(() => _fidelity = selection.first),
                ),
                FilterChip(
                  label: const Text('Batter'),
                  selected: _showBatterSilhouette,
                  onSelected: (on) =>
                      setState(() => _showBatterSilhouette = on),
                ),
                SegmentedButton<BatterSide>(
                  segments: const [
                    ButtonSegment(value: BatterSide.R, label: Text('RHB')),
                    ButtonSegment(value: BatterSide.L, label: Text('LHB')),
                  ],
                  selected: {_batterSide},
                  onSelectionChanged: (selection) =>
                      setState(() => _batterSide = selection.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: switch (_step) {
                _Step.call => ZoneCanvas(
                  mode: ZoneCanvasIntent.call,
                  value: _intendedLocation,
                  ballKind: _ballKind,
                  fidelity: _fidelity,
                  showBatterSilhouette: _showBatterSilhouette,
                  batterSide: _batterSide,
                  onCommit: (coord) => setState(() {
                    _intendedLocation = coord;
                    _step = _Step.actual;
                  }),
                  onSkip: () => setState(() {
                    _intendedLocation = null;
                    _step = _Step.actual;
                  }),
                  onCancel: () => setState(() => _intendedLocation = null),
                ),
                _Step.actual => ZoneCanvas(
                  mode: ZoneCanvasIntent.actual,
                  value: _actualLocation,
                  bounceValue: _bounceLocation,
                  ballKind: _ballKind,
                  fidelity: _fidelity,
                  showBatterSilhouette: _showBatterSilhouette,
                  batterSide: _batterSide,
                  onCommit: (coord) => setState(() {
                    _actualLocation = coord;
                    _bounceLocation = null;
                    _step = _Step.done;
                  }),
                  // Mutually exclusive with actualLocation, as on the event
                  // (§4.1): a bounced pitch has no observed ZoneCoord, and the
                  // conventional y_ground one projections use is derived at
                  // read time rather than stored here.
                  onCommitBounce: (bounce) => setState(() {
                    _bounceLocation = bounce;
                    _actualLocation = null;
                    _step = _Step.done;
                  }),
                  onSkip: () => setState(() {
                    _actualLocation = null;
                    _step = _Step.done;
                  }),
                  // Reverses the locked-in call, per DIA-005's onCancel
                  // contract — nothing was ever committed to an event
                  // stream, so this is always safe.
                  onCancel: () => setState(() {
                    _step = _Step.call;
                    _actualLocation = null;
                  }),
                ),
                _Step.done => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Call: ${_describe(_intendedLocation)}'),
                      Text('Actual: ${_describeActual()}'),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _resetForNextPitch,
                        child: const Text('Next pitch'),
                      ),
                    ],
                  ),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }

  String _describe(ZoneCoord? coord) => coord == null
      ? 'skipped'
      : '(${coord.x.toStringAsFixed(2)}, ${coord.y.toStringAsFixed(2)})';

  /// A pitch has an airborne location or a bounce, never both (§4.1) — and a
  /// bounce may have no depth, which reads differently from having no bounce.
  String _describeActual() {
    final bounce = _bounceLocation;
    if (bounce == null) return _describe(_actualLocation);
    final depth = bounce.depth;
    final where = depth == null
        ? 'depth unknown'
        : '${depth.toStringAsFixed(2)} ft';
    return 'in the dirt at x ${bounce.x.toStringAsFixed(2)}, $where';
  }
}
