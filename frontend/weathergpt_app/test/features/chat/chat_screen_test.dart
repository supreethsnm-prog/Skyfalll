import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
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

// `chatControllerProvider` is a `NotifierProvider<ChatController, ChatUiState>`,
// so `overrideWith` requires a factory that returns a `ChatController`
// specifically — mirrors the seeding pattern in
// test/golden/chat_screen_golden_test.dart.
class _SeededChatController extends ChatController {
  final ChatUiState seed;
  _SeededChatController(this.seed);

  @override
  ChatUiState build() => seed;
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

  testWidgets('disables the composer while ChatFailed, forcing Retry as the only path out', (tester) async {
    final fakeApi = FakeChatApi();
    const failedState = ChatFailed(
      [ChatTurn(role: 'user', content: 'Weather in Pune?')],
      'Weather in Pune?',
      null,
      NetworkConnectionError(),
    );
    final container = ProviderContainer(
      overrides: [
        chatApiProvider.overrideWithValue(fakeApi),
        chatControllerProvider.overrideWith(() => _SeededChatController(failedState)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.enabled, isFalse);

    // Attempting to type into the disabled field must not reach the
    // controller — the message list stays exactly what it was at
    // failure (no new optimistic user turn appears), proving a new send
    // was not silently started from a stale _rawHistory.
    await tester.enterText(find.byType(TextField), 'Try again?');
    await tester.pump();

    expect(find.text('Try again?'), findsNothing);
    expect(container.read(chatControllerProvider), same(failedState));
  });
}
