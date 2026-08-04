/// Monotone cubic interpolation (Fritsch–Carlson) for the fence model
/// (spec §16.2): a smooth curve through the five fence poles that never
/// overshoots them.
///
/// Generic over (x, y) knots because the math doesn't care that x is a
/// bearing and y a distance — the field profile owns that meaning. Monotone
/// here means *shape-preserving between knots*: where the data rises the
/// curve rises, where it falls the curve falls, and it never swings outside
/// the knot values the way a natural cubic would. The fence data itself is
/// not monotone end to end (line → center rises, center → line falls), which
/// this handles per segment.
library;

import 'dart:math' as math;

class MonotoneCubicSpline {
  /// Knots must be sorted by strictly increasing x. Asserted, not repaired:
  /// the caller (a `FieldProfile`) constructs them in pole order by design.
  MonotoneCubicSpline(List<double> xs, List<double> ys)
    : assert(xs.length == ys.length, 'xs and ys must pair up'),
      assert(xs.length >= 2, 'a curve needs at least two knots'),
      assert(
        _strictlyIncreasing(xs),
        'knot x values must be strictly increasing',
      ),
      _xs = xs,
      _ys = ys,
      _tangents = List.filled(xs.length, 0) {
    final n = _xs.length;
    final deltas = List<double>.generate(
      n - 1,
      (k) => (_ys[k + 1] - _ys[k]) / (_xs[k + 1] - _xs[k]),
    );

    // One-sided tangents at the ends; averaged interior tangents, zeroed at
    // local extrema so the curve turns exactly at a knot (the CF pole peaks
    // at CF, not somewhere in the gap).
    _tangents[0] = deltas[0];
    _tangents[n - 1] = deltas[n - 2];
    for (var k = 1; k < n - 1; k++) {
      _tangents[k] = deltas[k - 1].sign == deltas[k].sign
          ? (deltas[k - 1] + deltas[k]) / 2
          : 0;
    }

    // Fritsch–Carlson limiter: cap tangents so no segment overshoots its
    // knots. α² + β² ≤ 9 is the classic sufficient condition.
    for (var k = 0; k < n - 1; k++) {
      if (deltas[k] == 0) {
        _tangents[k] = 0;
        _tangents[k + 1] = 0;
        continue;
      }
      final alpha = _tangents[k] / deltas[k];
      final beta = _tangents[k + 1] / deltas[k];
      final s = alpha * alpha + beta * beta;
      if (s > 9) {
        final tau = 3 / math.sqrt(s);
        _tangents[k] = tau * alpha * deltas[k];
        _tangents[k + 1] = tau * beta * deltas[k];
      }
    }
  }

  final List<double> _xs;
  final List<double> _ys;
  final List<double> _tangents;

  static bool _strictlyIncreasing(List<double> xs) {
    for (var i = 1; i < xs.length; i++) {
      if (xs[i] <= xs[i - 1]) return false;
    }
    return true;
  }

  double get minX => _xs.first;
  double get maxX => _xs.last;

  /// Evaluates the spline at [x], clamped to the knot range — the fence
  /// doesn't extend past the foul poles, so a bearing beyond them reads as
  /// the pole itself (render edges, warning track). Fair/foul is the
  /// caller's question, answered from the bearing, never from this.
  double at(double x) {
    if (x <= _xs.first) return _ys.first;
    if (x >= _xs.last) return _ys.last;

    // Binary search for the segment with xs[k] <= x < xs[k+1].
    var lo = 0;
    var hi = _xs.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (_xs[mid] <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final h = _xs[lo + 1] - _xs[lo];
    final t = (x - _xs[lo]) / h;
    final t2 = t * t;
    final t3 = t2 * t;
    // Cubic Hermite basis.
    final h00 = 2 * t3 - 3 * t2 + 1;
    final h10 = t3 - 2 * t2 + t;
    final h01 = -2 * t3 + 3 * t2;
    final h11 = t3 - t2;
    return h00 * _ys[lo] +
        h10 * h * _tangents[lo] +
        h01 * _ys[lo + 1] +
        h11 * h * _tangents[lo + 1];
  }
}
