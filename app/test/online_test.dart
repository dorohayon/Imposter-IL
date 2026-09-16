import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/screens/live_room.dart';
import 'package:imposter_il/screens/online_flow.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

Map<String, dynamic> searchJson(String status, int players) => {
      'status': status,
      'categoryIds': ['food'],
      'players': [
        for (var i = 0; i < players; i++)
          player(i == 0 ? 'p_me' : 'p_$i', i == 0 ? 'דור' : 'שחקן$i'),
      ],
      'targetPlayers': 6,
      'maxPlayers': 8,
      'deadline': DateTime.now()
          .add(const Duration(seconds: 30))
          .toUtc()
          .toIso8601String(),
    };

/// Opens the categories, keeps only food, and starts searching.
Future<FakeChannel> startSearching(WidgetTester tester, FakeApi api) async {
  await startAtHome(tester, api);
  await tapText(tester, 'משחק ברשת');
  expect(find.byType(CategorySelectionScreen), findsOneWidget);
  await tapText(tester, 'הכול'); // all categories stay selected
  for (final name in ['חיות', 'ספורט', 'מקצועות', 'מקומות', 'חפצים']) {
    await tapText(tester, name);
  }
  await tapLive(tester, 'חפש משחק');
  final channel = api.channel;
  expect(channel.commands('matchmaking.join').single['payload'], {
    'categoryIds': ['food'],
  });
  channel.event('session.state',
      {'playerId': 'p_me', 'activity': 'matchmaking', 'roomId': 'r_pub'});
  return channel;
}

var _searchVersion = 0;

void pushSearch(FakeChannel channel, String status, int players) =>
    channel.event('matchmaking.state', {
      ...searchJson(status, players),
      'stateVersion': ++_searchVersion,
    });

void main() {
  testWidgets('search shows found players, empty spots and the status',
      (tester) async {
    final api = FakeApi();
    final channel = await startSearching(tester, api);

    pushSearch(channel, 'searching', 2);
    await settle(tester);
    expect(find.byType(LiveRoomScreen), findsOneWidget);
    expect(find.text('נמצאו 2 מתוך 8'), findsOneWidget);
    expect(find.text('צריך לפחות 4 שחקנים כדי להתחיל'), findsOneWidget);
    expect(find.text('מחפשים שחקן...'), findsNWidgets(6));

    pushSearch(channel, 'waiting_for_more', 4);
    await settle(tester);
    expect(
        find.text('נמצאו 4! מחכים עד 30 שניות לשחקנים נוספים'), findsOneWidget);

    pushSearch(channel, 'countdown', 6);
    await settle(tester);
    expect(find.text('המשחק מתחיל בעוד רגע!'), findsOneWidget);

    await tapLive(tester, 'ביטול חיפוש');
    expect(channel.commands('matchmaking.cancel'), hasLength(1));
    expect(find.byType(CategorySelectionScreen), findsOneWidget);
  });

  testWidgets('no match offers other categories or another try',
      (tester) async {
    final api = FakeApi();
    final channel = await startSearching(tester, api);
    pushSearch(channel, 'searching', 1);
    await settle(tester);

    channel.event('matchmaking.noMatch', {
      'categoryIds': ['food'],
    });
    channel.event('session.state', {'playerId': 'p_me', 'activity': 'none'});
    await settle(tester);
    expect(find.text('לא נמצא משחק מתאים'), findsWidgets);

    await tapLive(tester, 'ניסיון נוסף');
    expect(channel.commands('matchmaking.join'), hasLength(2));
    expect(channel.commands('matchmaking.join').last['payload'], {
      'categoryIds': ['food'],
    });
    channel.event('session.state',
        {'playerId': 'p_me', 'activity': 'matchmaking', 'roomId': 'r_pub2'});
    pushSearch(channel, 'searching', 1);
    await settle(tester);
    expect(find.text('נמצאו 1 מתוך 8'), findsOneWidget);

    channel.event('matchmaking.noMatch', {
      'categoryIds': ['food'],
    });
    channel.event('session.state', {'playerId': 'p_me', 'activity': 'none'});
    await settle(tester);
    await tapLive(tester, 'בחירת קטגוריות מחדש');
    expect(find.byType(CategorySelectionScreen), findsOneWidget);
  });

  testWidgets('a found match plays in place and another game searches again',
      (tester) async {
    final api = FakeApi();
    final channel = await startSearching(tester, api);
    pushSearch(channel, 'countdown', 4);
    await settle(tester);

    channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_pub',
      'gameId': 'g_1'
    });
    channel.event('game.state', {
      'stateVersion': 5000,
      'game': gameJson(phase: 'role_reveal'),
    });
    await settle(tester);
    expect(find.text('המשימה שלכם'), findsOneWidget);

    channel.event('game.state', {
      'stateVersion': 5001,
      'game': gameJson(phase: 'ended', result: {
        'winner': 'citizens',
        'reason': 'impostor_guess_wrong',
        'impostorPlayerId': 'p_3',
        'secretWord': 'פיל',
        'voteRounds': [],
        'outcomes': {'p_me': 'win'},
      }),
    });
    await settle(tester);
    expect(find.text('האזרחים ניצחו!'), findsOneWidget);
    await tapLive(tester, 'משחק נוסף');
    expect(channel.commands('game.playAgain'), hasLength(1));

    channel.event('session.state',
        {'playerId': 'p_me', 'activity': 'matchmaking', 'roomId': 'r_pub'});
    channel.event('matchmaking.state', {
      ...searchJson('searching', 3),
      'stateVersion': 5002,
    });
    await settle(tester);
    expect(find.text('נמצאו 3 מתוך 8'), findsOneWidget);
  });
}
