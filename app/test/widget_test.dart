import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/main.dart';

void main() {
  testWidgets('onboarding opens the Hebrew home screen', (tester) async {
    await tester.pumpWidget(const ImposterApp());

    expect(find.text('בואו נכיר'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'דור');
    await tester.scrollUntilVisible(
      find.text('ממשיכים'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('ממשיכים'));
    await tester.pumpAndSettle();

    expect(find.text('מי המתחזה?'), findsOneWidget);
    expect(find.text('משחק ברשת'), findsOneWidget);
    expect(find.text('משחק עם חברים'), findsOneWidget);
    expect(find.byTooltip('פרופיל'), findsOneWidget);
    expect(find.byTooltip('הגדרות'), findsOneWidget);
  });
}
