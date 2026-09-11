import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';
import 'package:weathergpt_app/data/voice_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';

class _FixedHomeController extends HomeController {
  _FixedHomeController(this._fixedState);
  final HomeUiState _fixedState;

  @override
  HomeUiState build() => _fixedState;
}

/// Implements only the public interface ChatApi exposes — its private
/// Dio field is not part of that interface, so no real Dio is needed.
class FakeChatApi implements ChatApi {
  ChatResult? nextResult;
  AppError? nextError;
  final List<String> messagesSent = [];
  final List<List<dynamic>?> historiesSent = [];
  double? lastLatitude;
  double? lastLongitude;
  String? lastPlaceName;

  @override
  Future<ChatResult> sendMessage(
    String message,
    List<dynamic>? history, {
    double? latitude,
    double? longitude,
    String? placeName,
  }) async {
    messagesSent.add(message);
    historiesSent.add(history);
    lastLatitude = latitude;
    lastLongitude = longitude;
    lastPlaceName = placeName;
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

/// Implements only the public interface VoiceApi exposes.
class FakeVoiceApi implements VoiceApi {
  VoiceChatResult? nextResult;
  AppError? nextError;
  final List<String> languagesSent = [];
  final List<List<dynamic>?> historiesSent = [];
  final List<String> audioPathsSent = [];
  final List<bool> autoDetectSent = [];
  double? lastLatitude;
  double? lastLongitude;
  String? lastPlaceName;

  @override
  Future<VoiceChatResult> sendVoiceMessage({
    required File audioFile,
    required String language,
    List<dynamic>? history,
    bool autoDetect = false,
    double? latitude,
    double? longitude,
    String? placeName,
  }) async {
    audioPathsSent.add(audioFile.path);
    languagesSent.add(language);
    historiesSent.add(history);
    autoDetectSent.add(autoDetect);
    lastLatitude = latitude;
    lastLongitude = longitude;
    lastPlaceName = placeName;
    if (nextError != null) throw nextError!;
    return nextResult!;
  }

  @override
  Future<List<VoiceLanguage>> fetchLanguages() async => const [];

  @override
  Future<SynthesizedSpeech> synthesize({required String text, required String language}) async {
    throw UnimplementedError();
  }
}

/// A real, throwaway file — `sendVoice` deletes it after the request, so
/// the test needs an actual file on disk to assert that against, not
/// just a path string.
File _tempWavFile() {
  final file = File(
    '${Directory.systemTemp.path}/chat_controller_test_${DateTime.now().microsecondsSinceEpoch}.wav',
  );
  file.writeAsBytesSync([0]);
  return file;
}

void main() {
  late FakeChatApi fakeApi;
  late FakeVoiceApi fakeVoiceApi;
  late ProviderContainer container;

  setUp(() {
    fakeApi = FakeChatApi();
    fakeVoiceApi = FakeVoiceApi();
    container = ProviderContainer(
      overrides: [
        chatApiProvider.overrideWithValue(fakeApi),
        voiceApiProvider.overrideWithValue(fakeVoiceApi),
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

  group('sendVoice', () {
    test('unlike sendMessage, adds no optimistic turn — there is no '
        'transcript to show until the response arrives', () async {
      final audio = _tempWavFile();
      fakeVoiceApi.nextResult = const VoiceChatResult(
        transcript: 'Weather in Pune?',
        detectedLanguage: 'hi',
        replyText: 'Sunny today',
        replyAudioBase64: '',
        history: [
          {'role': 'user', 'content': 'Weather in Pune?'},
          {'role': 'assistant', 'content': 'Sunny today'},
        ],
      );
      // Not awaited yet: `sendVoice` sets ChatSending synchronously,
      // before its first `await`, exactly like `sendMessage` does — so
      // the intermediate state is observable here without any manual
      // completer plumbing.
      final future = container.read(chatControllerProvider.notifier).sendVoice(
            audio.path,
            'hi',
          );

      final sendingState = container.read(chatControllerProvider);
      expect(sendingState, isA<ChatSending>());
      expect(sendingState.messages, isEmpty);

      await future;
    });

    test('a successful voice turn appends the transcript and reply, and '
        'reports reply audio via onReplyAudio', () async {
      final audio = _tempWavFile();
      fakeVoiceApi.nextResult = const VoiceChatResult(
        transcript: 'Weather in Pune?',
        detectedLanguage: 'en',
        replyText: 'Sunny today',
        replyAudioBase64: 'd2F2ZWZvcm0=',
        history: [
          {'role': 'user', 'content': 'Weather in Pune?'},
          {'role': 'assistant', 'content': 'Sunny today'},
        ],
      );

      String? reportedAudio;
      await container.read(chatControllerProvider.notifier).sendVoice(
            audio.path,
            'hi',
            onReplyAudio: (a) => reportedAudio = a,
          );

      final state = container.read(chatControllerProvider);
      expect(state, isA<ChatIdle>());
      expect(state.messages, hasLength(2));
      expect(state.messages[0].role, 'user');
      expect(state.messages[0].content, 'Weather in Pune?');
      expect(state.messages[1].role, 'assistant');
      expect(state.messages[1].content, 'Sunny today');
      expect(reportedAudio, 'd2F2ZWZvcm0=');
      expect(fakeVoiceApi.languagesSent, ['hi']);
    });

    test('onReplyAudio is never called when synthesis produced no audio', () async {
      final audio = _tempWavFile();
      fakeVoiceApi.nextResult = const VoiceChatResult(
        transcript: 'Weather?',
        detectedLanguage: 'hi',
        replyText: 'Sunny',
        replyAudioBase64: '',
        history: [
          {'role': 'user', 'content': 'Weather?'},
          {'role': 'assistant', 'content': 'Sunny'},
        ],
      );

      var called = false;
      await container.read(chatControllerProvider.notifier).sendVoice(
            audio.path,
            'hi',
            onReplyAudio: (_) => called = true,
          );

      expect(called, isFalse);
    });

    test('deletes the recorded file after the request, success or failure', () async {
      final successAudio = _tempWavFile();
      fakeVoiceApi.nextResult = const VoiceChatResult(
        transcript: 'Hi',
        detectedLanguage: 'hi',
        replyText: 'Hello',
        replyAudioBase64: '',
        history: [],
      );
      await container.read(chatControllerProvider.notifier).sendVoice(successAudio.path, 'hi');
      expect(successAudio.existsSync(), isFalse);

      final failureAudio = _tempWavFile();
      fakeVoiceApi.nextError = const NetworkTimeoutError();
      await container.read(chatControllerProvider.notifier).sendVoice(failureAudio.path, 'hi');
      expect(failureAudio.existsSync(), isFalse);
    });

    test('stamps the voice turns with the detected language and forwards '
        'autoDetect to the API', () async {
      final audio = _tempWavFile();
      fakeVoiceApi.nextResult = const VoiceChatResult(
        transcript: 'Weather in Pune?',
        detectedLanguage: 'en',
        replyText: 'Sunny today',
        replyAudioBase64: '',
        history: [
          {'role': 'user', 'content': 'Weather in Pune?'},
          {'role': 'assistant', 'content': 'Sunny today'},
        ],
      );

      await container.read(chatControllerProvider.notifier).sendVoice(
            audio.path,
            'hi',
            autoDetect: true,
          );

      final state = container.read(chatControllerProvider);
      expect(state.messages, hasLength(2));
      expect(state.messages[0].lang, 'en');
      expect(state.messages[1].lang, 'en');
      expect(fakeVoiceApi.autoDetectSent, [true]);
    });

    test('a failed voice send reverts to the messages from before the '
        'attempt and surfaces the error via onError — there is no '
        'transcript to keep as a "failed" turn', () async {
      fakeApi.nextResult = const ChatResult(
        reply: 'Earlier reply',
        history: [
          {'role': 'user', 'content': 'Earlier question'},
          {'role': 'assistant', 'content': 'Earlier reply'},
        ],
      );
      await container.read(chatControllerProvider.notifier).sendMessage('Earlier question');
      final messagesBefore = container.read(chatControllerProvider).messages;

      final audio = _tempWavFile();
      fakeVoiceApi.nextError = const NetworkConnectionError();
      AppError? reportedError;
      await container.read(chatControllerProvider.notifier).sendVoice(
            audio.path,
            'hi',
            onError: (e) => reportedError = e,
          );

      final state = container.read(chatControllerProvider);
      expect(state, isA<ChatIdle>());
      expect(state.messages, equals(messagesBefore));
      expect(reportedError, isA<NetworkConnectionError>());
    });

    test('forwards current location from HomeLoaded to sendMessage', () async {
      const loc = GeocodeResult(
        displayName: 'Pune, Maharashtra',
        latitude: 18.5204,
        longitude: 73.8567,
        country: 'India',
        state: 'Maharashtra',
      );
      const weather = CurrentWeather(
        temperatureC: 24.4,
        humidityPct: 78,
        weatherCode: 1,
        windSpeedKmh: 18.2,
        windDirectionDeg: 247,
        observedAt: '2026-09-09T14:00',
        timezone: 'Asia/Kolkata',
      );
      final containerWithHome = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(fakeApi),
          voiceApiProvider.overrideWithValue(fakeVoiceApi),
          conversationStoreProvider.overrideWithValue(_NoStore()),
          homeControllerProvider.overrideWith(
            () => _FixedHomeController(
              const HomeLoaded(
                location: loc,
                weather: weather,
                forecast: [],
                nearbyAlerts: [],
              ),
            ),
          ),
        ],
      );

      fakeApi.nextResult = const ChatResult(reply: 'Cloudy', history: []);
      await containerWithHome
          .read(chatControllerProvider.notifier)
          .sendMessage('Will it rain?');

      expect(fakeApi.lastLatitude, 18.5204);
      expect(fakeApi.lastLongitude, 73.8567);
      expect(fakeApi.lastPlaceName, 'Pune, Maharashtra');
    });

    test('forwards current location from HomeLoaded to sendVoice', () async {
      const loc = GeocodeResult(
        displayName: 'Bengaluru, Karnataka',
        latitude: 12.9716,
        longitude: 77.5946,
        country: 'India',
        state: 'Karnataka',
      );
      const weather = CurrentWeather(
        temperatureC: 22.0,
        humidityPct: 70,
        weatherCode: 1,
        windSpeedKmh: 15.0,
        windDirectionDeg: 90,
        observedAt: '2026-09-09T14:00',
        timezone: 'Asia/Kolkata',
      );
      final containerWithHome = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(fakeApi),
          voiceApiProvider.overrideWithValue(fakeVoiceApi),
          conversationStoreProvider.overrideWithValue(_NoStore()),
          homeControllerProvider.overrideWith(
            () => _FixedHomeController(
              const HomeLoaded(
                location: loc,
                weather: weather,
                forecast: [],
                nearbyAlerts: [],
              ),
            ),
          ),
        ],
      );

      final audio = _tempWavFile();
      fakeVoiceApi.nextResult = const VoiceChatResult(
        transcript: 'Weather?',
        detectedLanguage: 'en',
        replyText: 'Sunny',
        replyAudioBase64: '',
        history: [],
      );

      await containerWithHome
          .read(chatControllerProvider.notifier)
          .sendVoice(audio.path, 'en');

      expect(fakeVoiceApi.lastLatitude, 12.9716);
      expect(fakeVoiceApi.lastLongitude, 77.5946);
      expect(fakeVoiceApi.lastPlaceName, 'Bengaluru, Karnataka');
    });

    test('forwards fallback currentLocation when Home is still loading', () async {
      fakeApi.nextResult = const ChatResult(reply: 'Cloudy', history: []);
      await container
          .read(chatControllerProvider.notifier)
          .sendMessage('Will it rain?');

      expect(fakeApi.lastLatitude, isNotNull);
      expect(fakeApi.lastLongitude, isNotNull);
      expect(fakeApi.lastPlaceName, isNotNull);
    });
  });
}
