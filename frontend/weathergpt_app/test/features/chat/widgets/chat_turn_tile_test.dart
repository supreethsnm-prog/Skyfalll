import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/features/chat/widgets/chat_turn_tile.dart';

void main() {
  testWidgets('renders the turn\'s content text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatTurnTile(turn: ChatTurn(role: 'assistant', content: 'Sunny today')),
        ),
      ),
    );
    expect(find.text('Sunny today'), findsOneWidget);
  });

  testWidgets('gives a user turn a decorated Container background, unlike an assistant turn', (tester) async {
    // Pumped and scoped separately (rather than both tiles in one tree and
    // asserting "some Container somewhere has a decoration") so this test
    // actually catches isUser's branch being accidentally inverted — a
    // combined-tree assertion would still pass if the assistant tile got
    // the bubble and the user tile didn't.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatTurnTile(turn: ChatTurn(role: 'user', content: 'Hi')),
        ),
      ),
    );
    final userContainers = tester.widgetList<Container>(find.byType(Container));
    expect(
      userContainers.any((c) => c.decoration != null),
      isTrue,
      reason: 'user turn should have a decorated background container',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatTurnTile(turn: ChatTurn(role: 'assistant', content: 'Hello')),
        ),
      ),
    );
    final assistantContainers = tester.widgetList<Container>(find.byType(Container));
    expect(
      assistantContainers.any((c) => c.decoration != null),
      isFalse,
      reason: 'assistant turn should render as flat text with no decorated background container',
    );
  });
}
