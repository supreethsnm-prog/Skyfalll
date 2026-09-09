import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/shared/widgets/glass_panel.dart';

void main() {
  testWidgets('renders its child inside a blurred, rounded surface', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassPanel(child: Text('forecast')),
        ),
      ),
    );

    expect(find.text('forecast'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ClipRRect), findsOneWidget);
  });

  testWidgets('its fill is a low-alpha white, not an opaque card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GlassPanel(child: Text('x')))),
    );

    final decorated = tester.widgetList<Container>(find.byType(Container))
        .firstWhere((c) => c.decoration is BoxDecoration);
    final color = (decorated.decoration as BoxDecoration).color!;
    expect(color.a, lessThan(0.25),
        reason: 'glass panels are a subtle overlay, not an opaque card');
  });
}
