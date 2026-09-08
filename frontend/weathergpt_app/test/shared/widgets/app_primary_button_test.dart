import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/shared/widgets/app_primary_button.dart';

void main() {
  testWidgets('invokes onPressed when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppPrimaryButton(label: 'Go', onPressed: () => tapped = true),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
