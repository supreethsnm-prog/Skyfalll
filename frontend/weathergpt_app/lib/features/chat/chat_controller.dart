import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../data/chat_api.dart';
import '../../data/voice_api.dart';
import '../home/home_controller.dart';
import 'conversation_store.dart';

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
final voiceApiProvider = Provider<VoiceApi>((ref) => VoiceApi(buildApiClient()));

final chatControllerProvider =
    NotifierProvider<ChatController, ChatUiState>(ChatController.new);

/// Saved conversations, newest first. Backs the sidebar's Recents list.
final conversationsProvider =
    NotifierProvider<ConversationsController, List<Conversation>>(
  ConversationsController.new,
);

class ConversationsController extends Notifier<List<Conversation>> {
  /// Mutations await this, for the same reason saved places do: a message
  /// sent before storage answers would otherwise be written into an empty
  /// list and the in-flight restore would then wipe it.
  late final Future<void> _restored;

  @override
  List<Conversation> build() {
    _restored = _restore();
    return const [];
  }

  Future<void> _restore() async {
    state = await ref.read(conversationStoreProvider).load();
  }

  /// Inserts or updates one conversation, newest first.
  Future<void> upsert(Conversation conversation) async {
    await _restored;
    final next = [
      conversation,
      ...state.where((c) => c.id != conversation.id),
    ];
    state = next;
    await ref.read(conversationStoreProvider).save(next);
  }

  Future<void> remove(String id) async {
    await _restored;
    final next = state.where((c) => c.id != id).toList();
    state = next;
    await ref.read(conversationStoreProvider).save(next);
  }
}

/// The chat endpoint (`POST /chat`) is a single request/response call,
/// not a token stream. This controller's job is state management around
/// that one call — any "typing"/"streaming" feel is a UI-layer concern
/// (see TypingIndicator), not something this controller simulates.
class ChatController extends Notifier<ChatUiState> {
  /// The exact `history` list most recently returned by the backend, or
  /// null before the first successful turn. Tracked opaquely — never
  /// reconstructed — and sent back verbatim on the next request.
  List<dynamic>? _rawHistory;

  /// Identifies the conversation being persisted. Assigned on the first
  /// message so that every later turn updates the same saved record
  /// rather than piling up a new one per message.
  String? _conversationId;

  @override
  ChatUiState build() {
    _rawHistory = null;
    _conversationId = null;
    return const ChatIdle([]);
  }

  /// Clears the screen for a new conversation. The previous one is
  /// already saved, so this only drops the in-memory pointer to it.
  void startNew() {
    _rawHistory = null;
    _conversationId = null;
    state = const ChatIdle([]);
  }

  /// Reopens a saved conversation, restoring the backend history verbatim
  /// so the next turn continues it rather than starting over.
  void resume(Conversation conversation) {
    _conversationId = conversation.id;
    _rawHistory = conversation.rawHistory;
    state = ChatIdle(conversation.messages);
  }

  Future<void> _persist(List<ChatTurn> messages) async {
    if (messages.isEmpty) return;
    final id = _conversationId ??=
        DateTime.now().microsecondsSinceEpoch.toString();

    await ref.read(conversationsProvider.notifier).upsert(
          Conversation(
            id: id,
            messages: messages,
            rawHistory: _rawHistory,
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<void> sendMessage(String text) async {
    final api = ref.read(chatApiProvider);
    final historyForThisRequest = _rawHistory;
    final optimisticMessages = [
      ...state.messages,
      ChatTurn(role: 'user', content: text),
    ];
    state = ChatSending(optimisticMessages);

    final homeState = ref.read(homeControllerProvider);
    final location = homeState is HomeLoaded
        ? homeState.location
        : ref.read(homeControllerProvider.notifier).currentLocation;

    try {
      final result = await api.sendMessage(
        text,
        historyForThisRequest,
        latitude: location.latitude,
        longitude: location.longitude,
        placeName: location.displayName,
      );
      _rawHistory = result.history;
      final displayed = result.history
          .map(ChatTurn.tryFromRaw)
          .whereType<ChatTurn>()
          .toList();
      state = ChatIdle(displayed);
      // Saved only after a successful turn: persisting a failed send
      // would leave a conversation whose stored history the backend
      // never actually acknowledged.
      await _persist(displayed);
    } on AppError catch (e) {
      state = ChatFailed(optimisticMessages, text, historyForThisRequest, e);
    }
  }

  /// Sends a recorded voice message: uploads [audioPath] for
  /// transcription, appends both the transcript and the reply to the
  /// SAME conversation a text turn would, and reports the reply's audio
  /// (if synthesis succeeded) via [onReplyAudio] for the caller to
  /// auto-play — this controller has no audio-player dependency of its
  /// own, by design (that stays a UI-layer concern, shared with the
  /// per-message "read aloud" button).
  ///
  /// Unlike [sendMessage], there is no optimistic user bubble: the
  /// transcript does not exist yet when the request starts, so there is
  /// nothing honest to show until the response arrives.
  ///
  /// The uploaded file is deleted afterwards either way — it has no use
  /// once the request completes, successfully or not, and voice messages
  /// would otherwise accumulate unbounded in the temp directory over a
  /// session.
  Future<void> sendVoice(
    String audioPath,
    String language, {
    bool autoDetect = false,
    void Function(String audioBase64)? onReplyAudio,
    void Function(AppError error)? onError,
  }) async {
    final api = ref.read(voiceApiProvider);
    final historyForThisRequest = _rawHistory;
    final previousMessages = state.messages;
    state = ChatSending(previousMessages);

    final homeState = ref.read(homeControllerProvider);
    final location = homeState is HomeLoaded
        ? homeState.location
        : ref.read(homeControllerProvider.notifier).currentLocation;

    try {
      final result = await api.sendVoiceMessage(
        audioFile: File(audioPath),
        language: language,
        history: historyForThisRequest,
        autoDetect: autoDetect,
        latitude: location.latitude,
        longitude: location.longitude,
        placeName: location.displayName,
      );
      _rawHistory = result.history;
      // Stamp the two turns this voice round trip appended with the
      // effective language: old backends omit detected_language, so fall
      // back to the requested language (never null here).
      final heardIn = result.detectedLanguage.isNotEmpty
          ? result.detectedLanguage
          : language;
      final replyLang = result.replyLanguage.isNotEmpty
          ? result.replyLanguage
          : heardIn;
      final displayed = result.history
          .map(ChatTurn.tryFromRaw)
          .whereType<ChatTurn>()
          .toList();
      if (displayed.length >= 2) {
        displayed[displayed.length - 2] =
            displayed[displayed.length - 2].copyWith(lang: heardIn);
        displayed[displayed.length - 1] =
            displayed[displayed.length - 1].copyWith(lang: replyLang);
      }
      state = ChatIdle(displayed);
      await _persist(displayed);
      if (result.replyAudioBase64.isNotEmpty) {
        onReplyAudio?.call(result.replyAudioBase64);
      }
    } on AppError catch (e) {
      // No transcript exists to show as "the message that failed" and no
      // text to retry with (unlike a failed text send) — the honest
      // outcome is reverting to exactly where the user was, with the
      // error surfaced as a transient notice rather than a stuck bubble.
      state = ChatIdle(previousMessages);
      onError?.call(e);
    } finally {
      final file = File(audioPath);
      if (await file.exists()) await file.delete();
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
