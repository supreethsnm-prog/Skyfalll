import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/features/chat/widgets/chat_composer.dart';

void main() {
  testWidgets('sends the typed text and clears the field', (tester) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(onSend: (text) => sent = text),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'What is the weather?');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sent, 'What is the weather?');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('does nothing when the field is empty or whitespace-only', (tester) async {
    var callCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatComposer(onSend: (_) => callCount++)),
      ),
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(callCount, 0);
  });

  testWidgets('disables the field and send button when enabled is false', (tester) async {
    var callCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(onSend: (_) => callCount++, enabled: false),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);

    await tester.enterText(find.byType(TextField), 'Hi');
    await tester.tap(find.text('Send'), warnIfMissed: false);
    await tester.pump();

    expect(callCount, 0);
  });

  testWidgets('mic button is present but disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ChatComposer(onSend: (_) {}))),
    );

    final mic = tester.widget<IconButton>(find.byType(IconButton));
    expect(mic.onPressed, isNull);
  });
}
