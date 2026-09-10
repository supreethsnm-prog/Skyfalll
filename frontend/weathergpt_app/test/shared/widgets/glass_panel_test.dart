import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
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

    // Bounded on BOTH sides. A one-sided `< 0.25` was satisfied by a
    // fully transparent fill, i.e. by the panel not existing — and the
    // upper bound is load-bearing for contrast, since this fill sits
    // between the sky and the text on top of it (see the AA note in
    // sky_gradient.dart). Raising it pushes the darker skies below AA.
    expect(color.a, greaterThan(0),
        reason: 'a fully transparent fill is not a panel at all');
    expect(color.a, lessThan(0.25),
        reason: 'glass panels are a subtle overlay, not an opaque card');
    expect(color, AppColors.glassFill,
        reason: 'the fill is a token, not an inline literal');
  });
}
