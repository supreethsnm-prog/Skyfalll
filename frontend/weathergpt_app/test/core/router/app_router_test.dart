import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/router/app_router.dart';
import 'package:weathergpt_app/features/gallery/gallery_screen.dart';

void main() {
  // appRouter is a top-level singleton shared across every test file that
  // imports it. Reset navigation state before each test so these two
  // tests (and any future ones) are order-independent rather than relying
  // on whatever route the previous test left the router on.
  setUp(() {
    appRouter.go('/home');
  });

  testWidgets('starts at Home and shows the bottom nav bar', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pumpAndSettle();

    expect(find.text('Home — coming soon'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('navigating to /gallery shows the component gallery',
      (tester) async {
    // Was asserting a placeholder until Task 6 built the real gallery.
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pumpAndSettle();

    appRouter.go('/gallery');
    await tester.pumpAndSettle();

    expect(find.byType(GalleryScreen), findsOneWidget);
    expect(find.text('Gallery — coming soon'), findsNothing);
  });
}
