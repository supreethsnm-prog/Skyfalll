import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/main.dart';

void main() {
  testWidgets('WeatherGptApp boots to the Home tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: WeatherGptApp()));
    await tester.pumpAndSettle();

    expect(find.text('Home — coming soon'), findsOneWidget);
  });
}
