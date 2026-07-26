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
      appBar: AppBar(
        title: const Text('ZoneCanvas demo — DIA-005'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SegmentedButton<BallKind>(
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
            ),
          ),
        ],
      ),
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: switch (_step) {
                _Step.call => ZoneCanvas(
                  mode: ZoneCanvasIntent.call,
                  value: _intendedLocation,
                  ballKind: _ballKind,
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
