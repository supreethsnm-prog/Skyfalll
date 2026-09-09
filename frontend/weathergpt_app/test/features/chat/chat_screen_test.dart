import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/chat_screen.dart';
import 'package:weathergpt_app/shared/widgets/app_chip.dart';

class FakeChatApi implements ChatApi {
  ChatResult? nextResult;

  @override
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) async {
    return nextResult ??
        ChatResult(
          reply: 'Echo: $message',
          history: [
            {'role': 'user', 'content': message},
            {'role': 'assistant', 'content': 'Echo: $message'},
          ],
        );
  }
}

void main() {
  testWidgets('shows a welcome and suggested chips when empty, then sends on chip tap', (tester) async {
    final fakeApi = FakeChatApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(fakeApi)],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );

    expect(
      find.text('Ask WeatherGPT about weather, alerts, or advisories anywhere in India.'),
      findsOneWidget,
    );
    expect(find.byType(AppChip), findsWidgets);

    await tester.tap(find.byType(AppChip).first);
    await tester.pump();

    // Tapping a suggestion starts a send — the empty-state welcome is
    // gone and the composer no longer shows placeholder emptiness; the
    // typing indicator or the optimistic user turn is now in the tree.
    expect(
      find.text('Ask WeatherGPT about weather, alerts, or advisories anywhere in India.'),
      findsNothing,
    );
  });

  testWidgets('renders a populated conversation with the composer', (tester) async {
    final fakeApi = FakeChatApi();
    final container = ProviderContainer(
      overrides: [chatApiProvider.overrideWithValue(fakeApi)],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.notifier).sendMessage('Weather in Pune?');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Weather in Pune?'), findsOneWidget);
    expect(find.text('Echo: Weather in Pune?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // composer still present
  });
}
