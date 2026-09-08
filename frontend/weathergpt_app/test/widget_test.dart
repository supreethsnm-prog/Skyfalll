import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/main.dart';

void main() {
  testWidgets('WeatherGptApp renders without crashing', (tester) async {
    await tester.pumpWidget(const WeatherGptApp());
    expect(find.text('WeatherGPT'), findsOneWidget);
  });
}
