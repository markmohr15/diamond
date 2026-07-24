import 'package:diamond/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DiamondApp boots to the ZoneCanvas demo page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DiamondApp());

    expect(find.text('ZoneCanvas demo — DIA-005'), findsOneWidget);
  });
}
