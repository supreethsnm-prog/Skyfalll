import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_playback_device.dart';

/// One player shared by every "read aloud" button AND the
/// auto-play-after-a-voice-reply behaviour — deliberately a single
/// instance, not one per message, so starting a new playback always
/// stops whatever was already playing rather than overlapping audio.
final audioPlaybackDeviceProvider = Provider<AudioPlaybackDevice>((ref) {
  final device = JustAudioPlaybackDevice();
  ref.onDispose(() => device.dispose());
  return device;
});

/// Identifies WHICH thing is loading/playing, so a message's read-aloud
/// icon can show its own state (spinner vs. an active "playing" look)
/// distinctly from every other message's. Any value with proper equality
/// works — the chat screen uses each turn's index; the voice composer
/// uses a fixed sentinel for "the reply that was just spoken".
sealed class AudioPlaybackUiState {
  const AudioPlaybackUiState();
}

class PlaybackIdle extends AudioPlaybackUiState {
  const PlaybackIdle();
}

class PlaybackLoading extends AudioPlaybackUiState {
  final Object turnKey;
  const PlaybackLoading(this.turnKey);
}

class PlaybackPlaying extends AudioPlaybackUiState {
  final Object turnKey;
  const PlaybackPlaying(this.turnKey);
}

final audioPlaybackControllerProvider =
    NotifierProvider<AudioPlaybackController, AudioPlaybackUiState>(
  AudioPlaybackController.new,
);

class AudioPlaybackController extends Notifier<AudioPlaybackUiState> {
  @override
  AudioPlaybackUiState build() => const PlaybackIdle();

  /// Decodes and plays base64-encoded WAV audio, tagged with [turnKey].
  ///
  /// Always stops any current playback first — the device is shared, so
  /// starting a second clip while one is already going must replace it,
  /// never overlap it.
  Future<void> playBase64Wav(String base64Audio, {required Object turnKey}) async {
    // Set before any `await` (mirrors `ChatController.sendMessage`'s own
    // optimistic-state ordering) so a caller that starts this without
    // awaiting it sees the loading state immediately, synchronously.
    state = PlaybackLoading(turnKey);
    try {
      final device = ref.read(audioPlaybackDeviceProvider);
      await device.stop();
      final bytes = base64Decode(base64Audio);
      state = PlaybackPlaying(turnKey);
      // Resolves when playback completes, is paused, or is stopped — so
      // this line blocks for exactly as long as the reply is actually
      // audible, no separate completion listener needed.
      await device.playBytes(bytes);
    } finally {
      // Guards against a race: if a NEWER playback already started (and
      // so already changed `state`) while this one was finishing up,
      // that newer state must not be clobbered back to idle here.
      final current = state;
      final isStillThisPlayback = (current is PlaybackPlaying && current.turnKey == turnKey) ||
          (current is PlaybackLoading && current.turnKey == turnKey);
      if (isStillThisPlayback) state = const PlaybackIdle();
    }
  }

  Future<void> stop() async {
    await ref.read(audioPlaybackDeviceProvider).stop();
    state = const PlaybackIdle();
  }
}
