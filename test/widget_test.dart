import 'package:flutter_test/flutter_test.dart';
import 'package:eidos/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EidosApp());
    expect(find.text('eidos'), findsOneWidget);
  });
}
