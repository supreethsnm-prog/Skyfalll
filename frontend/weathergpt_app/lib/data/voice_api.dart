import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// One BHASHINI-supported language, from `GET /voice/languages`.
class VoiceLanguage {
  final String code;
  final String name;

  const VoiceLanguage({required this.code, required this.name});

  factory VoiceLanguage.fromJson(Map<String, dynamic> json) {
    return VoiceLanguage(
      code: json['code'] as String,
      name: json['name'] as String,
    );
  }
}

/// The full result of one voice turn: what was heard, what the assistant
/// said back, and (when synthesis succeeded) audio of the reply.
class VoiceChatResult {
  final String transcript;

  /// Bhashini code the transcript was actually produced in. Equals the
  /// requested `language` for manual turns; the winning retry language for
  /// auto-detect turns. Old backends omit it — then it falls back to the
  /// requested language on the caller side, never null here.
  final String detectedLanguage;
  /// Bhashini code of the reply text (used for TTS synthesis).
  final String replyLanguage;
  final String replyText;

  /// Empty when the backend could not synthesize the reply — a real,
  /// non-error outcome (see `voice_chat`'s own doc): the reply text still
  /// arrived and must still be shown, just without audio to auto-play.
  final String replyAudioBase64;

  /// The exact history the next turn (voice or text) must send back
  /// verbatim — tracked opaquely, mirroring `ChatResult.history`.
  final List<dynamic> history;

  const VoiceChatResult({
    required this.transcript,
    required this.detectedLanguage,
    this.replyLanguage = '',
    required this.replyText,
    required this.replyAudioBase64,
    required this.history,
  });

  factory VoiceChatResult.fromJson(Map<String, dynamic> json) {
    return VoiceChatResult(
      transcript: json['transcript'] as String,
      detectedLanguage: json['detected_language'] as String? ?? '',
      replyLanguage: json['reply_language'] as String? ?? '',
      replyText: json['reply_text'] as String,
      replyAudioBase64: json['reply_audio_base64'] as String? ?? '',
      history: json['history'] as List<dynamic>,
    );
  }
}

/// Synthesized speech for text that already exists — the "read aloud"
/// result from `GET /voice/synthesize`.
class SynthesizedSpeech {
  final String audioBase64;
  final String audioFormat;

  const SynthesizedSpeech({required this.audioBase64, required this.audioFormat});

  factory SynthesizedSpeech.fromJson(Map<String, dynamic> json) {
    return SynthesizedSpeech(
      audioBase64: json['audio_base64'] as String,
      audioFormat: json['audio_format'] as String,
    );
  }
}

/// A full voice round trip (STT -> chat -> TTS) plus standalone TTS chains
/// three external calls on the backend (BHASHINI discovery+compute twice,
/// plus the LLM) — much slower than a text `/chat` turn, so both calls
/// here use a longer receive timeout than `buildApiClient`'s 15s default.
const _voiceReceiveTimeout = Duration(seconds: 60);

/// Wraps `GET /voice/languages`, `POST /voice/chat`, and
/// `GET /voice/synthesize`.
class VoiceApi {
  final Dio _dio;

  VoiceApi(this._dio);

  Future<List<VoiceLanguage>> fetchLanguages() {
    return guardApi(() async {
      final response = await _dio.get<Map<String, dynamic>>('/voice/languages');
      final languages = response.data!['languages'] as List<dynamic>;
      return languages
          .map((entry) => VoiceLanguage.fromJson(entry as Map<String, dynamic>))
          .toList();
    });
  }

  /// [history] must be the exact `List<dynamic>` most recently returned by
  /// this or `ChatApi.sendMessage` — never a client-reconstructed list, the
  /// same rule `ChatApi.sendMessage` documents. Voice and text turns share
  /// one history, so either call can extend what the other started.
  Future<VoiceChatResult> sendVoiceMessage({
    required File audioFile,
    required String language,
    List<dynamic>? history,
    bool autoDetect = false,
    double? latitude,
    double? longitude,
    String? placeName,
  }) {
    return guardApi(() async {
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          audioFile.path,
          filename: 'audio.wav',
          contentType: DioMediaType('audio', 'wav'),
        ),
        'language': language,
        'auto_detect': autoDetect.toString(),
        if (history != null) 'history': jsonEncode(history),
        if (latitude != null) 'latitude': latitude.toString(),
        if (longitude != null) 'longitude': longitude.toString(),
        if (placeName != null && placeName.isNotEmpty) 'place_name': placeName,
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/voice/chat',
        data: formData,
        options: Options(receiveTimeout: _voiceReceiveTimeout),
      );
      return VoiceChatResult.fromJson(response.data!);
    });
  }

  Future<SynthesizedSpeech> synthesize({required String text, required String language}) {
    return guardApi(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/voice/synthesize',
        queryParameters: {'text': text, 'language': language},
        options: Options(receiveTimeout: _voiceReceiveTimeout),
      );
      return SynthesizedSpeech.fromJson(response.data!);
    });
  }
}
