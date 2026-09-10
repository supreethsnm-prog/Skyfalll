import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/audio/audio_playback_device.dart';
import 'package:weathergpt_app/features/chat/audio_playback_controller.dart';

/// A fake whose `playFile` future only resolves when the test tells it
/// to — real playback (via `just_audio`'s own documented contract) does
/// not resolve until the audio finishes, is paused, or is stopped, and
/// the race-guard tests below need to control exactly when that happens.
class _FakeAudioPlaybackDevice implements AudioPlaybackDevice {
  final List<Uint8List> playedBytes = [];
  int stopCalls = 0;
  final List<_PendingPlay> _pending = [];

  @override
  Future<void> playBytes(Uint8List bytes) {
    playedBytes.add(bytes);
    final completer = Completer<void>();
    _pending.add(_PendingPlay(completer));
    return completer.future;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    // Mirrors just_audio's real contract: stop() resolves any pending
    // play() future rather than leaving it hanging forever.
    for (final p in _pending.where((p) => !p.completer.isCompleted)) {
      p.completer.complete();
    }
  }

  /// Simulates the CURRENTLY playing clip finishing naturally (as opposed
  /// to being stopped) — completes the oldest still-pending play.
  void finishPlayback() {
    final next = _pending.firstWhere((p) => !p.completer.isCompleted);
    next.completer.complete();
  }

  @override
  Future<void> dispose() async {}
}

class _PendingPlay {
  _PendingPlay(this.completer);
  final Completer<void> completer;
}

ProviderContainer _containerWith(_FakeAudioPlaybackDevice device) {
  return ProviderContainer(
    overrides: [audioPlaybackDeviceProvider.overrideWithValue(device)],
  );
}

void main() {
  test('starts idle', () {
    final container = _containerWith(_FakeAudioPlaybackDevice());
    addTearDown(container.dispose);

    expect(container.read(audioPlaybackControllerProvider), isA<PlaybackIdle>());
  });

  test('playBase64Wav decodes the audio and plays it, tagged with turnKey', () async {
    final device = _FakeAudioPlaybackDevice();
    final container = _containerWith(device);
    addTearDown(container.dispose);

    final future = container
        .read(audioPlaybackControllerProvider.notifier)
        .playBase64Wav(base64Encode(utf8.encode('fake wav bytes')), turnKey: 'reply-1');

    // Set synchronously, before any await — observable immediately, with
    // nothing to wait for.
    final loadingState = container.read(audioPlaybackControllerProvider);
    expect(loadingState, isA<PlaybackLoading>());
    expect((loadingState as PlaybackLoading).turnKey, 'reply-1');

    // Playing, once the device's own stop() (awaited first) resolves —
    // one microtask turn is enough since the fake's stop() has no
    // internal await of its own.
    await Future<void>.delayed(Duration.zero);
    final playingState = container.read(audioPlaybackControllerProvider);
    expect(playingState, isA<PlaybackPlaying>());
    expect((playingState as PlaybackPlaying).turnKey, 'reply-1');
    expect(utf8.decode(device.playedBytes.single), 'fake wav bytes');

    device.finishPlayback();
    await future;

    expect(container.read(audioPlaybackControllerProvider), isA<PlaybackIdle>());
  });

  test(
      'starting a new playback while one is already playing stops the '
      'first, and the first resolving afterward does not clobber the '
      "second's state (the finally-block race guard)", () async {
    final device = _FakeAudioPlaybackDevice();
    final container = _containerWith(device);
    addTearDown(container.dispose);

    final firstFuture = container
        .read(audioPlaybackControllerProvider.notifier)
        .playBase64Wav(base64Encode(utf8.encode('first')), turnKey: 'a');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(audioPlaybackControllerProvider), isA<PlaybackPlaying>());

    // Starting the second call's own device.stop() resolves the FIRST
    // call's still-pending playBytes() — exactly like the real device
    // resolving a pending play() when told to stop.
    final secondFuture = container
        .read(audioPlaybackControllerProvider.notifier)
        .playBase64Wav(base64Encode(utf8.encode('second')), turnKey: 'b');
    await firstFuture;
    await Future<void>.delayed(Duration.zero);

    final state = container.read(audioPlaybackControllerProvider);
    expect(state, isA<PlaybackPlaying>());
    expect((state as PlaybackPlaying).turnKey, 'b');

    device.finishPlayback();
    await secondFuture;
    expect(container.read(audioPlaybackControllerProvider), isA<PlaybackIdle>());
  });

  test('stop() stops the device and returns to idle', () async {
    final device = _FakeAudioPlaybackDevice();
    final container = _containerWith(device);
    addTearDown(container.dispose);

    final future = container
        .read(audioPlaybackControllerProvider.notifier)
        .playBase64Wav(base64Encode(utf8.encode('audio')), turnKey: 'reply-1');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(audioPlaybackControllerProvider), isA<PlaybackPlaying>());

    await container.read(audioPlaybackControllerProvider.notifier).stop();
    await future;

    expect(container.read(audioPlaybackControllerProvider), isA<PlaybackIdle>());
    expect(device.stopCalls, greaterThanOrEqualTo(1));
  });
}
