# Claude Design exports

תיקייה זו מכילה את תוצרי העיצוב של **מי המתחזה?** כפי שיוצאו מפרויקט Claude Design
[Imposter IL mobile app](https://claude.ai/design/p/31a84db7-627c-4a39-8f3a-dbc5afd2378d).

| קובץ | תוכן |
| --- | --- |
| `Imposter IL Screens.dc.html` | 29 המסכים ומצבי המערכת ב־390×844. |
| `Imposter IL Prototype.dc.html` | Prototype לחיץ: משחק ברשת, חדר פרטי ומסלולי שגיאה. |
| `Imposter IL Local Game.dc.html` | 22 מסכי ומצבי המשחק המקומי במכשיר אחד, כולל ניווט, הגדרה, פרטיות, סבבים ותוצאות. |
| `support.js` | סביבת ההרצה של הייצוא. נדרשת לשני קובצי ה־HTML. |
| `design-system.md` | המידות של מערכת העיצוב (צבעים, טיפוגרפיה, כפתורים, שדות, טיימר, אווטארים ואיורים). |
| `assets` | קישור לתיקיית `assets/` בשורש, כדי שהאווטארים והאיורים יוצגו מקומית. |

גלריית `Imposter IL Design System.dc.html` נשארה בפרויקט בלבד; המידות שהמימוש צריך מרוכזות ב־`design-system.md`.

## הרחבת משחק במכשיר אחד

הייצוא `Imposter IL Local Game.dc.html` מרחיב את Design V1 לפי
`docs/local-game-design.md` ו־`wireframes/local-game.html`, תוך שימוש בשני
הנכסים `local-one-device.webp` ו־`pass-the-device.webp`. הוא כולל עדכון למסך
הבית, מסך בחירת משחק ברשת ואת כל הזרימה המקומית, בלי לעצב מחדש את 29 המסכים
הקיימים.

לפתיחה: `open "design/claude/Imposter IL Screens.dc.html"`. הקבצים נטענים פונטים מ־Google Fonts, ולכן במצב אופליין הטיפוגרפיה תיפול לפונט ברירת המחדל.

מקורות האמת למוצר הם `docs/`, `CLAUDE.md` ו־`TASKS.md`. קובצי העיצוב הם תוצר עיצובי ואינם רשאים לשנות חוקי משחק. כשהעיצוב והמסמכים אינם מסכימים, ההחלטה שב־`docs/decisions.md` קובעת, והפער נרשם ב־TASKS.md.
