// Audit repro (iOS/release audit): an invitation link must not open a room
// screen over the legal gate. A returning install (saved session, older
// accepted legal version) is the state every existing tester is in after the
// 1.1 bump, and main.dart's _openInvite only checks playerId. On iOS the link
// arrives through FlutterSceneLifeCycle -> pushRouteInformation, which is
// what handlePushRoute simulates.
//
// Expected today: the first test FAILS (JoinRoomScreen is pushed over
// LegalConsentScreen); the control passes.
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/screens/legal_screens.dart';
import 'package:imposter_il/screens/private_flow.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

const _savedSession = {
  'session.token': 'token-1',
  'session.playerId': 'p_me',
  'session.nickname': 'דור',
  'session.avatarId': 'avatar-m04-detective-hat',
};

Future<void> _openLink(WidgetTester tester) async {
  expect(
    await tester.binding.handlePushRoute('imposteril://join/123456'),
    isTrue,
  );
  // _openInvite only adds a post-frame callback and never schedules a frame;
  // on a device the resume that delivered the link does.
  tester.binding.scheduleFrame();
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('invite link does not bypass the legal gate', (tester) async {
    await startApp(tester, FakeApi(),
        saved: {legalAcceptedVersionKey: '1.0', ..._savedSession});
    expect(find.byType(LegalConsentScreen), findsOneWidget);

    await _openLink(tester);

    expect(find.byType(JoinRoomScreen), findsNothing,
        reason: 'JoinRoomScreen was pushed over LegalConsentScreen');
  });

  testWidgets('control: invite opens the join screen after consent',
      (tester) async {
    await startApp(tester, FakeApi(), saved: _savedSession);
    await _openLink(tester);
    expect(find.byType(JoinRoomScreen), findsOneWidget);
  });
}
