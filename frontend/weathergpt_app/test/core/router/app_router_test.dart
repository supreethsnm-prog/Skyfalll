import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/router/app_router.dart';
import 'package:weathergpt_app/features/advisory/advisory_screen.dart';
import 'package:weathergpt_app/features/chat/chat_screen.dart';
import 'package:weathergpt_app/features/gallery/gallery_screen.dart';
import 'package:weathergpt_app/features/home/home_screen.dart';
import 'package:weathergpt_app/features/shell/app_drawer.dart';

import '../../support/fake_apis.dart';

void main() {
  // appRouter is a top-level singleton shared across every test file that
  // imports it, so navigation state is reset before each test rather than
  // relying on execution order.
  setUp(() => appRouter.go('/home'));

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeApiOverrides,
        child: MaterialApp.router(routerConfig: appRouter),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts at Home', (tester) async {
    await pumpApp(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('has no bottom navigation bar anywhere', (tester) async {
    // The four-tab NavigationBar was the single biggest reason the first
    // build read as a generic Android app. This assertion is inverted on
    // purpose — it is what stops the tab bar coming back.
    await pumpApp(tester);
    expect(find.byType(NavigationBar), findsNothing);

    appRouter.go('/chat');
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Home reaches navigation through the drawer', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Open menu'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDrawer), findsOneWidget);
    expect(find.text('WeatherGPT'), findsOneWidget);
  });

  testWidgets('navigating to /chat shows the chat screen', (tester) async {
    await pumpApp(tester);

    appRouter.go('/chat');
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('navigating to /gallery shows the component gallery',
      (tester) async {
    await pumpApp(tester);

    appRouter.go('/gallery');
    await tester.pumpAndSettle();

    expect(find.byType(GalleryScreen), findsOneWidget);
    expect(find.text('Gallery — coming soon'), findsNothing);
  });

  testWidgets('navigating to /advisories shows the advisory screen',
      (tester) async {
    // Home loads first (pumpApp lands on /home and settles), so by the
    // time this navigates, homeControllerProvider already has a location
    // for Advisories to read.
    await pumpApp(tester);

    appRouter.go('/advisories');
    await tester.pumpAndSettle();

    expect(find.byType(AdvisoryScreen), findsOneWidget);
  });
}
