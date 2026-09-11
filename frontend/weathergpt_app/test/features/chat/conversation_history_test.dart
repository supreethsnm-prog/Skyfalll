import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';

/// Conversations survive a restart, and resuming one continues it rather
/// than starting over — which requires carrying the backend's opaque
/// `history` alongside the displayed turns, since that history cannot be
/// reconstructed from what is on screen.

class _FakeChatApi implements ChatApi {
  _FakeChatApi({this.fail = false});

  final bool fail;
  final sentHistories = <List<dynamic>?>[];

  @override
  Future<ChatResult> sendMessage(
    String message,
    List<dynamic>? history, {
    double? latitude,
    double? longitude,
    String? placeName,
  }) async {
    sentHistories.add(history);
    if (fail) throw const NetworkConnectionError();
    return ChatResult(
      reply: 'reply to $message',
      history: [
        ...?history,
        {'role': 'user', 'content': message},
        {'role': 'assistant', 'content': 'reply to $message'},
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _MemoryStore implements ConversationStore {
  _MemoryStore([this.conversations = const []]);

  List<Conversation> conversations;
  int saveCount = 0;

  @override
  Future<List<Conversation>> load() async => conversations;

  @override
  Future<void> save(List<Conversation> next) async {
    saveCount++;
    conversations = next;
  }
}

ProviderContainer _container(_FakeChatApi api, _MemoryStore store) {
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      conversationStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  container.read(conversationsProvider);
  return container;
}

void main() {
  test('a completed turn is saved', () async {
    final store = _MemoryStore();
    final container = _container(_FakeChatApi(), store);

    await container
        .read(chatControllerProvider.notifier)
        .sendMessage('Will it rain in Pune?');

    final saved = container.read(conversationsProvider);
    expect(saved, hasLength(1));
    expect(saved.single.messages.first.content, 'Will it rain in Pune?');
  });

  test('a failed send is NOT saved', () async {
    // Persisting a failure would store a history the backend never
    // acknowledged, and resuming it would send nonsense back.
    final store = _MemoryStore();
    final container = _container(_FakeChatApi(fail: true), store);

    await container.read(chatControllerProvider.notifier).sendMessage('hi');

    expect(container.read(conversationsProvider), isEmpty);
    expect(store.saveCount, 0);
  });

  test('further turns update the same conversation, not new ones', () async {
    final store = _MemoryStore();
    final container = _container(_FakeChatApi(), store);
    final chat = container.read(chatControllerProvider.notifier);

    await chat.sendMessage('first');
    await chat.sendMessage('second');

    // One conversation with both turns, not two conversations.
    expect(container.read(conversationsProvider), hasLength(1));
  });

  test('the sidebar title is the first thing the user asked', () async {
    final store = _MemoryStore();
    final container = _container(_FakeChatApi(), store);
    final chat = container.read(chatControllerProvider.notifier);

    await chat.sendMessage('Cyclone risk on the Odisha coast');
    await chat.sendMessage('and tomorrow?');

    expect(
      container.read(conversationsProvider).single.title,
      'Cyclone risk on the Odisha coast',
    );
  });

  test('a long title is truncated on a word boundary', () async {
    final store = _MemoryStore();
    final container = _container(_FakeChatApi(), store);

    await container.read(chatControllerProvider.notifier).sendMessage(
          'Will there be heavy rainfall across the Konkan coast this weekend',
        );

    final title = container.read(conversationsProvider).single.title;
    expect(title.length, lessThanOrEqualTo(40));
    expect(title, endsWith('…'));
    // A hard mid-word cut reads like a bug rather than a summary.
    expect(title, isNot(contains('  ')));
    expect(title.replaceAll('…', '').trim(), isNot(endsWith('t')));
  });

  test('startNew clears the screen without deleting the saved one',
      () async {
    final store = _MemoryStore();
    final container = _container(_FakeChatApi(), store);
    final chat = container.read(chatControllerProvider.notifier);

    await chat.sendMessage('first conversation');
    chat.startNew();

    expect(container.read(chatControllerProvider).messages, isEmpty);
    expect(container.read(conversationsProvider), hasLength(1));
  });

  test('a new conversation after startNew is saved separately', () async {
    final store = _MemoryStore();
    final container = _container(_FakeChatApi(), store);
    final chat = container.read(chatControllerProvider.notifier);

    await chat.sendMessage('first');
    chat.startNew();
    await chat.sendMessage('second');

    expect(container.read(conversationsProvider), hasLength(2));
  });

  test('resuming restores the messages AND the opaque backend history',
      () async {
    // The history is the whole point: it carries the model's tool calls,
    // which the displayed turns deliberately filter out and so cannot
    // rebuild.
    final api = _FakeChatApi();
    final store = _MemoryStore();
    final container = _container(api, store);
    final chat = container.read(chatControllerProvider.notifier);

    await chat.sendMessage('first');
    final saved = container.read(conversationsProvider).single;

    chat.startNew();
    chat.resume(saved);

    expect(container.read(chatControllerProvider).messages, saved.messages);

    await chat.sendMessage('follow up');
    // The follow-up carried the resumed history rather than starting from
    // null, which is what makes it a continuation.
    expect(api.sentHistories.last, isNotNull);
    expect(api.sentHistories.last, saved.rawHistory);
  });

  test('restores conversations saved in a previous session', () async {
    final store = _MemoryStore([
      Conversation(
        id: 'old',
        messages: const [ChatTurn(role: 'user', content: 'yesterday')],
        updatedAt: DateTime(2026, 9, 9),
      ),
    ]);
    final container = _container(_FakeChatApi(), store);

    await Future<void>.delayed(Duration.zero);

    expect(container.read(conversationsProvider).single.title, 'yesterday');
  });

  test('the newest conversation is first', () async {
    final store = _MemoryStore();
    final container = _container(_FakeChatApi(), store);
    final chat = container.read(chatControllerProvider.notifier);

    await chat.sendMessage('older');
    chat.startNew();
    await chat.sendMessage('newer');

    expect(container.read(conversationsProvider).first.title, 'newer');
  });

  test('remove deletes a conversation and persists', () async {
    final store = _MemoryStore([
      Conversation(
        id: 'conv1',
        messages: const [ChatTurn(role: 'user', content: 'first')],
        updatedAt: DateTime(2026, 9, 9),
      ),
      Conversation(
        id: 'conv2',
        messages: const [ChatTurn(role: 'user', content: 'second')],
        updatedAt: DateTime(2026, 9, 10),
      ),
    ]);
    final container = _container(_FakeChatApi(), store);

    await Future<void>.delayed(Duration.zero);

    expect(container.read(conversationsProvider), hasLength(2));

    await container.read(conversationsProvider.notifier).remove('conv1');

    final remaining = container.read(conversationsProvider);
    expect(remaining, hasLength(1));
    expect(remaining.single.id, 'conv2');
    expect(store.saveCount, 1);
  });
}
