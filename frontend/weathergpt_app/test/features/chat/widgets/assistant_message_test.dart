import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/features/chat/widgets/assistant_message.dart';

void main() {
  testWidgets('renders prose with no bubble container behind it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AssistantMessage(text: 'It is sunny.'))),
    );

    expect(find.text('It is sunny.'), findsOneWidget);

    final decoratedContainers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration != null);
    expect(decoratedContainers, isEmpty,
        reason: 'assistant turns are flat prose, never boxed');
  });

  testWidgets('shows the action row and fires each callback', (tester) async {
    var copied = false, readAloud = false, shared = false, more = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantMessage(
            text: 'reply',
            onCopy: () => copied = true,
            onReadAloud: () => readAloud = true,
            onShare: () => shared = true,
            onMore: () => more = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();

    expect([copied, readAloud, shared, more], everyElement(isTrue));
  });

  testWidgets('hides the action row when no callbacks are supplied', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AssistantMessage(text: 'reply'))),
    );

    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });
}
