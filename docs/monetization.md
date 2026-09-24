# מודל ההכנסות — קטגוריות, פרימיום ופרסומות

המסמך מתאר את מודל ההכנסות כפי שמומש: מה השחקן קונה, איך האפליקציה והשרת
יודעים מה פתוח לו, איפה מוצגות פרסומות, ומה החנויות דורשות. העיצוב המחייב
נמצא ב־`design/claude/Imposter IL Monetization.dc.html` (מסכים P01–P12 וכללי
הפרסומות) וב־`Imposter IL Purchase Prototype.dc.html`.

## המודל

- שלוש קטגוריות פתוחות לכולם: **אוכל, חיות ומקומות**. הרשימה נקבעת בשרת
  (`freeCategoryIds`) ואפשר לשנות אותה בלי גרסת אפליקציה.
- כל שאר הקטגוריות **גלויות ונעולות**: מנעול, שם מעומעם ו־`לפתיחה`. לחיצה
  עליהן פותחת חלון רכישה. **אין מסך חנות.**
- בחלון שלוש אפשרויות:
  1. **רק הקטגוריה הזו** — רכישה חד־פעמית, פתוחה לתמיד. **הפרסומות נשארות.**
  2. **פרימיום חודשי** — מנוי מתחדש: כל הקטגוריות, תכונות הפרימיום ובלי
     פרסומות, כל עוד המנוי פעיל.
  3. **פרימיום לכל החיים** — רכישה חד־פעמית: כל הקטגוריות, גם אלה שיתווספו,
     תכונות הפרימיום ובלי פרסומות לתמיד.
- "תכונות הפרימיום" הן כרגע כל הקטגוריות והיעדר פרסומות. אין תכונה נוספת
  שמומשה; `Monetization.premium` הוא הדגל שכל תכונה עתידית תיבדק מולו.
- המחירים **אינם בקוד ואינם בשרת**: הם נקראים מהחנות, במטבע ובפורמט של חשבון
  החנות, ומוצגים כפי שהם.

### מזהי מוצרים

| מוצר | מזהה | סוג ב־App Store | סוג ב־Google Play |
| --- | --- | --- | --- |
| קטגוריה | `category_<id>` (למשל `category_sports`) | Non-Consumable | One-time product |
| פרימיום חודשי | `premium_monthly` | Auto-Renewable Subscription, חודש | Subscription, base plan חודשי |
| פרימיום לכל החיים | `premium_lifetime` | Non-Consumable | One-time product |

קטגוריה חדשה צריכה מוצר חדש בשתי החנויות, ולא שינוי קוד או הגדרה. מזהה מוצר
ב־App Store אינו ניתן לשימוש חוזר לעולם, גם אחרי מחיקה.

## ארכיטקטורה

```text
StoreKit 2 / Play Billing 8 ──► app/lib/monetization/store.dart (PluginStore)
                                        │  purchases, restore, complete
                                        ▼
GET /v1/config ──────────────► Monetization (ChangeNotifier) ◄── SharedPreferences
                                        │   מה פתוח, מה מוצג       (מטמון לא־מקוון)
POST /v1/entitlements ◄─────────────────┘
        │
        ▼
server/internal/monetization: Apple JWS, Google Play API ──► session.entitlements
        │
        ▼
POST /v1/rooms · matchmaking.join · room.updateSettings ──► 403 category_locked
```

### מקור האמת: החנות

- בכל הפעלה ובכל חזרה מהרקע האפליקציה שואלת את החנות מה החשבון מחזיק עכשיו,
  **בשקט**: StoreKit 2 מחזיר את `Transaction.currentEntitlements` ו־Play Billing
  את הרכישות הפעילות. אף אחד מהם אינו מבקש להתחבר, ושניהם כבר מסננים החזרים
  כספיים, ביטולים ומנויים שפגו.
- התשובה **מחליפה** את מה שהאפליקציה החזיקה. כך החזר כספי, ביטול מנוי ופקיעתו
  מגיעים לאפליקציה בלי מנגנון נוסף.
- התשובה האחרונה נשמרת במכשיר (`monetization.*` ב־`SharedPreferences`), ולכן
  במצב לא מקוון השחקן שומר את מה ששילם עליו, כולל במשחק במכשיר אחד.
- מנוי חודשי פג במכשיר במועד שבעסקה החתומה של StoreKit. ב־Play אין לאפליקציה
  מועד כזה: היא משתמשת במועד שהשרת קיבל מ־Google, ואם אין — בחסד של 7 ימים
  (`Monetization.undatedGrace`) עד התשובה הבאה מהחנות. מנוי ש־StoreKit עדיין
  מחזיר אחרי מועדו (Billing Grace Period) נחשב פעיל.
- רכישה חדשה נמסרת ונפתחת במכשיר, ואז העסקה נסגרת (`completePurchase`). הסגירה
  **אינה מחכה לשרת שלנו**: Play מחזיר את הכסף על רכישה שלא אושרה תוך שלושה ימים,
  ותקלה בשרת אסור שתהפוך להחזר.
- רכישה ממתינה (Ask to Buy, אמצעי תשלום איטי) אינה פותחת דבר ואינה נסגרת עד
  שהחנות מוסרת אותה כמאושרת.

### השרת: אכיפה ברשת ובחדרים פרטיים

השרת סמכותי למשחק, ולכן גם לקטגוריות שבהן משחקים ברשת:

- האפליקציה שולחת את ההוכחות של החנות ל־`POST /v1/entitlements` אחרי כל שינוי
  ואחרי כל session חדש (כולל session שהוחלף אחרי אתחול שרת). השליחה סדרתית:
  בקשה אחת בכל פעם, ולא יותר מאחת ממתינה.
- **Apple:** העסקה החתומה (JWS) של StoreKit 2 נבדקת בשרת בלי רשת ובלי מפתח
  API: שרשרת ה־x5c עד Apple Root CA - G3 (מוטמע), הרחבות ה־OID של Apple על
  התעודות, חתימת ES256, bundle id, מזהה המוצר, `revocationDate` ו־`expiresDate`.
  השרשרת נבדקת לפי מועד החתימה, כמו הספרייה של Apple במצב לא מקוון.
- **Google:** purchase token נבדק מול Google Play Developer API
  (`purchases.products` ו־`purchases.subscriptionsv2`) בחשבון שירות. `ACTIVE`,
  `IN_GRACE_PERIOD` ו־`CANCELED` (עד סוף התקופה ששולמה) פותחים; `ON_HOLD`,
  `PAUSED`, `EXPIRED` ו־`REVOKED` לא.
- התוצאה נשמרת על ה־session בזיכרון בלבד, כמו כל השאר — אין מסד נתונים.
  הוכחה שבדיקתה נכשלה בגלל תקלה אצל החנות (`verification_unavailable`) אינה
  לוקחת מהשחקן את מה שהיה לו.
- **חדר פרטי:** נבדקות הקטגוריות שהמנהל בוחר, מול הרכישות שלו. המצטרפים אינם
  צריכים דבר — מי שקנה קטגוריה יכול לשחק בה עם חברים.
- **משחק ברשת:** כל מחפש נבדק מול הקטגוריות שלו. הקבוצה משחקת בחיתוך שלהן, ולכן
  שחקן חינמי מתאים רק לשחקנים שחולקים איתו קטגוריה חינמית.
- **משחק במכשיר אחד:** אין שרת, והאכיפה היא של האפליקציה, מאותו מקור.
- האפליקציה מונעת בחירה של קטגוריה נעולה בכל שלושת המצבים. `category_locked`
  מהשרת מגיע רק כשהשרת לא ראה רכישה שהמכשיר מחזיק; האפליקציה שולחת את ההוכחות
  שוב ומנסה פעם אחת נוספת.

**`serverEnforcement` כבוי כברירת מחדל**, כי אין עדיין חשבונות מפתח ולכן אין
מאמתים. להפעלה:

1. `APPLE_BUNDLE_ID=com.imposteril.app`, `GOOGLE_PLAY_PACKAGE=com.imposteril.app` ו־`GOOGLE_PLAY_SERVICE_ACCOUNT` (סוד:
   קובץ ה־JSON של חשבון שירות עם הרשאת "View financial data" ב־Play Console).
2. `MIN_CLIENT_BUILD=4`. גרסה ישנה שולחת את כל שש הקטגוריות ב־`הכול`, ובלי
   השער הזה היא הייתה מקבלת `category_locked` במקום מסך עדכון.
3. `MONETIZATION_CONFIG={"serverEnforcement":true}`.

שרת שבו האכיפה פעילה בלי שני המאמתים כותב אזהרה בלוג בעלייה.

### מה לא מומש, במכוון

- **App Store Server Notifications V2 ו־Play RTDN.** החזר כספי נקלט בפעם הבאה
  שהאפליקציה שואלת את החנות (בכל הפעלה וחזרה מהרקע), לא ברגע שהוא קורה. בלי
  חשבונות ובלי מסד נתונים אין למי לשייך הודעה כזו. אם יתווסף מסד נתונים — זה
  המקום.
- **רישום token שנוצל.** Google ממליצה לוודא שכל purchase token משמש רק פעם
  אחת. בלי חשבונות, אותה רכישה משוחזרת בכל מכשיר של אותו חשבון חנות, וזה נכון.
- **`appAccountToken` / `obfuscatedAccountId`.** אין חשבון לשייך אליו.

## הגדרה מרחוק

`MONETIZATION_CONFIG` בשרת (JSON, רק מה שמשתנה מברירת המחדל; מפתח שגוי עוצר את
השרת בעלייה) ומוגש ב־`GET /v1/config`. האפליקציה שומרת את האחרונה במכשיר ומשתמשת
בברירת המחדל המובנית בהפעלה הראשונה בלי רשת.

| שדה | ברירת מחדל | משמעות |
| --- | --- | --- |
| `freeCategoryIds` | `food, animals, places` | הקטגוריות החינמיות |
| `products.*` | ראו למעלה | מזהי המוצרים |
| `purchasesEnabled` | `true` | כיבוי כפתורי הקנייה (למשל בתקלה בחנות); השחזור נשאר |
| `serverEnforcement` | `false` | אכיפה בשרת |
| `ads.enabled` | `true` | כל הפרסומות |
| `ads.bannerPlacements` | כל המסכים שבעיצוב | המסכים שבהם יש באנר |
| `ads.interstitialEnabled` | `true` | מודעה במסך מלא אחרי משחק |
| `ads.interstitialMinIntervalSeconds` | `0` | מרווח מינימלי בין מודעות במסך מלא |
| `ads.maxAdContentRating` | `PG` | דירוג התוכן המרבי של AdMob |
| `ads.units.android` / `ads.units.ios` | יחידות ה־AdMob של `pub-9035143252838544` (באנר ומודעה במסך מלא לכל פלטפורמה) | מזהי יחידות המודעה. גרסת release בלי מזהים אינה מציגה פרסומות; גרסת debug משתמשת תמיד במזהי הבדיקה של Google |

## פרסומות

### באנר

באנר אדפטיבי קבוע (Large Anchored Adaptive, AdMob) בתחתית, מתחת לכפתור הראשי
ברווח של 16 פיקסלים — לא מעל כפתורים ולא מעל תוכן. השטח נשמר מרגע שגודל הבאנר
ידוע, ואם אין מודעה הוא נשאר ריק באותו גובה.

| יש באנר | אין באנר |
| --- | --- |
| בית (03), בחירת קטגוריות (04), חיפוש שחקנים (05א–05ג), משחק עם חברים / יצירת חדר / הצטרפות / לובי (18–22), פרופיל, הגדרות, איך משחקים (23–25), הגדרת משחק מקומי (L03, L05) | כניסה ראשונה ושער ההסכמה, חשיפת תפקיד והעברת מכשיר, תורות ורמזים, מעבר להצבעה והצבעה, ניחוש, מסכי תוצאה, ניתוקים ושגיאות, חלון הרכישה |

### מודעה במסך מלא

- רק אחרי משחק **שהושלם** — ברשת, בחדר פרטי ובמכשיר אחד: תוצאה עם מנצח
  (15, 16, L20, L21).
- **התוצאה המלאה מוצגת קודם.** המודעה נפתחת כשהשחקן בוחר `משחק נוסף` או
  `חזרה למסך הבית`, והמעבר קורה אחרי שנסגרה. ברשת, החיפוש החדש מתחיל רק אחרי
  הסגירה, כדי שמשחק לא יתחיל מאחורי המודעה.
- **לעולם לא** אחרי משחק שבוטל (`abandoned`), הופסק (`not_enough_players`),
  נקטע כי המתחזה עזב (`impostor_gone`), הסתיים בהוצאה אחרי ניתוק שלישי, בשגיאה,
  או חיפוש שלא מצא משחק.
- המודעה נטענת מראש. אם לא נטענה — עוברים מיד. תקלה במודעה לעולם אינה חוסמת.

### מי רואה פרסומות

שחקן חינמי, וגם מי שקנה קטגוריה בודדת. **פרימיום חודשי פעיל ופרימיום לכל החיים
— אף באנר ואף מודעה**, וה־SDK אפילו אינו מופעל. רכישת פרימיום באמצע השימוש
מעלימה את הפרסומות מיד.

### הסכמה ומעקב

- ה־SDK מופעל רק מהמסך הראשי, אחרי שער ההסכמה המשפטית, כדי שטופס ההסכמה לא יכסה
  אותו.
- קודם Google UMP: בקשת מידע הסכמה ו־`loadAndShowConsentFormIfRequired`
  (האיחוד האירופי, בריטניה, שווייץ). רק אם `canRequestAds` — אתחול ה־SDK.
- את בקשת ההרשאה של Apple למעקב (ATT) מציג UMP כשהודעת ה־IDFA מוגדרת ב־AdMob
  (Privacy & messaging). הנוסח ב־`NSUserTrackingUsageDescription`, ושום דבר
  במשחק אינו תלוי בתשובה.
- כש־UMP דורש, בהגדרות מופיעה שורה `העדפות פרטיות לפרסומות`.

## מצבים בחלון הרכישה

| מצב | עיצוב | מה קורה |
| --- | --- | --- |
| טעינת מחירים | P01 | שלד במקום המחירים, הכפתור מושבת |
| בחירה | P02–P04 | האפשרות הראשונה נבחרת מראש; הכפתור והגילוי משתנים לפי הבחירה |
| עיבוד | P05 | `מתחברים לחנות…`; אין סגירה, אין חזרה |
| הצלחה | P06, P07 | קטגוריה: `בוחרים ב״X״` בוחר אותה. פרימיום: `מתחילים לשחק` |
| בוטל | P08 | `הרכישה בוטלה. לא בוצע חיוב.` |
| שגיאה | P09 | הסבר ו־`ניסיון נוסף` |
| שחזור | P10–P12 | `משחזרים רכישות…`, `לא נמצאו רכישות קודמות…`, `הרכישות שוחזרו` |
| **ממתין לאישור** | — חדש | `הרכישה ממתינה לאישור…`; שום דבר לא נפתח |
| **שחזור של משהו אחר** | — חדש | `הרכישות שוחזרו, אבל ״X״ לא נמצאה ביניהן.` |
| **שחזור נכשל** | — חדש | `השחזור לא הושלם…` |
| **מחירים לא נטענו** | — חדש | `לא הצלחנו לטעון את המחירים מהחנות…` ו־`ניסיון נוסף` |
| **רכישות כבויות** | — חדש | `הרכישות אינן זמינות כרגע…` (`purchasesEnabled: false`) |

המצבים המסומנים "חדש" נדרשים בחנויות ואינם בעיצוב; הם בנויים מאותה הודעת מצב
(`!` / `i`) של P08–P11. יש להעביר אותם לפרויקט העיצוב.

שחזור רכישות נמצא גם בהגדרות. שחקן פרימיום במכשיר חדש לא רואה אף קטגוריה נעולה,
ולכן אין לו אחרת דרך להגיע לשחזור.

## דרישות החנויות

נבדק ב־23 בספטמבר 2026. המקורות בסוף.

### Apple

- **3.1.1:** פתיחת תוכן ותכונות — קטגוריות, פרימיום והסרת פרסומות — חייבת לעבור
  ב־In-App Purchase, ולרכישות שניתנות לשחזור צריך מנגנון שחזור. ✓ `שחזור רכישות`
  בחלון ובהגדרות.
- **3.1.2:** מנוי מתחדש חייב לתת ערך מתמשך. לפני ההרשמה צריך לתאר מה מקבלים,
  את משך המנוי ואת מחיר החידוש המלא, מקומי ובולט; והמחיר לחיוב חייב להיות
  הבולט ביותר. ✓ הכפתור והגילוי שמתחתיו. **סיכון:** אם הקטגוריות יפסיקו
  להתווסף, בוחן עלול לשאול מה הערך המתמשך מול אפשרות "לכל החיים" — יש להציג את
  המנוי כקטלוג שגדל.
- **קישורים לתנאי שימוש ולמדיניות פרטיות** בחלון הרכישה ובמטא־דאטה של App Store
  Connect. ✓ בחלון. **שדה ה־EULA נשאר ריק** (`docs/legal.md`), ולכן חל ה־EULA
  הסטנדרטי של Apple; יש לקשר אליו בתיאור האפליקציה.
- **5.1.1 / 5.1.2:** מדיניות הפרטיות מפרטת את Google AdMob כצד שלישי. ATT נדרש
  לגישה ל־IDFA ואסור לתת תגמול על הסכמה. ✓
- **2.5.18:** פרסומות מתאימות לדירוג הגיל. ✓ `maxAdContentRating: PG`.
- **קטגוריית הילדים (1.3, 5.1.4):** פרסומות צד שלישי ורכישות מחוץ לשער הורים
  אסורות בה. **לא נרשמים אליה** — קהל היעד המוצהר הוא 13+ (`docs/decisions.md`).
- **Privacy manifest:** `ios/Runner/PrivacyInfo.xcprivacy` מצהיר על הקוד של
  האפליקציה, כולל היסטוריית הרכישות שנשלחת לשרת; ה־SDK של Google Mobile Ads מביא
  manifest משלו.

### Google Play

- **Payments:** כל תוכן דיגיטלי, כולל גרסה בלי פרסומות, דרך Google Play Billing.
  ✓ `in_app_purchase_android` 0.5.3 על **Play Billing Library 8** — הגרסה
  המינימלית לאפליקציות ועדכונים מ־31 באוגוסט 2026.
- **אישור תוך 3 ימים** או החזר אוטומטי. ✓ נסגר מיד עם המסירה, בלי תלות בשרת.
- **Subscriptions:** מחיר, תדירות החיוב ותנאי החידוש, דרך קלה לבטל, והכול בשפת
  הממשק — גילוי חלקי או לא מתורגם הוא הפרה. ✓ בעברית.
- **Families:** חל רק על קהל יעד מתחת ל־13. מוצהר 13+, ולכן אינו חל. אילו הוצהר
  — AdMob מופיע ברשימת ה־SDK המאושרים למשפחות, עם תיוג בקשות לילדים ו־`G`.
- **Data safety:** יש להצהיר על מה שה־SDK של AdMob אוסף (ראו `docs/legal.md`).

### AdMob

- מודעות במסך מלא רק בהפסקות טבעיות, לא בפתיחת האפליקציה, לא ביציאה ממנה, לא
  באמצע משחק ולא אחת אחרי השנייה. ✓ אחרי תוצאה, כשהשחקן בחר להמשיך.
- באנר לא צמוד לכפתורים ולא במסכי משחק פעיל. ✓ 16 פיקסלים מתחת לכפתור, רק
  במסכים שמחוץ למשחק.
- **app-ads.txt** באתר המפתח שמופיע בדפי החנויות: `https://imposteril.github.io/app-ads.txt` (`site/app-ads.txt`), עם מזהה ה־publisher `pub-9035143252838544`.

## מזהי AdMob

| | Android | iOS |
| --- | --- | --- |
| אפליקציה | `ca-app-pub-9035143252838544~9971528166` (`AndroidManifest.xml`) | `ca-app-pub-9035143252838544~8790308438` (`Info.plist`) |
| באנר | `ca-app-pub-9035143252838544/5555882846` | `ca-app-pub-9035143252838544/4438156576` |
| מסך מלא אחרי משחק | `ca-app-pub-9035143252838544/5751238243` | `ca-app-pub-9035143252838544/8466874805` |

מזהי היחידות נמצאים בברירת המחדל של השרת ואפשר להחליף אותם ב־`MONETIZATION_CONFIG` בלי גרסה. מזהי האפליקציה נכנסים ל־build ולכן משתנים רק בגרסה חדשה.

## גרסאות

| חבילה | גרסה | הערה |
| --- | --- | --- |
| `in_app_purchase` | 3.3.1 | StoreKit 2 כברירת מחדל |
| `in_app_purchase_storekit` | 0.4.13 | ה־JWS ב־`serverVerificationData`; שחזור דרך `Transaction.currentEntitlements` |
| `in_app_purchase_android` | 0.5.3 | Play Billing Library 8.0.0 |
| `google_mobile_ads` | 9.1.0 | GMA Android 25.4, iOS 13.7, UMP מובנה |

## מקורות

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — 1.3, 2.5.18, 3.1.1, 3.1.2, 5.1.1, 5.1.2, 5.1.4
- [Apple — Auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/)
- [Apple — Custom license agreement](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/) · [Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)
- [Apple — User privacy and data use](https://developer.apple.com/app-store/user-privacy-and-data-use/) · [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple — Transaction.finish()](https://developer.apple.com/documentation/storekit/transaction/finish()) · [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype) · [Apple PKI](https://www.apple.com/certificateauthority/)
- [Google Play — Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738) · [Subscriptions policy](https://support.google.com/googleplay/android-developer/answer/9900533)
- [Play Billing — deprecation FAQ](https://developer.android.com/google/play/billing/deprecation-faq) · [Integrate](https://developer.android.com/google/play/billing/integrate) · [Subscription lifecycle](https://developer.android.com/google/play/billing/lifecycle/subscriptions) · [Security](https://developer.android.com/google/play/billing/security)
- [Google Play — Families policy](https://support.google.com/googleplay/android-developer/answer/9893335) · [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469)
- [AdMob — interstitial guidance](https://support.google.com/admob/answer/6201362) · [disallowed interstitial implementations](https://support.google.com/admob/answer/6066980) · [banner placement](https://support.google.com/admob/answer/6128877) · [app-ads.txt](https://support.google.com/admob/answer/9363762) · [frequency capping](https://support.google.com/admob/answer/6244508)
- [AdMob Flutter — banners](https://developers.google.com/admob/flutter/banner) · [privacy (UMP)](https://developers.google.com/admob/flutter/privacy) · [iOS privacy strategies](https://developers.google.com/admob/ios/privacy/strategies) · [iOS data disclosure](https://developers.google.com/admob/ios/privacy/data-disclosure) · [Android data disclosure](https://developers.google.com/admob/android/privacy/play-data-disclosure)
- [Google certified CMP requirement](https://support.google.com/admob/answer/13554116)
- pub.dev: [in_app_purchase](https://pub.dev/packages/in_app_purchase) · [in_app_purchase_android](https://pub.dev/packages/in_app_purchase_android/changelog) · [in_app_purchase_storekit](https://pub.dev/packages/in_app_purchase_storekit/changelog) · [google_mobile_ads](https://pub.dev/packages/google_mobile_ads/changelog)
