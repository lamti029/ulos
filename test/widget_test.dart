import 'package:flutter_test/flutter_test.dart';
import 'package:ulos/app.dart';

void main() {
  testWidgets('UlosApp builds SplashPage', (WidgetTester tester) async {
    await tester.pumpWidget(const UlosApp());
    expect(find.text('Ulos'), findsOneWidget);
  });
}
