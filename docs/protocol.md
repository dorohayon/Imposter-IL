# חוזי REST ו־WebSocket

גרסה: `v1` (טיוטה). ממומשים כרגע (`server/internal/api`): כל ה־REST, ו־`GET /v1/ws` לחדרים פרטיים, למשחק ברשת ולמשחקים בשניהם: כל הודעות `matchmaking.*`, `room.*` ו־`game.*`, `session.state`, `matchmaking.state`, `matchmaking.noMatch`, `room.state`, `room.kicked`, `game.state` ו־`game.reaction`. לא ממומש עדיין: `game.aborted`. שאר החוזה מגדיר את מה שהשרת והאפליקציה יממשו בהמשך. רקע ועקרונות: [`architecture.md`](architecture.md).

## מוסכמות

- JSON ב־UTF-8. שמות שדות ב־`camelCase`.
- זמנים ב־RFC 3339 ב־UTC, לדוגמה `2026-09-14T12:00:15Z`.
- מזהים (`playerId`, `roomId`, `gameId`) הם מחרוזות אטומות.
- אימות: `Authorization: Bearer <sessionToken>` בכל בקשת REST ובחיבור ה־WebSocket.
- השרת מחזיר קוד שגיאה יציב באנגלית. האפליקציה מציגה נוסח עברי לפי הקוד, ולא את `message`.

שגיאת REST:

```json
{ "error": { "code": "room_not_found", "message": "room not found" } }
```

שגיאות REST כלליות: `400 invalid_message` (גוף שאינו JSON או גדול מ־64KB), `401 session_not_found` (טוקן חסר או לא מוכר), `500 internal_error`.

## REST

| Method | Path | תיאור |
| --- | --- | --- |
| `GET` | `/healthz` | בדיקת חיות |
| `POST` | `/v1/sessions` | יצירת שחקן אורח |
| `PATCH` | `/v1/sessions/me` | עריכת כינוי או אווטאר |
| `GET` | `/v1/categories` | רשימת קטגוריות |
| `GET` | `/v1/reactions` | רשימת התגובות |
| `POST` | `/v1/rooms` | יצירת חדר פרטי |
| `POST` | `/v1/rooms/join` | הצטרפות לחדר לפי קוד |

### `GET /healthz`

`200 OK`

```json
{ "status": "ok" }
```

### `POST /v1/sessions`

```json
{ "nickname": "דור", "avatarId": "avatar-m04-detective-hat" }
```

`201 Created`

```json
{ "playerId": "p_01J8", "sessionToken": "…" }
```

שגיאות: `422 invalid_nickname` (אחרי הסרת רווחים בקצוות הכינוי ריק או קצר מ־2 תווים), `422 nickname_blocked` (מסך 2; ממתין למילון), `422 invalid_avatar`. הכינוי נשמר אחרי הסרת הרווחים.

ה־`sessionToken` מזהה את החיבור לצורך חיבור מחדש בלבד. האם ניצחונות והפסדים יגובו בשרת באמצעותו — פתוח. כללי הכינוי (אורך, מילון) — פתוחים. `avatarId` הוא שם קובץ האווטאר בלי הסיומת.

### `PATCH /v1/sessions/me`

גוף זהה ל־`POST /v1/sessions`, כל השדות אופציונליים. `200` עם `{ "playerId": "…" }`. אותן שגיאות. עדכון שאחד משדותיו אינו תקין אינו משנה דבר.

### `GET /v1/categories`

```json
{ "categories": [ { "id": "…", "name": "…" } ] }
```

מחזיר את המנה הראשונה שאושרה (`docs/decisions.md`): `food`, `animals`, `sports`, `professions`, `places`, `objects`. `categoryIds` בחדר חייבים להיות מהרשימה הזו.

### `GET /v1/reactions`

```json
{ "reactions": [ { "id": "laugh", "text": "😂" } ] }
```

הרשימה שאושרה. `reactionId` ב־`game.react` הוא אחד מהמזהים, והאפליקציה מציגה את `text`:

| `id` | `text` |
| --- | --- |
| `laugh` | 😂 |
| `thinking` | 🤔 |
| `eyes` | 👀 |
| `surprised` | 😮 |
| `applause` | 👏 |
| `eye_roll` | 🙄 |
| `good_hint` | רמז טוב! |
| `suspicious` | זה מחשיד |
| `not_convinced` | לא השתכנעתי |
| `what_connection` | מה הקשר? |

### `POST /v1/rooms`

```json
{ "maxPlayers": 8, "hintSeconds": 15, "categoryIds": ["…"] }
```

`maxPlayers` בין 4 ל־8. `hintSeconds` אחד מ־10, 15, 20. `categoryIds` אינו ריק ומכיל רק מזהים מ־`GET /v1/categories`. תשובה `201` עם `{ "room": Room }`, והשחקן הוא המנהל. שגיאות: `422 invalid_room_settings`, `409 already_in_activity`.

### `POST /v1/rooms/join`

```json
{ "code": "482913" }
```

`200` עם `{ "room": Room }`. שגיאות (מסך 28): `422 invalid_room_code` (לא שש ספרות), `404 room_not_found`, `409 room_unavailable` (החדר מלא או שמשחק בעיצומו). ניסיון הצטרפות חוזר לאותו חדר מחזיר `200`.

שחקן נמצא בחדר אחד לכל היותר. יצירת חדר או הצטרפות לחדר אחר מוציאה אותו מהלובי הקודם, רק אחרי שהחדר החדש קיבל אותו. אם בחדר הקודם מתנהל משחק, הבקשה נדחית ב־`409 already_in_activity`, כי יציאה ממשחק נחשבת הפסד.

## WebSocket

`GET /v1/ws` עם `Authorization: Bearer <sessionToken>`. חיבור אחד לכל session. טוקן לא מוכר מחזיר `401 session_not_found` — למשל אחרי קריסת שרת.

### מעטפת

מהאפליקציה לשרת:

```json
{ "v": 1, "id": "01J8Z6…", "type": "game.submitHint", "payload": { "gameId": "g_1", "text": "חדק" } }
```

מהשרת לאפליקציה:

```json
{ "v": 1, "type": "game.state", "serverTime": "2026-09-14T12:00:03Z", "payload": { } }
```

תשובה לכל הודעת לקוח:

```json
{ "v": 1, "type": "reply", "replyTo": "01J8Z6…", "serverTime": "…", "ok": false, "error": { "code": "hint_contains_secret" } }
```

### Versioning

- `v` הוא ה־major של הפרוטוקול. גרסה לא נתמכת מקבלת `unsupported_protocol_version` והחיבור נסגר.
- הוספת שדה או סוג הודעה אינה מעלה את `v`. האפליקציה מתעלמת משדות ומסוגי הודעות שאינה מכירה.
- שינוי שובר מעלה את `v` ואת נתיב ה־REST (`/v2`).

### Idempotency

- `id` חובה בכל הודעת לקוח (ULID או UUID).
- השרת שומר את 100 התשובות האחרונות לכל session למשך 5 דקות. הודעה עם `id` שכבר טופל מקבלת את אותה תשובה בלי לבצע את הפעולה שוב.
- גם בלי המטמון, המנוע דוחה רמז שני באותו תור (`not_your_turn`) והצבעה חוזרת מחליפה את הקודמת ולא מוסיפה קול.

### סדר, שחזור וזמן

- כל Snapshot (`game.state`, `room.state`, `matchmaking.state`) כולל `stateVersion` מונוטוני. האפליקציה מתעלמת מגרסה שאינה גדולה מהאחרונה שקיבלה. בחדר פרטי המספור משותף ל־`room.state` ול־`game.state` של החדר: כל Snapshot מקבל מספר גדול מכל הקודמים, גם בין משחקים וגם כשרק כינוי או אווטאר השתנו.
- מיד אחרי חיבור או חיבור מחדש השרת שולח `session.state` ואחריו את ה־Snapshot הרלוונטי. אין צורך בהודעת resume.
- כל `deadline` הוא זמן מוחלט של השרת. האפליקציה מחשבת היסט `serverTime − זמן קבלה מקומי` ומציגה ספירה לאחור לפי `deadline`.
- השרת שולח ping כל 10 שניות. שני pong חסרים או סגירת socket נחשבים ניתוק (`Disconnect` במנוע). ערכים טכניים הניתנים לכוונון.
- מסך `חיבור מחדש` (26) מוצג באפליקציה ברגע שהחיבור נפל, לפי ה־Snapshot האחרון.

### פרטי מימוש של החיבור

- חיבור חדש לאותו session מחליף את הקודם. הקודם נסגר (`1008`), וההחלפה אינה נספרת כניתוק.
- פתיחת חיבור של חבר חדר נחשבת חיבור מחדש (`Reconnect` בחדר), וסגירתו נחשבת ניתוק. חבר שהצטרף ב־REST מופיע כמחובר עד שחיבור ה־WebSocket שלו נסגר.
- ping נשלח כל 10 שניות. אם ה־pong לא הגיע תוך שני מרווחים, החיבור נסגר ונחשב ניתוק.
- הודעה שאינה JSON, או בלי `id` או `type`, מקבלת `reply` עם `invalid_message` (עם `replyTo` ריק כשאין `id`). תשובות כאלה אינן נשמרות במטמון.
- שינויים ב־REST שולחים גם הם `session.state` ו־`room.state` לחיבורים הפתוחים: יצירת חדר, הצטרפות, מעבר בין חדרים ועדכון כינוי או אווטאר.
- `room.kick` שולח לשחקן שהוסר `room.kicked` ואחריו `session.state` עם `activity: "none"`.
- לקוח שאינו קורא מספיק מהר ומצטבר אצלו תור של יותר מ־64 הודעות מנותק.

### פרטי מימוש של משחק

- `room.start` בוחר מילה באקראי מהקטגוריות של החדר. `content_unavailable` מוחזר רק כשהשרת הורכב בלי תוכן או מדיניות משחק.
- כל שחקני המשחק מקבלים `session.state` עם `activity: "game"`, `roomId` ו־`gameId`, ואחריו `game.state` מסונן. ה־`activity` נשאר `game` גם אחרי `ended` (מסך התוצאה), עד `game.playAgain` או `game.leave`.
- אחרי כל שינוי, כל שחקן שעדיין מציג את המשחק מקבל `game.state` משלו. זה כולל טיימרים, וגם פקודה שנכשלה אחרי שהפעילה זמן שפג (למשל רמז מאוחר שהעביר את התור לפני שנדחה ב־`not_your_turn`).
- שחקן שהוצא בניתוק שלישי ומתחבר מחדש מקבל `session.state` עם `activity: "game"` ו־`game.state` שבו הסטטוס שלו `removed` (מסך 27), עד `game.leave`. זה נכון גם אם בינתיים התחיל בחדר משחק חדש: הוא מקבל את המצב הסופי של המשחק שלו, ופקודות אחרות מלבד `game.leave` ו־`game.playAgain` מקבלות `game_not_found`.
- `game.react` שולח `game.reaction` לכל שחקני המשחק, בנוסף לספירה ב־`game.state`.
- `gameId` שאינו המשחק שהשחקן מציג מקבל `game_not_found`.

### פרטי מימוש של משחק ברשת

- `matchmaking.join` שולח `session.state` עם `activity: "matchmaking"` ו־`roomId` של קבוצת החיפוש, ואחריו `matchmaking.state` לכל המחפשים בקבוצה. כללי ההתחלה ב־`docs/matchmaking.md`.
- כשהמשחק מתחיל, כל שחקניו מקבלים `session.state` עם `activity: "game"` ו־`game.state`, כמו בחדר פרטי. אין סטטוס `starting`.
- `matchmaking.cancel`, או ניתוק בזמן החיפוש, מוציאים מהקבוצה ושולחים `session.state` עם `activity: "none"`.
- אחרי 2 דקות עם פחות מ־4 שחקנים השרת שולח `matchmaking.noMatch` ואחריו `session.state` עם `activity: "none"`.
- `game.playAgain` במשחק ברשת מחזיר את השחקן לחיפוש עם אותן קטגוריות, כך ששחקנים שממשיכים מגיעים לאותה קבוצה.
- פקודות `room.*` על קבוצת חיפוש מקבלות `room_not_found`.

## הודעות מהאפליקציה

| `type` | `payload` | שגיאות אפשריות |
| --- | --- | --- |
| `matchmaking.join` | `{ categoryIds }` | `already_in_activity`, `invalid_categories`, `content_unavailable` |
| `matchmaking.cancel` | `{}` | — |
| `room.updateSettings` | `{ roomId, maxPlayers, hintSeconds, categoryIds }` | `not_room_host`, `room_settings_locked`, `invalid_room_settings`, `room_in_game` |
| `room.kick` | `{ roomId, playerId }` | `not_room_host`, `cannot_kick_self`, `room_in_game`, `unknown_player` |
| `room.start` | `{ roomId }` | `not_room_host`, `not_enough_players`, `room_in_game`, `content_unavailable` |
| `room.leave` | `{ roomId }` | — |
| `game.confirmRole` | `{ gameId }` | `wrong_phase` |
| `game.submitHint` | `{ gameId, text }` | `not_your_turn`, `wrong_phase`, `hint_empty`, `hint_not_one_word`, `hint_too_long`, `hint_inappropriate`, `hint_contains_secret`, `hint_duplicate` |
| `game.react` | `{ gameId, hintIndex, reactionId }` | `invalid_hint`, `invalid_reaction`, `wrong_phase` |
| `game.vote` | `{ gameId, targetPlayerId }` | `self_vote`, `invalid_vote_target`, `wrong_phase` |
| `game.submitGuess` | `{ gameId, text }` | `not_impostor`, `wrong_phase` |
| `game.leave` | `{ gameId }` | — (יציאה לבית: לפני הסוף זו יציאה יזומה והפסד; ממסך התוצאות אינה נחשבת. בשני המקרים השחקן יוצא גם מהחדר) |
| `game.playAgain` | `{ gameId }` | `wrong_phase` (לפני `ended`). בחדר פרטי מחזיר את השחקן ללובי: `session.state` עם `activity: "room"` |

שגיאות כלליות לכל הודעה: `unknown_player`, `player_not_active`, `game_not_found`, `room_not_found`, `rate_limited`, `invalid_message`, `internal_error`.

## הודעות מהשרת

| `type` | `payload` |
| --- | --- |
| `session.state` | `{ playerId, activity: "none" \| "matchmaking" \| "room" \| "game", roomId?, gameId? }` |
| `matchmaking.state` | `{ stateVersion, status: "searching" \| "waiting_for_more" \| "countdown", categoryIds, players: PlayerSummary[], targetPlayers: 6, maxPlayers: 8, deadline }` — `categoryIds` הן הקטגוריות המשותפות לכל המחפשים; `deadline` הוא מתי יוצג `לא נמצא משחק מתאים` לשחקן הזה ב־`searching`, ומתי יתחיל המשחק ב־`waiting_for_more` וב־`countdown` |
| `matchmaking.noMatch` | `{ categoryIds }` — מסך 6 |
| `room.state` | `{ stateVersion, room: Room }` |
| `room.kicked` | `{ roomId }` |
| `game.state` | `{ stateVersion, game: GameView }` — מסונן לכל שחקן |
| `game.reaction` | `{ gameId, hintIndex, reactionId, playerId }` — לאנימציה בלבד; הספירה הסמכותית ב־`game.state` |
| `game.aborted` | `{ gameId, reason: "server_error", lossRecorded: false }` — מסך 29 |

## אובייקטים

### `PlayerSummary`

```json
{ "playerId": "p_1", "nickname": "נועה", "avatarId": "avatar-f01-notebook" }
```

### `Room`

```json
{
  "roomId": "r_1",
  "code": "482913",
  "status": "lobby",
  "hostPlayerId": "p_2",
  "maxPlayers": 8,
  "hintSeconds": 15,
  "categoryIds": ["…"],
  "settingsLocked": true,
  "players": [
    { "playerId": "p_1", "nickname": "דור", "avatarId": "avatar-m04-detective-hat", "connected": false, "joinedAt": "…" }
  ],
  "hostTransfer": { "fromPlayerId": "p_1", "toPlayerId": "p_2", "reason": "host_timeout" },
  "hostReconnectDeadline": null
}
```

`status`: `lobby` | `in_game`. `hostTransfer.reason`: `host_timeout` | `host_left` | `host_removed` (מסך 22). `hostReconnectDeadline` מלא בזמן 30 השניות שבהן ממתינים למנהל מנותק. `hostPlayerId` הוא `null` כשהזמן נגמר ואין שחקן אחר מחובר, עד שחבר אחר מתחבר או מצטרף.

### `GameView`

```json
{
  "gameId": "g_1",
  "phase": "hints",
  "deadline": "2026-09-14T12:00:15Z",
  "category": "…",
  "secretWord": "…",
  "myRole": "citizen",
  "players": [
    { "playerId": "p_1", "nickname": "דור", "avatarId": "…", "status": "active", "connected": true, "disconnects": 0, "roleConfirmed": true }
  ],
  "currentTurnPlayerId": "p_1",
  "awaitingReconnect": false,
  "hints": [ { "playerId": "p_3", "text": "חדק", "missing": false, "reactions": { "…": 3 } } ],
  "voteCandidates": [],
  "previousVotes": { "p_2": 2, "p_4": 2 },
  "myVote": null,
  "result": null
}
```

- `phase`: `role_reveal` | `hints` | `voting` | `runoff_voting` | `impostor_guess` | `ended`.
- `secretWord` חסר אצל המתחזה עד `ended`.
- `players` לפי סדר התורות. `status`: `active` | `left` | `removed`.
- `myVote` הוא הקול של השחקן עצמו בלבד. קולות אחרים נחשפים רק ב־`result`.
- `previousVotes` מופיע בהצבעה חוזרת בלבד, ומראה כמה קולות קיבל כל מועמד בסבב הקודם.

`result` בסיום:

```json
{
  "winner": "citizens",
  "reason": "impostor_guess_wrong",
  "impostorPlayerId": "p_4",
  "secretWord": "…",
  "voteRounds": [ { "p_1": "p_4", "p_2": "p_4" } ],
  "abstentions": [ 1 ],
  "outcomes": { "p_1": "win", "p_4": "loss" }
}
```

`abstentions` מונה לכל סבב כמה שחקנים פעילים לא הצביעו, כולל מי שהיה מנותק בסיום ההצבעה.

`winner`: `citizens` | `impostor` | `null` (עבור `not_enough_players`). ערכי `reason` ב־[`architecture.md`](architecture.md#משחק-internalgame--ממומש).

## מיפוי למסכים

| מסך | מקור |
| --- | --- |
| 2 כינוי חסום | `422 nickname_blocked` (נדחה להמשך; השרת אינו מחזיר אותו כרגע) |
| 5 חיפוש שחקנים | `matchmaking.state` |
| 6 אין התאמה | `matchmaking.noMatch` |
| 7–8 חשיפת תפקיד | `game.state` עם `phase: role_reveal` ו־`myRole` |
| 9–10 רמזים | `game.state` עם `phase: hints`; `currentTurnPlayerId` קובע אם זה התור שלי |
| 11 רמז חסום | `reply` עם קוד `hint_*` |
| 12–13 הצבעה | `phase: voting` / `runoff_voting` |
| 14 ניחוש | `phase: impostor_guess` |
| 15–17 תוצאה | `phase: ended` ו־`result.reason` |
| 21–22 לובי והעברת ניהול | `room.state`, `hostTransfer` |
| 26 חיבור מחדש | נפילת socket בצד האפליקציה + `players[].disconnects` |
| 27 הוצאה | `game.state` שבו הסטטוס שלי `removed` |
| 28 שגיאת הצטרפות | `404 room_not_found` / `409 room_unavailable` / `422 invalid_room_code` |
| 29 תקלה בשרת | `game.aborted` או `401 session_not_found` באמצע משחק |
