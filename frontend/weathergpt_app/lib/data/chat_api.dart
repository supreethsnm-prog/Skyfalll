import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// A display-only chat turn. The app's ONLY typed view of a history
/// entry — the raw entries themselves (which may carry `tool_calls`,
/// `tool_call_id`, `name`, etc. for tool turns the backend needs but the
/// UI never renders) are tracked separately as opaque `List<dynamic>`
/// by ChatController and must never be reconstructed from instances of
/// this class.
class ChatTurn {
  final String role; // always 'user' or 'assistant'
  final String content;

  const ChatTurn({required this.role, required this.content});

  /// Returns null (rather than throwing) for any entry this app cannot
  /// safely display: a role other than user/assistant (e.g. 'tool'), or
  /// non-String content. A future backend response shape change should
  /// degrade to "this turn doesn't render," never crash the chat screen.
  static ChatTurn? tryFromRaw(dynamic raw) {
    if (raw is! Map) return null;
    final role = raw['role'];
    final content = raw['content'];
    if (role != 'user' && role != 'assistant') return null;
    if (content is! String) return null;
    return ChatTurn(role: role as String, content: content);
  }
}

class ChatResult {
  final String reply;
  final List<dynamic> history;

  const ChatResult({required this.reply, required this.history});
}

/// Pure parsing logic, exposed separately from [ChatApi.sendMessage] so
/// it is directly unit-testable without a live or faked network round
/// trip — mirrors api_client.dart's own separation of
/// [mapDioException] from the interceptor that uses it.
ChatResult parseChatResult(Map<String, dynamic> json) {
  return ChatResult(
    reply: json['reply'] as String,
    history: json['history'] as List<dynamic>,
  );
}

/// Wraps `POST /chat`. This endpoint is a single request/response call —
/// it does NOT stream tokens. Any "typing"/"streaming" feel in the UI is
/// a client-side animation over this one response, not a real stream
/// (see ChatController and TypingIndicator).
class ChatApi {
  final Dio _dio;

  ChatApi(this._dio);

  /// [history] must be the exact `List<dynamic>` most recently returned
  /// by this same method (or null for the first turn in a conversation)
  /// — never a client-reconstructed or filtered list. The backend uses
  /// it verbatim to resume multi-turn tool-calling context.
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) {
    return guardApi(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/chat',
        data: {'message': message, 'history': history},
      );
      return parseChatResult(response.data!);
    });
  }
}
