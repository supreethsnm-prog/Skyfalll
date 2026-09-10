import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:path_provider/path_provider.dart';

/// Wraps `just_audio` so the rest of the app never imports it directly,
/// and so tests can substitute a fake without a plugin — mirrors
/// `VoiceRecorder`'s role for the `record` package.
///
/// Takes raw bytes rather than a file path: `just_audio` needs a seekable
/// source, so something has to write [bytes] to a temp file first, and
/// keeping that (and the `path_provider` platform channel it requires)
/// inside the implementation — never threaded in from outside — is what
/// lets `AudioPlaybackController` be unit-tested with a plain fake and no
/// Flutter test binding at all.
abstract class AudioPlaybackDevice {
  /// Plays [bytes] as WAV audio. The returned future resolves when
  /// playback completes, is paused, or is stopped — never before audio
  /// actually finishes, matching `just_audio`'s own `play()` contract.
  Future<void> playBytes(Uint8List bytes);

  Future<void> stop();

  Future<void> dispose();
}

class JustAudioPlaybackDevice implements AudioPlaybackDevice {
  JustAudioPlaybackDevice() : _player = just_audio.AudioPlayer();

  final just_audio.AudioPlayer _player;

  @override
  Future<void> playBytes(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/tts_reply_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(bytes, flush: true);
    await _player.setFilePath(file.path);
    await _player.play();
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
