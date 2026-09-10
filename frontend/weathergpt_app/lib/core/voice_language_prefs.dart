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
  @override
  String build() {
    _restore();
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
