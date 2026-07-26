import 'package:diamond/src/events/generated/events.dart';
import 'package:diamond/src/ui/zone_canvas/canvas_geometry.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

export 'package:diamond/src/ui/zone_canvas/canvas_geometry.dart';

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

// Placeholder palette — no app theme exists yet (pending a dedicated theming
// ticket). §18.7.3: the accent goes to the datum, not the frame — so the
// accent belongs to the tap marker, and structural lines (zone border, call
// grid) are dark on a light field, because light blue on white vanishes in
// sunlight. Ground tones are the dirt/chalk pair.
const Color _accentColor = Color(0xFF0A84FF);
const Color _structureLight = Color(0xFF1F1F22);
const Color _structureDark = Color(0xFFE8E8EA);
const Color _dirtLight = Color(0xFFC9A87A);
const Color _dirtDark = Color(0xFF4A3F31);
const Color _chalkColor = Color(0xFFFFFFFF);

const double _iconRadius = 16;
const double _dragFingerOffset = 56;

// Shorter than Flutter's default long-press threshold (kLongPressTimeout,
// 500ms — tuned for context-menu-style holds). Still enough of a deliberate
// hold to tell apart from a stray brush of the screen, but fast enough for
// 120+ pitches a game not to feel laggy.
const Duration zoneCanvasArmDuration = Duration(milliseconds: 180);

/// Key on the aspect-fitted drawing area, which excludes the control strip
/// below it.
///
/// Used only by the widget tests, to resolve gesture coordinates against the
/// painted canvas rather than against the widget's full bounds — production
/// code has no reason to look it up.
@visibleForTesting
const Key zoneCanvasDrawingAreaKey = Key('zoneCanvasDrawingArea');

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
    this.geometry = const FrontalGeometry(),
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

  /// The coordinate mapping and camera the canvas draws through (§11.4) — a
  /// parameter rather than hardcoded geometry, so the zone profile and virtual
  /// camera can change without touching the widget. DIA-011's second part adds
  /// the top-down `BounceCoord` plane as a sibling of this and extracts the
  /// common interface then, when both shapes are known.
  final FrontalGeometry geometry;

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
    // Controls sit in a strip *outside* the drawing area (§11.4). Overlaid on
    // the canvas they would cover the dirt band — the §11.1 hinge trigger —
    // which is a live hit-target conflict, and worse after the hinge, where
    // dirt is the whole canvas.
    return Column(
      children: [
        Expanded(child: _buildCanvas(context)),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: _AffordanceButton(
                  label: 'Cancel',
                  onPressed: widget.onCancel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AffordanceButton(
                  label: 'Skip location',
                  onPressed: widget.onSkip,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCanvas(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = widget.geometry.aspectRatio;
        var width = constraints.maxWidth;
        var height = width / aspectRatio;
        if (height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * aspectRatio;
        }
        final size = Size(width, height);
        final zoneRect = Rect.fromPoints(
          localFromZoneCoord(ZoneCoord(x: zoneMinX, y: zoneMaxY), size),
          localFromZoneCoord(ZoneCoord(x: zoneMaxX, y: zoneMinY), size),
        );

        return Center(
          child: SizedBox(
            key: zoneCanvasDrawingAreaKey,
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Ground furniture and zone fill, drawn first. When an
                // underlay is present it visually covers the fill within
                // zoneRect (intentional — the underlay takes its place), so
                // the border is painted separately, on top of the underlay,
                // below.
                Positioned.fill(
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      LongPressGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer
                          >(
                            () => LongPressGestureRecognizer(
                              duration: zoneCanvasArmDuration,
                            ),
                            (instance) => instance
                              ..onLongPressStart = _handleLongPressStart
                              ..onLongPressMoveUpdate =
                                  _handleLongPressMoveUpdate
                              ..onLongPressEnd = (details) =>
                                  _handleLongPressEnd(details, size),
                          ),
                    },
                    child: ClipRect(
                      child: CustomPaint(
                        size: size,
                        painter: _FrontalBackgroundPainter(
                          geometry: widget.geometry,
                          ballKind: widget.ballKind,
                          zoneRect: zoneRect,
                          brightness: Theme.of(context).brightness,
                        ),
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
                    painter: _ZoneBorderPainter(
                      zoneRect: zoneRect,
                      brightness: Theme.of(context).brightness,
                    ),
                  ),
                ),
                // A neutral starting marker at zone center, shown only
                // before anything's been placed or grabbed — gives the coach
                // something concrete to find and drag rather than a blind
                // first touch on an empty rect.
                if (widget.value == null && _dragLocal == null)
                  _DefaultMarker(
                    center: localFromZoneCoord(
                      ZoneCoord(x: 0, y: 0.5),
                      size,
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
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Frontal-plane background (§11.4): atmosphere, then the ground plane with
/// its distance fade, home plate and batter's-box chalk drawn through the
/// pinhole projector, and finally the zone fill.
///
/// Restrained fidelity — the richer treatment is a later comparison, and the
/// geometry is identical for both (§11.4). Ground furniture takes perspective;
/// the zone rect and grid stay orthographic, painted by [_ZoneBorderPainter]
/// above the underlay.
class _FrontalBackgroundPainter extends CustomPainter {
  const _FrontalBackgroundPainter({
    required this.geometry,
    required this.ballKind,
    required this.zoneRect,
    required this.brightness,
  });

  final FrontalGeometry geometry;
  final BallKind ballKind;
  final Rect zoneRect;
  final Brightness brightness;

  /// Batter's-box dimensions from the `RuleSet` placeholder (§11.4) — never an
  /// `if (softball)` branch at a call site.
  BatterBoxSpec get _box => ballKind == BallKind.softball
      ? BatterBoxSpec.fastpitch
      : BatterBoxSpec.baseball;

  /// Ground point (lateral inches, camera-relative distance `u`) → local px.
  ///
  /// This is the ground plane's *perspective* projection, not the frontal
  /// plane's height mapping, and the two are not isotropic (§11.4). It is
  /// deliberately one-way: nothing here or downstream turns a screen position
  /// back into a bounce depth — that comes only from the hinge and the
  /// top-down plane (§3.3, §11.1).
  Offset _groundPoint(double lateralInches, double u, Size size) {
    final xUnits = geometry.xUnitsAt(lateralInches, u);
    final yUnits = geometry.groundYAt(u);
    return localFromZoneCoord(ZoneCoord(x: xUnits, y: yUnits), size);
  }

  /// Closed path through ground points — the shape ground furniture is built
  /// from, so perspective is applied in exactly one place.
  Path _groundQuad(
    Size size,
    List<({double lateralInches, double u})> corners,
  ) {
    final path = Path();
    for (var i = 0; i < corners.length; i++) {
      final p = _groundPoint(corners[i].lateralInches, corners[i].u, size);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final isDark = brightness == Brightness.dark;

    final atmosphere = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F2);
    final dirt = isDark ? _dirtDark : _dirtLight;
    final zoneFill = isDark ? const Color(0xFF2C2C2E) : Colors.white;

    final fadeTopY = localFromZoneCoord(
      ZoneCoord(x: 0, y: FrontalGeometry.groundFadeEndY),
      size,
    ).dy;
    final groundLineY = localFromZoneCoord(
      ZoneCoord(x: 0, y: geometry.groundY),
      size,
    ).dy;

    canvas.drawRect(Offset.zero & size, Paint()..color = atmosphere);

    _paintGround(canvas, size, dirt, atmosphere, fadeTopY, groundLineY);
    _paintPlate(canvas, size, isDark);
    _paintBoxChalk(canvas, size, fadeTopY, groundLineY);

    canvas.drawRect(zoneRect, Paint()..color = zoneFill);
  }

  /// The ground's distance fade as a shader: opaque at and below the ground
  /// line, transparent at the fade end. Clamped at both ends, so anything
  /// painted on the ground can share it and fade with it.
  Shader _fadeShader(Color color, Size size, double fadeTopY, double top) =>
      LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0), color],
      ).createShader(Rect.fromLTRB(0, fadeTopY, size.width, top));

  /// Ground is drawn to its natural extent and bounded by a distance fade, not
  /// a `y` cap (§11.4): full tone at and below the ground line, fading to the
  /// atmosphere colour by [FrontalGeometry.groundFadeEndY] so it has reached
  /// neutral before it sits behind the zone rect. A treatment step at the
  /// ground line keeps the §11.1 trigger boundary legible — the trigger is
  /// never identified by "looks like dirt", since drawn ground spans the line.
  void _paintGround(
    Canvas canvas,
    Size size,
    Color dirt,
    Color atmosphere,
    double fadeTopY,
    double groundLineY,
  ) {
    // Above the ground line: fading scenery. Below: full tone.
    final scenery = Rect.fromLTRB(0, fadeTopY, size.width, groundLineY);
    if (!scenery.isEmpty) {
      canvas.drawRect(
        scenery,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [atmosphere, dirt],
          ).createShader(scenery),
      );
    }
    // Full tone below the ground line. The tonal step where the fade meets it
    // is itself the §11.1 trigger landmark — no drawn line: an explicit rule
    // across the full width read as an arbitrary graphic, and the step plus the
    // plate's front edge (which lands here by construction) already mark the
    // boundary. Worth re-checking against real taps when the hinge lands, since
    // that is when the boundary starts carrying interaction weight.
    canvas.drawRect(
      Rect.fromLTRB(0, groundLineY, size.width, size.height),
      Paint()..color = dirt,
    );
  }

  /// Home plate through the projector: 17″ edge toward the pitcher at `u = d`
  /// (which lands on `y_ground` — the identity in §11.4), 8.5″ straight sides,
  /// converging to the point at `u = d − 17″`. Foreshortening is never applied
  /// as a ratio; it falls out of the projection.
  void _paintPlate(Canvas canvas, Size size, bool isDark) {
    final path = _groundQuad(size, geometry.plateOutline);
    canvas
      ..drawPath(
        path,
        Paint()..color = isDark ? const Color(0xFFE0E0E0) : Colors.white,
      )
      ..drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
  }

  /// Batter's-box chalk: the inner line (parallel to the plate's side edge,
  /// 6″ off it to the chalk's inner edge) and the front line. Back and outer
  /// lines are deliberately not drawn — they carry no locating information and
  /// run off-frame at true scale (§11.4). Chalk is clipped only by the box's
  /// own extent and the canvas edge, and fades with the ground it sits on.
  void _paintBoxChalk(
    Canvas canvas,
    Size size,
    double fadeTopY,
    double groundLineY,
  ) {
    const innerEdge = plateHalfWidthInches + BatterBoxSpec.offsetInches;
    const outerEdge = innerEdge + BatterBoxSpec.chalkWidthInches;
    final frontU = geometry.plateCenterU + _box.foreInches;
    final backU = geometry.plateCenterU - _box.aftInches;

    for (final sign in [-1.0, 1.0]) {
      // Inner line: a quad between the chalk's inner and outer edges, running
      // from the box's back line to its front line.
      final inner = _groundQuad(size, [
        (lateralInches: sign * innerEdge, u: backU),
        (lateralInches: sign * innerEdge, u: frontU),
        (lateralInches: sign * outerEdge, u: frontU),
        (lateralInches: sign * outerEdge, u: backU),
      ]);

      // Front line: from the chalk's inner edge outward across the box width,
      // at the front line's depth. Only a stub of it is on-canvas.
      final frontOuterLateral = sign * (innerEdge + _box.widthInches);
      const chalk = BatterBoxSpec.chalkWidthInches;
      final front = _groundQuad(size, [
        (lateralInches: sign * innerEdge, u: frontU),
        (lateralInches: frontOuterLateral, u: frontU),
        (lateralInches: frontOuterLateral, u: frontU - chalk),
        (lateralInches: sign * innerEdge, u: frontU - chalk),
      ]);

      // One shader for both strokes, shared with the ground: a chalk line
      // running from the dirt band up into the scenery has to fade along its
      // own length, not carry a single alpha — otherwise its far end reads as a
      // solid white block sitting on top of faded ground.
      final paint = Paint()
        ..shader = _fadeShader(
          _chalkColor.withValues(alpha: 0.92),
          size,
          fadeTopY,
          groundLineY,
        );
      for (final chalk in [inner, front]) {
        canvas.drawPath(chalk, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FrontalBackgroundPainter oldDelegate) =>
      oldDelegate.zoneRect != zoneRect ||
      oldDelegate.brightness != brightness ||
      oldDelegate.ballKind != ballKind ||
      oldDelegate.geometry != geometry;
}

/// Zone-rect border stroke, plus the 3×3 in-zone grid lines (§10.1's default
/// `CallZone` layout) for visual reference. Painted above the underlay so it
/// stays crisp regardless of what the underlay draws underneath it.
///
/// The grid here is presentational only — no centroid/snapping logic, no
/// `callZoneId`. That's DIA-006/007's tap-tap `CallZone` grid, a separate
/// widget; this canvas stays freeform per DIA-005.
///
/// Strictly orthographic: perspective belongs to the ground furniture and stops
/// at the zone (§11.4). Perspective here would make §10.1's `bounds` cells
/// unequal tap targets and break tap-equals-coordinate.
///
/// Rendered dark, not in the accent (§18.7.3): a border and a grid are
/// scaffolding, the accent belongs to the tap marker, and light blue on white
/// disappears in daylight.
class _ZoneBorderPainter extends CustomPainter {
  const _ZoneBorderPainter({required this.zoneRect, required this.brightness});

  final Rect zoneRect;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final structure = brightness == Brightness.dark
        ? _structureDark
        : _structureLight;

    final gridLine = Paint()
      ..color = structure.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final colWidth = zoneRect.width / 3;
    final rowHeight = zoneRect.height / 3;
    for (var i = 1; i < 3; i++) {
      final x = zoneRect.left + colWidth * i;
      canvas.drawLine(
        Offset(x, zoneRect.top),
        Offset(x, zoneRect.bottom),
        gridLine,
      );
      final y = zoneRect.top + rowHeight * i;
      canvas.drawLine(
        Offset(zoneRect.left, y),
        Offset(zoneRect.right, y),
        gridLine,
      );
    }

    final zoneBorder = Paint()
      ..color = structure
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(zoneRect, zoneBorder);
  }

  @override
  bool shouldRepaint(covariant _ZoneBorderPainter oldDelegate) =>
      oldDelegate.zoneRect != zoneRect ||
      oldDelegate.brightness != brightness;
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
        child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
      ),
    );
  }
}

/// Starting dot at zone center, shown before anything's been placed —
/// deliberately not mode-styled (no reticle/ball imagery), since it isn't a
/// call or a result yet, just something to find and drag.
///
/// Carries the accent: it is the datum, and §18.7.3 puts the accent on the
/// datum rather than the frame. Previously this was neutral gray while the zone
/// border took the accent, which inverted the hierarchy.
class _DefaultMarker extends StatelessWidget {
  const _DefaultMarker({required this.center});

  final Offset center;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - _iconRadius,
      top: center.dy - _iconRadius,
      child: IgnorePointer(
        child: SizedBox(
          width: _iconRadius * 2,
          height: _iconRadius * 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accentColor.withValues(alpha: 0.28),
              border: Border.all(color: _accentColor, width: 2),
            ),
          ),
        ),
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
