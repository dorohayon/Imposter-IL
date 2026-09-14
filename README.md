# מי המתחזה?

אפליקציית משחק חברתי בעברית שבה כל השחקנים מקבלים מילה סודית, מלבד המתחזה. כל שחקן כותב רמז בתורו, הקבוצה מצביעה, ואם המתחזה נתפס הוא מקבל הזדמנות אחרונה לנחש את המילה.

המאגר הוא monorepo: אפיון ועיצוב תחת `docs/` ו־`assets/`, ושרת Go תחת `server/`. אפליקציית Flutter תיווצר תחת `app/`.

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

- מצב מילה: באפיון
- Wireframe: גרסה מעודכנת עם 29 מסכים ומצבי מערכת
- מצב שאלה: מחוץ ל־MVP ויתוכנן בהמשך
- כיוון עיצובי: נקבע; 12 אווטארים ו־11 אילוסטרציות בגרסת v1 נמצאים תחת `assets/`
- שרת Go: שלד עם `/healthz` ומנוע משחק ראשון עם Unit Tests
- Flutter: טרם נוצר

## הרצת בדיקות השרת

```sh
cd server
go test -race ./...
go run ./cmd/server
```
