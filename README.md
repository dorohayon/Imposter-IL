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
- [מעקב משימות וסטטוס](TASKS.md)

## סטטוס

- מצב מילה: משחק ברשת וחדר פרטי פועלים מקצה לקצה בשרת ובאפליקציה
- Wireframe: גרסה מעודכנת עם 29 מסכים ומצבי מערכת
- מצב שאלה: מחוץ ל־MVP ויתוכנן בהמשך
- כיוון עיצובי: נקבע; 12 אווטארים ו־11 אילוסטרציות בגרסת v1 נמצאים תחת `assets/`
- שרת Go: מנוע משחק, חדרים פרטיים, Matchmaking, REST ו־WebSocket, 6 קטגוריות תוכן ורשימת תגובות
- Flutter: מעטפות Android/iOS; משחק ברשת, חדרים פרטיים ומשחקים מחוברים לשרת; הפונטים טרם נוספו

## הרצת בדיקות השרת

```sh
cd server
go test -race ./...
go run ./cmd/server
```

מילון התוכן הלא ראוי עדיין פתוח, ולכן התחלת משחק זמינה רק עם מדיניות הפיתוח: `IMPOSTER_DEV_POLICY=1 go run ./cmd/server`.


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
cd server && IMPOSTER_DEV_POLICY=1 go run ./cmd/server   # טרמינל אחד
cd app && flutter run                                     # טרמינל שני
```

האפליקציה מתחברת כברירת מחדל ל־`http://10.0.2.2:8080` באמולטור Android ול־`http://localhost:8080` בסימולטור iOS. לשרת אחר: `flutter run --dart-define=IMPOSTER_SERVER=http://HOST:PORT`. בגרסת debug מותרים http ו־ws לא מוצפנים לשרת מקומי. מזהה האפליקציה `com.example.imposter_il` זמני, ויש להחליף אותו לפני פרסום.

בדיקות ה־End-to-End מריצות ארבעה שחקנים במשחק פרטי מלא, וארבעה שחקנים שמוצאים זה את זה במשחק ברשת, מול השרת:

```sh
cd server && IMPOSTER_DEV_POLICY=1 PORT=18080 go run ./cmd/server
cd app && IMPOSTER_E2E_SERVER=http://localhost:18080 flutter test test/e2e
```

### מה מחובר ומה פתוח

**מחובר לשרת:** כניסה כאורח ושמירת הזהות במכשיר, קטגוריות ותגובות מהשרת, משחק ברשת (בחירת קטגוריות, חיפוש שחקנים עם טיימר, ביטול, `לא נמצא משחק מתאים` ומשחק נוסף שחוזר לחיפוש), יצירת חדר פרטי והצטרפות לפי קוד, לובי חי (הסרת שחקן, העברת ניהול, מנותקים), וכל שלבי המשחק: חשיפת תפקיד, רמזים לפי תור ושגיאות חסימה מהשרת, תגובות, הצבעה והצבעה חוזרת, ניחוש, תוצאה ומשחק נוסף. כל טיימר סופר לאחור ל־`deadline` של השרת. חיבור שנפל מתחבר מחדש אוטומטית עם הודעת `מתחברים מחדש...`, שחקן שהוצא רואה את מסך ההוצאה, ושרת שאיבד את ה־session מציג את מסך התקלה בלי הפסד ויוצר session חדש עם אותו כינוי ואווטאר.

**פתוח:** שמירת ניצחונות והפסדים והגדרות, עריכת פרופיל, הפונטים Secular One ו־Rubik, מזהה אפליקציה סופי, שיתוף מערכת של קוד החדר, מילון תוכן לא ראוי (ובלעדיו משחק מתחיל רק בשרת עם `IMPOSTER_DEV_POLICY=1`), ותנאי שימוש ומדיניות פרטיות.
