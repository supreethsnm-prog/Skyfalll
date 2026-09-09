import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/features/chat/widgets/typing_indicator.dart';

void main() {
  testWidgets('renders three dots and keeps rendering across animation ticks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TypingIndicator())),
    );

    // Deliberately pump() with explicit durations, never pumpAndSettle() —
    // this widget's animation repeats forever, so pumpAndSettle() would
    // hang (the exact bug found and fixed in Phase 0's router test).
    await tester.pump();
    expect(find.byType(CircleAvatar), findsNWidgets(3));

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircleAvatar), findsNWidgets(3));

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircleAvatar), findsNWidgets(3));
  });
}
