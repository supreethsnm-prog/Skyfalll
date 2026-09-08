import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/shared/widgets/error_view.dart';

void main() {
  testWidgets('shows the message and invokes onRetry when Retry is tapped', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ErrorView(
          message: 'Could not load weather',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Could not load weather'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(retried, isTrue);
  });
}
