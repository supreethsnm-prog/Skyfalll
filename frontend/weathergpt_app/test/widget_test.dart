import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/router/app_router.dart';
import 'package:weathergpt_app/features/home/home_screen.dart';
import 'package:weathergpt_app/main.dart';

import 'support/fake_apis.dart';

void main() {
  setUp(() => appRouter.go('/home'));

  testWidgets('WeatherGptApp boots straight to Home', (tester) async {
    // Was asserting the "Home — coming soon" placeholder; Home is now a
    // real screen and the app opens on it, with no tab shell in between.
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeApiOverrides,
        child: const WeatherGptApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Home — coming soon'), findsNothing);
  });
}
