import 'package:flutter/material.dart';

/// Diamond's mark: a chalk baseline diamond with a clay home plate at its near
/// vertex (Claude Design, Turn 03). Two shapes, which is why it survives at
/// 40px — it is a lockup, not a scene.
///
/// **Drawn rather than loaded.** The same art also ships as PNG for the
/// launcher icon and the native splash, because those are rasters the OS reads
/// before Dart runs (`tools/brand/make_marks.py`). In the app itself a painter
/// is better: it re-colors with the theme instead of needing one file per
/// brightness, it stays sharp at any size, and it loads synchronously — an
/// `Image.asset` does not, which makes it invisible in a widget test unless
/// every caller remembers to precache it.
///
/// **The ratios below and the ones in `make_marks.py` are the same numbers and
/// have to stay that way**, or the native splash will jump when this replaces
/// it. They are the design's 104px lockup: a 44px square with a 5px border,
/// and an 11px plate whose top sits at 78px.
class DiamondMark extends StatelessWidget {
  const DiamondMark({
    required this.size,
    required this.line,
    required this.plate,
    super.key,
  });

  /// The chalk baseline — Grass on light, Grass&nbsp;lit on dark (§23.3's "as
  /// line" rule).
  final Color line;

  /// The plate. Clay in both themes: it is the only saturated element at small
  /// size, and it is what makes the mark findable in a folder.
  final Color plate;

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _MarkPainter(line: line, plate: plate),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.line, required this.plate});

  final Color line;
  final Color plate;

  static const double _square = 44 / 104;
  static const double _border = 5 / 104;
  static const double _plate = 11 / 104;
  static const double _plateTop = 78 / 104;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);

    // A square rotated 45 degrees is a diamond whose half-diagonal is
    // side * sqrt(2) / 2. Built as two paths rather than a stroked rotated
    // square: a stroke miters its corners outward, which fattens the vertices
    // exactly where the plate meets them.
    Path diamond(double half) => Path()
      ..moveTo(c.dx - half, c.dy)
      ..lineTo(c.dx, c.dy - half)
      ..lineTo(c.dx + half, c.dy)
      ..lineTo(c.dx, c.dy + half)
      ..close();

    const root2Over2 = 0.7071067811865476;
    final outer = _square * d * root2Over2;
    final inner = (_square - 2 * _border) * d * root2Over2;

    canvas.drawPath(
      Path.combine(PathOperation.difference, diamond(outer), diamond(inner)),
      Paint()..color = line,
    );

    final p = _plate * d;
    final top = _plateTop * d;
    final left = c.dx - p / 2;
    // The plate's shoulders sit at 45% of its height, then it comes to a
    // point — the same polygon the design clips its plate with.
    canvas.drawPath(
      Path()
        ..moveTo(left, top)
        ..lineTo(left + p, top)
        ..lineTo(left + p, top + 0.45 * p)
        ..lineTo(c.dx, top + p)
        ..lineTo(left, top + 0.45 * p)
        ..close(),
      Paint()..color = plate,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.line != line || old.plate != plate;
}
