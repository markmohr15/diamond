import 'package:diamond/src/ui/zone_canvas/canvas_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

// Numeric geometry assertions (§3.1, §11.4) — about the mapping, not the look,
// so no widget pumping and no goldens here.
//
// Every expectation is computed from the canonical inputs rather than copied
// from the spec's prose. Rounded figures in prose are display, not source
// (§3.1): asserting `y_ground == -0.65` with a 2% tolerance would pass against
// a hardcoded constant, which is exactly the bug these tests exist to catch.
void main() {
  group('ZoneProfile — per-batter, never constants', () {
    const p = ZoneProfile.canonical12U;

    test('canonical 12U inputs give a 24in zone height', () {
      expect(p.bottomInches, 15.5);
      expect(p.topInches, 39.5);
      expect(p.heightInches, closeTo(24, 1e-9));
    });

    test('y_ground is -(zoneBottom / zoneHeight), i.e. -0.6458 at 12U', () {
      expect(p.groundY, closeTo(-15.5 / 24, 1e-12));
      // Tight enough to fail against the rounded -0.65 (a 0.65% gap), which a
      // 2% tolerance would have let through.
      expect(p.groundY, closeTo(-0.645833, 1e-5));
      expect(p.groundY, isNot(closeTo(-0.65, 1e-4)));
    });

    test('axis scale ratio is 8.5/zoneHeight and moves with the profile', () {
      expect(p.axisScaleRatio, closeTo(8.5 / 24, 1e-12));
      expect(p.axisScaleRatio, closeTo(0.354, 0.0005));

      // A smaller athlete with a 20in zone: §3.1 quotes 0.425. Driven at a
      // second profile so a hardcoded ratio cannot pass.
      const small = ZoneProfile(bottomInches: 13, topInches: 33);
      expect(small.heightInches, closeTo(20, 1e-9));
      expect(small.axisScaleRatio, closeTo(0.425, 1e-9));
      expect(small.axisScaleRatio, isNot(closeTo(p.axisScaleRatio, 0.01)));
    });

    test('y_ground moves when the zone-height inputs change', () {
      const taller = ZoneProfile(bottomInches: 20, topInches: 50);
      expect(taller.groundY, closeTo(-20 / 30, 1e-12));
      expect(taller.groundY, isNot(closeTo(p.groundY, 0.01)));
    });
  });

  group('GroundCamera — coupled constraints', () {
    test('default camera renders the plate at 0.215 with 3.7% splay', () {
      const c = GroundCamera.defaultCamera;
      expect(c.plateDepthRatio, closeTo(48 / (240 - 17), 1e-12));
      expect(c.plateDepthRatio, closeTo(0.215, 0.0005));
      expect((c.nearCornerSplay - 1) * 100, closeTo(3.7, 0.05));
      expect(c.isValid, isTrue);
    });

    test('the ratio uses d - 17in, not d + 17in (the sign error to watch)', () {
      const c = GroundCamera.defaultCamera;
      expect(c.plateDepthRatio, greaterThan(48 / (240 + 17)));
      expect(c.plateDepthRatio, isNot(closeTo(0.187, 0.01)));
    });

    test('ratio band bounds d at H = 4ft: legal in [17.4ft, 28.1ft]', () {
      // 0.25 = 48/(d-17) => d = 209in = 17.42ft; 0.15 => d = 337in = 28.08ft.
      expect(
        const GroundCamera(heightInches: 48, distanceInches: 209).isValid,
        isTrue,
      );
      expect(
        const GroundCamera(heightInches: 48, distanceInches: 337).isValid,
        isTrue,
      );
      expect(
        const GroundCamera(heightInches: 48, distanceInches: 208).isValid,
        isFalse,
      );
      expect(
        const GroundCamera(heightInches: 48, distanceInches: 338).isValid,
        isFalse,
      );
    });

    test('d = 15ft passes splay but fails the ratio band — 0.294', () {
      const c = GroundCamera(heightInches: 48, distanceInches: 180);
      expect((c.nearCornerSplay - 1) * 100, lessThanOrEqualTo(5));
      expect(c.plateDepthRatio, closeTo(0.294, 0.0005));
      expect(c.isValid, isFalse);
      expect(c.violations.single, contains('plate depth ratio'));
    });

    test('splay alone rejects a camera too close in', () {
      // d = 10ft: splay 7.6%, and the ratio is far out of band too.
      const c = GroundCamera(heightInches: 48, distanceInches: 120);
      expect(c.nearCornerSplay, greaterThan(GroundCamera.maxNearCornerSplay));
      expect(c.violations.length, 2);
    });
  });

  group('FrontalGeometry — the projection', () {
    const g = FrontalGeometry();

    test('horizon sits at eye height mapped through the height axis', () {
      expect(g.horizonY, closeTo(g.groundY + 48 / 24, 1e-12));
      expect(g.horizonY, closeTo((48 - 15.5) / 24, 1e-12));
      expect(g.horizonY, closeTo(1.354167, 1e-5));
      // Inside the canvas and above the zone rect — never drawn (§11.4).
      expect(g.horizonY, greaterThan(zoneMaxY));
      expect(g.horizonY, lessThan(zoneCanvasExtentMaxY));
    });

    test('ground at u = d lands exactly on y_ground', () {
      expect(g.groundYAt(g.camera.distanceInches), closeTo(g.groundY, 1e-12));
    });

    test(
      'the front-edge identity holds across cameras, independent of H and d',
      () {
        // The test that distinguishes a real projection from a ratio applied by
        // hand: a single-camera assertion would pass either way.
        const cameras = [
          GroundCamera.defaultCamera, // 4ft / 20ft -> 0.215
          GroundCamera(heightInches: 36, distanceInches: 216), // 3ft/18ft 0.181
          GroundCamera(heightInches: 60, distanceInches: 300),
        ];
        for (final camera in cameras) {
          expect(camera.isValid, isTrue, reason: '$camera should be legal');
          final geo = FrontalGeometry(camera: camera);
          expect(
            geo.groundYAt(camera.distanceInches),
            closeTo(geo.groundY, 1e-12),
            reason: 'front edge must land on y_ground for every camera',
          );
        }
      },
    );

    test('second test camera (3ft, 18ft) renders at 0.181 and is legal', () {
      const c = GroundCamera(heightInches: 36, distanceInches: 216);
      expect(c.plateDepthRatio, closeTo(0.181, 0.0005));
      expect(c.isValid, isTrue);
    });

    test('plate point lands at y = -0.798, two ways', () {
      final viaDepth = g.groundY - g.plateOnScreenDepthYUnits;
      final viaProjection = g.groundYAt(
        g.camera.distanceInches - plateDepthInches,
      );
      // Ratio-times-scale and the projection itself must agree; if they ever
      // diverge, the plate is being drawn by something other than the camera.
      expect(viaDepth, closeTo(viaProjection, 1e-6));
      expect(viaProjection, closeTo(-0.798, 0.0005));
    });

    test('plate on-screen depth is 0.152 y-units', () {
      // 816/5352 = 0.15247. Computed, not copied: the spec quoted 0.153, which
      // is a rounding slip — 0.215 x (17/24) is 0.15229 and the exact value is
      // 0.15247, both of which round to 0.152.
      expect(
        g.plateOnScreenDepthYUnits,
        closeTo((48 / 223) * (plateWidthInches / 24), 1e-12),
      );
      expect(g.plateOnScreenDepthYUnits, closeTo(0.152, 0.0005));
    });

    test('x = ±1 maps to the plate 17in edge; near corners splay wider', () {
      final d = g.camera.distanceInches;
      expect(g.xUnitsAt(plateHalfWidthInches, d), closeTo(1, 1e-12));
      expect(g.xUnitsAt(-plateHalfWidthInches, d), closeTo(-1, 1e-12));

      // Registration is asserted against the 17in edge, never the widest
      // visible point: the shoulders are 8.5in nearer and project wider.
      final shoulderX = g.xUnitsAt(plateHalfWidthInches, d - plateSideInches);
      expect(shoulderX, greaterThan(1));
      expect(shoulderX, closeTo(g.camera.nearCornerSplay, 1e-9));
      expect(shoulderX, closeTo(1.037, 0.0005));
    });

    test('ground projection is invertible but only used for drawing', () {
      for (final u in [200.0, 240.0, 300.0, 480.0]) {
        expect(g.groundDistanceAtY(g.groundYAt(u)), closeTo(u, 1e-6));
      }
      // §11.4's worked example for why the frontal plane never reads depth:
      // y = -0.40 is simultaneously ground 2.8ft out front and a pitch 5.9in
      // off the dirt as it crosses the plate.
      final u = g.groundDistanceAtY(-0.40);
      expect((u - g.camera.distanceInches) / 12, closeTo(2.8, 0.05));
      final apparentHeight =
          g.profile.bottomInches + (-0.40 * g.profile.heightInches);
      expect(apparentHeight, closeTo(5.9, 0.05));
    });

    test('scenery projects above the ground line and compresses', () {
      double atFeet(double ft) =>
          g.groundYAt(g.camera.distanceInches + ft * 12);
      expect(atFeet(1), closeTo(-0.55, 0.005));
      expect(atFeet(2), closeTo(-0.46, 0.005));
      expect(atFeet(5), closeTo(-0.25, 0.005));
      // All above the ground line: drawn ground spans it (§11.4 v0.31).
      expect(atFeet(1), greaterThan(g.groundY));
    });

    test('ground fade is full below the line and neutral by the fade end', () {
      expect(g.groundFadeAt(g.groundY), 1);
      expect(g.groundFadeAt(g.groundY - 0.3), 1);
      expect(g.groundFadeAt(FrontalGeometry.groundFadeEndY), 0);
      expect(g.groundFadeAt(0), 0);
      final mid = g.groundFadeAt(
        (g.groundY + FrontalGeometry.groundFadeEndY) / 2,
      );
      expect(mid, closeTo(0.5, 1e-9));
      // Neutral before it sits behind the zone rect (§11.4).
      expect(FrontalGeometry.groundFadeEndY, lessThan(zoneMinY));
    });
  });

  group('Batter box chalk', () {
    const g = FrontalGeometry();

    test('inner and outer chalk edges fall at 1.706 and 2.059', () {
      expect(BatterBoxSpec.innerChalkXUnits, closeTo(14.5 / 8.5, 1e-12));
      expect(BatterBoxSpec.innerChalkXUnits, closeTo(1.706, 0.0005));
      expect(BatterBoxSpec.outerChalkXUnits, closeTo(2.059, 0.0005));
      // At ±4.0 both chalk edges sit comfortably on-canvas at plate depth: the
      // lateral range now contains where the batter stands rather than merely
      // reaching the chalk, so the band no longer clips into a wedge.
      expect(BatterBoxSpec.outerChalkXUnits, lessThan(zoneCanvasExtentMaxX));
    });

    test('box dimensions come from the RuleSet spec, not a sport branch', () {
      expect(BatterBoxSpec.fastpitch.widthInches, 36);
      expect(BatterBoxSpec.fastpitch.foreInches, 48);
      expect(BatterBoxSpec.baseball.widthInches, 48);
      expect(BatterBoxSpec.baseball.foreInches, 36);
      // Both codes measure the 6in gap to the chalk's inner edge, so the inner
      // line lands identically; what differs is width and how far it runs.
      expect(BatterBoxSpec.offsetInches, 6);
      expect(BatterBoxSpec.chalkWidthInches, 3);
    });

    test('the lateral clip no longer bounds the box; the bottom does', () {
      const box = BatterBoxSpec.fastpitch;
      final backU = g.plateCenterU - box.aftInches;

      // At ±4.0 the inner edge is on-canvas from u = 0.426 d — far nearer than
      // the box's own back line, so the whole line is laterally on-canvas and
      // the wedge-shaped clip at ±1.9 is gone.
      expect(
        g.innerChalkOnCanvasU / g.camera.distanceInches,
        closeTo(0.426, 0.0005),
      );
      expect(g.innerChalkOnCanvasU, lessThan(backU));
      expect(
        g.xUnitsAt(14.5, g.innerChalkOnCanvasU),
        closeTo(zoneCanvasExtentMaxX, 1e-9),
      );

      // What bounds the near end now is the canvas bottom.
      final bottomU = g.groundDistanceAtY(zoneCanvasExtentMinY);
      expect(bottomU, closeTo(199.65, 0.05));
      expect(bottomU, greaterThan(g.innerChalkOnCanvasU));
    });

    test('visible inner line spans y -1.05 to -0.363, ~80in of 84in', () {
      const box = BatterBoxSpec.fastpitch;
      final frontU = g.plateCenterU + box.foreInches;
      final backU = g.plateCenterU - box.aftInches;
      expect(frontU, closeTo(279.5, 1e-9));
      expect(backU, closeTo(195.5, 1e-9));
      expect(frontU - backU, closeTo(84, 1e-9));

      // Visible run: whichever bound bites first — lateral clip or the canvas
      // bottom — up to the front line. At ±4.0 that is the canvas bottom.
      final visibleFrom = [
        g.innerChalkOnCanvasU,
        g.groundDistanceAtY(zoneCanvasExtentMinY),
        backU,
      ].reduce((a, b) => a > b ? a : b);
      expect(visibleFrom, closeTo(199.65, 0.05));
      expect(frontU - visibleFrom, closeTo(80, 0.5));
      expect(g.groundYAt(visibleFrom), closeTo(zoneCanvasExtentMinY, 1e-6));
      expect(g.groundYAt(frontU), closeTo(-0.363, 0.0005));

      // The visible run crosses the ground line: part dirt, part scenery.
      expect(g.groundYAt(visibleFrom), lessThan(g.groundY));
      expect(g.groundYAt(frontU), greaterThan(g.groundY));
    });

    test('front line shows ~25in of its 36in run before leaving frame', () {
      const box = BatterBoxSpec.fastpitch;
      final frontU = g.plateCenterU + box.foreInches;
      const innerEdge = plateHalfWidthInches + BatterBoxSpec.offsetInches;

      // World lateral offset that sits on the frame edge at the front line's
      // depth: solve xUnitsAt(X, frontU) == maxX.
      final frameEdgeInches =
          zoneCanvasExtentMaxX *
          plateHalfWidthInches *
          frontU /
          g.camera.distanceInches;
      expect(
        g.xUnitsAt(frameEdgeInches, frontU),
        closeTo(zoneCanvasExtentMaxX, 1e-9),
      );
      expect(frameEdgeInches - innerEdge, closeTo(25.1, 0.05));

      // Still short of the full width, so the box reads as receding out of
      // frame rather than as a closed rectangle.
      expect(frameEdgeInches - innerEdge, lessThan(box.widthInches));
    });
  });

  group('Canvas extents', () {
    test('at 12U the canvas covers 68in x 61.2in, ~1.11 : 1', () {
      const g = FrontalGeometry();
      expect(g.aspectRatio, closeTo(1.111, 0.0005));

      const widthInches =
          (zoneCanvasExtentMaxX - zoneCanvasExtentMinX) * plateHalfWidthInches;
      final heightInches =
          (zoneCanvasExtentMaxY - zoneCanvasExtentMinY) *
          g.profile.heightInches;
      expect(widthInches, closeTo(68, 0.05));
      expect(heightInches, closeTo(61.2, 0.05));
    });

    test('width-constrained, zone tap size follows lateral extent only', () {
      // The invariant behind both frame decisions. In the side-by-side layout
      // with the call grid the canvas is width-constrained, and then the zone's
      // on-screen size is fixed by the lateral extent and the 17in/24in world
      // ratio — the vertical extent does not enter. So widening laterally is
      // what costs (or buys) tap precision, and trimming the top is free.
      const panelWidth = 700.0;
      const zoneWidthPx =
          panelWidth *
          (zoneMaxX - zoneMinX) /
          (zoneCanvasExtentMaxX - zoneCanvasExtentMinX);
      final zoneHeightPx =
          zoneWidthPx *
          ZoneProfile.canonical12U.heightInches /
          plateWidthInches;
      expect(zoneWidthPx, closeTo(175, 0.5));
      expect(zoneHeightPx, closeTo(247, 0.5));

      // Same zone, shorter panel: trimming the top spends canvas height, not
      // tap targets.
      const g = FrontalGeometry();
      expect(panelWidth / g.aspectRatio, closeTo(630, 1));
    });

    test('a shorter zone changes the aspect ratio', () {
      const small = FrontalGeometry(
        profile: ZoneProfile(bottomInches: 13, topInches: 33),
      );
      const canonical = FrontalGeometry();
      expect(small.aspectRatio, greaterThan(canonical.aspectRatio));
    });

    test('vertical range leaves a tappable margin below the plate point', () {
      const g = FrontalGeometry();
      final platePoint = g.groundY - g.plateOnScreenDepthYUnits;
      expect(platePoint, greaterThan(zoneCanvasExtentMinY));
      final marginInches =
          (platePoint - zoneCanvasExtentMinY) * g.profile.heightInches;
      expect(marginInches, greaterThan(5));
    });
  });
}
