import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';

/// Implements only the public interface ChatApi exposes — its private
/// Dio field is not part of that interface, so no real Dio is needed.
class FakeChatApi implements ChatApi {
  ChatResult? nextResult;
  AppError? nextError;
  final List<String> messagesSent = [];
  final List<List<dynamic>?> historiesSent = [];

  @override
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) async {
    messagesSent.add(message);
    historiesSent.add(history);
    if (nextError != null) throw nextError!;
    return nextResult!;
  }
}

class _NoStore implements ConversationStore {
  @override
  Future<List<Conversation>> load() async => const [];

  @override
  Future<void> save(List<Conversation> next) async {}
}

void main() {
  late FakeChatApi fakeApi;
  late ProviderContainer container;

  setUp(() {
    fakeApi = FakeChatApi();
    container = ProviderContainer(
      overrides: [
        chatApiProvider.overrideWithValue(fakeApi),
        // A completed turn is now persisted; without this the controller
        // reaches for shared_preferences, which has no implementation in
        // a plain Dart test.
        conversationStoreProvider.overrideWithValue(_NoStore()),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('starts idle with no messages', () {
    final state = container.read(chatControllerProvider);
    expect(state, isA<ChatIdle>());
    expect(state.messages, isEmpty);
  });

  test('sendMessage appends an optimistic user turn immediately, before the response arrives', () async {
    fakeApi.nextResult = const ChatResult(reply: 'placeholder', history: []);
    final future = container.read(chatControllerProvider.notifier).sendMessage('Hi');

    final sendingState = container.read(chatControllerProvider);
    expect(sendingState, isA<ChatSending>());
    expect(sendingState.messages, hasLength(1));
    expect(sendingState.messages.single.role, 'user');
    expect(sendingState.messages.single.content, 'Hi');

    await future;
  });

  test('a successful response replaces state with the server\'s own filtered history', () async {
    fakeApi.nextResult = const ChatResult(
      reply: 'Sunny today',
      history: [
        {'role': 'user', 'content': 'Weather?'},
        {'role': 'tool', 'tool_call_id': 'x', 'name': 'get_weather', 'content': '{}'},
        {'role': 'assistant', 'content': 'Sunny today'},
      ],
    );

    await container.read(chatControllerProvider.notifier).sendMessage('Weather?');

    final state = container.read(chatControllerProvider);
    expect(state, isA<ChatIdle>());
    // The tool-role entry is present in the raw history but must not appear in the displayed messages.
    expect(state.messages, hasLength(2));
    expect(state.messages[0].role, 'user');
    expect(state.messages[1].role, 'assistant');
    expect(state.messages[1].content, 'Sunny today');
  });

  test('the second call sends the exact history returned by the first, unmodified', () async {
    final firstHistory = [
      {'role': 'user', 'content': 'Weather?'},
      {'role': 'assistant', 'content': 'Sunny'},
    ];
    fakeApi.nextResult = ChatResult(reply: 'Sunny', history: firstHistory);
    await container.read(chatControllerProvider.notifier).sendMessage('Weather?');

    fakeApi.nextResult = const ChatResult(reply: 'And tomorrow?', history: []);
    await container.read(chatControllerProvider.notifier).sendMessage('And tomorrow?');

    expect(fakeApi.historiesSent[0], isNull); // first turn in a fresh conversation
    expect(fakeApi.historiesSent[1], same(firstHistory)); // exact instance, not a rebuilt copy
  });

  test('a failed request preserves the optimistic user turn and surfaces the error', () async {
    fakeApi.nextError = const NetworkTimeoutError();

    await container.read(chatControllerProvider.notifier).sendMessage('Hi');

    final state = container.read(chatControllerProvider);
    expect(state, isA<ChatFailed>());
    expect(state.messages, hasLength(1));
    expect(state.messages.single.content, 'Hi');
    expect((state as ChatFailed).failedMessage, 'Hi');
    expect(state.error, isA<NetworkTimeoutError>());
  });

  test('retry re-issues the identical failed message and history', () async {
    fakeApi.nextError = const NetworkTimeoutError();
    await container.read(chatControllerProvider.notifier).sendMessage('Hi');

    fakeApi.nextError = null;
    fakeApi.nextResult = const ChatResult(
      reply: 'Hello!',
      history: [
        {'role': 'user', 'content': 'Hi'},
        {'role': 'assistant', 'content': 'Hello!'},
      ],
    );
    await container.read(chatControllerProvider.notifier).retry();

    expect(fakeApi.messagesSent, ['Hi', 'Hi']);
    expect(fakeApi.historiesSent, [null, null]); // both attempts are the first turn — no history existed yet
    final state = container.read(chatControllerProvider);
    expect(state, isA<ChatIdle>());
    expect(state.messages, hasLength(2));
  });
}
