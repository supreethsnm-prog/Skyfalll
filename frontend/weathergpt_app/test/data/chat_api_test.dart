import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/chat_api.dart';

void main() {
  group('ChatTurn.tryFromRaw', () {
    test('parses a valid user entry', () {
      final turn = ChatTurn.tryFromRaw({'role': 'user', 'content': 'Hello'});
      expect(turn, isNotNull);
      expect(turn!.role, 'user');
      expect(turn.content, 'Hello');
    });

    test('parses a valid assistant entry', () {
      final turn = ChatTurn.tryFromRaw({'role': 'assistant', 'content': 'Hi there'});
      expect(turn, isNotNull);
      expect(turn!.role, 'assistant');
    });

    test('returns null for a tool-role entry', () {
      final turn = ChatTurn.tryFromRaw({
        'role': 'tool',
        'tool_call_id': 'abc',
        'name': 'get_weather',
        'content': '{"temp": 28}',
      });
      expect(turn, isNull);
    });

    test('returns null when content is missing', () {
      expect(ChatTurn.tryFromRaw({'role': 'user'}), isNull);
    });

    test('returns null when content is not a String', () {
      expect(ChatTurn.tryFromRaw({'role': 'user', 'content': 42}), isNull);
    });

    test('returns null for a non-map input', () {
      expect(ChatTurn.tryFromRaw('not a map'), isNull);
      expect(ChatTurn.tryFromRaw(null), isNull);
    });

    test('returns null for an assistant entry with empty content and a tool_calls key', () {
      // The exact real-world shape backend/app/chat/service.py appends for
      // every tool-calling round: content is "" (turn.text was None) and
      // tool_calls marks this as a tool-initiating turn, not a reply.
      final turn = ChatTurn.tryFromRaw({
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {'id': 'call_1', 'name': 'get_weather', 'input': {}},
        ],
      });
      expect(turn, isNull);
    });

    test('parses an assistant entry with non-empty content and no tool_calls key', () {
      final turn = ChatTurn.tryFromRaw({
        'role': 'assistant',
        'content': 'It is sunny in Mumbai.',
      });
      expect(turn, isNotNull);
      expect(turn!.role, 'assistant');
      expect(turn.content, 'It is sunny in Mumbai.');
    });

    test('returns null for whitespace-only content with no tool_calls key', () {
      final turn = ChatTurn.tryFromRaw({'role': 'assistant', 'content': '   '});
      expect(turn, isNull);
    });
  });

  group('parseChatResult', () {
    test('extracts reply and history from a raw response body', () {
      final result = parseChatResult({
        'reply': 'It is sunny in Mumbai.',
        'history': [
          {'role': 'user', 'content': 'Weather in Mumbai?'},
          {'role': 'assistant', 'content': 'It is sunny in Mumbai.'},
        ],
      });
      expect(result.reply, 'It is sunny in Mumbai.');
      expect(result.history, hasLength(2));
      expect(result.history[0], {'role': 'user', 'content': 'Weather in Mumbai?'});
    });
  });
}
