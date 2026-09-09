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
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ChatTurnTile(turn: ChatTurn(role: 'user', content: 'Hi')),
              ChatTurnTile(turn: ChatTurn(role: 'assistant', content: 'Hello')),
            ],
          ),
        ),
      ),
    );

    final userContainer = tester.widgetList<Container>(find.byType(Container));
    // The user turn's tile must contain at least one Container with a
    // non-null BoxDecoration (its background surface); the assistant
    // turn renders as flat text with no such decorated Container.
    expect(
      userContainer.any((c) => c.decoration != null),
      isTrue,
      reason: 'user turn should have a decorated background container',
    );
  });
}
