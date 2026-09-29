// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppLocalizationsHe extends AppLocalizations {
  AppLocalizationsHe([String locale = 'he']) : super(locale);

  @override
  String get appTitle => 'מי המתחזה?‏';

  @override
  String get settings => 'הגדרות';

  @override
  String get profile => 'פרופיל';

  @override
  String get gameName => 'מי המתחזה?';

  @override
  String get homeTagline => 'כולם יודעים את המילה. חוץ מאחד.';

  @override
  String get onlineGame => 'משחק ברשת';

  @override
  String get oneDeviceGame => 'משחק במכשיר אחד';

  @override
  String get howToPlay => 'איך משחקים?';

  @override
  String get resumeGameTitle => 'להמשיך את המשחק?';

  @override
  String resumeGameDetails(Object round, Object playersLength) {
    return 'סיבוב $round נשמר במכשיר · $playersLength שחקנים';
  }

  @override
  String get resumeGame => 'המשך משחק';

  @override
  String get deleteGame => 'מחיקת המשחק';

  @override
  String get legalDate => '26 בספטמבר 2026';

  @override
  String get legalGateTitle => 'לפני שמתחילים';

  @override
  String get legalConsent =>
      'קראתי ואני מסכים/ה לתנאי השימוש ומאשר/ת שקראתי את מדיניות הפרטיות.';

  @override
  String get saving => 'שומרים...';

  @override
  String get acceptAndContinue => 'אישור והמשך';

  @override
  String get legalGateHeadline => 'משחק הוגן מתחיל בכללים ברורים';

  @override
  String get legalGateBody =>
      'במשחק כותבים כינויים ורמזים ששחקנים אחרים יכולים לראות. אנחנו מסננים תוכן לא מתאים ומאפשרים לדווח ולהסתיר שחקנים.';

  @override
  String get termsTitle => 'תנאי שימוש';

  @override
  String get termsSubtitle => 'כללי המשחק, תוכן אסור ודיווחים';

  @override
  String get privacyTitle => 'מדיניות פרטיות';

  @override
  String get privacySubtitle => 'איזה מידע נשמר, איפה ולכמה זמן';

  @override
  String legalDocsVersion(Object legalVersion, Object legalDate) {
    return 'גרסת מסמכים $legalVersion · $legalDate';
  }

  @override
  String termsIntro(Object legalVersion, Object legalDate) {
    return 'גרסה $legalVersion · בתוקף מ־$legalDate\n\nהשימוש ב״מי המתחזה?״ כפוף לתנאים הבאים. המשחק מיועד לבני 13 ומעלה. אם מלאו לכם 13 אך אינכם בגיל שמאפשר לכם להסכים לתנאים במקום מגוריכם, השתמשו במשחק רק באישור ובהשגחת הורה או אפוטרופוס.';
  }

  @override
  String get terms1Title => '1. השירות';

  @override
  String get terms1 =>
      '״מי המתחזה?״ הוא משחק חברתי מקוון המופעל על ידי Imposter IL (imposteril36@gmail.com). אין צורך בחשבון. אתם בוחרים כינוי ואווטאר ומקבלים מזהה אורח זמני לצורך המשחק.';

  @override
  String get terms2Title => '2. כללי התנהגות ותוכן';

  @override
  String get terms2 =>
      'אין לפרסם בכינוי או ברמז תוכן מיני מפורש, איומים, דברי שנאה, השפלה או הטרדה, תוכן בלתי חוקי, התחזות לאדם אחר, פרטים אישיים של אדם אחר או תוכן שנועד לפגוע בשחקנים. אין לנסות לעקוף את מסנני התוכן או לנצל לרעה את השרת, החדרים, מנגנון הדיווח או המשחק.';

  @override
  String get terms3Title => '3. תוכן של שחקנים';

  @override
  String get terms3 =>
      'כינויים ורמזים שכתבתם מוצגים לשחקנים אחרים במשחק. אתם אחראים לתוכן שאתם שולחים. המשחק רשאי לסרב לתוכן, להסתירו או להפסיק גישה במקרה של הפרת הכללים. שחקנים יכולים לדווח על תוכן ולהסתיר תוכן של שחקן שדווח במכשיר שלהם. דיווחים נבדקים בתוך 24 שעות, ותוכן שמפר את הכללים מתווסף לסינון.';

  @override
  String get terms4Title => '4. משחקים, תוצאות וסטטיסטיקה';

  @override
  String get terms4 =>
      'המשחק עשוי להסתיים עקב ניתוק, תקלה או תחזוקה. ניצחונות והפסדים נשמרים במכשיר בלבד ואינם חשבון, דירוג או נכס שניתן לשחזר לאחר מחיקת האפליקציה או מעבר מכשיר.';

  @override
  String get terms5Title => '5. רכישות, מנויים ופרסומות';

  @override
  String get terms5 =>
      'שלוש קטגוריות פתוחות בחינם. את שאר הקטגוריות אפשר לפתוח ברכישה של קטגוריה אחת לתמיד, במנוי פרימיום חודשי או ברכישת פרימיום לכל החיים. פרימיום פותח את כל הקטגוריות, גם כאלה שיתווספו, ומסיר את הפרסומות; רכישת קטגוריה בודדת אינה מסירה פרסומות. התשלום, החיוב, החידוש וההחזרים מתבצעים דרך App Store או Google Play, בכפוף לתנאים שלהם ובמחיר שהחנות מציגה במטבע של חשבונכם. המנוי החודשי מתחדש אוטומטית בכל חודש עד לביטול. אפשר לבטל אותו בכל עת בהגדרות המנויים בחנות, לפחות 24 שעות לפני מועד החידוש, והגישה נשארת עד סוף התקופה ששולמה. רכישה שהוחזרה או בוטלה בחנות מפסיקה לפתוח את מה שפתחה. רכישות שייכות לחשבון החנות ולא למכשיר, ואפשר לשחזר אותן בכל מכשיר עם אותו חשבון באמצעות ״שחזור רכישות״. למי שאין לו פרימיום מוצגות פרסומות של צד שלישי במסכים שמחוץ למשחק ואחרי משחק שהסתיים. במכשירי Apple חל גם הסכם הרישיון הסטנדרטי של Apple למשתמש קצה (EULA). אין באמור כדי לגרוע מזכויות שלכם לפי דיני הגנת הצרכן החלים, לרבות ביטול עסקה.';

  @override
  String get terms6Title => '6. זמינות ושינויים';

  @override
  String get terms6 =>
      'השירות ניתן כפי שהוא ובהתאם לזמינות. מפעיל השירות רשאי לתקן באגים, לשנות כללים ותוכן, להגביל גרסאות ישנות או להפסיק חלקים מהשירות. כששינוי מהותי בתנאים דורש הסכמה מחודשת, האפליקציה תציג את הגרסה החדשה לפני המשך המשחק.';

  @override
  String get terms7Title => '7. קניין רוחני';

  @override
  String get terms7 =>
      'השם, העיצוב, הקוד, האיורים ותוכן המשחק שייכים לבעליהם ומוגנים לפי הדין החל. אין להעתיק, להפיץ, לבצע הנדסה לאחור או להשתמש בנכסי המשחק מעבר למה שמותר בדין או ברישיונות החלים.';

  @override
  String get terms8Title => '8. אחריות';

  @override
  String get terms8 =>
      'במידה המרבית המותרת לפי דין, אין התחייבות שהשירות יהיה רציף או נטול שגיאות. אין בתנאים כדי לגרוע מזכויות צרכניות שלא ניתן לוותר עליהן לפי הדין החל.';

  @override
  String get terms9Title => '9. פרטיות';

  @override
  String get terms9 =>
      'מדיניות הפרטיות מתארת את המידע שבו השירות משתמש ואת תקופות השמירה והיא חלק מהשימוש בשירות.';

  @override
  String get terms10Title => '10. שינויים בתנאים';

  @override
  String get terms10 =>
      'שינוי מהותי יקבל גרסת מסמכים חדשה. האפליקציה שומרת במכשיר את גרסת התנאים שאושרה ויכולה לדרוש אישור מחדש לגרסה חדשה.';

  @override
  String get terms11Title => '11. דין וסמכות שיפוט';

  @override
  String get terms11 =>
      'על תנאים אלה חלים דיני מדינת ישראל, וסמכות השיפוט הבלעדית נתונה לבתי המשפט המוסמכים במחוז תל אביב־יפו. אין באמור כדי לגרוע מזכותכם לתבוע במקום מגוריכם כאשר הדין החל עליכם מקנה לכם זכות כזו.';

  @override
  String get terms12Title => '12. יצירת קשר';

  @override
  String get terms12 =>
      'Imposter IL · imposteril36@gmail.com\nלתמיכה, לדיווח על תוכן פוגעני ולכל שאלה על התנאים האלה.';

  @override
  String privacyIntro(Object legalVersion, Object legalDate) {
    return 'גרסה $legalVersion · בתוקף מ־$legalDate\n\nהמדיניות מתארת את המידע שבו ״מי המתחזה?״ משתמש כדי להפעיל משחקים, לשמור העדפות ולהגן על שחקנים.';
  }

  @override
  String get privacy1Title => '1. מי אנחנו';

  @override
  String get privacy1 =>
      'המשחק ״מי המתחזה?״ מופעל על ידי Imposter IL, והמדיניות הזאת חלה על האפליקציה ועל השרת שמפעיל אותה. לפניות בנושא פרטיות: imposteril36@gmail.com.';

  @override
  String get privacy2Title => '2. מידע שנשמר במכשיר';

  @override
  String get privacy2 =>
      'האפליקציה שומרת במכשיר את מזהה ה־session וה־player הזמניים, הכינוי והאווטאר, ניצחונות והפסדים, הגדרות רטט ותגובות, גרסת המסמכים שאושרה ורשימת מזהי שחקנים שדיווחתם עליהם כדי להסתיר את התוכן שלהם. מחיקת האפליקציה או נתוניה עשויה למחוק מידע זה. לאחר רכישה נשמרים גם הקטגוריות והפרימיום שבבעלותכם ומועד התוקף של המנוי, כדי שיישארו פתוחים גם בלי חיבור, וכן הגדרות הפרסומות שהתקבלו מהשרת ומועד המודעה האחרונה במסך מלא.';

  @override
  String get privacy3Title => '3. מידע שנשלח לשרת';

  @override
  String get privacy3 =>
      'כדי להפעיל משחקים השרת מקבל מזהה שחקן ו־session, כינוי, אווטאר, כתובת IP לצורכי אבטחה והגבלת קצב, חברות בחדרים ובמשחקים, קטגוריות שנבחרו, רמזים, תגובות, הצבעות, ניחושים ודיווחים. אין צורך בשם אמיתי, מספר טלפון או כתובת דוא״ל כדי לשחק. כדי לפתוח ברשת קטגוריות שרכשתם, האפליקציה שולחת לשרת את ההוכחה שהחנות מספקת לרכישה — עסקה חתומה של Apple או אסימון רכישה של Google, הכוללים את מזהה המוצר, מזהה העסקה ומועדיה. השרת מאמת אותה מול Apple או Google. אנחנו לא מקבלים את פרטי התשלום שלכם.';

  @override
  String get privacy4Title => '4. מטרות השימוש';

  @override
  String get privacy4 =>
      'המידע משמש להפעלת matchmaking וחדרים, סנכרון המשחק בזמן אמת, חיבור מחדש, אכיפת כללי המשחק, מניעת abuse, טיפול בדיווחים, אבטחה, איתור תקלות ומדידת בריאות השרת. המידע משמש גם לאימות רכישות ולאכיפת הקטגוריות הפתוחות, ולהצגת פרסומות למי שאין לו פרימיום.';

  @override
  String get privacy5Title => '5. מה שחקנים אחרים רואים';

  @override
  String get privacy5 =>
      'שחקנים באותו משחק יכולים לראות את הכינוי והאווטאר שלכם, רמזים ששלחתם, מצב החיבור ומידע משחק הנדרש להצבעה ולתוצאה. המילה הסודית אינה נשלחת למתחזה לפני שלב התוצאה.';

  @override
  String get privacy6Title => '6. שמירה ומחיקה';

  @override
  String get privacy6 =>
      'מצב המשחק והחדרים נשמר בזיכרון השרת ולא במסד נתונים קבוע. session מנותק שאינו נמצא בחדר נמחק לאחר תקופת חוסר פעילות של עד 24 שעות, וחדר ריק נסגר לאחר 30 דקות. אתחול שרת מוחק את מצב המשחק שבזיכרון. לוגים תפעוליים עשויים להישמר לצורכי אבטחה ואבחון ולכלול מזהי שחקן בדויים ומטא־דאטה של דיווחים. תוצאת אימות הרכישות נשמרת בזיכרון השרת לצד ה־session בלבד ונמחקת איתו. דיווח נשמר בלוג יחד עם הרמז והכינוי שדווחו, כדי שאפשר יהיה לבדוק אותו.';

  @override
  String get privacy7Title => '7. שירותים חיצוניים';

  @override
  String get privacy7 =>
      'השרת מתארח ב־Google Cloud Platform (Cloud Run, אזור us-central1), וגוגל מעבדת מידע טכני הנדרש להעברת התעבורה ולשמירת הלוגים התפעוליים, כמעבדת מידע מטעמנו ובכפוף להתחייבויות אבטחה ופרטיות ברמה זהה או טובה יותר מזו שמתוארת כאן. התשלומים מתבצעים ב־App Store של Apple וב־Google Play, לפי מדיניות הפרטיות שלהם. למי שאין לו פרימיום מוצגות פרסומות של Google AdMob. AdMob עשויה לאסוף מזהי מכשיר ומזהה פרסום, כתובת IP, מידע על אינטראקציה עם מודעות, מידע אבחון וביצועים, לצורך הצגת מודעות, מדידתן ומניעת הונאה, לפי מדיניות הפרסום של Google (policies.google.com/technologies/ads). במקומות שבהם הדין מחייב, ובהם האיחוד האירופי ובריטניה, מתבקשת הסכמתכם לפני פרסום מותאם אישית; ב־iPhone לא נעשה שימוש במזהה הפרסום ללא הרשאתכם. כדי לאתר ולתקן תקלות, כשהאפליקציה קורסת או נתקלת בשגיאה היא שולחת דוח ל־Firebase Crashlytics של Google: פרטי השגיאה ומיקומה בקוד, דגם המכשיר, מערכת ההפעלה, גרסת האפליקציה ומזהה התקנה אקראי של Crashlytics. הדוח אינו כולל כינוי, רמזים או מזהה פרסום, והוא נשמר עד 90 יום. אין מכירת מידע אישי, ואין SDK צד שלישי ל־analytics.';

  @override
  String get privacy8Title => '8. ילדים ופרטים אישיים';

  @override
  String get privacy8 =>
      'המשחק אינו מבקש שם אמיתי או פרטי קשר. אין לכתוב בכינוי או ברמז מידע אישי שלכם או של אחרים. המשחק מיועד לבני 13 ומעלה ואינו מיועד לילדים. איננו אוספים ביודעין מידע מילדים מתחת לגיל 13, ואם ייוודע לנו על כך נמחק את המידע הקשור אליהם. המודעות מוגבלות לתוכן בדירוג שמתאים לקהל רחב.';

  @override
  String get privacy9Title => '9. בחירה ושליטה';

  @override
  String get privacy9 =>
      'אפשר לשנות כינוי ואווטאר, לכבות רטט או תגובות, לדווח על שחקן ולנקות את רשימת השחקנים שהוסתרו. מחיקת נתוני האפליקציה מסירה את המידע המקומי. מאחר שאין חשבון קבוע, אין מנגנון שחזור של נתונים מקומיים. אפשר גם לשנות את העדפות הפרטיות לפרסומות בהגדרות, כשהדין מחייב, לסרב להרשאת מעקב ב־iPhone או לאפס את מזהה הפרסום בהגדרות המכשיר. פרימיום מסיר את כל הפרסומות.';

  @override
  String get privacy10Title => '10. הזכויות שלכם';

  @override
  String get privacy10 =>
      'לפי חוק הגנת הפרטיות התשמ״א־1981 ותיקון 13 לו, ובמקומות שבהם חל ה־GDPR, יש לכם זכות לעיין במידע שנשמר עליכם, לבקש את תיקונו, למחוק אותו, להגביל או להתנגד לעיבודו ולקבלו בפורמט נגיש. מאחר שאין חשבון, נדרש מזהה השחקן או ה־session שמופיע במסך ההגדרות כדי לאתר מידע שקשור אליכם. לבקשה כתבו ל־imposteril36@gmail.com; נענה בתוך 30 יום. מרבית המידע נמחק ממילא מאליו — מצב המשחק בסיום המשחק, session לאחר 24 שעות והלוגים לאחר 30 יום.';

  @override
  String get privacy11Title => '11. אבטחה';

  @override
  String get privacy11 =>
      'התעבורה בגרסאות הפצה נועדה לעבור בחיבור מוצפן. השרת מפעיל מגבלות קצב, מגבלות גודל הודעה וסינון תוכן כדי להפחית שימוש לרעה. אין מערכת שיכולה להבטיח אבטחה מוחלטת.';

  @override
  String get privacy12Title => '12. שינויים במדיניות';

  @override
  String get privacy12 =>
      'שינוי מהותי במדיניות יקבל גרסה חדשה. כאשר נדרשת הסכמה מחודשת, האפליקציה תציג את הגרסה החדשה לפני המשך המשחק.';

  @override
  String get privacy13Title => '13. יצירת קשר';

  @override
  String get privacy13 =>
      'Imposter IL · imposteril36@gmail.com\nלפניות בנושא פרטיות, בקשות למימוש זכויות ודיווח על תוכן פוגעני. נשתדל להשיב בתוך 30 יום.';

  @override
  String legalPublicCopy(Object value) {
    return 'עותק ציבורי: $value';
  }

  @override
  String get errNotRoomHost => 'רק מנהל החדר יכול לבצע את הפעולה הזאת.';

  @override
  String get errNotEnoughPlayers => 'צריך לפחות 4 שחקנים כדי להתחיל.';

  @override
  String get errContentUnavailable =>
      'אי אפשר להתחיל משחק כרגע. נסו שוב בעוד רגע.';

  @override
  String get errRoomInGame => 'כבר מתנהל משחק בחדר הזה.';

  @override
  String get errWrongPhase => 'השלב הזה כבר הסתיים.';

  @override
  String get errNotYourTurn => 'זה לא התור שלכם.';

  @override
  String get errHintEmpty => 'כתבו רמז לפני השליחה.';

  @override
  String get errHintNotOneWord => 'אפשר לשלוח מילה אחת בלבד.';

  @override
  String get errHintTooLong => 'הרמז יכול להכיל עד 25 תווים.';

  @override
  String get errHintInappropriate => 'הרמז הזה לא מתאים. נסו מילה אחרת.';

  @override
  String get errHintContainsSecret =>
      'הרמז מכיל את המילה הסודית. בחרו מילה אחרת.';

  @override
  String get errHintDuplicate => 'הרמז הזה כבר נשלח במשחק. בחרו מילה אחרת.';

  @override
  String get errSelfVote => 'אי אפשר להצביע לעצמכם.';

  @override
  String get errInvalidVoteTarget => 'אי אפשר להצביע לשחקן הזה.';

  @override
  String get errNetwork => 'אין חיבור לשרת. בדקו את החיבור ונסו שוב.';

  @override
  String get errCategoryLockedRoom =>
      'אחת הקטגוריות כבר לא פתוחה. קטגוריה שנפתחה בצפייה במודעה פתוחה למשחק אחד בלבד. אפשר לחדש את הפרימיום, לשחזר רכישות או ליצור חדר חדש.';

  @override
  String get errGeneric => 'משהו השתבש. נסו שוב בעוד רגע.';

  @override
  String get leaveGameTitle => 'לצאת מהמשחק?';

  @override
  String get leaveGameBody => 'יציאה באמצע המשחק נרשמת כהפסד.';

  @override
  String get leave => 'יציאה';

  @override
  String get stillCantConnect => 'עדיין אי אפשר להתחבר. נסו שוב בעוד רגע.';

  @override
  String get kickedByHost => 'מנהל החדר הסיר אתכם מהחדר.';

  @override
  String get reconnecting => 'מתחברים מחדש...';

  @override
  String get connectionLostOnTurn =>
      'החיבור אבד בזמן התור שלכם. ננסה להחזיר אתכם למשחק במשך 30 שניות.';

  @override
  String get connectionLost =>
      'החיבור אבד. ננסה להחזיר אתכם למשחק במשך 30 שניות.';

  @override
  String get disconnectFinalWarning =>
      'אם לא תחזרו בתוך 30 שניות, זה ייספר כניתוק 3 מתוך 3 ותוצאו מהמשחק.';

  @override
  String disconnectWarning(Object disconnectNumber) {
    return 'אם לא תחזרו בתוך 30 שניות, זה ייספר כניתוק $disconnectNumber מתוך 3.';
  }

  @override
  String get turnTimerRunning => ' הזמן בתור ממשיך לרוץ.';

  @override
  String get leaveGameButton => 'יציאה מהמשחק';

  @override
  String disconnectCount(Object disconnectNumber) {
    return 'ניתוק $disconnectNumber מתוך 3';
  }

  @override
  String get groupReady => 'הקבוצה מוכנה!';

  @override
  String get gameStartingSoon => 'המשחק מתחיל בעוד רגע.';

  @override
  String get enoughPlayers => 'יש מספיק שחקנים!';

  @override
  String get waitingForMore =>
      'מחכים כמה שניות לשחקנים נוספים ומתחילים כשהזמן מסתיים.';

  @override
  String get oneMorePlayer => 'עוד שחקן אחד כדי להתחיל';

  @override
  String get stillSearching => 'ממשיכים לחפש שחקנים מתאימים בקטגוריות שבחרתם.';

  @override
  String morePlayersNeeded(Object missing) {
    return 'עוד $missing שחקנים כדי להתחיל';
  }

  @override
  String get searchingPlayers => 'מחפשים שחקנים';

  @override
  String get buildingGroup => 'מרכיבים קבוצת שחקנים';

  @override
  String get cancelSearch => 'ביטול חיפוש';

  @override
  String get yourGroup => 'הקבוצה שלך';

  @override
  String countOfMax(Object count, Object maxPlayers) {
    return '$count מתוך $maxPlayers';
  }

  @override
  String get dontLeavePage => 'נא לא לעזוב עמוד זה.';

  @override
  String get you => 'אתם';

  @override
  String get searchingPlayer => 'מחפשים שחקן...';

  @override
  String get noMatchTitle => 'לא נמצא משחק בקטגוריות שבחרתם';

  @override
  String get noMatchBody =>
      'אפשר לנסות שוב עם אותן קטגוריות, או לבחור קטגוריות אחרות.';

  @override
  String get tryAgain => 'ניסיון נוסף';

  @override
  String get chooseOtherCategories => 'בחירת קטגוריות אחרות';

  @override
  String get privateRoom => 'חדר פרטי';

  @override
  String roomOf(Object hostNickname) {
    return 'החדר של $hostNickname';
  }

  @override
  String get startGame => 'התחלת משחק';

  @override
  String get onlyHostCanStart => 'רק מנהל החדר יכול להתחיל';

  @override
  String get roomCode => 'קוד החדר';

  @override
  String get shareCode => 'שיתוף הקוד';

  @override
  String shareInvite(Object code, Object value) {
    return 'בואו לשחק איתי ב״מי המתחזה?״\nקוד החדר: $code\n$value';
  }

  @override
  String get copyCode => 'העתקת הקוד';

  @override
  String get codeCopied => 'קוד החדר הועתק';

  @override
  String get hostDisconnected => 'מנהל החדר התנתק. ממתינים שיחזור.';

  @override
  String get waitingForNewHost => 'מחכים ששחקן נוסף יתחבר ויקבל את ניהול החדר.';

  @override
  String get hostTransferredToYou => 'מנהל החדר לא חזר בזמן. הניהול עבר אליכם.';

  @override
  String hostTransferredTo(Object hostNickname) {
    return 'הניהול עבר ל־$hostNickname.';
  }

  @override
  String playersOfMax(Object playersLength, Object maxPlayers) {
    return '$playersLength מתוך $maxPlayers שחקנים';
  }

  @override
  String get needFourPlayers => 'צריך לפחות 4 שחקנים כדי להתחיל';

  @override
  String get roomHost => 'מנהל החדר';

  @override
  String get disconnected => 'מנותק';

  @override
  String removePlayer(Object pNickname) {
    return 'הסרת $pNickname';
  }

  @override
  String categoriesList(Object categoryNames) {
    return 'קטגוריות: $categoryNames';
  }

  @override
  String secondsPerHint(Object hintSeconds) {
    return '$hintSeconds שניות לרמז';
  }

  @override
  String get settingsLockedSinceJoin => 'ההגדרות נעולות מאז שהצטרפו שחקנים';

  @override
  String get waitingForOthers => 'ממתינים לשאר השחקנים';

  @override
  String get gotIt => 'הבנתי';

  @override
  String get youAreImpostor => 'את/ה המתחזה';

  @override
  String get youAreCitizen => 'את/ה אזרח/ית';

  @override
  String get impostorDoesntKnow =>
      'המתחזה לא יודע את המילה הסודית. שמרו עליה בסוד.';

  @override
  String get impostorTip1 => 'הקשיבו לרמזים של האחרים ונסו להשתלב.';

  @override
  String get impostorTip2 =>
      'אם תיתפסו — תקבלו הזדמנות אחת לנחש את המילה ולנצח.';

  @override
  String get citizenTip1 => 'בתורכם, כתבו רמז של מילה אחת שמתאים למילה הסודית.';

  @override
  String get citizenTip2 => 'רמז ברור מדי יעזור למתחזה. רמז דק מדי יעורר חשד.';

  @override
  String get nextRoundContinues => 'ממשיכים לסבב הבא';

  @override
  String continuingToRound(Object value) {
    return 'ממשיכים לסיבוב $value';
  }

  @override
  String get tieAgain => 'שוב יש תיקו';

  @override
  String get votesSplitAgain => 'גם הפעם הקולות התחלקו שווה בשווה';

  @override
  String get noOneEliminatedNextRound =>
      'איש לא הודח. ממשיכים לסבב רמזים נוסף.';

  @override
  String get oneVote => 'קול אחד';

  @override
  String nVotes(Object n) {
    return '$n קולות';
  }

  @override
  String get loading => 'טוענים…';

  @override
  String wasCitizen(Object outNickname) {
    return '$outNickname היה/הייתה אזרח/ית';
  }

  @override
  String get decideImpostor => 'זה הזמן להחליט מי המתחזה';

  @override
  String get youEliminatedSpectator => 'הודחת · צופה';

  @override
  String get eliminatedSpectator => 'הודח/ה · צופה';

  @override
  String get leftGame => 'יצא/ה מהמשחק';

  @override
  String get disconnectedWaiting => 'מנותק · ממתינים 30 שניות';

  @override
  String get writingHint => 'כותב/ת רמז';

  @override
  String get waitingTurn => 'ממתין/ה לתור';

  @override
  String get oneHint => '1 רמז';

  @override
  String nHints(Object said) {
    return '$said רמזים';
  }

  @override
  String get noHintSent => 'לא נשלח רמז';

  @override
  String get hidden => 'הוסתר';

  @override
  String get category => 'קטגוריה';

  @override
  String roundTurnOf(Object round, Object turn, Object playingLength) {
    return 'סיבוב $round · תור $turn מתוך $playingLength';
  }

  @override
  String get roundHints => 'הרמזים בסיבוב';

  @override
  String playerWriting(Object currentNickname) {
    return '$currentNickname כותב/ת עכשיו. אפשר להמשיך להגיב למטה.';
  }

  @override
  String playerMe(Object playerNickname) {
    return '$playerNickname · אני';
  }

  @override
  String get yourHintOneWord => 'הרמז שלך · מילה אחת';

  @override
  String get yourHint => 'הרמז שלכם';

  @override
  String hintNotSent(Object error) {
    return '$error הרמז לא נשלח.';
  }

  @override
  String get sendHint => 'שליחת רמז';

  @override
  String get send => 'שליחה';

  @override
  String get showMyWord => 'הצגת המילה שלי';

  @override
  String get myWord => 'המילה שלי';

  @override
  String get close => 'סגירה';

  @override
  String categoryIs(Object category) {
    return 'קטגוריה: $category';
  }

  @override
  String roundN(Object first) {
    return 'סיבוב $first';
  }

  @override
  String roundsRange(Object first, Object last) {
    return 'סיבובים $first–$last';
  }

  @override
  String hintsOf(Object playerNickname) {
    return 'הרמזים של $playerNickname';
  }

  @override
  String get noHintsYet => 'עוד לא נשלחו רמזים.';

  @override
  String get reportHint => 'דיווח על הרמז';

  @override
  String playerDisconnectedTurn(Object nickname) {
    return '$nickname התנתק. ממתינים לו עד 30 שניות — אחר כך התור שלו ידולג.';
  }

  @override
  String get reactions => 'תגובות';

  @override
  String get swipeForReactions => 'גררו לצדדים לעוד תגובות ↔';

  @override
  String get revote => 'הצבעה חוזרת';

  @override
  String get voteReceived => 'ההצבעה נקלטה';

  @override
  String get confirmVote => 'אישור הצבעה';

  @override
  String get choosePlayer =>
      'בחרו שחקן אחד. אפשר לשנות את הבחירה עד שהזמן נגמר.';

  @override
  String get tieRevoteExplain =>
      'היה תיקו. מצביעים שוב רק בין השחקנים שקיבלו את מספר הקולות הגבוה. תיקו נוסף — איש לא מודח והמשחק ממשיך לסבב נוסף.';

  @override
  String get cantVoteSelf => 'אי אפשר להצביע לעצמכם';

  @override
  String get oneVotePrevious => 'קול אחד בסבב הקודם';

  @override
  String nVotesPrevious(Object votes) {
    return '$votes קולות בסבב הקודם';
  }

  @override
  String get youWereCaught => 'נתפסתם';

  @override
  String get sendGuess => 'שליחת ניחוש';

  @override
  String get stillCanWin => 'עוד אפשר לנצח';

  @override
  String get impostorGuessing => 'המתחזה נתפס ועכשיו הוא מנסה לנחש את המילה.';

  @override
  String get guessWinsExplain =>
      'ניחוש נכון של המילה הסודית מעניק לכם את הניצחון. יש לכם ניסיון אחד.';

  @override
  String get othersHints => 'הרמזים של שאר השחקנים';

  @override
  String get whatsTheWord => 'מה המילה?';

  @override
  String get guessHidden => 'הניחוש לא מוצג לשחקנים בזמן ההקלדה';

  @override
  String get guessFailExplain =>
      'אם הזמן ייגמר או שהניחוש יהיה שגוי — האזרחים מנצחים.';

  @override
  String get reasonCitizenVoted => 'ההצבעה סימנה אזרח, והמתחזה נשאר במשחק.';

  @override
  String get reasonParity =>
      'נשארו אזרח אחד ומתחזה — ובשלב הזה המתחזה מנצח מיד.';

  @override
  String get reasonGuessed => 'המתחזה נתפס, אבל הצליח לנחש את המילה.';

  @override
  String get reasonWrongGuess => 'המתחזה נתפס ולא הצליח לנחש את המילה.';

  @override
  String get reasonGuessTimeout => 'המתחזה נתפס, אבל הזמן לניחוש נגמר.';

  @override
  String get reasonImpostorLeft => 'המתחזה עזב את המשחק.';

  @override
  String get reasonNotEnoughPlayers =>
      'נשארו פחות משלושה שחקנים, ולכן המשחק הופסק.';

  @override
  String get reasonAbandoned =>
      'שני סבבי הצבעה עברו בלי אף הצבעה, ולכן המשחק בוטל. הוא לא נספר לאף אחד — לא כניצחון ולא כהפסד.';

  @override
  String get gameCancelled => 'המשחק בוטל';

  @override
  String get citizensWon => 'האזרחים ניצחו!';

  @override
  String get impostorWon => 'המתחזה ניצח!';

  @override
  String get gameStopped => 'המשחק הופסק';

  @override
  String get impostorWas => 'המתחזה היה';

  @override
  String get winRecorded => 'נרשם לכם ניצחון';

  @override
  String get lossRecorded => 'נרשם לכם הפסד';

  @override
  String get abstained => 'נמנעו';

  @override
  String get youLeftGame => 'יצאתם מהמשחק';

  @override
  String get removedThirdDisconnect =>
      'התנתקתם שלוש פעמים במשחק הזה, ולכן שאר השחקנים ממשיכים בלעדיכם.';

  @override
  String get backToHome => 'חזרה למסך הבית';

  @override
  String get reportHintTitle => 'לדווח על הרמז?';

  @override
  String reportHintBody(Object nickname) {
    return 'הרמז יישלח לבדיקה ונטפל בו בתוך 24 שעות. לא תראו יותר רמזים של $nickname במכשיר הזה.';
  }

  @override
  String get cancel => 'ביטול';

  @override
  String get report => 'דיווח';

  @override
  String get reportThanks =>
      'תודה, הדיווח התקבל ויטופל. הרמזים של השחקן יוסתרו במכשיר שלכם.';

  @override
  String reportNotSent(Object value) {
    return 'הרמזים האלה יוסתרו, אבל הדיווח לא נשלח. $value';
  }

  @override
  String get whoAreYou => 'מי אתם במשחק?';

  @override
  String get onboardingSubtitle => 'בוחרים כינוי ואווטאר ומתחילים. בלי הרשמה.';

  @override
  String get continueLabel => 'ממשיכים';

  @override
  String get connecting => 'מתחברים...';

  @override
  String get editDetails => 'עריכת פרטים';

  @override
  String get save => 'שמירה';

  @override
  String get nicknameRule =>
      'בחרו כינוי באורך 2–18 תווים, כולל ניקוד ואימוג׳י.';

  @override
  String get nicknameBlocked => 'הכינוי הזה לא מתאים למשחק. בחרו כינוי אחר.';

  @override
  String get yourNickname => 'הכינוי שלכם';

  @override
  String get nicknameExample => 'למשל: דורון';

  @override
  String nicknameLength(Object maxNicknameLength) {
    return '2–$maxNicknameLength תווים';
  }

  @override
  String get chooseAvatar => 'בחירת אווטאר';

  @override
  String avatarN(Object value) {
    return 'דמות $value';
  }

  @override
  String get errAlreadyInActivity => 'כבר הצטרפתם למשחק או לחדר אחר.';

  @override
  String get errCategoryLocked =>
      'אחת הקטגוריות נעולה. אפשר לשחזר רכישות מחלון הפתיחה של הקטגוריה.';

  @override
  String get canPickSeveral => 'אפשר לבחור כמה קטגוריות';

  @override
  String get all => 'הכול';

  @override
  String get chooseCategories => 'בחירת קטגוריות';

  @override
  String get searchingGame => 'מחפשים משחק...';

  @override
  String get searchGame => 'חפש משחק';

  @override
  String get loadingCategories => 'טוענים את הקטגוריות...';

  @override
  String get allCategories => 'כל הקטגוריות';

  @override
  String get allOpenCategories => 'כל הקטגוריות הפתוחות';

  @override
  String get premium => 'פרימיום';

  @override
  String lockedTapToOpen(Object name) {
    return '$name — נעולה, לחצו לפתיחה';
  }

  @override
  String get purchasedTag => '✓ נרכשה';

  @override
  String get playWithFriends => 'משחק עם חברים';

  @override
  String get createRoom => 'יצירת חדר';

  @override
  String get createRoomSubtitle =>
      'בוחרים הגדרות, מקבלים קוד ומשתפים עם החברים.';

  @override
  String get joinRoom => 'הצטרפות לחדר';

  @override
  String get joinRoomSubtitle => 'יש לכם קוד בן שש ספרות? מזינים ונכנסים.';

  @override
  String get playersRange4to8 => 'המשחק מתאים ל־4 עד 8 שחקנים';

  @override
  String get creatingRoom => 'יוצרים חדר...';

  @override
  String get settingsLockNotice =>
      'לאחר יצירת החדר, לא יהיה ניתן לשנות את ההגדרות.';

  @override
  String get maxPlayers => 'מספר שחקנים מרבי';

  @override
  String get timePerHint => 'זמן לרמז';

  @override
  String nSeconds(Object value) {
    return '$value שניות';
  }

  @override
  String get categories => 'קטגוריות';

  @override
  String get loadingCategoriesShort => 'טוענים קטגוריות...';

  @override
  String get settingsLockAfterJoin =>
      'אחרי ששחקן נוסף יצטרף, אי אפשר יהיה לשנות את ההגדרות.';

  @override
  String get roomCodeSixDigits => 'קוד החדר צריך להיות בן שש ספרות';

  @override
  String get roomNotFound =>
      'החדר לא נמצא או שאינו זמין. בדקו את הקוד עם מי שפתח את החדר.';

  @override
  String get roomFull => 'החדר מלא או שהמשחק כבר התחיל.';

  @override
  String get alreadyInOtherGame => 'כבר הצטרפתם למשחק אחר.';

  @override
  String get join => 'הצטרפות';

  @override
  String get enterRoomCode => 'הזינו את קוד החדר בן שש הספרות שקיבלתם.';

  @override
  String get delete => 'מחיקה';

  @override
  String get myProfile => 'הפרופיל שלי';

  @override
  String get editNicknameAvatar => 'עריכת כינוי ואווטאר';

  @override
  String get wins => 'ניצחונות';

  @override
  String get losses => 'הפסדים';

  @override
  String get sounds => 'צלילים';

  @override
  String get comingSoon => 'בקרוב';

  @override
  String get vibration => 'רטט';

  @override
  String get showReactions => 'הצגת תגובות';

  @override
  String get language => 'שפה';

  @override
  String get languageName => 'עברית';

  @override
  String versionN(Object legalVersion) {
    return 'גרסה $legalVersion';
  }

  @override
  String get manageSubscription => 'ניהול המנוי';

  @override
  String get premiumMonthly => 'פרימיום חודשי';

  @override
  String get adPrivacy => 'העדפות פרטיות לפרסומות';

  @override
  String get appVersion => 'מי המתחזה? · גרסה 1.0';

  @override
  String get contact => 'יצירת קשר';

  @override
  String get reportedPlayers => 'שחקנים שדיווחתם עליהם';

  @override
  String hiddenPlayersCount(Object mutedLength) {
    return '$mutedLength שחקנים מוסתרים';
  }

  @override
  String get clear => 'ניקוי';

  @override
  String get purchasesRestored => 'הרכישות שוחזרו.';

  @override
  String get noPurchasesFound => 'לא נמצאו רכישות קודמות בחשבון החנות הזה.';

  @override
  String get restoreFailed =>
      'השחזור לא הושלם. בדקו את החיבור לאינטרנט ונסו שוב.';

  @override
  String get restoringPurchases => 'משחזרים רכישות…';

  @override
  String get restorePurchases => 'שחזור רכישות';

  @override
  String get howStep1 =>
      'כולם מקבלים את אותה מילה סודית — חוץ מהמתחזה, שרואה רק את הקטגוריה.';

  @override
  String get howStep2 =>
      'כל שחקן כותב בתורו רמז של מילה אחת. לכל תור יש 60 שניות.';

  @override
  String get howStep4 => 'אפשר להגיב לרמזים באמצעות אימוג׳ים והודעות מוכנות.';

  @override
  String get howStep5 => 'בסוף הסבב מצביעים מי המתחזה. יש 20 שניות להצביע.';

  @override
  String get howStep6 =>
      'אם המתחזה נתפס, יש לו 60 שניות לנחש את המילה ולנצח בכל זאת.';

  @override
  String get updateNeeded => 'צריך לעדכן';

  @override
  String get newVersion => 'יש גרסה חדשה של המשחק';

  @override
  String get versionUnsupported =>
      'הגרסה שמותקנת אצלכם כבר לא נתמכת.\nעדכנו את האפליקציה בחנות כדי להמשיך לשחק.';

  @override
  String get somethingWrong => 'משהו השתבש';

  @override
  String get serverFaultStopped =>
      'המשחק הופסק בגלל תקלה בחיבור לשרת. זו לא אשמתכם.';

  @override
  String get serverUnavailable => 'השרת לא זמין כרגע. נסו שוב בעוד רגע.';

  @override
  String get noLossRecorded => 'לא נרשם לכם הפסד';

  @override
  String get localDeleteWarning =>
      'המשחק הנוכחי יימחק ולא יהיה אפשר להמשיך אותו.';

  @override
  String get leaveAndDelete => 'יציאה ומחיקה';

  @override
  String iAmVote(Object currentName) {
    return 'אני $currentName — להצבעה';
  }

  @override
  String iAmShow(Object currentName) {
    return 'אני $currentName — הציגו לי';
  }

  @override
  String votedOf(Object done, Object activePlayersLength) {
    return 'הצביעו $done מתוך $activePlayersLength';
  }

  @override
  String passDeviceTo(Object currentName) {
    return 'העבירו את המכשיר ל$currentName';
  }

  @override
  String get noOneElseLooking => 'אף אחד אחר לא מסתכל על המסך.';

  @override
  String onlyPlayerLooking(Object currentName) {
    return 'רק $currentName מסתכל/ת על המסך.';
  }

  @override
  String get gotItHide => 'הבנתי — הסתירו';

  @override
  String get localImpostorTip => 'הקשיבו לרמזים, השתלבו ונסו לגלות את המילה.';

  @override
  String get localCitizenTip => 'בתור שלכם אומרים בקול רמז של מילה אחת.';

  @override
  String get startRound1 => 'מתחילים סיבוב 1';

  @override
  String startRoundN(Object round) {
    return 'התחלת סיבוב $round';
  }

  @override
  String get everyoneKnowsRoles => 'כולם יודעים מי הם';

  @override
  String get anotherRound => 'סיבוב נוסף';

  @override
  String get placeDevice => 'מניחים את המכשיר במקום שכולם רואים.';

  @override
  String get impostorStillAmong =>
      'המתחזה עדיין ביניכם. סדר התורות הוגרל מחדש.';

  @override
  String get turnOrderThisRound => 'סדר התורות בסיבוב זה';

  @override
  String get startsFirst => 'מתחיל/ה';

  @override
  String get spectator => 'צופה';

  @override
  String get hintRuleLocal =>
      'רמז של מילה אחת, בלי לחזור על רמז קודם ובלי לומר את המילה עצמה.';

  @override
  String roundCategory(Object round, Object category) {
    return 'סיבוב $round · $category';
  }

  @override
  String get hintSaid => 'הרמז נאמר';

  @override
  String turnOf(Object speakerName) {
    return 'התור של $speakerName';
  }

  @override
  String get sayHintAloud => 'אומרים בקול רמז של מילה אחת';

  @override
  String get turnOrder => 'סדר התורות';

  @override
  String get now => 'עכשיו';

  @override
  String get nextUp => 'הבא בתור';

  @override
  String get noHintSaid => 'לא נאמר רמז';

  @override
  String get said => 'אמר/ה';

  @override
  String get waiting => 'ממתין/ה';

  @override
  String get hintsSpokenAloud =>
      'הרמזים נאמרים בקול — אין הקלדה ואין לוח רמזים.';

  @override
  String get passDeviceVote =>
      'מעבירים את המכשיר בין השחקנים. אל תגלו למי הצבעתם.';

  @override
  String get tie => 'יש תיקו';

  @override
  String tieCandidates(Object tieCandidatesLength, int tiedVotes) {
    String _temp0 = intl.Intl.pluralLogic(
      tiedVotes,
      locale: localeName,
      other: '$tiedVotes קולות',
      one: 'קול אחד',
    );
    return '$tieCandidatesLength מועמדים קיבלו $_temp0';
  }

  @override
  String get startRevote => 'מתחילים הצבעה חוזרת';

  @override
  String get thenPassNext => 'אחר כך מעבירים את המכשיר לשחקן הבא';

  @override
  String youreCaught(Object impostorName) {
    return '$impostorName, נתפסת';
  }

  @override
  String get guessWinsLocal =>
      'ניחוש נכון של המילה הסודית מעניק לך את הניצחון. יש ניסיון אחד.';

  @override
  String onlyPlayerLookingNoDot(Object impostorName) {
    return 'רק $impostorName מסתכל/ת על המסך';
  }

  @override
  String get localReasonGuessed => 'המתחזה נתפס וניחש נכון את המילה.';

  @override
  String get localReasonMissed => 'המתחזה נתפס ולא ניחש את המילה.';

  @override
  String get theImpostor => 'המתחזה';

  @override
  String get howItEnded => 'איך זה נגמר';

  @override
  String get whoWasEliminated => 'מי הודח במהלך המשחק';

  @override
  String get localNoStats => 'משחק במכשיר אחד אינו משנה את הסטטיסטיקה בפרופיל.';

  @override
  String playerRound(Object playerName, Object round) {
    return '$playerName · סיבוב $round';
  }

  @override
  String get hiddenNextPlayer => 'הסתרתי — לשחקן הבא';

  @override
  String get voteSaved => 'ההצבעה נשמרה';

  @override
  String get choiceHidden => 'הבחירה הוסתרה מהמסך. אף אחד לא יראה למי הצבעת.';

  @override
  String votingAgainSecret(Object meName) {
    return '$meName מצביע/ה שוב · הבחירה תישאר סודית';
  }

  @override
  String votingSecret(Object meName) {
    return '$meName מצביע/ה · הבחירה תישאר סודית';
  }

  @override
  String get ifTieAgain =>
      'אם גם עכשיו יהיה תיקו — אף אחד לא יודח ומתחיל סיבוב רמזים חדש.';

  @override
  String get screenClearsNext =>
      'אחרי האישור המסך יתנקה לפני ההעברה לשחקן הבא.';

  @override
  String playerN(Object seat) {
    return 'שחקן $seat';
  }

  @override
  String get everyPlayerNeedsName => 'לכל שחקן צריך להיות שם';

  @override
  String get namesMustDiffer => 'לכל שחקן צריך להיות שם שונה';

  @override
  String get continueToSettings => 'המשך להגדרות';

  @override
  String get whoIsPlaying => 'מי משחק?';

  @override
  String get oneDevicePassed => 'מכשיר אחד עובר בין כולם. הרמזים נאמרים בקול.';

  @override
  String get tapAvatarToChange =>
      'לחיצה על אווטאר מחליפה אותו באחד שלא בשימוש.';

  @override
  String get fewerPlayers => 'פחות שחקנים';

  @override
  String nPlayers(Object count) {
    return '$count שחקנים';
  }

  @override
  String get morePlayers => 'עוד שחקנים';

  @override
  String get gameSettings => 'הגדרות המשחק';

  @override
  String get start => 'מתחילים';

  @override
  String get timeForEachHint => 'זמן לכל רמז';

  @override
  String get noTimer => 'ללא טיימר';

  @override
  String get summary => 'סיכום';

  @override
  String get players => 'שחקנים';

  @override
  String get impostors => 'מתחזים';

  @override
  String get oneImpostor => 'מתחזה אחד';

  @override
  String get voting => 'הצבעה';

  @override
  String get privateVoteOnDevice => 'הצבעה פרטית במכשיר';

  @override
  String get onlineChoiceSubtitle =>
      'שני מצבים, אותו משחק. אפשר להצטרף לשחקנים אחרים או לפתוח חדר לחברים.';

  @override
  String get quickGame => 'משחק מהיר';

  @override
  String get quickGameSubtitle => 'בוחרים קטגוריות ומצטרפים לשחקנים ברשת.';

  @override
  String get players4to8 => '4–8 שחקנים';

  @override
  String get privateRoomSubtitle =>
      'יוצרים חדר ושולחים קוד, או מצטרפים לחדר קיים.';

  @override
  String get youDecideStart => 'אתם קובעים מתי מתחילים';

  @override
  String get adLabel => 'פרסומת';

  @override
  String adFailed(Object widgetName) {
    return 'לא הצלחנו להציג מודעה עד הסוף, ולכן ״$widgetName״ לא נפתחה. אפשר לנסות שוב מאוחר יותר או לבחור אפשרות אחרת.';
  }

  @override
  String get purchasesUnavailableLater =>
      'הרכישות אינן זמינות כרגע. אנא נסו שוב מאוחר יותר.';

  @override
  String get pricesFailed =>
      'לא הצלחנו לטעון את המחירים מהחנות. בדקו את החיבור לאינטרנט ונסו שוב.';

  @override
  String get purchaseCancelled => 'הרכישה בוטלה. לא בוצע חיוב.';

  @override
  String get purchaseFailed =>
      'הרכישה לא הושלמה ולא בוצע חיוב. בדקו את החיבור לאינטרנט ונסו שוב.';

  @override
  String purchasePending(Object widgetName) {
    return 'הרכישה ממתינה לאישור. ״$widgetName״ תיפתח ברגע שהתשלום יאושר.';
  }

  @override
  String restoredOther(Object widgetName) {
    return 'הרכישות שוחזרו, אבל ״$widgetName״ לא נמצאה ביניהן.';
  }

  @override
  String get purchasesUnavailableRestore =>
      'הרכישות אינן זמינות כרגע. אפשר לשחזר רכישות קודמות.';

  @override
  String categoryLockedTitle(Object widgetName) {
    return '״$widgetName״ נעולה';
  }

  @override
  String get chooseHowToUnlock => 'בחרו איך לפתוח אותה';

  @override
  String get perMonth => 'לחודש';

  @override
  String get oneTimePayment => 'תשלום אחד';

  @override
  String get watchAd => 'צפייה במודעה';

  @override
  String adUnlocksNextGame(Object widgetName) {
    return 'פותחת את ״$widgetName״ למשחק הבא בלבד';
  }

  @override
  String watchAgainIn(Object value) {
    return 'אפשר לצפות שוב בעוד $value';
  }

  @override
  String get free => 'חינם';

  @override
  String get oneGame => 'משחק אחד';

  @override
  String durationHours(Object h) {
    return '$h שע׳';
  }

  @override
  String durationMinutes(Object min) {
    return '$min דק׳';
  }

  @override
  String get durationAnd => ' ו־';

  @override
  String get premiumLifetime => 'פרימיום לכל החיים';

  @override
  String onlyCategory(Object widgetName) {
    return 'רק ״$widgetName״';
  }

  @override
  String get premiumMonthlyDesc =>
      'כל הקטגוריות ותכונות הפרימיום, בלי פרסומות — כל עוד המנוי פעיל';

  @override
  String get premiumLifetimeDesc =>
      'כל הקטגוריות, גם אלה שיתווספו בעתיד, ותכונות הפרימיום. בלי פרסומות לתמיד';

  @override
  String get categoryForeverDesc => 'פתוחה לתמיד · הפרסומות נשארות';

  @override
  String get purchasesRestoredTitle => 'הרכישות שוחזרו';

  @override
  String categoryOpenAgain(Object widgetName) {
    return '״$widgetName״ פתוחה שוב במכשיר הזה.';
  }

  @override
  String categoryOpenNextGame(Object widgetName) {
    return '״$widgetName״ פתוחה למשחק הבא';
  }

  @override
  String get thanksForWatching =>
      'תודה שצפיתם. אחרי המשחק הבא הקטגוריה תינעל שוב.';

  @override
  String get welcomePremium => 'ברוכים הבאים לפרימיום';

  @override
  String get monthlyActive =>
      'המנוי החודשי פעיל. אפשר לנהל או לבטל אותו בהגדרות המנויים בחנות.';

  @override
  String get lifetimeWithMonthly =>
      'הכול פתוח לתמיד — כולל קטגוריות שיתווספו בעתיד. המנוי החודשי שלכם עדיין פעיל; אפשר לבטל אותו בהגדרות המנויים בחנות.';

  @override
  String get lifetimeUnlocked =>
      'הכול פתוח לתמיד — כולל קטגוריות שיתווספו בעתיד.';

  @override
  String categoryUnlocked(Object widgetName) {
    return '״$widgetName״ נפתחה!';
  }

  @override
  String get categoryYoursForever =>
      'הקטגוריה שלכם לתמיד. הפרסומות ממשיכות להופיע.';

  @override
  String get allCategoriesOpen => 'כל הקטגוריות פתוחות';

  @override
  String get premiumFeaturesActive => 'תכונות הפרימיום פעילות';

  @override
  String get noBannersNoAds => 'בלי באנרים ובלי מודעות במסך מלא';

  @override
  String get startPlaying => 'מתחילים לשחק';

  @override
  String chooseCategoryN(Object widgetName) {
    return 'בוחרים ב״$widgetName״';
  }

  @override
  String get loadingAd => 'טוענים מודעה…';

  @override
  String adDisclosure(Object widgetName) {
    return '״$widgetName״ תיפתח אחרי צפייה מלאה במודעה, למשחק הבא בלבד. אפשר לפתוח כך קטגוריה פעם בארבע שעות.';
  }

  @override
  String get loadingPrices => 'טוענים מחירים…';

  @override
  String get connectingStore => 'מתחברים לחנות…';

  @override
  String get pricesInStoreCurrency =>
      'המחירים מוצגים במטבע של חשבון החנות שלכם.';

  @override
  String get continueInStore =>
      'ממשיכים בחלון התשלום של החנות. אין לסגור את האפליקציה.';

  @override
  String subscriptionDisclosure(Object p) {
    return 'המנוי מתחדש אוטומטית ב־$p בכל חודש עד לביטול. אפשר לבטל בכל עת בהגדרות המנויים בחנות, לפחות 24 שעות לפני מועד החידוש.';
  }

  @override
  String categoryPurchaseDisclosure(Object p, Object widgetName) {
    return 'תשלום אחד של $p דרך החנות. ״$widgetName״ נשארת פתוחה לתמיד; הפרסומות ממשיכות להופיע.';
  }

  @override
  String premiumPurchaseDisclosure(Object p) {
    return 'תשלום אחד של $p דרך החנות. בלי מנוי ובלי חיובים נוספים.';
  }

  @override
  String get joinPremium => 'הצטרפות לפרימיום';

  @override
  String buyPrice(Object p) {
    return 'קנייה · $p';
  }

  @override
  String playerEliminated(Object eliminatedName) {
    return '$eliminatedName הודח/ה';
  }

  @override
  String get role => 'התפקיד';

  @override
  String get wordStaysSecret => 'המילה נשארת סודית — המשחק ממשיך.';

  @override
  String get stillInGame => 'נשארו במשחק';

  @override
  String previousHint(Object nickname) {
    return 'הרמז הקודם · $nickname';
  }

  @override
  String roundLabel(Object round) {
    return 'סבב $round';
  }

  @override
  String get youWereEliminated => 'הודחתם מהמשחק';

  @override
  String get spectatorExplain =>
      'אתם ממשיכים לצפות ולהגיב, בלי רמזים והצבעות. התוצאה שלכם היא של הקבוצה שלכם.';

  @override
  String get secretWord => 'המילה הסודית';

  @override
  String get wordNotShown => 'המילה לא מוצגת לכם — רק הקטגוריה.';

  @override
  String get votingOpensAuto => 'מסך ההצבעה נפתח אוטומטית';

  @override
  String get allHintsSent => 'כל הרמזים נשלחו';

  @override
  String get toVoting => 'עוברים להצבעה';

  @override
  String get wordWas => 'המילה הייתה';

  @override
  String get theGuess => 'הניחוש';

  @override
  String get rounds => 'סבבים';

  @override
  String get voteBreakdown => 'חלוקת הקולות';

  @override
  String get playAgain => 'משחק נוסף';

  @override
  String openFreeCount(Object count) {
    return '$count פתוחות בחינם';
  }

  @override
  String openCount(Object count) {
    return '$count פתוחות';
  }

  @override
  String rewardRefused(Object name) {
    return 'אפשר לפתוח קטגוריה בצפייה במודעה פעם בארבע שעות, ולכן ״$name״ לא נפתחה.';
  }

  @override
  String watchAgainInSentence(Object time) {
    return ' אפשר לצפות שוב בעוד $time.';
  }

  @override
  String get phoneLanguage => 'שפת הטלפון';

  @override
  String roomLanguageMismatch(Object language) {
    return 'שפת החדר: $language. כדי להצטרף, מחליפים שפה בהגדרות.';
  }

  @override
  String get guessTheWord => 'ניחוש המילה';

  @override
  String get whoIsImpostor => 'מי המתחזה?';
}
