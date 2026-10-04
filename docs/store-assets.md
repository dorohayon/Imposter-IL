# חומרי חנות: צילומי מסך, גרפיקה וסרטון

כל החומרים נוצרים מהאפליקציה האמיתית, לא משרטוטים: משחק מתוסרט רץ על המסכים עצמם מול השרת המדומה של הבדיקות, בעברית ובאנגלית, ונלכד ברזולוציית החנות. אחרי שינוי במסכים מריצים שוב ומקבלים חומרים מעודכנים.

## מה נוצר

הכול תחת `app/build/store/` (לא ב־git):

| קובץ | חנות | מפרט |
|---|---|---|
| `appstore/<he\|en>/01…06_*.jpg` | App Store, iPhone 6.9" | 1320×2868, JPEG בלי שקיפות, 6 מתוך עד 10 |
| `appstore/<he\|en>/preview.mp4` | App Store, App Preview | 886×1920, 26.7 שניות (15–30), 30fps, H.264 High 4.0, AAC סטריאו 44.1kHz |
| `googleplay/<he\|en>/01…06_*.jpg` | Google Play, טלפון | 1080×1920 (9:16, הגודל שמזכה בקידום), JPEG בלי שקיפות |
| `googleplay/<he\|en>/feature_graphic.jpg` | Google Play, Feature graphic | 1024×500, JPEG בלי שקיפות |
| `googleplay/icon_512.png` | Google Play, אייקון | 512×512, PNG 32 ביט עם ערוץ אלפא |

- ב־Google Play הסרטון הוא קישור YouTube: מעלים את `preview.mp4` ל־YouTube (אנכי נתמך) ומדביקים את הקישור.
- האפליקציה ל־iPhone בלבד, ולכן אין צילומי iPad (`docs/decisions.md`).

## מה רואים

שש התמונות, בכל שפה ובשתי החנויות:

1. מסך הבית — "תפסו את המתחזה" / "Catch the imposter", ומתחת: "משחק הרמזים שבו כולם חשודים" / "The clue game where everyone’s a suspect" (גם ב־feature graphic).
2. כרטיס התפקיד של אזרח ושל המתחזה, זה לצד זה — "מילה סודית אחת. מתחזה אחד."
3. לוח הרמזים עם תגובות — "מילה אחת. רמז אחד."
4. ההצבעה — "הצביעו מי המתחזה".
5. התוצאה — "חשפו את המבלף".
6. בחירת הקטגוריות — "אינספור מילים מכל תחום" / "Endless words from every topic". בלי מספרים, כדי שהכיתוב לא יתיישן כשמוסיפים מילים.

הטלפון במסגרת כללית בלי סימני יצרן (מותר בשתי החנויות), ושורת הסטטוס הפוכה בעברית. הסרטון: כרטיס האזרח ואחריו המתחזה, רמזים מגיעים אחד אחד (כולל הקלדה) עם תגובות, "עוברים להצבעה", הצבעה עם ספירה לאחור, וניצחון האזרחים — עם הצלילים של המשחק ברגעים שלהם. Apple מתירה כיתוב מעל צילום המסך של האפליקציה.

## יצירה מחדש

מהתיקייה `app/`, על Mac (פונט האימוג'י נלקח מהמערכת):

```sh
STORE_ASSETS=1 flutter test test/store
# Screenshots to JPEG, which has no alpha channel (the App Store refuses one);
# Play's icon stays a PNG.
for f in build/store/{appstore,googleplay}/*/*.png; do
  sips -s format jpeg -s formatOptions 92 "$f" --out "${f%.png}.jpg" >/dev/null && rm "$f"
done
for l in he en; do
  swift test/store/encode_video.swift build/store/video/$l build/store/appstore/$l/preview.mp4
done
```

- `test/store/scenes.dart` — השחקנים, המילה והרמזים בכל שפה, והמשחק המתוסרט.
- `test/store/panel.dart` — הרקע, הכותרת והטלפון.
- `test/store/store_test.dart` — הצילומים, הכיתובים, הגדלים וה־feature graphic.
- `test/store/video_test.dart` — הסרטון, פריים אחר פריים, ורגעי הצלילים.
- `test/store/encode_video.swift` — מיקס הצלילים וקידוד ה־MP4.

הבדיקות האלה מדולגות בריצה הרגילה (`flutter test`) ורצות רק עם `STORE_ASSETS=1`.
