import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../data/chat_api.dart';

sealed class ChatUiState {
  final List<ChatTurn> messages;
  const ChatUiState(this.messages);
}

class ChatIdle extends ChatUiState {
  const ChatIdle(super.messages);
}

class ChatSending extends ChatUiState {
  const ChatSending(super.messages);
}

class ChatFailed extends ChatUiState {
  final String failedMessage;
  final List<dynamic>? historyAtFailure;
  final AppError error;

  const ChatFailed(
    super.messages,
    this.failedMessage,
    this.historyAtFailure,
    this.error,
  );
}

final chatApiProvider = Provider<ChatApi>((ref) => ChatApi(buildApiClient()));

final chatControllerProvider =
    NotifierProvider<ChatController, ChatUiState>(ChatController.new);

/// The chat endpoint (`POST /chat`) is a single request/response call,
/// not a token stream. This controller's job is state management around
/// that one call — any "typing"/"streaming" feel is a UI-layer concern
/// (see TypingIndicator), not something this controller simulates.
class ChatController extends Notifier<ChatUiState> {
  /// The exact `history` list most recently returned by the backend, or
  /// null before the first successful turn. Tracked opaquely — never
  /// reconstructed — and sent back verbatim on the next request.
  List<dynamic>? _rawHistory;

  @override
  ChatUiState build() {
    _rawHistory = null;
    return const ChatIdle([]);
  }

  Future<void> sendMessage(String text) async {
    final api = ref.read(chatApiProvider);
    final historyForThisRequest = _rawHistory;
    final optimisticMessages = [
      ...state.messages,
      ChatTurn(role: 'user', content: text),
    ];
    state = ChatSending(optimisticMessages);

    try {
      final result = await api.sendMessage(text, historyForThisRequest);
      _rawHistory = result.history;
      final displayed = result.history
          .map(ChatTurn.tryFromRaw)
          .whereType<ChatTurn>()
          .toList();
      state = ChatIdle(displayed);
    } on AppError catch (e) {
      state = ChatFailed(optimisticMessages, text, historyForThisRequest, e);
    }
  }

  Future<void> retry() async {
    final current = state;
    if (current is! ChatFailed) return;
    // Drop the optimistic turn that failed — sendMessage re-adds it, and
    // roll _rawHistory back to what it was before that attempt so the
    // retried request is byte-for-byte identical to the one that failed.
    final messagesBeforeFailedTurn =
        current.messages.sublist(0, current.messages.length - 1);
    state = ChatIdle(messagesBeforeFailedTurn);
    _rawHistory = current.historyAtFailure;
    await sendMessage(current.failedMessage);
  }
}
