import 'package:flutter_test/flutter_test.dart';
import 'package:inline_lyrics/main.dart';

void main() {
  testWidgets('Inline App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const InlineApp());
    expect(find.text('Inline'), findsOneWidget);
    expect(find.text('Launch Overlay'), findsOneWidget);
  });
}
