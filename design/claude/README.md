# Claude Design exports

תיקייה זו מכילה את תוצרי העיצוב של **מי המתחזה?** כפי שיוצאו מפרויקט Claude Design
[Imposter IL mobile app](https://claude.ai/design/p/31a84db7-627c-4a39-8f3a-dbc5afd2378d).

| קובץ | תוכן |
| --- | --- |
| `Imposter IL Screens.dc.html` | מסכי המערכת ב־390×844, כולל שלושת מצבי חיפוש השחקנים (05a/05b/05c). |
| `Imposter IL Prototype.dc.html` | Prototype לחיץ: משחק ברשת, חדר פרטי ומסלולי שגיאה. |
| `Imposter IL Local Game.dc.html` | 22 מסכי ומצבי המשחק המקומי במכשיר אחד, כולל ניווט, הגדרה, פרטיות, סבבים ותוצאות. |
| `Imposter IL Clue Screen.dc.html` | מסך כתיבת הרמזים המחודש: שמונה מצבים (C01–C08) עם גריד המשתתפים, כרטיס המילה, היסטוריית הרמזים ומצבי הקצה. |
| `Clue Reaction Dock.dc.html` | סרגל התגובות הקבוע בתחתית מסך הרמזים, נגלל אופקית. |
| `Imposter IL Monetization.dc.html` | מודל ההכנסות: קטגוריות נעולות (04, L05), חלון הרכישה P01–P12, באנרים ומודעה במסך מלא, וכללי הפרסומות. |
| `Imposter IL Purchase Prototype.dc.html` | Prototype לחיץ של הרכישה והמודעה במסך מלא, עם סימולציית תוצאה וגודל מסך. |
| `support.js` | סביבת ההרצה של הייצוא. נדרשת לשני קובצי ה־HTML. |
| `design-system.md` | המידות של מערכת העיצוב (צבעים, טיפוגרפיה, כפתורים, שדות, טיימר, אווטארים ואיורים). |
| `assets` | קישור לתיקיית `assets/` בשורש, כדי שהאווטארים והאיורים יוצגו מקומית. |

בסנכרון האחרון של `Imposter IL Screens.dc.html` חזר במסך 13 הנוסח הישן על ניצחון
למתחזה בתיקו חוזר, ואיתו טיימר של 20 שניות להצבעה החוזרת. שניהם סותרים את
`docs/decisions.md` (15 שניות; תיקו חוזר אינו מדיח איש), ולכן תוקנו בעותק המקומי
לפי סדר העדיפות שב־`CLAUDE.md`. יש לתקן אותם גם בפרויקט Claude Design.

גלריית `Imposter IL Design System.dc.html` נשארה בפרויקט בלבד; המידות שהמימוש צריך מרוכזות ב־`design-system.md`.

הרחבת הכרזת התיקו מתועדת ב־`docs/tie-screen-design.md`, עם הדמיית המסך
`wireframes/tie-announcement.html` ואיור `assets/illustrations/tie-announcement.webp`.
יש להעביר את ההרחבה לייצוא Claude Design הקנוני. הטקסט הישן על ניצחון למתחזה
בתיקו חוזר אינו תקף; לאחר תיקו חוזר ממשיכים לסבב נוסף בלי הדחה.

עיצוב ארבעת מצבי חיפוש השחקנים מתועד ב־`docs/matchmaking-screen-design.md`
וב־`wireframes/matchmaking-states.html`. יש להעביר את המצבים לייצוא הקנוני,
להשתמש באווטארים הקיימים וב־`assets/illustrations/no-category-match.webp`, ולא
ליצור איור חלופי. הכותרת המאושרת היא `מרכיבים קבוצת שחקנים` וכותרת הגריד היא
`הקבוצה שלך`.

## הרחבת משחק במכשיר אחד

הייצוא `Imposter IL Local Game.dc.html` מרחיב את Design V1 לפי
`docs/local-game-design.md` ו־`wireframes/local-game.html`, תוך שימוש בשני
הנכסים `local-one-device.webp` ו־`pass-the-device.webp`. הוא כולל עדכון למסך
הבית, מסך בחירת משחק ברשת ואת כל הזרימה המקומית, בלי לעצב מחדש את 29 המסכים
הקיימים.

לפתיחה: `open "design/claude/Imposter IL Screens.dc.html"`. הקבצים נטענים פונטים מ־Google Fonts, ולכן במצב אופליין הטיפוגרפיה תיפול לפונט ברירת המחדל.

מקורות האמת למוצר הם `docs/`, `CLAUDE.md` ו־`TASKS.md`. קובצי העיצוב הם תוצר עיצובי ואינם רשאים לשנות חוקי משחק. כשהעיצוב והמסמכים אינם מסכימים, ההחלטה שב־`docs/decisions.md` קובעת, והפער נרשם ב־TASKS.md.

## סנכרון 23 בספטמבר 2026

נמשכו מהפרויקט: מודל ההכנסות וה־Prototype שלו, כרטיס הרמז הקצר (שדה, מונה
`מילה אחת · 6/25` וכפתור `שליחה` בשורה אחת) ומסך ניחוש המתחזה עם `הרמזים של
שאר השחקנים`, וה־Prototype עם מסך החיפוש המחודש. שלושתם מומשו
(`docs/monetization.md`). הייצוא של `Imposter IL Screens.dc.html` החזיר שוב את
הטיימר של 20 שניות ואת `תיקו נוסף מעניק ניצחון למתחזה` במסך 13, ושניהם תוקנו
בעותק המקומי כמו בפעם הקודמת.
