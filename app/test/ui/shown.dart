import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the control under [key] is on screen.
///
/// A control that can't act is hidden but keeps its space (§23.1 v0.63), so
/// it is still in the tree; this reads the `Visibility` that hides it.
bool isShown(WidgetTester tester, Key key) {
  final hiding = find.ancestor(
    of: find.byKey(key),
    matching: find.byType(Visibility),
  );
  if (hiding.evaluate().isEmpty) return true;
  return tester.widgetList<Visibility>(hiding).every((v) => v.visible);
}
