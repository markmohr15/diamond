import 'dart:math' as math;

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

/// Which plane the canvas is currently showing (§11.4).
///
/// [frontal] is lateral × height and captures a [ZoneCoord]; [topDown] is
/// lateral × depth and captures a [BounceCoord]. The canvas enters [topDown]
/// only through §11.1's hinge — a release inside the dirt band, in
/// [ZoneCanvasIntent.actual] — and leaves it on commit or on Back.
enum ZoneCanvasPlane { frontal, topDown }

/// Baseball vs. softball, for the drag/marker icon in
/// [ZoneCanvasIntent.actual].
///
/// Narrow placeholder standing in for the eventual `RuleSet` config
/// (CLAUDE.md: sport differences route through `RuleSet`, never scattered
/// `if (softball)` checks) — replace call sites with a real `RuleSet` field
/// once that type exists.
enum BallKind { baseball, softball }

/// How richly the canvas renders (§11.4). Both treatments draw through the
/// *same* [FrontalGeometry] / [TopDownGeometry] — fidelity changes paint, never
/// a coordinate, which is what makes comparing them a fair test of the look
/// rather than of the geometry.
///
/// Deliberately unsettled: §11.4 makes fidelity a question to be answered by
/// field test in daylight, not by argument, so both ship here for comparison
/// and the losing one is deleted once a choice is made. This enum is not
/// intended to survive that decision as a permanent configuration knob.
enum CanvasFidelity {
  /// Flat fills, neutral background. Every decorated pixel competes with the
  /// markers and grid that carry the information (§18.7).
  restrained,

  /// Dimensional plate, textured dirt, chalk with weight. Visual craft signals
  /// a serious product, and precision is most of what reads as "serious".
  rich,
}

// Depiction of physical objects — dirt, chalk, ball leather, plate — rather
// than palette. §23.4 governs these as per-surface fidelity, and whether any of
// them should become theme tokens is a design question DIA-012 puts out of
// scope; they are on that ticket's documented literal allowlist until it is
// answered. The *accent* is not among them: it moved to
// `Theme.of(context).colorScheme.primary`, because §23.1.3 puts the accent on
// the datum (the tap marker) and the datum's colour is the team's, not the
// canvas's. Structural lines stay dark on a light field — light blue on white
// vanishes in sunlight.
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

/// Maps a local point to a [BounceCoord] in the top-down plane (§3.3).
///
/// Lateral is the *same* computation as [zoneCoordFromLocal]'s — deliberately
/// not a parallel one — because the two planes share that axis and nothing
/// else. Depth comes from the vertical fraction through [TopDownGeometry],
/// which is the only place a depth is ever read from a screen position: no
/// frontal-plane position is ever inverted into one (§11.4).
BounceCoord bounceCoordFromLocal(
  Offset local,
  Size size,
  TopDownGeometry geometry,
) => BounceCoord(
  x: zoneCoordFromLocal(local, size).x,
  depth: geometry.depthFeetAtFraction(local.dy / size.height),
);

/// Inverse of [bounceCoordFromLocal]. Requires a known depth — a
/// depth-unknown bounce has no point to place, and is rendered as a lateral
/// band instead.
Offset localFromBounceCoord(
  BounceCoord coord,
  Size size,
  TopDownGeometry geometry,
) => Offset(
  localFromZoneCoord(ZoneCoord(x: coord.x, y: 0), size).dx,
  geometry.fractionAtDepthFeet(coord.depth!) * size.height,
);

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
    this.bounceValue,
    this.onCommitBounce,
    this.batterSide = BatterSide.R,
    this.showBatterSilhouette = false,
    this.ballKind = BallKind.baseball,
    this.fidelity = CanvasFidelity.restrained,
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

  /// The committed bounce, or null if this pitch did not hit the dirt. A
  /// non-null value with a null `depth` is "in the dirt, depth unknown"
  /// (§11.1) — a real observation, not a missing one, and rendered as a
  /// lateral band rather than a point.
  ///
  /// Mutually exclusive with [value], as `actualLocation` and `bounceLocation`
  /// are on the event (§4.1). Passing one non-null opens the canvas on the
  /// plane that owns it.
  final BounceCoord? bounceValue;

  /// Fired once, on release, with the committed bounce. Null means this
  /// instance cannot capture a bounce at all, which disables the hinge — the
  /// canvas then behaves exactly as it did before DIA-011's third part, and a
  /// release in the dirt band just commits a low [ZoneCoord].
  ///
  /// Never fires in [ZoneCanvasIntent.call]: a call is never a bounce (§4.1).
  /// A coach calls "bury it down" as a low/chase zone, not a bounce depth.
  final ValueChanged<BounceCoord>? onCommitBounce;

  /// Which box the batter is standing in, for the silhouette (§11.4).
  ///
  /// Placement only — the canvas never mirrors coordinates, since `x` is
  /// absolute (§3.1). A pitch tapped at a given spot means the same thing
  /// whoever is up; all this moves is where she is drawn.
  final BatterSide batterSide;

  /// Whether to draw the batter silhouette (§11.4).
  ///
  /// Off by default while the *drawing* is provisional — the figure is built
  /// from round-capped strokes and does not yet read convincingly as a batter
  /// (DIA-013). The geometry behind it is correct and stays: knee on the zone's
  /// bottom edge, armpit on its top, derived from [geometry]'s profile.
  ///
  /// Not a temporary gate to be deleted once the art is good. A future practice
  /// state — pitchers throwing bullpens with no batter in the box — wants the
  /// same switch, driven by a user setting rather than a constant, so this
  /// parameter has a reason to exist independent of how the figure looks.
  final bool showBatterSilhouette;

  /// Baseball vs. softball for the actual-location ball icon. See [BallKind].
  final BallKind ballKind;

  /// How richly to render. See [CanvasFidelity] — both treatments draw through
  /// the same geometry, and this parameter is expected to be removed once the
  /// daylight comparison picks one.
  final CanvasFidelity fidelity;

  /// The coordinate mapping and camera the canvas draws through (§11.4) — a
  /// parameter rather than hardcoded geometry, so the zone profile and virtual
  /// camera can change without touching the widget.
  ///
  /// The top-down plane's geometry is *derived* from this rather than passed
  /// alongside it (see [topDownGeometry]) — the two planes have to share a
  /// lateral axis (§3.3), and deriving is what makes that structural instead
  /// of a pair of parameters that could be set inconsistently.
  final FrontalGeometry geometry;

  /// The top-down plane's geometry, derived from [geometry]. See above.
  TopDownGeometry get topDownGeometry => TopDownGeometry(frontal: geometry);

  /// Optional content rendered beneath the zone grid, clipped to the zone
  /// rect's exact bounds (future §18.6 heat-map underlay; unused until then).
  /// Should fill whatever size it's given (e.g. `SizedBox.expand`).
  final Widget? underlay;

  @override
  State<ZoneCanvas> createState() => _ZoneCanvasState();
}

class _ZoneCanvasState extends State<ZoneCanvas> {
  Offset? _dragLocal;
  late ZoneCanvasPlane _plane = widget.bounceValue == null
      ? ZoneCanvasPlane.frontal
      : ZoneCanvasPlane.topDown;

  /// Lateral position of the dirt-band release that opened the hinge. Kept so
  /// "depth unknown" can still record the `x` the coach already gave us — the
  /// second placement is what's skipped, not the first.
  double? _hingeX;

  /// Whether a release in the dirt band should hinge rather than commit
  /// (§11.1). Actual-mode only — a call is never a bounce (§4.1) — and only
  /// when the parent can actually receive one.
  bool get _hingeEnabled =>
      widget.mode == ZoneCanvasIntent.actual && widget.onCommitBounce != null;

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

    if (_plane == ZoneCanvasPlane.topDown) {
      widget.onCommitBounce!(
        bounceCoordFromLocal(local, size, widget.topDownGeometry),
      );
      return;
    }

    final coord = zoneCoordFromLocal(local, size);

    // The hinge, and the only branch point in this handler (§11.1). It fires
    // on *release*, never on arm or drag: the whole press-drag-preview stays in
    // the frontal plane, so arming low and dragging up to correct still commits
    // a normal location and coordinate spaces never change mid-gesture.
    //
    // The trigger is `y < y_ground` and nothing else — not "the tap looked like
    // it landed on dirt". Drawn ground spans the line, since ground in front of
    // the plate projects above it (§11.4), so the two regions are different
    // shapes and only this one is the trigger.
    if (_hingeEnabled && coord.y < widget.geometry.groundY) {
      setState(() {
        _plane = ZoneCanvasPlane.topDown;
        _hingeX = coord.x;
      });
      return;
    }

    widget.onCommit(coord);
  }

  /// Back, from the top-down plane: un-hinges without committing anything.
  /// Distinct from the frontal plane's Cancel, which reverses the whole step.
  void _handleUnhinge() {
    setState(() {
      _plane = ZoneCanvasPlane.frontal;
      _hingeX = null;
      _dragLocal = null;
    });
  }

  /// Skip, from the top-down plane: records "in the dirt, depth unknown"
  /// (§11.1) rather than nothing at all. The lateral position is already known
  /// from the release that opened the hinge, so it is kept — dropping it too
  /// would discard an observation the coach actually made.
  void _handleSkipDepth() {
    widget.onCommitBounce!(BounceCoord(x: _hingeX ?? widget.bounceValue!.x));
  }

  @override
  Widget build(BuildContext context) {
    // Controls sit in a strip *outside* the drawing area (§11.4). Overlaid on
    // the canvas they would cover the dirt band — the §11.1 hinge trigger —
    // which is a live hit-target conflict, and worse after the hinge, where
    // dirt is the whole canvas.
    //
    // The strip is in the same place with the same shape in both planes; only
    // the labels and destinations change, because both buttons mean something
    // narrower once the hinge has fired. Back un-hinges rather than reversing
    // the step, and skipping now means "depth unknown" rather than "no
    // location" — the lateral position was already given.
    final topDown = _plane == ZoneCanvasPlane.topDown;
    return Column(
      children: [
        Expanded(child: _buildCanvas(context)),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: _AffordanceButton(
                  label: topDown ? 'Back to zone' : 'Cancel',
                  onPressed: topDown ? _handleUnhinge : widget.onCancel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AffordanceButton(
                  label: topDown ? 'Depth unknown' : 'Skip location',
                  onPressed: topDown ? _handleSkipDepth : widget.onSkip,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The marker layer, drawn above everything else in both planes — including
  /// the ground furniture and, later, the batter silhouette (§11.4): the datum
  /// is never occluded by scenery.
  List<Widget> _buildMarkerLayer(Size size, {required bool topDown}) {
    final geometry = widget.topDownGeometry;
    final bounce = widget.bounceValue;

    // A depth-unknown bounce has no point to place. Rendering it at some
    // default depth would be a fabricated observation — Core Principle #3 —
    // so it draws as a band across every depth at the lateral position we do
    // know, which reads as exactly what it is.
    if (topDown && bounce != null && bounce.depth == null) {
      return [
        _DepthUnknownBand(
          x: localFromZoneCoord(ZoneCoord(x: bounce.x, y: 0), size).dx,
        ),
        if (_dragLocal != null)
          _MarkerIcon(
            mode: widget.mode,
            ballKind: widget.ballKind,
            center: _dragLocal!.translate(0, -_dragFingerOffset),
            ghost: true,
          ),
      ];
    }

    // Where the neutral starting marker sits, before anything is placed or
    // grabbed: zone center in the frontal plane, and in the top-down plane the
    // seam at the lateral position the hinge arrived with — the coach has
    // already told us the `x`, so starting anywhere else would throw it away
    // and make her give it again.
    final start = topDown
        ? Offset(
            localFromZoneCoord(ZoneCoord(x: _hingeX ?? 0, y: 0), size).dx,
            geometry.seamFraction * size.height,
          )
        : localFromZoneCoord(ZoneCoord(x: 0, y: 0.5), size);

    final placed = topDown
        ? (bounce == null ? null : localFromBounceCoord(bounce, size, geometry))
        : (widget.value == null
              ? null
              : localFromZoneCoord(widget.value!, size));

    return [
      if (placed == null && _dragLocal == null) _DefaultMarker(center: start),
      if (placed != null)
        _MarkerIcon(
          mode: widget.mode,
          ballKind: widget.ballKind,
          center: placed,
          ghost: false,
        ),
      if (_dragLocal != null)
        _MarkerIcon(
          mode: widget.mode,
          ballKind: widget.ballKind,
          center: _dragLocal!.translate(0, -_dragFingerOffset),
          ghost: true,
        ),
    ];
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

        final topDown = _plane == ZoneCanvasPlane.topDown;
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
                //
                // The gesture recognizer is identical in both planes: same
                // arm duration, same drag-preview, same release semantics. The
                // hinge changes which coordinate space a release is read in,
                // never how the gesture itself works, so the grammar a coach
                // learns for the zone carries over to the dirt unchanged.
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
                        painter: topDown
                            ? _TopDownBackgroundPainter(
                                geometry: widget.topDownGeometry,
                                ballKind: widget.ballKind,
                                brightness: Theme.of(context).brightness,
                                fidelity: widget.fidelity,
                              )
                            : _FrontalBackgroundPainter(
                                geometry: widget.geometry,
                                ballKind: widget.ballKind,
                                zoneRect: zoneRect,
                                brightness: Theme.of(context).brightness,
                                fidelity: widget.fidelity,
                                atmosphere: Theme.of(
                                  context,
                                ).colorScheme.surface,
                                zoneFill: Theme.of(
                                  context,
                                ).colorScheme.surfaceBright,
                              ),
                      ),
                    ),
                  ),
                ),
                // The silhouette sits on the ground furniture and beneath
                // everything that carries information — she is scenery. Frontal
                // plane only: her job is the vertical read (knee-to-armpit
                // against the zone rect), which the top-down plane has no axis
                // for, and a body-shaped mass there would compete with depth.
                if (!topDown && widget.showBatterSilhouette)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRect(
                        child: CustomPaint(
                          size: size,
                          painter: _SilhouettePainter(
                            silhouette: BatterSilhouette(
                              profile: widget.geometry.profile,
                            ),
                            frontal: widget.geometry,
                            batterSide: widget.batterSide,
                            brightness: Theme.of(context).brightness,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!topDown && widget.underlay != null)
                  Positioned.fromRect(
                    rect: zoneRect,
                    child: IgnorePointer(
                      child: ClipRect(child: widget.underlay),
                    ),
                  ),
                if (!topDown)
                  IgnorePointer(
                    child: CustomPaint(
                      size: size,
                      painter: _ZoneBorderPainter(
                        zoneRect: zoneRect,
                        brightness: Theme.of(context).brightness,
                      ),
                    ),
                  ),
                ..._buildMarkerLayer(size, topDown: topDown),
                // Paint, never a hit target — the same rule the markers and
                // the future silhouette follow. A label that swallows taps
                // makes the region it covers uncapturable, and a pitch may be
                // recorded anywhere on the canvas. Worse after the hinge,
                // where the banner sits over live dirt.
                Positioned(
                  top: 8,
                  left: 8,
                  child: IgnorePointer(
                    child: _ModeBanner(mode: widget.mode, plane: _plane),
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
    required this.fidelity,
    required this.atmosphere,
    required this.zoneFill,
  });

  final FrontalGeometry geometry;
  final BallKind ballKind;
  final Rect zoneRect;
  final Brightness brightness;
  final CanvasFidelity fidelity;

  /// The page behind the canvas — `colorScheme.surface`, passed in rather than
  /// chosen here so the canvas sits on the app's surface rather than its own.
  final Color atmosphere;

  /// The strike zone's fill — `colorScheme.surfaceBright`, the brightest
  /// surface in either mode: paper on light, a lifted plane on dark.
  final Color zoneFill;

  bool get _rich => fidelity == CanvasFidelity.rich;

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

    final dirt = isDark ? _dirtDark : _dirtLight;

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
    final band = Rect.fromLTRB(0, groundLineY, size.width, size.height);
    canvas.drawRect(band, Paint()..color = dirt);
    if (_rich) _paintDirtGrain(canvas, band, dirt);
  }

  /// Home plate through the projector: 17″ edge toward the pitcher at `u = d`
  /// (which lands on `y_ground` — the identity in §11.4), 8.5″ straight sides,
  /// converging to the point at `u = d − 17″`. Foreshortening is never applied
  /// as a ratio; it falls out of the projection.
  void _paintPlate(Canvas canvas, Size size, bool isDark) {
    final path = _groundQuad(size, geometry.plateOutline);
    final bounds = path.getBounds();

    // Rich: the plate sits proud of the dirt — a contact shadow under its near
    // edge and a top-lit face. Restrained: a flat fill. Same outline either
    // way; fidelity never moves a coordinate (§11.4).
    if (_rich) {
      canvas.drawPath(
        path.shift(const Offset(0, 2)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    final face = Paint();
    if (_rich) {
      face.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [const Color(0xFFF2F2F2), const Color(0xFFC4C4C4)]
            : [Colors.white, const Color(0xFFDCDCDC)],
      ).createShader(bounds);
    } else {
      face.color = isDark ? const Color(0xFFE0E0E0) : Colors.white;
    }
    canvas
      ..drawPath(path, face)
      ..drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: _rich ? 0.38 : 0.30)
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
        if (_rich) _paintChalkBloom(canvas, chalk, paint);
        canvas.drawPath(chalk, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FrontalBackgroundPainter oldDelegate) =>
      oldDelegate.zoneRect != zoneRect ||
      oldDelegate.brightness != brightness ||
      oldDelegate.ballKind != ballKind ||
      oldDelegate.fidelity != fidelity ||
      oldDelegate.geometry != geometry ||
      oldDelegate.atmosphere != atmosphere ||
      oldDelegate.zoneFill != zoneFill;
}

/// Procedural dirt grain for [CanvasFidelity.rich].
///
/// Seeded from a constant so the same canvas draws the same speckles every
/// frame and every golden run — a texture that resampled itself on repaint
/// would shimmer under the finger and make golden diffs meaningless.
void _paintDirtGrain(Canvas canvas, Rect area, Color dirt) {
  if (area.isEmpty) return;
  final rng = math.Random(20260726);
  final light = Paint()..color = Colors.white.withValues(alpha: 0.05);
  final dark = Paint()..color = Colors.black.withValues(alpha: 0.06);
  final count = (area.width * area.height / 900).clamp(0, 1400).toInt();
  for (var i = 0; i < count; i++) {
    final p = Offset(
      area.left + rng.nextDouble() * area.width,
      area.top + rng.nextDouble() * area.height,
    );
    canvas.drawCircle(
      p,
      rng.nextDouble() * 1.6 + 0.4,
      rng.nextBool() ? light : dark,
    );
  }
}

/// Chalk with weight for [CanvasFidelity.rich]: a soft spread under the hard
/// edge, so the line sits *in* the dirt rather than on top of it.
void _paintChalkBloom(Canvas canvas, Path path, Paint base) {
  canvas.drawPath(
    path,
    Paint()
      ..shader = base.shader
      ..color = base.color
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
  );
}

/// The batter silhouette (§11.4): a body to read a call or an actual against,
/// instead of an empty rectangle.
///
/// Every landmark comes from [BatterSilhouette], which derives them from the
/// zone profile — her knee is the zone's bottom edge and her armpit its top, so
/// she cannot disagree with the rect she stands beside. Nothing here is a fixed
/// pixel size.
///
/// Drawn beneath the marker layer and wrapped in `IgnorePointer` by the caller.
/// A pitch may be recorded anywhere on the canvas, including at her body — a
/// silhouette that swallowed taps would make the region it occupies
/// uncapturable, which is the opposite of why the lateral range was widened to
/// contain her (§11.4).
class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter({
    required this.silhouette,
    required this.frontal,
    required this.batterSide,
    required this.brightness,
  });

  final BatterSilhouette silhouette;

  /// Used for one thing only: projecting the two feet, which stand at
  /// different depths, onto their true ground heights.
  final FrontalGeometry frontal;

  final BatterSide batterSide;
  final Brightness brightness;

  /// Her centre, in x-units. Handedness lives in [BatterSilhouette] so the
  /// catcher's-view convention is written down once.
  double get _centreX =>
      silhouette.centreXUnits(rightHanded: batterSide == BatterSide.R);

  double _xUnits(double inches) => inches / plateHalfWidthInches;

  Offset _p(double xUnits, double y, Size size) =>
      localFromZoneCoord(ZoneCoord(x: xUnits, y: y), size);

  @override
  void paint(Canvas canvas, Size size) {
    final s = silhouette;
    final tone = brightness == Brightness.dark
        ? _structureDark
        : _structureLight;

    final pxPerInch = size.width / zoneCanvasLateralExtentInches;
    double w(double inches) => inches * pxPerInch;

    // The figure is built in "inches toward the plate" and flipped by
    // handedness once, here — so the stance is written down in one orientation
    // and the mirror cannot be got wrong limb by limb.
    final toward = s.towardPlateSign(rightHanded: batterSide == BatterSide.R);
    Offset at(double towardPlateInches, double y) =>
        _p(_centreX + toward * _xUnits(towardPlateInches), y, size);

    // Both feet sit the *same* distance from the box line — a batting stance
    // separates them along the pitcher-catcher axis, not across the plate — so
    // there is no lateral offset between them at all. What separates them on
    // screen is depth: the back foot stands nearer the catcher, and nearer
    // ground projects below `y_ground` while further ground projects above it.
    // Read from the ground projector, so the split is the real one rather than
    // a number chosen to look right.
    const ankle = 0.0;
    final backDrop =
        frontal.groundYAt(frontal.plateCenterU - s.stanceDepthHalfInches) -
        s.feetY;
    final frontDrop =
        frontal.groundYAt(frontal.plateCenterU + s.stanceDepthHalfInches) -
        s.feetY;

    // Each leg is translated bodily by its own ground offset, knee included.
    // Standing at different depths, the two knees *straddle* `y = 0` rather
    // than both sitting on it — the zone's bottom edge is the batter's knee
    // height, one physical value, which the two knees project either side of.
    // Translating the foot alone would stretch the back leg instead.
    final backKneeY = s.kneeY + backDrop;
    final frontKneeY = s.kneeY + frontDrop;

    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = tone.withValues(alpha: 0.13),
    );
    final limb = Paint()
      ..color = tone
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path polyline(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      return path;
    }

    // The torso leans in over the plate from the waist — a batter is hinged
    // forward at the hips, not standing upright. Roughly 25 degrees, which at
    // this torso length puts the shoulders about a chest-depth further toward
    // the plate than the hips.
    final chest = s.chestDepthInches;
    const hipX = -2.0;
    final shoulderX = hipX + chest * 1.1;
    final handsX = -chest * 0.9;
    final handsY = s.shoulderY + 0.05;

    canvas
      // Back leg, then front leg: hip over a bent knee down to the ankle.
      ..drawPath(
        polyline([
          at(hipX - chest * 0.15, s.hipY),
          at(ankle + s.kneeForwardInches, backKneeY),
          at(ankle, s.feetY + backDrop),
        ]),
        limb..strokeWidth = w(s.thighWidthInches),
      )
      ..drawPath(
        polyline([
          at(hipX + chest * 0.15, s.hipY),
          at(ankle + s.kneeForwardInches * 1.2, frontKneeY),
          at(ankle, s.feetY + frontDrop),
        ]),
        limb..strokeWidth = w(s.shinWidthInches * 1.15),
      )
      // Feet, pointing at the plate — square to the pitch, which is what makes
      // the figure read as a batter in the box rather than a person standing
      // beside it. Equidistant from the line by construction: same lateral
      // position, same length, different depth.
      ..drawPath(
        polyline([
          at(ankle, s.feetY + backDrop),
          at(ankle + s.footLengthInches, s.feetY + backDrop),
        ]),
        limb..strokeWidth = w(s.statureInches * 0.045),
      )
      ..drawPath(
        polyline([
          at(ankle, s.feetY + frontDrop),
          at(ankle + s.footLengthInches, s.feetY + frontDrop),
        ]),
        limb..strokeWidth = w(s.statureInches * 0.045),
      )
      // Torso, hips to shoulders, hinged forward over the plate.
      ..drawPath(
        polyline([at(hipX, s.hipY), at(shoulderX, s.shoulderY)]),
        limb..strokeWidth = w(chest),
      )
      // Both arms, each with its own elbow, meeting at the hands. The front
      // elbow drops toward the plate and the back elbow lifts away from it —
      // drawing one arm made the figure read as a person with a hand raised.
      ..drawPath(
        polyline([
          at(shoulderX + chest * 0.15, s.shoulderY - 0.05),
          at(shoulderX + chest * 0.1, s.shoulderY - 0.34),
          at(handsX, handsY),
        ]),
        limb..strokeWidth = w(s.armWidthInches),
      )
      ..drawPath(
        polyline([
          at(shoulderX - chest * 0.35, s.shoulderY - 0.02),
          at(handsX - chest * 0.75, s.shoulderY - 0.22),
          at(handsX, handsY),
        ]),
        limb..strokeWidth = w(s.armWidthInches),
      )
      // Bat, up and back over the rear shoulder — clear of the zone rect, and
      // running off the top of the frame as in the reference.
      ..drawPath(
        polyline([at(handsX, handsY), at(handsX - chest * 1.3, handsY + 0.5)]),
        limb..strokeWidth = w(s.statureInches * 0.038),
      )
      // Head, in profile and turned toward the pitcher. Frame-cut at
      // upper-face level by the +1.5 top (§11.4) — as the reference is.
      ..drawOval(
        Rect.fromPoints(
          at(shoulderX + chest * 0.25 - s.headDepthInches / 2, s.headTopY),
          at(shoulderX + chest * 0.25 + s.headDepthInches / 2, s.chinY),
        ),
        Paint()..color = tone,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _SilhouettePainter oldDelegate) =>
      oldDelegate.batterSide != batterSide ||
      oldDelegate.brightness != brightness ||
      oldDelegate.frontal != frontal ||
      oldDelegate.silhouette != silhouette;
}

/// Top-down plate/dirt plane (§3.3, §11.4), shown after §11.1's hinge.
///
/// Has to be **unmistakable at a glance** — if the two planes could be confused
/// the hinge design fails — so nothing here is shared with the frontal plane's
/// look: no zone rect, no call grid, dirt edge to edge, the plate as a true
/// pentagon rather than a foreshortened trapezoid, and a depth ruler no frontal
/// view has. What *is* shared is the lateral axis, exactly (§3.3): the plate is
/// literally the same width in both views, which is the register cue.
///
/// Restrained fidelity, matching [_FrontalBackgroundPainter]; the richer
/// treatment is DIA-011's fourth part and uses this same geometry (§11.4).
class _TopDownBackgroundPainter extends CustomPainter {
  const _TopDownBackgroundPainter({
    required this.geometry,
    required this.ballKind,
    required this.brightness,
    required this.fidelity,
  });

  final TopDownGeometry geometry;
  final BallKind ballKind;
  final Brightness brightness;
  final CanvasFidelity fidelity;

  bool get _rich => fidelity == CanvasFidelity.rich;

  BatterBoxSpec get _box => ballKind == BallKind.softball
      ? BatterBoxSpec.fastpitch
      : BatterBoxSpec.baseball;

  /// (lateral inches, depth inches) → local px. True scale in both axes: the
  /// lateral term is the frontal plane's own mapping, and the depth term uses
  /// the same px-per-inch, which is what [TopDownGeometry] exists to guarantee.
  Offset _point(double lateralInches, double depthInches, Size size) => Offset(
    localFromZoneCoord(
      ZoneCoord(x: lateralInches / plateHalfWidthInches, y: 0),
      size,
    ).dx,
    geometry.fractionAtDepthFeet(depthInches / 12) * size.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final isDark = brightness == Brightness.dark;
    final dirt = isDark ? _dirtDark : _dirtLight;
    final structure = isDark ? _structureDark : _structureLight;

    // Dirt edge to edge: after the hinge, the whole canvas is ground. There is
    // no atmosphere here and no ground/sky boundary to read — which is itself
    // most of what makes the two planes impossible to confuse.
    canvas.drawRect(Offset.zero & size, Paint()..color = dirt);
    if (_rich) _paintDirtGrain(canvas, Offset.zero & size, dirt);

    _paintDepthRuler(canvas, size, structure);
    _paintBoxChalk(canvas, size);
    _paintPlate(canvas, size, isDark);
    // Labels last: they run down the canvas's left margin, which the near end
    // of the left-hand chalk band reaches into at narrow widths. Reading the
    // axis matters more than an unbroken chalk line.
    _paintDepthLabels(canvas, size, structure);
  }

  /// A ruler, not bands. §11.4's 0–2 / 2–4 / 4 ft+ buckets are gone (v0.35):
  /// they assumed a depth range this plane does not afford, and `depth` is a
  /// continuous float that never gets bucketed in storage anyway (§3.3), so a
  /// gridline every foot tells the truth about the axis with less ink.
  ///
  /// `depth = 0` is one of these lines and looks like the rest of them. It
  /// needs no emphasis: it *is* the plate's 17″ front edge, so the plate draws
  /// it far more legibly than a heavier rule could, and which side is front is
  /// told by where the plate points (§11.4) rather than by any line weight.
  void _paintDepthRuler(Canvas canvas, Size size, Color structure) {
    final line = Paint()
      ..color = structure.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (final foot in _gridlineFeet) {
      final y = geometry.fractionAtDepthFeet(foot) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  /// The ruler's labels. Sign is spelled out rather than punctuated — "2 ft
  /// back" cannot be misread the way a minus sign glanced at in sunlight can,
  /// and the direction is what a coach is actually reading.
  void _paintDepthLabels(Canvas canvas, Size size, Color structure) {
    for (final foot in _gridlineFeet) {
      if (foot == 0) continue; // The plate marks it; a "0 ft" label is noise.
      final y = geometry.fractionAtDepthFeet(foot) * size.height;
      final label = TextPainter(
        text: TextSpan(
          // Unsigned: the plate sits between the two sides, so which way is
          // toward the catcher is not something a label has to carry.
          text: '${foot.abs().toInt()} ft',
          style: TextStyle(
            color: structure.withValues(alpha: 0.55),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(6, y - label.height - 2));
    }
  }

  /// Whole-foot depths with a gridline, 0 included and indistinguishable from
  /// the rest.
  Iterable<double> get _gridlineFeet sync* {
    const step = TopDownGeometry.gridlineSpacingFeet;
    for (
      var foot = (geometry.minDepthFeet / step).ceil() * step;
      foot <= geometry.maxDepthFeet;
      foot += step
    ) {
      yield foot;
    }
  }

  /// The plate from directly above, and the `depth = 0` seam it defines. Drawn
  /// last so it sits over the ruler and chalk — it is the anchor a coach reads
  /// the whole plane against.
  void _paintPlate(Canvas canvas, Size size, bool isDark) {
    final corners = geometry.plateOutline;
    final path = Path();
    for (var i = 0; i < corners.length; i++) {
      final p = _point(corners[i].lateralInches, corners[i].depthInches, size);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();

    if (_rich) {
      canvas.drawPath(
        path.shift(const Offset(0, 2)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    final face = Paint();
    if (_rich) {
      face.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [const Color(0xFFF2F2F2), const Color(0xFFC4C4C4)]
            : [Colors.white, const Color(0xFFDCDCDC)],
      ).createShader(path.getBounds());
    } else {
      face.color = isDark ? const Color(0xFFE0E0E0) : Colors.white;
    }
    canvas
      ..drawPath(path, face)
      ..drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: _rich ? 0.38 : 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
  }

  /// Batter's-box chalk, flanking the plate (§11.4): the inner line and the
  /// front line, never the back or outer ones — the same rule the frontal plane
  /// follows. No perspective here, so these are plain rectangles.
  ///
  /// Whether the front line is visible is a `RuleSet` consequence, not a
  /// special case: baseball's box reaches 2.29 ft in front of the plate and
  /// lands inside this canvas, fastpitch's reaches 4.0 ft and does not, so the
  /// same code draws a terminated box for one sport and a band running off the
  /// top edge for the other. Drawing only the inner line, as this did before,
  /// left baseball's band stopping at a depth with nothing to say why.
  void _paintBoxChalk(Canvas canvas, Size size) {
    const innerEdge = plateHalfWidthInches + BatterBoxSpec.offsetInches;
    const outerEdge = innerEdge + BatterBoxSpec.chalkWidthInches;
    const chalk = BatterBoxSpec.chalkWidthInches;
    final frontDepth = TopDownGeometry.plateCenterDepthInches + _box.foreInches;
    final backDepth = TopDownGeometry.plateCenterDepthInches - _box.aftInches;

    final paint = Paint()..color = _chalkColor.withValues(alpha: 0.92);
    for (final sign in [-1.0, 1.0]) {
      final corner = _point(sign * innerEdge, frontDepth, size);
      final outerFront = _point(
        sign * (innerEdge + _box.widthInches),
        frontDepth - chalk,
        size,
      );
      final inner = Rect.fromPoints(
        corner,
        _point(sign * outerEdge, backDepth, size),
      );
      final front = Rect.fromPoints(corner, outerFront);
      if (_rich) {
        for (final r in [inner, front]) {
          _paintChalkBloom(canvas, Path()..addRect(r), paint);
        }
      }
      canvas
        // Inner line: back of the box up to its front line.
        ..drawRect(inner, paint)
        // Front line: outward from the inner edge across the box width, its 3″
        // measured back toward the plate so the corner closes flush with the
        // inner line rather than overhanging it. Clipped by the canvas when the
        // sport puts it off-frame.
        ..drawRect(front, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TopDownBackgroundPainter oldDelegate) =>
      oldDelegate.brightness != brightness ||
      oldDelegate.ballKind != ballKind ||
      oldDelegate.fidelity != fidelity ||
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
      oldDelegate.zoneRect != zoneRect || oldDelegate.brightness != brightness;
}

/// A committed bounce whose depth was never captured (§11.1): the lateral
/// position is known, every depth is equally possible, so it draws as a band
/// spanning the axis rather than a point somewhere along it.
///
/// Deliberately not a marker at a default depth. That would render a value
/// nobody observed, which is the same mistake as storing a fabricated
/// coordinate (Core Principle #3) — here it would just be made in pixels.
class _DepthUnknownBand extends StatelessWidget {
  const _DepthUnknownBand({required this.x});

  final double x;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Positioned(
      left: x - _iconRadius,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: _iconRadius * 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.22),
              border: Border.symmetric(
                vertical: BorderSide(color: accent, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.mode, required this.plane});

  final ZoneCanvasIntent mode;
  final ZoneCanvasPlane plane;

  @override
  Widget build(BuildContext context) {
    // The top-down plane never appears in call mode, so its banner replaces the
    // mode label outright rather than qualifying it.
    final label = switch ((mode, plane)) {
      (_, ZoneCanvasPlane.topDown) => 'IN THE DIRT',
      (ZoneCanvasIntent.call, _) => 'CALL',
      (ZoneCanvasIntent.actual, _) => 'ACTUAL',
    };
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: scheme.onPrimary,
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
    final accent = Theme.of(context).colorScheme.primary;
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
              color: accent.withValues(alpha: 0.28),
              border: Border.all(color: accent, width: 2),
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
                  ? _ReticlePainter(
                      accent: Theme.of(context).colorScheme.primary,
                    )
                  : _BallPainter(ballKind: ballKind),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  const _ReticlePainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final stroke = Paint()
      ..color = accent
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
  bool shouldRepaint(covariant _ReticlePainter oldDelegate) =>
      oldDelegate.accent != accent;
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
