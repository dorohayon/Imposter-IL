import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/screens/legal_screens.dart';
import 'package:imposter_il/widgets/game_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

void main() {
  testWidgets('a fresh install cannot create a session before accepting v1',
      (tester) async {
    final api = FakeApi();
    await startApp(tester, api, saved: {legalAcceptedVersionKey: ''});

    expect(find.byType(LegalConsentScreen), findsOneWidget);
    expect(find.text('תנאי שימוש'), findsOneWidget);
    expect(find.text('מדיניות פרטיות'), findsOneWidget);
    expect(isEnabled(tester, 'אישור והמשך'), isFalse);
    expect(api.requests.where((r) => r.$2 == '/v1/sessions'), isEmpty);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(isEnabled(tester, 'אישור והמשך'), isTrue);
    await tapText(tester, 'אישור והמשך');

    expect(find.text('מי אתם במשחק?'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(legalAcceptedVersionKey), legalVersion);
    expect(api.requests.where((r) => r.$2 == '/v1/sessions'), isEmpty);
  });

  testWidgets('legal documents are readable before acceptance', (tester) async {
    await startApp(tester, FakeApi(), saved: {legalAcceptedVersionKey: ''});

    await tapText(tester, 'מדיניות פרטיות');
    expect(find.byType(PrivacyScreen), findsOneWidget);
    expect(find.text('מידע שנשמר במכשיר'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tapText(tester, 'תנאי שימוש');
    expect(find.byType(TermsScreen), findsOneWidget);
    expect(find.text('2. כללי התנהגות ותוכן'), findsOneWidget);
  });

  testWidgets('an old accepted version is gated again', (tester) async {
    await startApp(tester, FakeApi(), saved: {
      legalAcceptedVersionKey: '0.9',
      'session.token': 'token-1',
      'session.playerId': 'p_me',
      'session.nickname': 'דור',
      'session.avatarId': 'avatar-m04-detective-hat',
    });

    expect(find.byType(LegalConsentScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('settings opens both current legal documents', (tester) async {
    await startAtHome(tester);
    await tester.tap(find.byTooltip('הגדרות'));
    await tester.pumpAndSettle();

    expect(find.text('גרסה $legalVersion'), findsNWidgets(2));
    await tapText(tester, 'תנאי שימוש');
    expect(find.byType(TermsScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tapText(tester, 'מדיניות פרטיות');
    expect(find.byType(PrivacyScreen), findsOneWidget);
  });

  testWidgets('legal gate fits the narrow supported viewport', (tester) async {
    await startApp(tester, FakeApi(), saved: {legalAcceptedVersionKey: ''});
    expect(tester.takeException(), isNull);
    expect(find.byType(PrimaryButton), findsOneWidget);
  });
}
