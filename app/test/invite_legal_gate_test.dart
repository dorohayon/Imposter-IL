// An invitation link must not open a room screen over the legal gate: a
// returning install (saved session, older accepted legal version) has a player
// id but still owes the re-acceptance. The invitation waits and opens once the
// new version is accepted. On iOS the link arrives through
// FlutterSceneLifeCycle -> pushRouteInformation, which handlePushRoute
// simulates.
import 'package:flutter/material.dart';
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

    // Accepting opens the room the link was for.
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tapText(tester, 'אישור והמשך');
    await tester.pumpAndSettle();
    expect(find.byType(JoinRoomScreen), findsOneWidget);
  });

  testWidgets('control: invite opens the join screen after consent',
      (tester) async {
    await startApp(tester, FakeApi(), saved: _savedSession);
    await _openLink(tester);
    expect(find.byType(JoinRoomScreen), findsOneWidget);
  });
}
