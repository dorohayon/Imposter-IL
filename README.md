# מי המתחזה?

אפליקציית משחק חברתי בעברית שבה כל השחקנים מקבלים מילה סודית, מלבד המתחזה. כל שחקן כותב רמז בתורו, הקבוצה מצביעה, ואם המתחזה נתפס הוא מקבל הזדמנות אחרונה לנחש את המילה.

המאגר הוא monorepo: אפיון ועיצוב תחת `docs/`, `design/` ו־`assets/`, אפליקציית Flutter תחת `app/`, ושרת Go תחת `server/`.

## מסמכים

- [היקף המוצר](docs/product-scope.md)
- [חוקי המשחק](docs/game-rules.md)
- [מפת המסכים](docs/screen-flow.md)
- [אפיון המסכים](docs/screens.md)
- [משחק ברשת ו־Matchmaking](docs/matchmaking.md)
- [ניתוקים ומקרי קצה](docs/disconnections-and-edge-cases.md)
- [החלטות מאושרות](docs/decisions.md)
- [שאלות פתוחות](docs/open-decisions.md)
- [כיוון עיצובי](docs/design-direction.md)
- [Wireframes וכל מצבי המסכים](docs/wireframes.md)
- [הנחיות עיצוב לקלוד](CLAUDE.md)
- [נכסי איור — 12 אווטארים ו־11 אילוסטרציות](assets/README.md)
- [ארכיטקטורה ו־State Machines](docs/architecture.md)
- [חוזי REST ו־WebSocket](docs/protocol.md)
- [סקירת ארכיטקטורה לקראת ייצור](docs/production-architecture-review.md)
- [הרצה ב־Production](deploy/README.md)
- [מעקב משימות וסטטוס](TASKS.md)

## סטטוס

- מצב מילה: משחק ברשת וחדר פרטי פועלים מקצה לקצה בשרת ובאפליקציה
- Wireframe: גרסה מעודכנת עם 29 מסכים ומצבי מערכת
- מצב שאלה: מחוץ ל־MVP ויתוכנן בהמשך
- כיוון עיצובי: נקבע; 12 אווטארים ו־11 אילוסטרציות בגרסת v1 נמצאים תחת `assets/`
- שרת Go: מנוע משחק, חדרים פרטיים, Matchmaking, REST ו־WebSocket, 6 קטגוריות תוכן ורשימת תגובות
- חוסן ייצור: כיבוי מסודר, הכלת `panic`, ניקוי sessions וחדרים, הגבלות קצב, `/metrics` ולוגים ב־JSON
- Hosting: מכונה אחת ב־GCE (`e2-micro`, Free Tier) עם Caddy; הנוהל ב־[`deploy/`](deploy/)
- Flutter: מעטפות Android/iOS; משחק ברשת, חדרים פרטיים ומשחקים מחוברים לשרת; פרופיל, הגדרות, פונטים, שיתוף ואייקון זמני

## הרצת בדיקות השרת

```sh
cd server
go test -race ./...
go run ./cmd/server
```

### בדיקת עומס

`cmd/loadbot` מריץ שחקנים מדומים מול הפרוטוקול האמיתי, כדי שתקרת הקיבולת תהיה מדידה ולא הערכה:

```sh
RATE_LIMITS=off go run ./cmd/server                      # טרמינל אחד
go run ./cmd/loadbot -players 240 -for 60s               # טרמינל שני
curl -s localhost:9090/metrics | grep imposter_publish   # וגם המדדים של השרת
```


## אפליקציית Flutter

נדרש Flutter 3.44.0 ומעלה, בגלל תבניות Android ו־iOS. ה־CI מריץ `flutter analyze` ו־`flutter test` על גרסת המינימום ועל stable, בדיקת פורמט על stable, build של Android ושל iOS (סימולטור) על גרסת המינימום, ובדיקת End-to-End מול שרת אמיתי.

```sh
cd app
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

### הרצה מול שרת מקומי

```sh
cd server && go run ./cmd/server   # טרמינל אחד
cd app && flutter run                                     # טרמינל שני
```

האפליקציה מתחברת כברירת מחדל ל־`http://10.0.2.2:8080` באמולטור Android ול־`http://localhost:8080` בסימולטור iOS. לשרת אחר: `flutter run --dart-define=IMPOSTER_SERVER=http://HOST:PORT`. בגרסת debug מותרים http ו־ws לא מוצפנים לשרת מקומי. מזהה האפליקציה `com.example.imposter_il` זמני, ויש להחליף אותו לפני פרסום.

בדיקות ה־End-to-End מריצות ארבעה שחקנים במשחק פרטי מלא, וארבעה שחקנים שמוצאים זה את זה במשחק ברשת, מול השרת:

```sh
cd server && PORT=18080 go run ./cmd/server
cd app && IMPOSTER_E2E_SERVER=http://localhost:18080 flutter test test/e2e
```

### מה מחובר ומה פתוח

**מחובר לשרת:** כניסה כאורח ושמירת הזהות במכשיר, קטגוריות ותגובות מהשרת, משחק ברשת (בחירת קטגוריות, חיפוש שחקנים עם טיימר, ביטול, `לא נמצא משחק מתאים` ומשחק נוסף שחוזר לחיפוש), יצירת חדר פרטי והצטרפות לפי קוד, לובי חי (הסרת שחקן, העברת ניהול, מנותקים), וכל שלבי המשחק: חשיפת תפקיד, רמזים לפי תור ושגיאות חסימה מהשרת, תגובות, הצבעה והצבעה חוזרת, ניחוש, תוצאה ומשחק נוסף. כל טיימר סופר לאחור ל־`deadline` של השרת. חיבור שנפל מתחבר מחדש אוטומטית עם הודעת `מתחברים מחדש...`, שחקן שהוצא רואה את מסך ההוצאה, ושרת שאיבד את ה־session מציג את מסך התקלה בלי הפסד ויוצר session חדש עם אותו כינוי ואווטאר.

**באפליקציה:** עריכת כינוי ואווטאר, ניצחונות והפסדים שנשמרים במכשיר בלבד, הגדרות רטט ותגובות, שיתוף קוד החדר בתפריט המערכת, והפונטים Secular One ו־Rubik. האייקון ומסך הפתיחה זמניים (`app/branding`; נוצרים מחדש עם `dart run flutter_launcher_icons` ו־`dart run flutter_native_splash:create`).

**פתוח:** צלילים, לוגו ואייקון סופיים, בדיקה על מכשירים, מזהה אפליקציה סופי ו־keystore ל־Release, אישור רשימת המילים החסומות, כתובת תמיכה, דיווח קריסות, ותנאי שימוש ומדיניות פרטיות. הרשימה המלאה ב־[`TASKS.md`](TASKS.md).
