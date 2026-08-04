import 'package:diamond/src/field/fence_spline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonotoneCubicSpline (§16.2)', () {
    // The 12U fence shape: rises to CF, falls back to the line.
    final xs = [-2.0, -1.0, 0.0, 1.0, 2.0];
    final ys = [190.0, 200.0, 210.0, 200.0, 190.0];
    final spline = MonotoneCubicSpline(xs, ys);

    test('passes through every knot', () {
      for (var i = 0; i < xs.length; i++) {
        expect(spline.at(xs[i]), closeTo(ys[i], 1e-9));
      }
    });

    test('never overshoots the knots — the whole point of Fritsch–Carlson', () {
      for (var i = 0; i <= 400; i++) {
        final x = -2 + i / 100;
        final y = spline.at(x);
        expect(y, greaterThanOrEqualTo(190 - 1e-9), reason: 'at x=$x');
        expect(y, lessThanOrEqualTo(210 + 1e-9), reason: 'at x=$x');
      }
    });

    test('is shape-preserving per segment: rising data, rising curve', () {
      var previous = spline.at(-2);
      for (var i = 1; i <= 200; i++) {
        final x = -2 + i / 100;
        final y = spline.at(x);
        expect(y, greaterThanOrEqualTo(previous - 1e-9), reason: 'at x=$x');
        previous = y;
      }
    });

    test('symmetric knots produce a symmetric curve', () {
      for (var i = 0; i <= 100; i++) {
        final x = i / 50; // 0..2
        expect(spline.at(x), closeTo(spline.at(-x), 1e-9));
      }
    });

    test('clamps beyond the knot range — the fence ends at the poles', () {
      expect(spline.at(-99), 190);
      expect(spline.at(99), 190);
    });

    test('rejects unsorted knots', () {
      expect(
        () => MonotoneCubicSpline([0, 1, 1], [1, 2, 3]),
        throwsAssertionError,
      );
    });
  });
}
