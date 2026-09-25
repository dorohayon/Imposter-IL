import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/screens/live_room.dart';
import 'package:imposter_il/screens/online_flow.dart';
import 'package:imposter_il/state/game_session.dart';
import 'package:imposter_il/local/online_choice_screen.dart';

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
  await openQuickGame(tester);
  expect(find.byType(CategorySelectionScreen), findsOneWidget);
  // "הכול" is the default; tapping one category leaves it for just that one.
  await tapText(tester, 'אוכל ושתייה');
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
  testWidgets('first online tap continues after choosing a nickname',
      (tester) async {
    final api = FakeApi();
    await startApp(tester, api);

    await tapText(tester, 'משחק ברשת');
    await tester.enterText(find.byType(TextField), 'דור');
    await tapText(tester, 'ממשיכים');

    expect(find.byType(OnlineChoiceScreen), findsOneWidget);
    expect(find.text('משחק מהיר'), findsOneWidget);
    expect(find.text('חדר פרטי'), findsOneWidget);
  });

  testWidgets('category load failure shows the server error and retries',
      (tester) async {
    final api = FakeApi();
    final categories = api.responses['GET /v1/categories']!;
    api.responses['GET /v1/categories'] = const ApiException('network_error');
    await startAtHome(tester, api);

    await openQuickGame(tester);
    expect(find.text('משהו השתבש'), findsOneWidget);
    expect(find.text('השרת לא זמין כרגע. נסו שוב בעוד רגע.'), findsOneWidget);
    expect(find.text('ניסיון נוסף'), findsOneWidget);
    expect(find.text('חזרה למסך הבית'), findsOneWidget);

    await tapText(tester, 'חזרה למסך הבית');
    expect(find.byType(HomeScreen), findsOneWidget);

    await openQuickGame(tester);
    api.responses['GET /v1/categories'] = categories;
    await tapText(tester, 'ניסיון נוסף');
    expect(find.text('אוכל ושתייה'), findsOneWidget);
    expect(find.text('משהו השתבש'), findsNothing);
  });

  testWidgets('search shows found players, empty spots and the status',
      (tester) async {
    final api = FakeApi();
    final channel = await startSearching(tester, api);

    pushSearch(channel, 'searching', 2);
    await settle(tester);
    expect(find.byType(LiveRoomScreen), findsOneWidget);
    // Screen 05a: the card counts what is still missing to a game at all.
    expect(find.text('2 מתוך 8'), findsOneWidget);
    expect(find.text('עוד 2 שחקנים כדי להתחיל'), findsOneWidget);
    expect(
      find.text('ממשיכים לחפש שחקנים מתאימים בקטגוריות שבחרתם.'),
      findsOneWidget,
    );
    expect(find.text('מחפשים שחקן...'), findsNWidgets(6));
    expect(find.text('נא לא לעזוב עמוד זה.'), findsOneWidget);

    // Join order is shared by everyone; the current player is identified by ID.
    channel.event('matchmaking.state', {
      ...searchJson('searching', 2),
      'players': [player('p_2', 'נועה'), player('p_me', 'דור')],
      'stateVersion': ++_searchVersion,
    });
    await settle(tester);
    // The seats sit two to a row now, so "אתם" is placed by which column it
    // is in, not which line.
    final meLabelX = tester.getCenter(find.text('אתם')).dx;
    expect(
        (meLabelX - tester.getCenter(find.text('דור')).dx).abs(), lessThan(30));
    expect((meLabelX - tester.getCenter(find.text('נועה')).dx).abs(),
        greaterThan(60));

    pushSearch(channel, 'waiting_for_more', 4);
    await settle(tester);
    // Screen 05b: enough to play, still waiting for a fuller table.
    expect(find.text('יש מספיק שחקנים!'), findsOneWidget);
    expect(
      find.text('מחכים כמה שניות לשחקנים נוספים ומתחילים כשהזמן מסתיים.'),
      findsOneWidget,
    );

    pushSearch(channel, 'countdown', 6);
    await settle(tester);
    // Screen 05c.
    expect(find.text('הקבוצה מוכנה!'), findsOneWidget);
    expect(find.text('המשחק מתחיל בעוד רגע.'), findsOneWidget);

    await tapLive(tester, 'ביטול חיפוש');
    expect(channel.commands('matchmaking.cancel'), hasLength(1));
    expect(find.byType(CategorySelectionScreen), findsOneWidget);
  });

  testWidgets('a search cancelled offline is cancelled again on reconnect',
      (tester) async {
    final api = FakeApi();
    final first = await startSearching(tester, api);
    pushSearch(first, 'searching', 2);
    await settle(tester);
    final session =
        SessionScope.read(tester.element(find.byType(Scaffold).first));

    api.connectError = Exception('down');
    await first.close();
    await settle(tester);
    expect(await session.cancelSearch(), isNull); // gone here at once
    expect(session.activity, 'none');

    // Back online: the server kept the place for 30 s and says so.
    api.connectError = null;
    await settle(tester);
    final second = api.channel;
    expect(second, isNot(same(first)));
    second.event('session.state',
        {'playerId': 'p_me', 'activity': 'matchmaking', 'roomId': 'r_pub'});
    await settle(tester);
    expect(second.commands('matchmaking.cancel'), hasLength(1));
    expect(session.activity, 'none');
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
    expect(find.text('לא נמצא משחק בקטגוריות שבחרתם'), findsOneWidget);

    await tapLive(tester, 'ניסיון נוסף');
    expect(channel.commands('matchmaking.join'), hasLength(2));
    expect(channel.commands('matchmaking.join').last['payload'], {
      'categoryIds': ['food'],
    });
    channel.event('session.state',
        {'playerId': 'p_me', 'activity': 'matchmaking', 'roomId': 'r_pub2'});
    pushSearch(channel, 'searching', 1);
    await settle(tester);
    expect(find.text('1 מתוך 8'), findsOneWidget);

    channel.event('matchmaking.noMatch', {
      'categoryIds': ['food'],
    });
    channel.event('session.state', {'playerId': 'p_me', 'activity': 'none'});
    await settle(tester);
    await tapLive(tester, 'בחירת קטגוריות אחרות');
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
    expect(find.text('את/ה אזרח/ית'), findsOneWidget);

    channel.event('game.state', {
      'stateVersion': 5001,
      'game': gameJson(phase: 'ended', result: {
        'winner': 'citizens',
        'reason': 'impostor_guess_wrong',
        'impostorPlayerId': 'p_3',
        'secretWord': 'פיל',
        'voteRounds': [],
        'abstentions': [4],
        'outcomes': {'p_me': 'win'},
      }),
    });
    await settle(tester);
    expect(find.text('האזרחים ניצחו!'), findsOneWidget);
    expect(find.text('חלוקת הקולות'), findsOneWidget);
    expect(find.text('נמנעו'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    await tapLive(tester, 'משחק נוסף');
    expect(channel.commands('game.playAgain'), hasLength(1));

    channel.event('session.state',
        {'playerId': 'p_me', 'activity': 'matchmaking', 'roomId': 'r_pub'});
    channel.event('matchmaking.state', {
      ...searchJson('searching', 3),
      'stateVersion': 5002,
    });
    await settle(tester);
    expect(find.text('3 מתוך 8'), findsOneWidget);
  });

  testWidgets('"הכול" stands alone, and no categories blocks the search',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openQuickGame(tester);

    // "הכול" is selected on its own — the six categories are not lit up too.
    expect(isSelectedTile(tester, 'הכול'), isTrue);
    for (final name in ['אוכל ושתייה', 'בבית', 'בית ספר וסטודנטים']) {
      expect(isSelectedTile(tester, name), isFalse);
    }
    expect(isEnabled(tester, 'חפש משחק'), isTrue);

    // Turning "הכול" off leaves nothing chosen, so there is nothing to search.
    await tapText(tester, 'הכול');
    expect(isSelectedTile(tester, 'הכול'), isFalse);
    expect(isEnabled(tester, 'חפש משחק'), isFalse);

    // Any single category is a valid choice, and can be turned off again.
    // (That picking one leaves "הכול" rather than keeping all six is covered
    // by startSearching, which asserts the search sends only ['food'].)
    await tapText(tester, 'אוכל ושתייה');
    expect(isSelectedTile(tester, 'אוכל ושתייה'), isTrue);
    expect(isEnabled(tester, 'חפש משחק'), isTrue);

    await tapText(tester, 'אוכל ושתייה');
    expect(isEnabled(tester, 'חפש משחק'), isFalse);
  });
}
