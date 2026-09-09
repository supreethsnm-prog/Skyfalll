import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
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
    expect(tester.getSize(decorated).width, lessThanOrEqualTo(screenWidth * 0.72 + 1));
  });
}
