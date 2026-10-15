// On iOS the link arrives through FlutterSceneLifeCycle ->
// pushRouteInformation, which handlePushRoute simulates.
import 'package:flutter_test/flutter_test.dart';
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
  testWidgets('an invite link opens the join screen', (tester) async {
    await startApp(tester, FakeApi(), saved: _savedSession);
    await _openLink(tester);
    expect(find.byType(JoinRoomScreen), findsOneWidget);
  });
}
