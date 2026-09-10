import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/features/chat/widgets/voice_waveform.dart';

void main() {
  testWidgets('renders without error given a live amplitude stream',
      (tester) async {
    final controller = StreamController<double>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VoiceWaveform(amplitude: controller.stream)),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);

    // Loud, then quiet — pumping fixed frames (never pumpAndSettle: the
    // waveform's Ticker runs continuously while mounted, by design, so
    // pumpAndSettle would never return) exercises the smoothing/repaint
    // path without asserting on exact pixel output.
    controller.add(-5.0);
    await tester.pump(const Duration(milliseconds: 100));
    controller.add(-45.0);
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes its ticker and subscription cleanly on unmount',
      (tester) async {
    final controller = StreamController<double>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VoiceWaveform(amplitude: controller.stream)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Replace with an empty screen — unmounts VoiceWaveform.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    // A sample delivered after disposal must not throw inside the
    // (now-cancelled) subscription's listener.
    controller.add(-10.0);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
