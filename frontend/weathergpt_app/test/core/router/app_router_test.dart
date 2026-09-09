import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/router/app_router.dart';

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

  testWidgets('navigating to /gallery shows the component gallery', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pumpAndSettle();

    appRouter.go('/gallery');
    // Not pumpAndSettle(): GalleryScreen's States section renders a
    // LoadingView, whose CircularProgressIndicator animates indefinitely
    // and would make pumpAndSettle time out waiting for animations to
    // finish. A single pump is enough to build the new route.
    await tester.pump();

    expect(find.text('Component gallery'), findsOneWidget);
  });
}
