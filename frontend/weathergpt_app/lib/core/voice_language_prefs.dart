import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hindi — the largest single-language audience among the 22 scheduled
/// languages BHASHINI serves, and a reasonable default until the user
/// picks their own via the language sheet.
const defaultVoiceLanguageCode = 'hi';

/// Persists the user's chosen voice language across app restarts.
///
/// Local only, mirroring `PrefsSavedPlacesStore`: there is no per-user
/// account for this to sync to, and one string is far too little state
/// to justify anything heavier than `SharedPreferences`.
abstract class VoiceLanguagePrefs {
  Future<String> load();
  Future<void> save(String languageCode);
}

class PrefsVoiceLanguagePrefs implements VoiceLanguagePrefs {
  static const _key = 'voice_language_code';

  @override
  Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? defaultVoiceLanguageCode;
  }

  @override
  Future<void> save(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, languageCode);
  }
}

final voiceLanguagePrefsProvider =
    Provider<VoiceLanguagePrefs>((ref) => PrefsVoiceLanguagePrefs());

/// The current voice language code, persisted. Defaults to
/// [defaultVoiceLanguageCode] until `load()` resolves or the user changes
/// it — never left null, so every call site has an immediate, valid code
/// to send `/voice/chat`/`/voice/synthesize` without a placeholder check.
final voiceLanguageProvider =
    NotifierProvider<VoiceLanguageController, String>(VoiceLanguageController.new);

class VoiceLanguageController extends Notifier<String> {
  /// Completes when the persisted value (if any) has been loaded. Callers
  /// that read the language on a tap (mic send, read-aloud) await this
  /// first — otherwise the very first tap after launch races the
  /// SharedPreferences read and silently uses the default. Same pattern
  /// as `ConversationsController._restored`.
  late final Future<void> restored;

  @override
  String build() {
    restored = _restore();
    return defaultVoiceLanguageCode;
  }

  Future<void> _restore() async {
    state = await ref.read(voiceLanguagePrefsProvider).load();
  }

  Future<void> setLanguage(String languageCode) async {
    state = languageCode;
    await ref.read(voiceLanguagePrefsProvider).save(languageCode);
  }
}

/// Mic mode + read-aloud mode, persisted alongside the global language.
/// Split from [VoiceLanguagePrefs] (new keys, same SharedPreferences) so
/// the existing `voice_language_code` value is never migrated or disturbed.
enum ReadAloudMode { message, global }

abstract class LanguageSettingsPrefs {
  Future<bool> loadAutoDetect();
  Future<void> saveAutoDetect(bool value);
  Future<ReadAloudMode> loadReadAloudMode();
  Future<void> saveReadAloudMode(ReadAloudMode mode);
}

class PrefsLanguageSettingsPrefs implements LanguageSettingsPrefs {
  static const _autoKey = 'voice_auto_detect';
  static const _readAloudKey = 'read_aloud_mode';

  @override
  Future<bool> loadAutoDetect() async {
    final prefs = await SharedPreferences.getInstance();
    // ON by default: the mic should just work across all 23 languages.
    return prefs.getBool(_autoKey) ?? true;
  }

  @override
  Future<void> saveAutoDetect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoKey, value);
  }

  @override
  Future<ReadAloudMode> loadReadAloudMode() async {
    final prefs = await SharedPreferences.getInstance();
    // Message language by default: an English reply must read in English
    // even when the global voice language is Marathi.
    return prefs.getString(_readAloudKey) == 'global'
        ? ReadAloudMode.global
        : ReadAloudMode.message;
  }

  @override
  Future<void> saveReadAloudMode(ReadAloudMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_readAloudKey, mode.name);
  }
}

final languageSettingsPrefsProvider =
    Provider<LanguageSettingsPrefs>((ref) => PrefsLanguageSettingsPrefs());

final voiceAutoDetectProvider =
    NotifierProvider<VoiceAutoDetectController, bool>(
        VoiceAutoDetectController.new);

class VoiceAutoDetectController extends Notifier<bool> {
  /// See [VoiceLanguageController.restored].
  late final Future<void> restored;

  @override
  bool build() {
    restored = _restore();
    return true;
  }

  Future<void> _restore() async {
    state = await ref.read(languageSettingsPrefsProvider).loadAutoDetect();
  }

  Future<void> setAutoDetect(bool value) async {
    state = value;
    await ref.read(languageSettingsPrefsProvider).saveAutoDetect(value);
  }
}

final readAloudModeProvider =
    NotifierProvider<ReadAloudModeController, ReadAloudMode>(
        ReadAloudModeController.new);

class ReadAloudModeController extends Notifier<ReadAloudMode> {
  /// See [VoiceLanguageController.restored].
  late final Future<void> restored;

  @override
  ReadAloudMode build() {
    restored = _restore();
    return ReadAloudMode.message;
  }

  Future<void> _restore() async {
    state = await ref.read(languageSettingsPrefsProvider).loadReadAloudMode();
  }

  Future<void> setMode(ReadAloudMode mode) async {
    state = mode;
    await ref.read(languageSettingsPrefsProvider).saveReadAloudMode(mode);
  }
}
