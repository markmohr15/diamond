import 'package:diamond/src/events/generated/events.dart';
import 'package:flutter/material.dart';

/// Which step of the per-pitch loop (§11.1) a [ZoneCanvas] instance
/// represents.
///
/// Presentational only: DIA-005 does not implement call-zone-grid snapping
/// (§10.1's `CallZone` grid is DIA-006/007). Both modes capture a freeform
/// [ZoneCoord] per the v0.18 dual-input allowance in §10.1.
enum ZoneCanvasIntent { call, actual }

/// Baseball vs. softball, for the drag/marker icon in
/// [ZoneCanvasIntent.actual].
///
/// Narrow placeholder standing in for the eventual `RuleSet` config
/// (CLAUDE.md: sport differences route through `RuleSet`, never scattered
/// `if (softball)` checks) — replace call sites with a real `RuleSet` field
/// once that type exists.
enum BallKind { baseball, softball }

/// Strike-zone rectangle bounds (§3.1): x ∈ [-1, 1], y ∈ [0, 1].
const double zoneMinX = -1;
const double zoneMaxX = 1;
const double zoneMinY = 0;
const double zoneMaxY = 1;

// Out-of-zone capture margin around the zone rect (tunable implementation
// constant, not spec-mandated). Symmetric for now; low ("in the dirt") and
// up/in/out waste spots are all representable within it.
const double _marginX = 0.6;
const double _marginTop = 0.6;
const double _marginBottom = 0.6;

/// The full tap-capture range, including the out-of-zone margin. A release
/// anywhere inside this extent commits; anywhere outside it cancels.
const double zoneCanvasExtentMinX = zoneMinX - _marginX;
const double zoneCanvasExtentMaxX = zoneMaxX + _marginX;
const double zoneCanvasExtentMinY = zoneMinY - _marginBottom;
const double zoneCanvasExtentMaxY = zoneMaxY + _marginTop;

const double _canvasAspectRatio =
    (zoneCanvasExtentMaxX - zoneCanvasExtentMinX) /
    (zoneCanvasExtentMaxY - zoneCanvasExtentMinY);

// Placeholder palette — no app theme exists yet (pending a dedicated theming
// ticket). One accent, per §18.7; light/dark surface pair for the margin vs.
// zone-rect contrast.
const Color _accentColor = Color(0xFF0A84FF);

const double _iconRadius = 16;
const double _dragFingerOffset = 56;

/// Maps a local point within a canvas of [size] to a [ZoneCoord], using the
/// full widget bounds → [zoneCanvasExtentMinX]..[zoneCanvasExtentMaxY] extent.
ZoneCoord zoneCoordFromLocal(Offset local, Size size) {
  final fx = local.dx / size.width;
  final fy = local.dy / size.height;
  final x =
      zoneCanvasExtentMinX + fx * (zoneCanvasExtentMaxX - zoneCanvasExtentMinX);
  // Canvas y grows downward; ZoneCoord.y grows upward (0 = bottom, 1 = top).
  final y =
      zoneCanvasExtentMaxY - fy * (zoneCanvasExtentMaxY - zoneCanvasExtentMinY);
  return ZoneCoord(x: x, y: y);
}

/// Inverse of [zoneCoordFromLocal]: maps a [ZoneCoord] to a local point within
/// a canvas of [size].
Offset localFromZoneCoord(ZoneCoord coord, Size size) {
  final fx =
      (coord.x - zoneCanvasExtentMinX) /
      (zoneCanvasExtentMaxX - zoneCanvasExtentMinX);
  final fy =
      (zoneCanvasExtentMaxY - coord.y) /
      (zoneCanvasExtentMaxY - zoneCanvasExtentMinY);
  return Offset(fx * size.width, fy * size.height);
}

bool _isInside(Offset local, Size size) =>
    local.dx >= 0 &&
    local.dx <= size.width &&
    local.dy >= 0 &&
    local.dy <= size.height;

/// Live-drawn strike-zone entry canvas (§3.1, §10.1, §11.1, §18.7).
///
/// Controlled widget: [value] is the committed coordinate (or null); all
/// mutation happens through the callbacks. The widget holds no game state of
/// its own — only the transient in-progress drag position.
///
/// Interaction: long-press inside the canvas arms a drag icon (a target
/// reticle in [ZoneCanvasIntent.call], a sport-specific ball in
/// [ZoneCanvasIntent.actual]) offset above the fingertip; dragging repositions
/// a live preview; releasing inside the canvas commits via [onCommit], and
/// releasing outside it cancels with no commit. Long-pressing again — even
/// over an existing marker — starts a fresh placement that overwrites it on
/// release, which is the "quickly undone" correction path.
class ZoneCanvas extends StatefulWidget {
  const ZoneCanvas({
    required this.mode,
    required this.value,
    required this.onCommit,
    required this.onSkip,
    required this.onCancel,
    this.ballKind = BallKind.baseball,
    this.underlay,
    super.key,
  });

  /// Whether this instance is capturing the call (`intendedLocation`) or the
  /// actual pitch location (`actualLocation`). Presentational only.
  final ZoneCanvasIntent mode;

  /// The committed coordinate, or null if none has been captured yet.
  final ZoneCoord? value;

  /// Fired once, on release, with the committed coordinate.
  final ValueChanged<ZoneCoord> onCommit;

  /// "Skip location" affordance (§11.2) — deliberately capture no location.
  final VoidCallback onSkip;

  /// Cancel/Back — available in both modes; lets the parent step (DIA-007's
  /// pitch loop) reverse a locked-in call/actual and return to the previous
  /// step. Nothing is committed to the event stream until the full pitch
  /// resolves (§10.3), so this is always safe to wire up.
  final VoidCallback onCancel;

  /// Baseball vs. softball for the actual-location ball icon. See [BallKind].
  final BallKind ballKind;

  /// Optional content rendered beneath the zone grid, clipped to the zone
  /// rect's exact bounds (future §18.6 heat-map underlay; unused until then).
  /// Should fill whatever size it's given (e.g. `SizedBox.expand`).
  final Widget? underlay;

  @override
  State<ZoneCanvas> createState() => _ZoneCanvasState();
}

class _ZoneCanvasState extends State<ZoneCanvas> {
  Offset? _dragLocal;

  void _handleLongPressStart(LongPressStartDetails details) {
    setState(() => _dragLocal = details.localPosition);
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    setState(() => _dragLocal = details.localPosition);
  }

  void _handleLongPressEnd(LongPressEndDetails details, Size size) {
    final local = _dragLocal;
    setState(() => _dragLocal = null);
    if (local == null || !_isInside(local, size)) {
      return; // Released outside the canvas: cancel, no commit.
    }
    widget.onCommit(zoneCoordFromLocal(local, size));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var width = constraints.maxWidth;
        var height = width / _canvasAspectRatio;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * _canvasAspectRatio;
        }
        final size = Size(width, height);
        final zoneRect = Rect.fromPoints(
          localFromZoneCoord(ZoneCoord(x: zoneMinX, y: zoneMaxY), size),
          localFromZoneCoord(ZoneCoord(x: zoneMaxX, y: zoneMinY), size),
        );

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Background + opaque zone fill, drawn first. When an
                // underlay is present it visually covers the fill within
                // zoneRect (intentional — the underlay takes its place), so
                // the border is painted separately, on top of the underlay,
                // below.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: _handleLongPressStart,
                    onLongPressMoveUpdate: _handleLongPressMoveUpdate,
                    onLongPressEnd: (details) =>
                        _handleLongPressEnd(details, size),
                    child: CustomPaint(
                      size: size,
                      painter: _ZoneCanvasBackgroundPainter(
                        zoneRect: zoneRect,
                        brightness: Theme.of(context).brightness,
                      ),
                    ),
                  ),
                ),
                if (widget.underlay != null)
                  Positioned.fromRect(
                    rect: zoneRect,
                    child: IgnorePointer(
                      child: ClipRect(child: widget.underlay),
                    ),
                  ),
                IgnorePointer(
                  child: CustomPaint(
                    size: size,
                    painter: _ZoneBorderPainter(zoneRect: zoneRect),
                  ),
                ),
                if (widget.value != null)
                  _MarkerIcon(
                    mode: widget.mode,
                    ballKind: widget.ballKind,
                    center: localFromZoneCoord(widget.value!, size),
                    ghost: false,
                  ),
                if (_dragLocal != null)
                  _MarkerIcon(
                    mode: widget.mode,
                    ballKind: widget.ballKind,
                    center: _dragLocal!.translate(0, -_dragFingerOffset),
                    ghost: true,
                  ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: _ModeBanner(mode: widget.mode),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: _AffordanceButton(
                    label: 'Cancel',
                    onPressed: widget.onCancel,
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: _AffordanceButton(
                    label: 'Skip location',
                    onPressed: widget.onSkip,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Margin background + opaque zone fill. Painted first (bottom of the
/// stack) — an underlay, if present, is layered on top of this and visually
/// replaces the zone fill within [zoneRect].
class _ZoneCanvasBackgroundPainter extends CustomPainter {
  const _ZoneCanvasBackgroundPainter({
    required this.zoneRect,
    required this.brightness,
  });

  final Rect zoneRect;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final isDark = brightness == Brightness.dark;

    final marginPaint = Paint()
      ..color = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F2);
    final zoneFill = Paint()
      ..color = isDark ? const Color(0xFF2C2C2E) : Colors.white;

    canvas
      ..drawRect(Offset.zero & size, marginPaint)
      ..drawRect(zoneRect, zoneFill);
  }

  @override
  bool shouldRepaint(covariant _ZoneCanvasBackgroundPainter oldDelegate) =>
      oldDelegate.zoneRect != zoneRect || oldDelegate.brightness != brightness;
}

/// Zone-rect border stroke only. Painted above the underlay so it stays
/// crisp regardless of what the underlay draws underneath it.
class _ZoneBorderPainter extends CustomPainter {
  const _ZoneBorderPainter({required this.zoneRect});

  final Rect zoneRect;

  @override
  void paint(Canvas canvas, Size size) {
    final zoneBorder = Paint()
      ..color = _accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(zoneRect, zoneBorder);
  }

  @override
  bool shouldRepaint(covariant _ZoneBorderPainter oldDelegate) =>
      oldDelegate.zoneRect != zoneRect;
}

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.mode});

  final ZoneCanvasIntent mode;

  @override
  Widget build(BuildContext context) {
    final label = mode == ZoneCanvasIntent.call ? 'CALL' : 'ACTUAL';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _accentColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _AffordanceButton extends StatelessWidget {
  const _AffordanceButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Drag/marker icon: a target reticle for [ZoneCanvasIntent.call] (aiming at
/// a target), a sport-specific ball for [ZoneCanvasIntent.actual] (recording
/// what actually happened). [ghost] renders the in-progress drag preview at
/// reduced opacity; the committed marker renders fully opaque.
class _MarkerIcon extends StatelessWidget {
  const _MarkerIcon({
    required this.mode,
    required this.ballKind,
    required this.center,
    required this.ghost,
  });

  final ZoneCanvasIntent mode;
  final BallKind ballKind;
  final Offset center;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - _iconRadius,
      top: center.dy - _iconRadius,
      child: IgnorePointer(
        child: Opacity(
          opacity: ghost ? 0.6 : 1,
          child: SizedBox(
            width: _iconRadius * 2,
            height: _iconRadius * 2,
            child: CustomPaint(
              painter: mode == ZoneCanvasIntent.call
                  ? const _ReticlePainter()
                  : _BallPainter(ballKind: ballKind),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  const _ReticlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final stroke = Paint()
      ..color = _accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas
      ..drawCircle(center, radius * 0.7, stroke)
      ..drawLine(
        center.translate(-radius, 0),
        center.translate(radius, 0),
        stroke,
      )
      ..drawLine(
        center.translate(0, -radius),
        center.translate(0, radius),
        stroke,
      );
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) => false;
}

class _BallPainter extends CustomPainter {
  const _BallPainter({required this.ballKind});

  final BallKind ballKind;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final softball = ballKind == BallKind.softball;
    final radius = size.width / 2 * (softball ? 1 : 0.85);

    final fill = Paint()
      ..color = softball ? const Color(0xFFE8F26A) : Colors.white;
    final outline = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final stitch = Paint()
      ..color = const Color(0xFFC62828)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final stitchArcBounds = Rect.fromCircle(
      center: center,
      radius: radius * 0.7,
    );

    canvas
      ..drawCircle(center, radius, fill)
      ..drawCircle(center, radius, outline)
      ..drawArc(stitchArcBounds, 0.5, 2.2, false, stitch)
      ..drawArc(stitchArcBounds, 0.5 + 3.14159, 2.2, false, stitch);
  }

  @override
  bool shouldRepaint(covariant _BallPainter oldDelegate) =>
      oldDelegate.ballKind != ballKind;
}
