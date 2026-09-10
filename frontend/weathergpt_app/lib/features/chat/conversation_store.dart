import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/chat_api.dart';

/// One saved conversation.
///
/// Carries the backend's opaque `history` alongside the displayed turns,
/// because resuming a conversation means sending that history back
/// verbatim — it is the model's own record of tool calls and results, and
/// it cannot be reconstructed from the displayed messages (see
/// ChatTurn.tryFromRaw for what gets filtered out of the display).
class Conversation {
  final String id;
  final List<ChatTurn> messages;

  /// The backend's `history` as of the last successful turn, stored
  /// opaquely. Null for a conversation saved before any reply landed.
  final List<dynamic>? rawHistory;

  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.messages,
    required this.updatedAt,
    this.rawHistory,
  });

  /// The sidebar label: the first thing the user actually asked.
  ///
  /// Truncated on a word boundary where possible, because a hard cut
  /// mid-word reads like a bug rather than a summary.
  String get title {
    final firstUser = messages.where((m) => m.role == 'user');
    if (firstUser.isEmpty) return 'New chat';

    final text = firstUser.first.content.trim();
    if (text.length <= 38) return text;

    final cut = text.substring(0, 38);
    final lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > 20 ? cut.substring(0, lastSpace) : cut}…';
  }
}

abstract class ConversationStore {
  Future<List<Conversation>> load();
  Future<void> save(List<Conversation> conversations);
}

class PrefsConversationStore implements ConversationStore {
  static const _key = 'conversations';

  /// Hard cap. Chat history is unbounded by nature and SharedPreferences
  /// is a single blob rewritten on every save, so an uncapped list would
  /// grow until saving a message became visibly slow.
  static const maxConversations = 30;

  static Map<String, dynamic> _encode(Conversation c) => {
        'id': c.id,
        'updated_at': c.updatedAt.toIso8601String(),
        'raw_history': c.rawHistory,
        'messages': [
          for (final m in c.messages) {'role': m.role, 'content': m.content},
        ],
      };

  static Conversation? _decode(dynamic raw) {
    if (raw is! Map) return null;

    final id = raw['id'];
    final messages = raw['messages'];
    if (id is! String || messages is! List) return null;

    final turns = <ChatTurn>[];
    for (final m in messages) {
      if (m is! Map) continue;
      final role = m['role'];
      final content = m['content'];
      if (role is! String || content is! String) continue;
      turns.add(ChatTurn(role: role, content: content));
    }
    // A conversation with nothing displayable is not worth restoring.
    if (turns.isEmpty) return null;

    return Conversation(
      id: id,
      messages: turns,
      rawHistory: raw['raw_history'] as List<dynamic>?,
      updatedAt:
          DateTime.tryParse(raw['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  Future<List<Conversation>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(_decode).whereType<Conversation>().toList();
    } catch (_) {
      // Corrupt storage costs the history, not the app.
      return const [];
    }
  }

  @override
  Future<void> save(List<Conversation> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = conversations.take(maxConversations).toList();
    await prefs.setString(_key, jsonEncode(capped.map(_encode).toList()));
  }
}

final conversationStoreProvider =
    Provider<ConversationStore>((ref) => PrefsConversationStore());
