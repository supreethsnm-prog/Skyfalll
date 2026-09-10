import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/core/theme/app_radius.dart';
import 'package:weathergpt_app/features/chat/widgets/user_bubble.dart';

void main() {
  testWidgets('renders its text in a userBubble-filled rounded container', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UserBubble(text: 'hello'))),
    );

    expect(find.text('hello'), findsOneWidget);

    final decorated = tester.widgetList<Container>(find.byType(Container))
        .firstWhere((c) => c.decoration is BoxDecoration);
    final decoration = decorated.decoration as BoxDecoration;
    expect(decoration.color, AppColors.userBubble);

    // The 18dp radius is one of the values measured off the reference,
    // and nothing asserted it — a square bubble passed this test.
    expect(decoration.borderRadius, BorderRadius.circular(AppRadius.bubble));
  });

  testWidgets('is right-aligned', (tester) async {
    // Nothing pinned this either: flipping the bubble to the left, which
    // would put it where assistant prose lives and destroy the whole
    // user/assistant asymmetry, passed every other test in this file.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UserBubble(text: 'hi'))),
    );

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final bubble = tester.getRect(
      find.byType(Container).first,
    );

    expect(bubble.center.dx, greaterThan(screenWidth / 2),
        reason: 'user turns sit on the right; assistant prose is left');
  });

  testWidgets('never exceeds 72% of the available width', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserBubble(
            text: 'a very long message that would otherwise span the entire '
                'width of the screen if it were not constrained by the '
                'bubble max width rule from the design spec',
          ),
        ),
      ),
    );

    final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final decorated = find.byType(Container).first;
    final width = tester.getSize(decorated).width;

    expect(width, lessThanOrEqualTo(screenWidth * 0.72 + 1));

    // Bounded below as well. A one-sided cap was satisfied by ANY
    // smaller factor — 0.5, or 0.1 — so the specific 72% measured off
    // the reference was not actually pinned by anything. Text this long
    // is guaranteed to hit the cap, so the bubble should sit right at it.
    expect(width, greaterThanOrEqualTo(screenWidth * 0.72 - 1),
        reason: 'a long message should reach the 72% cap, not fall short');
  });
}
