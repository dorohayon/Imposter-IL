import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('he')
  ];

  /// No description provided for @appTitle.
  ///
  /// In he, this message translates to:
  /// **'מי המתחזה?‏'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In he, this message translates to:
  /// **'הגדרות'**
  String get settings;

  /// No description provided for @profile.
  ///
  /// In he, this message translates to:
  /// **'פרופיל'**
  String get profile;

  /// No description provided for @gameName.
  ///
  /// In he, this message translates to:
  /// **'מי המתחזה?'**
  String get gameName;

  /// No description provided for @homeTagline.
  ///
  /// In he, this message translates to:
  /// **'כולם יודעים את המילה. חוץ מאחד.'**
  String get homeTagline;

  /// No description provided for @onlineGame.
  ///
  /// In he, this message translates to:
  /// **'משחק ברשת'**
  String get onlineGame;

  /// No description provided for @oneDeviceGame.
  ///
  /// In he, this message translates to:
  /// **'משחק במכשיר אחד'**
  String get oneDeviceGame;

  /// No description provided for @howToPlay.
  ///
  /// In he, this message translates to:
  /// **'איך משחקים?'**
  String get howToPlay;

  /// No description provided for @resumeGameTitle.
  ///
  /// In he, this message translates to:
  /// **'להמשיך את המשחק?'**
  String get resumeGameTitle;

  /// No description provided for @resumeGameDetails.
  ///
  /// In he, this message translates to:
  /// **'סיבוב {round} נשמר במכשיר · {playersLength} שחקנים'**
  String resumeGameDetails(Object round, Object playersLength);

  /// No description provided for @resumeGame.
  ///
  /// In he, this message translates to:
  /// **'המשך משחק'**
  String get resumeGame;

  /// No description provided for @deleteGame.
  ///
  /// In he, this message translates to:
  /// **'מחיקת המשחק'**
  String get deleteGame;

  /// No description provided for @legalDate.
  ///
  /// In he, this message translates to:
  /// **'26 בספטמבר 2026'**
  String get legalDate;

  /// No description provided for @legalGateTitle.
  ///
  /// In he, this message translates to:
  /// **'לפני שמתחילים'**
  String get legalGateTitle;

  /// No description provided for @legalConsent.
  ///
  /// In he, this message translates to:
  /// **'קראתי ואני מסכים/ה לתנאי השימוש ומאשר/ת שקראתי את מדיניות הפרטיות.'**
  String get legalConsent;

  /// No description provided for @saving.
  ///
  /// In he, this message translates to:
  /// **'שומרים...'**
  String get saving;

  /// No description provided for @acceptAndContinue.
  ///
  /// In he, this message translates to:
  /// **'אישור והמשך'**
  String get acceptAndContinue;

  /// No description provided for @legalGateHeadline.
  ///
  /// In he, this message translates to:
  /// **'משחק הוגן מתחיל בכללים ברורים'**
  String get legalGateHeadline;

  /// No description provided for @legalGateBody.
  ///
  /// In he, this message translates to:
  /// **'במשחק כותבים כינויים ורמזים ששחקנים אחרים יכולים לראות. אנחנו מסננים תוכן לא מתאים ומאפשרים לדווח ולהסתיר שחקנים.'**
  String get legalGateBody;

  /// No description provided for @termsTitle.
  ///
  /// In he, this message translates to:
  /// **'תנאי שימוש'**
  String get termsTitle;

  /// No description provided for @termsSubtitle.
  ///
  /// In he, this message translates to:
  /// **'כללי המשחק, תוכן אסור ודיווחים'**
  String get termsSubtitle;

  /// No description provided for @privacyTitle.
  ///
  /// In he, this message translates to:
  /// **'מדיניות פרטיות'**
  String get privacyTitle;

  /// No description provided for @privacySubtitle.
  ///
  /// In he, this message translates to:
  /// **'איזה מידע נשמר, איפה ולכמה זמן'**
  String get privacySubtitle;

  /// No description provided for @legalDocsVersion.
  ///
  /// In he, this message translates to:
  /// **'גרסת מסמכים {legalVersion} · {legalDate}'**
  String legalDocsVersion(Object legalVersion, Object legalDate);

  /// No description provided for @termsIntro.
  ///
  /// In he, this message translates to:
  /// **'גרסה {legalVersion} · בתוקף מ־{legalDate}\n\nהשימוש ב״מי המתחזה?״ כפוף לתנאים הבאים. המשחק מיועד לבני 13 ומעלה. אם מלאו לכם 13 אך אינכם בגיל שמאפשר לכם להסכים לתנאים במקום מגוריכם, השתמשו במשחק רק באישור ובהשגחת הורה או אפוטרופוס.'**
  String termsIntro(Object legalVersion, Object legalDate);

  /// No description provided for @terms1Title.
  ///
  /// In he, this message translates to:
  /// **'1. השירות'**
  String get terms1Title;

  /// No description provided for @terms1.
  ///
  /// In he, this message translates to:
  /// **'״מי המתחזה?״ הוא משחק חברתי מקוון המופעל על ידי Imposter IL (imposteril36@gmail.com). אין צורך בחשבון. אתם בוחרים כינוי ואווטאר ומקבלים מזהה אורח זמני לצורך המשחק.'**
  String get terms1;

  /// No description provided for @terms2Title.
  ///
  /// In he, this message translates to:
  /// **'2. כללי התנהגות ותוכן'**
  String get terms2Title;

  /// No description provided for @terms2.
  ///
  /// In he, this message translates to:
  /// **'אין לפרסם בכינוי או ברמז תוכן מיני מפורש, איומים, דברי שנאה, השפלה או הטרדה, תוכן בלתי חוקי, התחזות לאדם אחר, פרטים אישיים של אדם אחר או תוכן שנועד לפגוע בשחקנים. אין לנסות לעקוף את מסנני התוכן או לנצל לרעה את השרת, החדרים, מנגנון הדיווח או המשחק.'**
  String get terms2;

  /// No description provided for @terms3Title.
  ///
  /// In he, this message translates to:
  /// **'3. תוכן של שחקנים'**
  String get terms3Title;

  /// No description provided for @terms3.
  ///
  /// In he, this message translates to:
  /// **'כינויים ורמזים שכתבתם מוצגים לשחקנים אחרים במשחק. אתם אחראים לתוכן שאתם שולחים. המשחק רשאי לסרב לתוכן, להסתירו או להפסיק גישה במקרה של הפרת הכללים. שחקנים יכולים לדווח על תוכן ולהסתיר תוכן של שחקן שדווח במכשיר שלהם. דיווחים נבדקים בתוך 24 שעות, ותוכן שמפר את הכללים מתווסף לסינון.'**
  String get terms3;

  /// No description provided for @terms4Title.
  ///
  /// In he, this message translates to:
  /// **'4. משחקים, תוצאות וסטטיסטיקה'**
  String get terms4Title;

  /// No description provided for @terms4.
  ///
  /// In he, this message translates to:
  /// **'המשחק עשוי להסתיים עקב ניתוק, תקלה או תחזוקה. ניצחונות והפסדים נשמרים במכשיר בלבד ואינם חשבון, דירוג או נכס שניתן לשחזר לאחר מחיקת האפליקציה או מעבר מכשיר.'**
  String get terms4;

  /// No description provided for @terms5Title.
  ///
  /// In he, this message translates to:
  /// **'5. רכישות, מנויים ופרסומות'**
  String get terms5Title;

  /// No description provided for @terms5.
  ///
  /// In he, this message translates to:
  /// **'שלוש קטגוריות פתוחות בחינם. את שאר הקטגוריות אפשר לפתוח ברכישה של קטגוריה אחת לתמיד, במנוי פרימיום חודשי או ברכישת פרימיום לכל החיים. פרימיום פותח את כל הקטגוריות, גם כאלה שיתווספו, ומסיר את הפרסומות; רכישת קטגוריה בודדת אינה מסירה פרסומות. התשלום, החיוב, החידוש וההחזרים מתבצעים דרך App Store או Google Play, בכפוף לתנאים שלהם ובמחיר שהחנות מציגה במטבע של חשבונכם. המנוי החודשי מתחדש אוטומטית בכל חודש עד לביטול. אפשר לבטל אותו בכל עת בהגדרות המנויים בחנות, לפחות 24 שעות לפני מועד החידוש, והגישה נשארת עד סוף התקופה ששולמה. רכישה שהוחזרה או בוטלה בחנות מפסיקה לפתוח את מה שפתחה. רכישות שייכות לחשבון החנות ולא למכשיר, ואפשר לשחזר אותן בכל מכשיר עם אותו חשבון באמצעות ״שחזור רכישות״. למי שאין לו פרימיום מוצגות פרסומות של צד שלישי במסכים שמחוץ למשחק ואחרי משחק שהסתיים. במכשירי Apple חל גם הסכם הרישיון הסטנדרטי של Apple למשתמש קצה (EULA). אין באמור כדי לגרוע מזכויות שלכם לפי דיני הגנת הצרכן החלים, לרבות ביטול עסקה.'**
  String get terms5;

  /// No description provided for @terms6Title.
  ///
  /// In he, this message translates to:
  /// **'6. זמינות ושינויים'**
  String get terms6Title;

  /// No description provided for @terms6.
  ///
  /// In he, this message translates to:
  /// **'השירות ניתן כפי שהוא ובהתאם לזמינות. מפעיל השירות רשאי לתקן באגים, לשנות כללים ותוכן, להגביל גרסאות ישנות או להפסיק חלקים מהשירות. כששינוי מהותי בתנאים דורש הסכמה מחודשת, האפליקציה תציג את הגרסה החדשה לפני המשך המשחק.'**
  String get terms6;

  /// No description provided for @terms7Title.
  ///
  /// In he, this message translates to:
  /// **'7. קניין רוחני'**
  String get terms7Title;

  /// No description provided for @terms7.
  ///
  /// In he, this message translates to:
  /// **'השם, העיצוב, הקוד, האיורים ותוכן המשחק שייכים לבעליהם ומוגנים לפי הדין החל. אין להעתיק, להפיץ, לבצע הנדסה לאחור או להשתמש בנכסי המשחק מעבר למה שמותר בדין או ברישיונות החלים.'**
  String get terms7;

  /// No description provided for @terms8Title.
  ///
  /// In he, this message translates to:
  /// **'8. אחריות'**
  String get terms8Title;

  /// No description provided for @terms8.
  ///
  /// In he, this message translates to:
  /// **'במידה המרבית המותרת לפי דין, אין התחייבות שהשירות יהיה רציף או נטול שגיאות. אין בתנאים כדי לגרוע מזכויות צרכניות שלא ניתן לוותר עליהן לפי הדין החל.'**
  String get terms8;

  /// No description provided for @terms9Title.
  ///
  /// In he, this message translates to:
  /// **'9. פרטיות'**
  String get terms9Title;

  /// No description provided for @terms9.
  ///
  /// In he, this message translates to:
  /// **'מדיניות הפרטיות מתארת את המידע שבו השירות משתמש ואת תקופות השמירה והיא חלק מהשימוש בשירות.'**
  String get terms9;

  /// No description provided for @terms10Title.
  ///
  /// In he, this message translates to:
  /// **'10. שינויים בתנאים'**
  String get terms10Title;

  /// No description provided for @terms10.
  ///
  /// In he, this message translates to:
  /// **'שינוי מהותי יקבל גרסת מסמכים חדשה. האפליקציה שומרת במכשיר את גרסת התנאים שאושרה ויכולה לדרוש אישור מחדש לגרסה חדשה.'**
  String get terms10;

  /// No description provided for @terms11Title.
  ///
  /// In he, this message translates to:
  /// **'11. דין וסמכות שיפוט'**
  String get terms11Title;

  /// No description provided for @terms11.
  ///
  /// In he, this message translates to:
  /// **'על תנאים אלה חלים דיני מדינת ישראל, וסמכות השיפוט הבלעדית נתונה לבתי המשפט המוסמכים במחוז תל אביב־יפו. אין באמור כדי לגרוע מזכותכם לתבוע במקום מגוריכם כאשר הדין החל עליכם מקנה לכם זכות כזו.'**
  String get terms11;

  /// No description provided for @terms12Title.
  ///
  /// In he, this message translates to:
  /// **'12. יצירת קשר'**
  String get terms12Title;

  /// No description provided for @terms12.
  ///
  /// In he, this message translates to:
  /// **'Imposter IL · imposteril36@gmail.com\nלתמיכה, לדיווח על תוכן פוגעני ולכל שאלה על התנאים האלה.'**
  String get terms12;

  /// No description provided for @privacyIntro.
  ///
  /// In he, this message translates to:
  /// **'גרסה {legalVersion} · בתוקף מ־{legalDate}\n\nהמדיניות מתארת את המידע שבו ״מי המתחזה?״ משתמש כדי להפעיל משחקים, לשמור העדפות ולהגן על שחקנים.'**
  String privacyIntro(Object legalVersion, Object legalDate);

  /// No description provided for @privacy1Title.
  ///
  /// In he, this message translates to:
  /// **'1. מי אנחנו'**
  String get privacy1Title;

  /// No description provided for @privacy1.
  ///
  /// In he, this message translates to:
  /// **'המשחק ״מי המתחזה?״ מופעל על ידי Imposter IL, והמדיניות הזאת חלה על האפליקציה ועל השרת שמפעיל אותה. לפניות בנושא פרטיות: imposteril36@gmail.com.'**
  String get privacy1;

  /// No description provided for @privacy2Title.
  ///
  /// In he, this message translates to:
  /// **'2. מידע שנשמר במכשיר'**
  String get privacy2Title;

  /// No description provided for @privacy2.
  ///
  /// In he, this message translates to:
  /// **'האפליקציה שומרת במכשיר את מזהה ה־session וה־player הזמניים, הכינוי והאווטאר, ניצחונות והפסדים, הגדרות רטט ותגובות, גרסת המסמכים שאושרה ורשימת מזהי שחקנים שדיווחתם עליהם כדי להסתיר את התוכן שלהם. מחיקת האפליקציה או נתוניה עשויה למחוק מידע זה. לאחר רכישה נשמרים גם הקטגוריות והפרימיום שבבעלותכם ומועד התוקף של המנוי, כדי שיישארו פתוחים גם בלי חיבור, וכן הגדרות הפרסומות שהתקבלו מהשרת ומועד המודעה האחרונה במסך מלא.'**
  String get privacy2;

  /// No description provided for @privacy3Title.
  ///
  /// In he, this message translates to:
  /// **'3. מידע שנשלח לשרת'**
  String get privacy3Title;

  /// No description provided for @privacy3.
  ///
  /// In he, this message translates to:
  /// **'כדי להפעיל משחקים השרת מקבל מזהה שחקן ו־session, כינוי, אווטאר, כתובת IP לצורכי אבטחה והגבלת קצב, חברות בחדרים ובמשחקים, קטגוריות שנבחרו, רמזים, תגובות, הצבעות, ניחושים ודיווחים. אין צורך בשם אמיתי, מספר טלפון או כתובת דוא״ל כדי לשחק. כדי לפתוח ברשת קטגוריות שרכשתם, האפליקציה שולחת לשרת את ההוכחה שהחנות מספקת לרכישה — עסקה חתומה של Apple או אסימון רכישה של Google, הכוללים את מזהה המוצר, מזהה העסקה ומועדיה. השרת מאמת אותה מול Apple או Google. אנחנו לא מקבלים את פרטי התשלום שלכם.'**
  String get privacy3;

  /// No description provided for @privacy4Title.
  ///
  /// In he, this message translates to:
  /// **'4. מטרות השימוש'**
  String get privacy4Title;

  /// No description provided for @privacy4.
  ///
  /// In he, this message translates to:
  /// **'המידע משמש להפעלת matchmaking וחדרים, סנכרון המשחק בזמן אמת, חיבור מחדש, אכיפת כללי המשחק, מניעת abuse, טיפול בדיווחים, אבטחה, איתור תקלות ומדידת בריאות השרת. המידע משמש גם לאימות רכישות ולאכיפת הקטגוריות הפתוחות, ולהצגת פרסומות למי שאין לו פרימיום.'**
  String get privacy4;

  /// No description provided for @privacy5Title.
  ///
  /// In he, this message translates to:
  /// **'5. מה שחקנים אחרים רואים'**
  String get privacy5Title;

  /// No description provided for @privacy5.
  ///
  /// In he, this message translates to:
  /// **'שחקנים באותו משחק יכולים לראות את הכינוי והאווטאר שלכם, רמזים ששלחתם, מצב החיבור ומידע משחק הנדרש להצבעה ולתוצאה. המילה הסודית אינה נשלחת למתחזה לפני שלב התוצאה.'**
  String get privacy5;

  /// No description provided for @privacy6Title.
  ///
  /// In he, this message translates to:
  /// **'6. שמירה ומחיקה'**
  String get privacy6Title;

  /// No description provided for @privacy6.
  ///
  /// In he, this message translates to:
  /// **'מצב המשחק והחדרים נשמר בזיכרון השרת ולא במסד נתונים קבוע. session מנותק שאינו נמצא בחדר נמחק לאחר תקופת חוסר פעילות של עד 24 שעות, וחדר ריק נסגר לאחר 30 דקות. אתחול שרת מוחק את מצב המשחק שבזיכרון. לוגים תפעוליים עשויים להישמר לצורכי אבטחה ואבחון ולכלול מזהי שחקן בדויים ומטא־דאטה של דיווחים. תוצאת אימות הרכישות נשמרת בזיכרון השרת לצד ה־session בלבד ונמחקת איתו. דיווח נשמר בלוג יחד עם הרמז והכינוי שדווחו, כדי שאפשר יהיה לבדוק אותו.'**
  String get privacy6;

  /// No description provided for @privacy7Title.
  ///
  /// In he, this message translates to:
  /// **'7. שירותים חיצוניים'**
  String get privacy7Title;

  /// No description provided for @privacy7.
  ///
  /// In he, this message translates to:
  /// **'השרת מתארח ב־Google Cloud Platform (Cloud Run, אזור us-central1), וגוגל מעבדת מידע טכני הנדרש להעברת התעבורה ולשמירת הלוגים התפעוליים, כמעבדת מידע מטעמנו ובכפוף להתחייבויות אבטחה ופרטיות ברמה זהה או טובה יותר מזו שמתוארת כאן. התשלומים מתבצעים ב־App Store של Apple וב־Google Play, לפי מדיניות הפרטיות שלהם. למי שאין לו פרימיום מוצגות פרסומות של Google AdMob. AdMob עשויה לאסוף מזהי מכשיר ומזהה פרסום, כתובת IP, מידע על אינטראקציה עם מודעות, מידע אבחון וביצועים, לצורך הצגת מודעות, מדידתן ומניעת הונאה, לפי מדיניות הפרסום של Google (policies.google.com/technologies/ads). במקומות שבהם הדין מחייב, ובהם האיחוד האירופי ובריטניה, מתבקשת הסכמתכם לפני פרסום מותאם אישית; ב־iPhone לא נעשה שימוש במזהה הפרסום ללא הרשאתכם. כדי לאתר ולתקן תקלות, כשהאפליקציה קורסת או נתקלת בשגיאה היא שולחת דוח ל־Firebase Crashlytics של Google: פרטי השגיאה ומיקומה בקוד, דגם המכשיר, מערכת ההפעלה, גרסת האפליקציה ומזהה התקנה אקראי של Crashlytics. הדוח אינו כולל כינוי, רמזים או מזהה פרסום, והוא נשמר עד 90 יום. אין מכירת מידע אישי, ואין SDK צד שלישי ל־analytics.'**
  String get privacy7;

  /// No description provided for @privacy8Title.
  ///
  /// In he, this message translates to:
  /// **'8. ילדים ופרטים אישיים'**
  String get privacy8Title;

  /// No description provided for @privacy8.
  ///
  /// In he, this message translates to:
  /// **'המשחק אינו מבקש שם אמיתי או פרטי קשר. אין לכתוב בכינוי או ברמז מידע אישי שלכם או של אחרים. המשחק מיועד לבני 13 ומעלה ואינו מיועד לילדים. איננו אוספים ביודעין מידע מילדים מתחת לגיל 13, ואם ייוודע לנו על כך נמחק את המידע הקשור אליהם. המודעות מוגבלות לתוכן בדירוג שמתאים לקהל רחב.'**
  String get privacy8;

  /// No description provided for @privacy9Title.
  ///
  /// In he, this message translates to:
  /// **'9. בחירה ושליטה'**
  String get privacy9Title;

  /// No description provided for @privacy9.
  ///
  /// In he, this message translates to:
  /// **'אפשר לשנות כינוי ואווטאר, לכבות רטט או תגובות, לדווח על שחקן ולנקות את רשימת השחקנים שהוסתרו. מחיקת נתוני האפליקציה מסירה את המידע המקומי. מאחר שאין חשבון קבוע, אין מנגנון שחזור של נתונים מקומיים. אפשר גם לשנות את העדפות הפרטיות לפרסומות בהגדרות, כשהדין מחייב, לסרב להרשאת מעקב ב־iPhone או לאפס את מזהה הפרסום בהגדרות המכשיר. פרימיום מסיר את כל הפרסומות.'**
  String get privacy9;

  /// No description provided for @privacy10Title.
  ///
  /// In he, this message translates to:
  /// **'10. הזכויות שלכם'**
  String get privacy10Title;

  /// No description provided for @privacy10.
  ///
  /// In he, this message translates to:
  /// **'לפי חוק הגנת הפרטיות התשמ״א־1981 ותיקון 13 לו, ובמקומות שבהם חל ה־GDPR, יש לכם זכות לעיין במידע שנשמר עליכם, לבקש את תיקונו, למחוק אותו, להגביל או להתנגד לעיבודו ולקבלו בפורמט נגיש. מאחר שאין חשבון, נדרש מזהה השחקן או ה־session שמופיע במסך ההגדרות כדי לאתר מידע שקשור אליכם. לבקשה כתבו ל־imposteril36@gmail.com; נענה בתוך 30 יום. מרבית המידע נמחק ממילא מאליו — מצב המשחק בסיום המשחק, session לאחר 24 שעות והלוגים לאחר 30 יום.'**
  String get privacy10;

  /// No description provided for @privacy11Title.
  ///
  /// In he, this message translates to:
  /// **'11. אבטחה'**
  String get privacy11Title;

  /// No description provided for @privacy11.
  ///
  /// In he, this message translates to:
  /// **'התעבורה בגרסאות הפצה נועדה לעבור בחיבור מוצפן. השרת מפעיל מגבלות קצב, מגבלות גודל הודעה וסינון תוכן כדי להפחית שימוש לרעה. אין מערכת שיכולה להבטיח אבטחה מוחלטת.'**
  String get privacy11;

  /// No description provided for @privacy12Title.
  ///
  /// In he, this message translates to:
  /// **'12. שינויים במדיניות'**
  String get privacy12Title;

  /// No description provided for @privacy12.
  ///
  /// In he, this message translates to:
  /// **'שינוי מהותי במדיניות יקבל גרסה חדשה. כאשר נדרשת הסכמה מחודשת, האפליקציה תציג את הגרסה החדשה לפני המשך המשחק.'**
  String get privacy12;

  /// No description provided for @privacy13Title.
  ///
  /// In he, this message translates to:
  /// **'13. יצירת קשר'**
  String get privacy13Title;

  /// No description provided for @privacy13.
  ///
  /// In he, this message translates to:
  /// **'Imposter IL · imposteril36@gmail.com\nלפניות בנושא פרטיות, בקשות למימוש זכויות ודיווח על תוכן פוגעני. נשתדל להשיב בתוך 30 יום.'**
  String get privacy13;

  /// No description provided for @legalPublicCopy.
  ///
  /// In he, this message translates to:
  /// **'עותק ציבורי: {value}'**
  String legalPublicCopy(Object value);

  /// No description provided for @errNotRoomHost.
  ///
  /// In he, this message translates to:
  /// **'רק מנהל החדר יכול לבצע את הפעולה הזאת.'**
  String get errNotRoomHost;

  /// No description provided for @errNotEnoughPlayers.
  ///
  /// In he, this message translates to:
  /// **'צריך לפחות 4 שחקנים כדי להתחיל.'**
  String get errNotEnoughPlayers;

  /// No description provided for @errContentUnavailable.
  ///
  /// In he, this message translates to:
  /// **'אי אפשר להתחיל משחק כרגע. נסו שוב בעוד רגע.'**
  String get errContentUnavailable;

  /// No description provided for @errRoomInGame.
  ///
  /// In he, this message translates to:
  /// **'כבר מתנהל משחק בחדר הזה.'**
  String get errRoomInGame;

  /// No description provided for @errWrongPhase.
  ///
  /// In he, this message translates to:
  /// **'השלב הזה כבר הסתיים.'**
  String get errWrongPhase;

  /// No description provided for @errNotYourTurn.
  ///
  /// In he, this message translates to:
  /// **'זה לא התור שלכם.'**
  String get errNotYourTurn;

  /// No description provided for @errHintEmpty.
  ///
  /// In he, this message translates to:
  /// **'כתבו רמז לפני השליחה.'**
  String get errHintEmpty;

  /// No description provided for @errHintNotOneWord.
  ///
  /// In he, this message translates to:
  /// **'אפשר לשלוח מילה אחת בלבד.'**
  String get errHintNotOneWord;

  /// No description provided for @errHintTooLong.
  ///
  /// In he, this message translates to:
  /// **'הרמז יכול להכיל עד 25 תווים.'**
  String get errHintTooLong;

  /// No description provided for @errHintInappropriate.
  ///
  /// In he, this message translates to:
  /// **'הרמז הזה לא מתאים. נסו מילה אחרת.'**
  String get errHintInappropriate;

  /// No description provided for @errHintContainsSecret.
  ///
  /// In he, this message translates to:
  /// **'הרמז מכיל את המילה הסודית. בחרו מילה אחרת.'**
  String get errHintContainsSecret;

  /// No description provided for @errHintDuplicate.
  ///
  /// In he, this message translates to:
  /// **'הרמז הזה כבר נשלח במשחק. בחרו מילה אחרת.'**
  String get errHintDuplicate;

  /// No description provided for @errSelfVote.
  ///
  /// In he, this message translates to:
  /// **'אי אפשר להצביע לעצמכם.'**
  String get errSelfVote;

  /// No description provided for @errInvalidVoteTarget.
  ///
  /// In he, this message translates to:
  /// **'אי אפשר להצביע לשחקן הזה.'**
  String get errInvalidVoteTarget;

  /// No description provided for @errNetwork.
  ///
  /// In he, this message translates to:
  /// **'אין חיבור לשרת. בדקו את החיבור ונסו שוב.'**
  String get errNetwork;

  /// No description provided for @errCategoryLockedRoom.
  ///
  /// In he, this message translates to:
  /// **'אחת הקטגוריות כבר לא פתוחה. קטגוריה שנפתחה בצפייה במודעה פתוחה למשחק אחד בלבד. אפשר לחדש את הפרימיום, לשחזר רכישות או ליצור חדר חדש.'**
  String get errCategoryLockedRoom;

  /// No description provided for @errGeneric.
  ///
  /// In he, this message translates to:
  /// **'משהו השתבש. נסו שוב בעוד רגע.'**
  String get errGeneric;

  /// No description provided for @leaveGameTitle.
  ///
  /// In he, this message translates to:
  /// **'לצאת מהמשחק?'**
  String get leaveGameTitle;

  /// No description provided for @leaveGameBody.
  ///
  /// In he, this message translates to:
  /// **'יציאה באמצע המשחק נרשמת כהפסד.'**
  String get leaveGameBody;

  /// No description provided for @leave.
  ///
  /// In he, this message translates to:
  /// **'יציאה'**
  String get leave;

  /// No description provided for @stillCantConnect.
  ///
  /// In he, this message translates to:
  /// **'עדיין אי אפשר להתחבר. נסו שוב בעוד רגע.'**
  String get stillCantConnect;

  /// No description provided for @kickedByHost.
  ///
  /// In he, this message translates to:
  /// **'מנהל החדר הסיר אתכם מהחדר.'**
  String get kickedByHost;

  /// No description provided for @reconnecting.
  ///
  /// In he, this message translates to:
  /// **'מתחברים מחדש...'**
  String get reconnecting;

  /// No description provided for @connectionLostOnTurn.
  ///
  /// In he, this message translates to:
  /// **'החיבור אבד בזמן התור שלכם. ננסה להחזיר אתכם למשחק במשך 30 שניות.'**
  String get connectionLostOnTurn;

  /// No description provided for @connectionLost.
  ///
  /// In he, this message translates to:
  /// **'החיבור אבד. ננסה להחזיר אתכם למשחק במשך 30 שניות.'**
  String get connectionLost;

  /// No description provided for @disconnectFinalWarning.
  ///
  /// In he, this message translates to:
  /// **'אם לא תחזרו בתוך 30 שניות, זה ייספר כניתוק 3 מתוך 3 ותוצאו מהמשחק.'**
  String get disconnectFinalWarning;

  /// No description provided for @disconnectWarning.
  ///
  /// In he, this message translates to:
  /// **'אם לא תחזרו בתוך 30 שניות, זה ייספר כניתוק {disconnectNumber} מתוך 3.'**
  String disconnectWarning(Object disconnectNumber);

  /// No description provided for @turnTimerRunning.
  ///
  /// In he, this message translates to:
  /// **' הזמן בתור ממשיך לרוץ.'**
  String get turnTimerRunning;

  /// No description provided for @leaveGameButton.
  ///
  /// In he, this message translates to:
  /// **'יציאה מהמשחק'**
  String get leaveGameButton;

  /// No description provided for @disconnectCount.
  ///
  /// In he, this message translates to:
  /// **'ניתוק {disconnectNumber} מתוך 3'**
  String disconnectCount(Object disconnectNumber);

  /// No description provided for @groupReady.
  ///
  /// In he, this message translates to:
  /// **'הקבוצה מוכנה!'**
  String get groupReady;

  /// No description provided for @gameStartingSoon.
  ///
  /// In he, this message translates to:
  /// **'המשחק מתחיל בעוד רגע.'**
  String get gameStartingSoon;

  /// No description provided for @enoughPlayers.
  ///
  /// In he, this message translates to:
  /// **'יש מספיק שחקנים!'**
  String get enoughPlayers;

  /// No description provided for @waitingForMore.
  ///
  /// In he, this message translates to:
  /// **'מחכים כמה שניות לשחקנים נוספים ומתחילים כשהזמן מסתיים.'**
  String get waitingForMore;

  /// No description provided for @oneMorePlayer.
  ///
  /// In he, this message translates to:
  /// **'עוד שחקן אחד כדי להתחיל'**
  String get oneMorePlayer;

  /// No description provided for @stillSearching.
  ///
  /// In he, this message translates to:
  /// **'ממשיכים לחפש שחקנים מתאימים בקטגוריות שבחרתם.'**
  String get stillSearching;

  /// No description provided for @morePlayersNeeded.
  ///
  /// In he, this message translates to:
  /// **'עוד {missing} שחקנים כדי להתחיל'**
  String morePlayersNeeded(Object missing);

  /// No description provided for @searchingPlayers.
  ///
  /// In he, this message translates to:
  /// **'מחפשים שחקנים'**
  String get searchingPlayers;

  /// No description provided for @buildingGroup.
  ///
  /// In he, this message translates to:
  /// **'מרכיבים קבוצת שחקנים'**
  String get buildingGroup;

  /// No description provided for @cancelSearch.
  ///
  /// In he, this message translates to:
  /// **'ביטול חיפוש'**
  String get cancelSearch;

  /// No description provided for @yourGroup.
  ///
  /// In he, this message translates to:
  /// **'הקבוצה שלך'**
  String get yourGroup;

  /// No description provided for @countOfMax.
  ///
  /// In he, this message translates to:
  /// **'{count} מתוך {maxPlayers}'**
  String countOfMax(Object count, Object maxPlayers);

  /// No description provided for @dontLeavePage.
  ///
  /// In he, this message translates to:
  /// **'נא לא לעזוב עמוד זה.'**
  String get dontLeavePage;

  /// No description provided for @you.
  ///
  /// In he, this message translates to:
  /// **'אתם'**
  String get you;

  /// No description provided for @searchingPlayer.
  ///
  /// In he, this message translates to:
  /// **'מחפשים שחקן...'**
  String get searchingPlayer;

  /// No description provided for @noMatchTitle.
  ///
  /// In he, this message translates to:
  /// **'לא נמצא משחק בקטגוריות שבחרתם'**
  String get noMatchTitle;

  /// No description provided for @noMatchBody.
  ///
  /// In he, this message translates to:
  /// **'אפשר לנסות שוב עם אותן קטגוריות, או לבחור קטגוריות אחרות.'**
  String get noMatchBody;

  /// No description provided for @tryAgain.
  ///
  /// In he, this message translates to:
  /// **'ניסיון נוסף'**
  String get tryAgain;

  /// No description provided for @chooseOtherCategories.
  ///
  /// In he, this message translates to:
  /// **'בחירת קטגוריות אחרות'**
  String get chooseOtherCategories;

  /// No description provided for @privateRoom.
  ///
  /// In he, this message translates to:
  /// **'חדר פרטי'**
  String get privateRoom;

  /// No description provided for @roomOf.
  ///
  /// In he, this message translates to:
  /// **'החדר של {hostNickname}'**
  String roomOf(Object hostNickname);

  /// No description provided for @startGame.
  ///
  /// In he, this message translates to:
  /// **'התחלת משחק'**
  String get startGame;

  /// No description provided for @onlyHostCanStart.
  ///
  /// In he, this message translates to:
  /// **'רק מנהל החדר יכול להתחיל'**
  String get onlyHostCanStart;

  /// No description provided for @roomCode.
  ///
  /// In he, this message translates to:
  /// **'קוד החדר'**
  String get roomCode;

  /// No description provided for @shareCode.
  ///
  /// In he, this message translates to:
  /// **'שיתוף הקוד'**
  String get shareCode;

  /// No description provided for @shareInvite.
  ///
  /// In he, this message translates to:
  /// **'בואו לשחק איתי ב״מי המתחזה?״\nקוד החדר: {code}\n{value}'**
  String shareInvite(Object code, Object value);

  /// No description provided for @copyCode.
  ///
  /// In he, this message translates to:
  /// **'העתקת הקוד'**
  String get copyCode;

  /// No description provided for @codeCopied.
  ///
  /// In he, this message translates to:
  /// **'קוד החדר הועתק'**
  String get codeCopied;

  /// No description provided for @hostDisconnected.
  ///
  /// In he, this message translates to:
  /// **'מנהל החדר התנתק. ממתינים שיחזור.'**
  String get hostDisconnected;

  /// No description provided for @waitingForNewHost.
  ///
  /// In he, this message translates to:
  /// **'מחכים ששחקן נוסף יתחבר ויקבל את ניהול החדר.'**
  String get waitingForNewHost;

  /// No description provided for @hostTransferredToYou.
  ///
  /// In he, this message translates to:
  /// **'מנהל החדר לא חזר בזמן. הניהול עבר אליכם.'**
  String get hostTransferredToYou;

  /// No description provided for @hostTransferredTo.
  ///
  /// In he, this message translates to:
  /// **'הניהול עבר ל־{hostNickname}.'**
  String hostTransferredTo(Object hostNickname);

  /// No description provided for @playersOfMax.
  ///
  /// In he, this message translates to:
  /// **'{playersLength} מתוך {maxPlayers} שחקנים'**
  String playersOfMax(Object playersLength, Object maxPlayers);

  /// No description provided for @needFourPlayers.
  ///
  /// In he, this message translates to:
  /// **'צריך לפחות 4 שחקנים כדי להתחיל'**
  String get needFourPlayers;

  /// No description provided for @roomHost.
  ///
  /// In he, this message translates to:
  /// **'מנהל החדר'**
  String get roomHost;

  /// No description provided for @disconnected.
  ///
  /// In he, this message translates to:
  /// **'מנותק'**
  String get disconnected;

  /// No description provided for @removePlayer.
  ///
  /// In he, this message translates to:
  /// **'הסרת {pNickname}'**
  String removePlayer(Object pNickname);

  /// No description provided for @categoriesList.
  ///
  /// In he, this message translates to:
  /// **'קטגוריות: {categoryNames}'**
  String categoriesList(Object categoryNames);

  /// No description provided for @secondsPerHint.
  ///
  /// In he, this message translates to:
  /// **'{hintSeconds} שניות לרמז'**
  String secondsPerHint(Object hintSeconds);

  /// No description provided for @settingsLockedSinceJoin.
  ///
  /// In he, this message translates to:
  /// **'ההגדרות נעולות מאז שהצטרפו שחקנים'**
  String get settingsLockedSinceJoin;

  /// No description provided for @waitingForOthers.
  ///
  /// In he, this message translates to:
  /// **'ממתינים לשאר השחקנים'**
  String get waitingForOthers;

  /// No description provided for @gotIt.
  ///
  /// In he, this message translates to:
  /// **'הבנתי'**
  String get gotIt;

  /// No description provided for @youAreImpostor.
  ///
  /// In he, this message translates to:
  /// **'את/ה המתחזה'**
  String get youAreImpostor;

  /// No description provided for @youAreCitizen.
  ///
  /// In he, this message translates to:
  /// **'את/ה אזרח/ית'**
  String get youAreCitizen;

  /// No description provided for @impostorDoesntKnow.
  ///
  /// In he, this message translates to:
  /// **'המתחזה לא יודע את המילה הסודית. שמרו עליה בסוד.'**
  String get impostorDoesntKnow;

  /// No description provided for @impostorTip1.
  ///
  /// In he, this message translates to:
  /// **'הקשיבו לרמזים של האחרים ונסו להשתלב.'**
  String get impostorTip1;

  /// No description provided for @impostorTip2.
  ///
  /// In he, this message translates to:
  /// **'אם תיתפסו — תקבלו הזדמנות אחת לנחש את המילה ולנצח.'**
  String get impostorTip2;

  /// No description provided for @citizenTip1.
  ///
  /// In he, this message translates to:
  /// **'בתורכם, כתבו רמז של מילה אחת שמתאים למילה הסודית.'**
  String get citizenTip1;

  /// No description provided for @citizenTip2.
  ///
  /// In he, this message translates to:
  /// **'רמז ברור מדי יעזור למתחזה. רמז דק מדי יעורר חשד.'**
  String get citizenTip2;

  /// No description provided for @nextRoundContinues.
  ///
  /// In he, this message translates to:
  /// **'ממשיכים לסבב הבא'**
  String get nextRoundContinues;

  /// No description provided for @continuingToRound.
  ///
  /// In he, this message translates to:
  /// **'ממשיכים לסיבוב {value}'**
  String continuingToRound(Object value);

  /// No description provided for @tieAgain.
  ///
  /// In he, this message translates to:
  /// **'שוב יש תיקו'**
  String get tieAgain;

  /// No description provided for @votesSplitAgain.
  ///
  /// In he, this message translates to:
  /// **'גם הפעם הקולות התחלקו שווה בשווה'**
  String get votesSplitAgain;

  /// No description provided for @noOneEliminatedNextRound.
  ///
  /// In he, this message translates to:
  /// **'איש לא הודח. ממשיכים לסבב רמזים נוסף.'**
  String get noOneEliminatedNextRound;

  /// No description provided for @oneVote.
  ///
  /// In he, this message translates to:
  /// **'קול אחד'**
  String get oneVote;

  /// No description provided for @nVotes.
  ///
  /// In he, this message translates to:
  /// **'{n} קולות'**
  String nVotes(Object n);

  /// No description provided for @loading.
  ///
  /// In he, this message translates to:
  /// **'טוענים…'**
  String get loading;

  /// No description provided for @wasCitizen.
  ///
  /// In he, this message translates to:
  /// **'{outNickname} היה/הייתה אזרח/ית'**
  String wasCitizen(Object outNickname);

  /// No description provided for @decideImpostor.
  ///
  /// In he, this message translates to:
  /// **'זה הזמן להחליט מי המתחזה'**
  String get decideImpostor;

  /// No description provided for @youEliminatedSpectator.
  ///
  /// In he, this message translates to:
  /// **'הודחת · צופה'**
  String get youEliminatedSpectator;

  /// No description provided for @eliminatedSpectator.
  ///
  /// In he, this message translates to:
  /// **'הודח/ה · צופה'**
  String get eliminatedSpectator;

  /// No description provided for @leftGame.
  ///
  /// In he, this message translates to:
  /// **'יצא/ה מהמשחק'**
  String get leftGame;

  /// No description provided for @disconnectedWaiting.
  ///
  /// In he, this message translates to:
  /// **'מנותק · ממתינים 30 שניות'**
  String get disconnectedWaiting;

  /// No description provided for @writingHint.
  ///
  /// In he, this message translates to:
  /// **'כותב/ת רמז'**
  String get writingHint;

  /// No description provided for @waitingTurn.
  ///
  /// In he, this message translates to:
  /// **'ממתין/ה לתור'**
  String get waitingTurn;

  /// No description provided for @oneHint.
  ///
  /// In he, this message translates to:
  /// **'1 רמז'**
  String get oneHint;

  /// No description provided for @nHints.
  ///
  /// In he, this message translates to:
  /// **'{said} רמזים'**
  String nHints(Object said);

  /// No description provided for @noHintSent.
  ///
  /// In he, this message translates to:
  /// **'לא נשלח רמז'**
  String get noHintSent;

  /// No description provided for @hidden.
  ///
  /// In he, this message translates to:
  /// **'הוסתר'**
  String get hidden;

  /// No description provided for @category.
  ///
  /// In he, this message translates to:
  /// **'קטגוריה'**
  String get category;

  /// No description provided for @roundTurnOf.
  ///
  /// In he, this message translates to:
  /// **'סיבוב {round} · תור {turn} מתוך {playingLength}'**
  String roundTurnOf(Object round, Object turn, Object playingLength);

  /// No description provided for @roundHints.
  ///
  /// In he, this message translates to:
  /// **'הרמזים בסיבוב'**
  String get roundHints;

  /// No description provided for @playerWriting.
  ///
  /// In he, this message translates to:
  /// **'{currentNickname} כותב/ת עכשיו. אפשר להמשיך להגיב למטה.'**
  String playerWriting(Object currentNickname);

  /// No description provided for @playerMe.
  ///
  /// In he, this message translates to:
  /// **'{playerNickname} · אני'**
  String playerMe(Object playerNickname);

  /// No description provided for @yourHintOneWord.
  ///
  /// In he, this message translates to:
  /// **'הרמז שלך · מילה אחת'**
  String get yourHintOneWord;

  /// No description provided for @yourHint.
  ///
  /// In he, this message translates to:
  /// **'הרמז שלכם'**
  String get yourHint;

  /// No description provided for @hintNotSent.
  ///
  /// In he, this message translates to:
  /// **'{error} הרמז לא נשלח.'**
  String hintNotSent(Object error);

  /// No description provided for @sendHint.
  ///
  /// In he, this message translates to:
  /// **'שליחת רמז'**
  String get sendHint;

  /// No description provided for @send.
  ///
  /// In he, this message translates to:
  /// **'שליחה'**
  String get send;

  /// No description provided for @showMyWord.
  ///
  /// In he, this message translates to:
  /// **'הצגת המילה שלי'**
  String get showMyWord;

  /// No description provided for @myWord.
  ///
  /// In he, this message translates to:
  /// **'המילה שלי'**
  String get myWord;

  /// No description provided for @close.
  ///
  /// In he, this message translates to:
  /// **'סגירה'**
  String get close;

  /// No description provided for @categoryIs.
  ///
  /// In he, this message translates to:
  /// **'קטגוריה: {category}'**
  String categoryIs(Object category);

  /// No description provided for @roundN.
  ///
  /// In he, this message translates to:
  /// **'סיבוב {first}'**
  String roundN(Object first);

  /// No description provided for @roundsRange.
  ///
  /// In he, this message translates to:
  /// **'סיבובים {first}–{last}'**
  String roundsRange(Object first, Object last);

  /// No description provided for @hintsOf.
  ///
  /// In he, this message translates to:
  /// **'הרמזים של {playerNickname}'**
  String hintsOf(Object playerNickname);

  /// No description provided for @noHintsYet.
  ///
  /// In he, this message translates to:
  /// **'עוד לא נשלחו רמזים.'**
  String get noHintsYet;

  /// No description provided for @reportHint.
  ///
  /// In he, this message translates to:
  /// **'דיווח על הרמז'**
  String get reportHint;

  /// No description provided for @playerDisconnectedTurn.
  ///
  /// In he, this message translates to:
  /// **'{nickname} התנתק. ממתינים לו עד 30 שניות — אחר כך התור שלו ידולג.'**
  String playerDisconnectedTurn(Object nickname);

  /// No description provided for @reactions.
  ///
  /// In he, this message translates to:
  /// **'תגובות'**
  String get reactions;

  /// No description provided for @swipeForReactions.
  ///
  /// In he, this message translates to:
  /// **'גררו לצדדים לעוד תגובות ↔'**
  String get swipeForReactions;

  /// No description provided for @revote.
  ///
  /// In he, this message translates to:
  /// **'הצבעה חוזרת'**
  String get revote;

  /// No description provided for @voteReceived.
  ///
  /// In he, this message translates to:
  /// **'ההצבעה נקלטה'**
  String get voteReceived;

  /// No description provided for @confirmVote.
  ///
  /// In he, this message translates to:
  /// **'אישור הצבעה'**
  String get confirmVote;

  /// No description provided for @choosePlayer.
  ///
  /// In he, this message translates to:
  /// **'בחרו שחקן אחד. אפשר לשנות את הבחירה עד שהזמן נגמר.'**
  String get choosePlayer;

  /// No description provided for @tieRevoteExplain.
  ///
  /// In he, this message translates to:
  /// **'היה תיקו. מצביעים שוב רק בין השחקנים שקיבלו את מספר הקולות הגבוה. תיקו נוסף — איש לא מודח והמשחק ממשיך לסבב נוסף.'**
  String get tieRevoteExplain;

  /// No description provided for @cantVoteSelf.
  ///
  /// In he, this message translates to:
  /// **'אי אפשר להצביע לעצמכם'**
  String get cantVoteSelf;

  /// No description provided for @oneVotePrevious.
  ///
  /// In he, this message translates to:
  /// **'קול אחד בסבב הקודם'**
  String get oneVotePrevious;

  /// No description provided for @nVotesPrevious.
  ///
  /// In he, this message translates to:
  /// **'{votes} קולות בסבב הקודם'**
  String nVotesPrevious(Object votes);

  /// No description provided for @youWereCaught.
  ///
  /// In he, this message translates to:
  /// **'נתפסתם'**
  String get youWereCaught;

  /// No description provided for @sendGuess.
  ///
  /// In he, this message translates to:
  /// **'שליחת ניחוש'**
  String get sendGuess;

  /// No description provided for @stillCanWin.
  ///
  /// In he, this message translates to:
  /// **'עוד אפשר לנצח'**
  String get stillCanWin;

  /// No description provided for @impostorGuessing.
  ///
  /// In he, this message translates to:
  /// **'המתחזה נתפס ועכשיו הוא מנסה לנחש את המילה.'**
  String get impostorGuessing;

  /// No description provided for @guessWinsExplain.
  ///
  /// In he, this message translates to:
  /// **'ניחוש נכון של המילה הסודית מעניק לכם את הניצחון. יש לכם ניסיון אחד.'**
  String get guessWinsExplain;

  /// No description provided for @othersHints.
  ///
  /// In he, this message translates to:
  /// **'הרמזים של שאר השחקנים'**
  String get othersHints;

  /// No description provided for @whatsTheWord.
  ///
  /// In he, this message translates to:
  /// **'מה המילה?'**
  String get whatsTheWord;

  /// No description provided for @guessHidden.
  ///
  /// In he, this message translates to:
  /// **'הניחוש לא מוצג לשחקנים בזמן ההקלדה'**
  String get guessHidden;

  /// No description provided for @guessFailExplain.
  ///
  /// In he, this message translates to:
  /// **'אם הזמן ייגמר או שהניחוש יהיה שגוי — האזרחים מנצחים.'**
  String get guessFailExplain;

  /// No description provided for @reasonCitizenVoted.
  ///
  /// In he, this message translates to:
  /// **'ההצבעה סימנה אזרח, והמתחזה נשאר במשחק.'**
  String get reasonCitizenVoted;

  /// No description provided for @reasonParity.
  ///
  /// In he, this message translates to:
  /// **'נשארו אזרח אחד ומתחזה — ובשלב הזה המתחזה מנצח מיד.'**
  String get reasonParity;

  /// No description provided for @reasonGuessed.
  ///
  /// In he, this message translates to:
  /// **'המתחזה נתפס, אבל הצליח לנחש את המילה.'**
  String get reasonGuessed;

  /// No description provided for @reasonWrongGuess.
  ///
  /// In he, this message translates to:
  /// **'המתחזה נתפס ולא הצליח לנחש את המילה.'**
  String get reasonWrongGuess;

  /// No description provided for @reasonGuessTimeout.
  ///
  /// In he, this message translates to:
  /// **'המתחזה נתפס, אבל הזמן לניחוש נגמר.'**
  String get reasonGuessTimeout;

  /// No description provided for @reasonImpostorLeft.
  ///
  /// In he, this message translates to:
  /// **'המתחזה עזב את המשחק.'**
  String get reasonImpostorLeft;

  /// No description provided for @reasonNotEnoughPlayers.
  ///
  /// In he, this message translates to:
  /// **'נשארו פחות משלושה שחקנים, ולכן המשחק הופסק.'**
  String get reasonNotEnoughPlayers;

  /// No description provided for @reasonAbandoned.
  ///
  /// In he, this message translates to:
  /// **'שני סבבי הצבעה עברו בלי אף הצבעה, ולכן המשחק בוטל. הוא לא נספר לאף אחד — לא כניצחון ולא כהפסד.'**
  String get reasonAbandoned;

  /// No description provided for @gameCancelled.
  ///
  /// In he, this message translates to:
  /// **'המשחק בוטל'**
  String get gameCancelled;

  /// No description provided for @citizensWon.
  ///
  /// In he, this message translates to:
  /// **'האזרחים ניצחו!'**
  String get citizensWon;

  /// No description provided for @impostorWon.
  ///
  /// In he, this message translates to:
  /// **'המתחזה ניצח!'**
  String get impostorWon;

  /// No description provided for @gameStopped.
  ///
  /// In he, this message translates to:
  /// **'המשחק הופסק'**
  String get gameStopped;

  /// No description provided for @impostorWas.
  ///
  /// In he, this message translates to:
  /// **'המתחזה היה'**
  String get impostorWas;

  /// No description provided for @winRecorded.
  ///
  /// In he, this message translates to:
  /// **'נרשם לכם ניצחון'**
  String get winRecorded;

  /// No description provided for @lossRecorded.
  ///
  /// In he, this message translates to:
  /// **'נרשם לכם הפסד'**
  String get lossRecorded;

  /// No description provided for @abstained.
  ///
  /// In he, this message translates to:
  /// **'נמנעו'**
  String get abstained;

  /// No description provided for @youLeftGame.
  ///
  /// In he, this message translates to:
  /// **'יצאתם מהמשחק'**
  String get youLeftGame;

  /// No description provided for @removedThirdDisconnect.
  ///
  /// In he, this message translates to:
  /// **'התנתקתם שלוש פעמים במשחק הזה, ולכן שאר השחקנים ממשיכים בלעדיכם.'**
  String get removedThirdDisconnect;

  /// No description provided for @backToHome.
  ///
  /// In he, this message translates to:
  /// **'חזרה למסך הבית'**
  String get backToHome;

  /// No description provided for @reportHintTitle.
  ///
  /// In he, this message translates to:
  /// **'לדווח על הרמז?'**
  String get reportHintTitle;

  /// No description provided for @reportHintBody.
  ///
  /// In he, this message translates to:
  /// **'הרמז יישלח לבדיקה ונטפל בו בתוך 24 שעות. לא תראו יותר רמזים של {nickname} במכשיר הזה.'**
  String reportHintBody(Object nickname);

  /// No description provided for @cancel.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get cancel;

  /// No description provided for @report.
  ///
  /// In he, this message translates to:
  /// **'דיווח'**
  String get report;

  /// No description provided for @reportThanks.
  ///
  /// In he, this message translates to:
  /// **'תודה, הדיווח התקבל ויטופל. הרמזים של השחקן יוסתרו במכשיר שלכם.'**
  String get reportThanks;

  /// No description provided for @reportNotSent.
  ///
  /// In he, this message translates to:
  /// **'הרמזים האלה יוסתרו, אבל הדיווח לא נשלח. {value}'**
  String reportNotSent(Object value);

  /// No description provided for @whoAreYou.
  ///
  /// In he, this message translates to:
  /// **'מי אתם במשחק?'**
  String get whoAreYou;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In he, this message translates to:
  /// **'בוחרים כינוי ואווטאר ומתחילים. בלי הרשמה.'**
  String get onboardingSubtitle;

  /// No description provided for @continueLabel.
  ///
  /// In he, this message translates to:
  /// **'ממשיכים'**
  String get continueLabel;

  /// No description provided for @connecting.
  ///
  /// In he, this message translates to:
  /// **'מתחברים...'**
  String get connecting;

  /// No description provided for @editDetails.
  ///
  /// In he, this message translates to:
  /// **'עריכת פרטים'**
  String get editDetails;

  /// No description provided for @save.
  ///
  /// In he, this message translates to:
  /// **'שמירה'**
  String get save;

  /// No description provided for @nicknameRule.
  ///
  /// In he, this message translates to:
  /// **'בחרו כינוי באורך 2–18 תווים, כולל ניקוד ואימוג׳י.'**
  String get nicknameRule;

  /// No description provided for @nicknameBlocked.
  ///
  /// In he, this message translates to:
  /// **'הכינוי הזה לא מתאים למשחק. בחרו כינוי אחר.'**
  String get nicknameBlocked;

  /// No description provided for @yourNickname.
  ///
  /// In he, this message translates to:
  /// **'הכינוי שלכם'**
  String get yourNickname;

  /// No description provided for @nicknameExample.
  ///
  /// In he, this message translates to:
  /// **'למשל: דורון'**
  String get nicknameExample;

  /// No description provided for @nicknameLength.
  ///
  /// In he, this message translates to:
  /// **'2–{maxNicknameLength} תווים'**
  String nicknameLength(Object maxNicknameLength);

  /// No description provided for @chooseAvatar.
  ///
  /// In he, this message translates to:
  /// **'בחירת אווטאר'**
  String get chooseAvatar;

  /// No description provided for @avatarN.
  ///
  /// In he, this message translates to:
  /// **'דמות {value}'**
  String avatarN(Object value);

  /// No description provided for @errAlreadyInActivity.
  ///
  /// In he, this message translates to:
  /// **'כבר הצטרפתם למשחק או לחדר אחר.'**
  String get errAlreadyInActivity;

  /// No description provided for @errCategoryLocked.
  ///
  /// In he, this message translates to:
  /// **'אחת הקטגוריות נעולה. אפשר לשחזר רכישות מחלון הפתיחה של הקטגוריה.'**
  String get errCategoryLocked;

  /// No description provided for @canPickSeveral.
  ///
  /// In he, this message translates to:
  /// **'אפשר לבחור כמה קטגוריות'**
  String get canPickSeveral;

  /// No description provided for @all.
  ///
  /// In he, this message translates to:
  /// **'הכול'**
  String get all;

  /// No description provided for @chooseCategories.
  ///
  /// In he, this message translates to:
  /// **'בחירת קטגוריות'**
  String get chooseCategories;

  /// No description provided for @searchingGame.
  ///
  /// In he, this message translates to:
  /// **'מחפשים משחק...'**
  String get searchingGame;

  /// No description provided for @searchGame.
  ///
  /// In he, this message translates to:
  /// **'חפש משחק'**
  String get searchGame;

  /// No description provided for @loadingCategories.
  ///
  /// In he, this message translates to:
  /// **'טוענים את הקטגוריות...'**
  String get loadingCategories;

  /// No description provided for @allCategories.
  ///
  /// In he, this message translates to:
  /// **'כל הקטגוריות'**
  String get allCategories;

  /// No description provided for @allOpenCategories.
  ///
  /// In he, this message translates to:
  /// **'כל הקטגוריות הפתוחות'**
  String get allOpenCategories;

  /// No description provided for @premium.
  ///
  /// In he, this message translates to:
  /// **'פרימיום'**
  String get premium;

  /// No description provided for @lockedTapToOpen.
  ///
  /// In he, this message translates to:
  /// **'{name} — נעולה, לחצו לפתיחה'**
  String lockedTapToOpen(Object name);

  /// No description provided for @purchasedTag.
  ///
  /// In he, this message translates to:
  /// **'✓ נרכשה'**
  String get purchasedTag;

  /// No description provided for @playWithFriends.
  ///
  /// In he, this message translates to:
  /// **'משחק עם חברים'**
  String get playWithFriends;

  /// No description provided for @createRoom.
  ///
  /// In he, this message translates to:
  /// **'יצירת חדר'**
  String get createRoom;

  /// No description provided for @createRoomSubtitle.
  ///
  /// In he, this message translates to:
  /// **'בוחרים הגדרות, מקבלים קוד ומשתפים עם החברים.'**
  String get createRoomSubtitle;

  /// No description provided for @joinRoom.
  ///
  /// In he, this message translates to:
  /// **'הצטרפות לחדר'**
  String get joinRoom;

  /// No description provided for @joinRoomSubtitle.
  ///
  /// In he, this message translates to:
  /// **'יש לכם קוד בן שש ספרות? מזינים ונכנסים.'**
  String get joinRoomSubtitle;

  /// No description provided for @playersRange4to8.
  ///
  /// In he, this message translates to:
  /// **'המשחק מתאים ל־4 עד 8 שחקנים'**
  String get playersRange4to8;

  /// No description provided for @creatingRoom.
  ///
  /// In he, this message translates to:
  /// **'יוצרים חדר...'**
  String get creatingRoom;

  /// No description provided for @settingsLockNotice.
  ///
  /// In he, this message translates to:
  /// **'לאחר יצירת החדר, לא יהיה ניתן לשנות את ההגדרות.'**
  String get settingsLockNotice;

  /// No description provided for @maxPlayers.
  ///
  /// In he, this message translates to:
  /// **'מספר שחקנים מרבי'**
  String get maxPlayers;

  /// No description provided for @timePerHint.
  ///
  /// In he, this message translates to:
  /// **'זמן לרמז'**
  String get timePerHint;

  /// No description provided for @nSeconds.
  ///
  /// In he, this message translates to:
  /// **'{value} שניות'**
  String nSeconds(Object value);

  /// No description provided for @categories.
  ///
  /// In he, this message translates to:
  /// **'קטגוריות'**
  String get categories;

  /// No description provided for @loadingCategoriesShort.
  ///
  /// In he, this message translates to:
  /// **'טוענים קטגוריות...'**
  String get loadingCategoriesShort;

  /// No description provided for @roomCodeSixDigits.
  ///
  /// In he, this message translates to:
  /// **'קוד החדר צריך להיות בן שש ספרות'**
  String get roomCodeSixDigits;

  /// No description provided for @roomNotFound.
  ///
  /// In he, this message translates to:
  /// **'החדר לא נמצא או שאינו זמין. בדקו את הקוד עם מי שפתח את החדר.'**
  String get roomNotFound;

  /// No description provided for @roomFull.
  ///
  /// In he, this message translates to:
  /// **'החדר מלא או שהמשחק כבר התחיל.'**
  String get roomFull;

  /// No description provided for @alreadyInOtherGame.
  ///
  /// In he, this message translates to:
  /// **'כבר הצטרפתם למשחק אחר.'**
  String get alreadyInOtherGame;

  /// No description provided for @join.
  ///
  /// In he, this message translates to:
  /// **'הצטרפות'**
  String get join;

  /// No description provided for @enterRoomCode.
  ///
  /// In he, this message translates to:
  /// **'הזינו את קוד החדר בן שש הספרות שקיבלתם.'**
  String get enterRoomCode;

  /// No description provided for @delete.
  ///
  /// In he, this message translates to:
  /// **'מחיקה'**
  String get delete;

  /// No description provided for @myProfile.
  ///
  /// In he, this message translates to:
  /// **'הפרופיל שלי'**
  String get myProfile;

  /// No description provided for @editNicknameAvatar.
  ///
  /// In he, this message translates to:
  /// **'עריכת כינוי ואווטאר'**
  String get editNicknameAvatar;

  /// No description provided for @wins.
  ///
  /// In he, this message translates to:
  /// **'ניצחונות'**
  String get wins;

  /// No description provided for @losses.
  ///
  /// In he, this message translates to:
  /// **'הפסדים'**
  String get losses;

  /// No description provided for @sounds.
  ///
  /// In he, this message translates to:
  /// **'צלילים'**
  String get sounds;

  /// No description provided for @comingSoon.
  ///
  /// In he, this message translates to:
  /// **'בקרוב'**
  String get comingSoon;

  /// No description provided for @vibration.
  ///
  /// In he, this message translates to:
  /// **'רטט'**
  String get vibration;

  /// No description provided for @showReactions.
  ///
  /// In he, this message translates to:
  /// **'הצגת תגובות'**
  String get showReactions;

  /// No description provided for @language.
  ///
  /// In he, this message translates to:
  /// **'שפה'**
  String get language;

  /// No description provided for @languageName.
  ///
  /// In he, this message translates to:
  /// **'עברית'**
  String get languageName;

  /// No description provided for @versionN.
  ///
  /// In he, this message translates to:
  /// **'גרסה {legalVersion}'**
  String versionN(Object legalVersion);

  /// No description provided for @manageSubscription.
  ///
  /// In he, this message translates to:
  /// **'ניהול המנוי'**
  String get manageSubscription;

  /// No description provided for @premiumMonthly.
  ///
  /// In he, this message translates to:
  /// **'פרימיום חודשי'**
  String get premiumMonthly;

  /// No description provided for @adPrivacy.
  ///
  /// In he, this message translates to:
  /// **'העדפות פרטיות לפרסומות'**
  String get adPrivacy;

  /// No description provided for @appVersion.
  ///
  /// In he, this message translates to:
  /// **'מי המתחזה? · גרסה 1.0'**
  String get appVersion;

  /// No description provided for @contact.
  ///
  /// In he, this message translates to:
  /// **'יצירת קשר'**
  String get contact;

  /// No description provided for @emailCopied.
  ///
  /// In he, this message translates to:
  /// **'כתובת המייל הועתקה'**
  String get emailCopied;

  /// No description provided for @reportedPlayers.
  ///
  /// In he, this message translates to:
  /// **'שחקנים שדיווחתם עליהם'**
  String get reportedPlayers;

  /// No description provided for @hiddenPlayersCount.
  ///
  /// In he, this message translates to:
  /// **'{mutedLength} שחקנים מוסתרים'**
  String hiddenPlayersCount(Object mutedLength);

  /// No description provided for @clear.
  ///
  /// In he, this message translates to:
  /// **'ניקוי'**
  String get clear;

  /// No description provided for @purchasesRestored.
  ///
  /// In he, this message translates to:
  /// **'הרכישות שוחזרו.'**
  String get purchasesRestored;

  /// No description provided for @noPurchasesFound.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו רכישות קודמות בחשבון החנות הזה.'**
  String get noPurchasesFound;

  /// No description provided for @restoreFailed.
  ///
  /// In he, this message translates to:
  /// **'השחזור לא הושלם. בדקו את החיבור לאינטרנט ונסו שוב.'**
  String get restoreFailed;

  /// No description provided for @restoringPurchases.
  ///
  /// In he, this message translates to:
  /// **'משחזרים רכישות…'**
  String get restoringPurchases;

  /// No description provided for @restorePurchases.
  ///
  /// In he, this message translates to:
  /// **'שחזור רכישות'**
  String get restorePurchases;

  /// No description provided for @howStep1.
  ///
  /// In he, this message translates to:
  /// **'כולם מקבלים את אותה מילה סודית — חוץ מהמתחזה, שרואה רק את הקטגוריה.'**
  String get howStep1;

  /// No description provided for @howStep2.
  ///
  /// In he, this message translates to:
  /// **'כל שחקן כותב בתורו רמז של מילה אחת. לכל תור יש 60 שניות.'**
  String get howStep2;

  /// No description provided for @howStep4.
  ///
  /// In he, this message translates to:
  /// **'אפשר להגיב לרמזים באמצעות אימוג׳ים והודעות מוכנות.'**
  String get howStep4;

  /// No description provided for @howStep5.
  ///
  /// In he, this message translates to:
  /// **'בסוף הסבב מצביעים מי המתחזה. יש 20 שניות להצביע.'**
  String get howStep5;

  /// No description provided for @howStep6.
  ///
  /// In he, this message translates to:
  /// **'אם המתחזה נתפס, יש לו 60 שניות לנחש את המילה ולנצח בכל זאת.'**
  String get howStep6;

  /// No description provided for @updateNeeded.
  ///
  /// In he, this message translates to:
  /// **'צריך לעדכן'**
  String get updateNeeded;

  /// No description provided for @newVersion.
  ///
  /// In he, this message translates to:
  /// **'יש גרסה חדשה של המשחק'**
  String get newVersion;

  /// No description provided for @versionUnsupported.
  ///
  /// In he, this message translates to:
  /// **'הגרסה שמותקנת אצלכם כבר לא נתמכת.\nעדכנו את האפליקציה בחנות כדי להמשיך לשחק.'**
  String get versionUnsupported;

  /// No description provided for @somethingWrong.
  ///
  /// In he, this message translates to:
  /// **'משהו השתבש'**
  String get somethingWrong;

  /// No description provided for @serverFaultStopped.
  ///
  /// In he, this message translates to:
  /// **'המשחק הופסק בגלל תקלה בחיבור לשרת. זו לא אשמתכם.'**
  String get serverFaultStopped;

  /// No description provided for @serverUnavailable.
  ///
  /// In he, this message translates to:
  /// **'השרת לא זמין כרגע. נסו שוב בעוד רגע.'**
  String get serverUnavailable;

  /// No description provided for @noLossRecorded.
  ///
  /// In he, this message translates to:
  /// **'לא נרשם לכם הפסד'**
  String get noLossRecorded;

  /// No description provided for @localDeleteWarning.
  ///
  /// In he, this message translates to:
  /// **'המשחק הנוכחי יימחק ולא יהיה אפשר להמשיך אותו.'**
  String get localDeleteWarning;

  /// No description provided for @leaveAndDelete.
  ///
  /// In he, this message translates to:
  /// **'יציאה ומחיקה'**
  String get leaveAndDelete;

  /// No description provided for @iAmVote.
  ///
  /// In he, this message translates to:
  /// **'אני {currentName} — להצבעה'**
  String iAmVote(Object currentName);

  /// No description provided for @iAmShow.
  ///
  /// In he, this message translates to:
  /// **'אני {currentName} — הציגו לי'**
  String iAmShow(Object currentName);

  /// No description provided for @votedOf.
  ///
  /// In he, this message translates to:
  /// **'הצביעו {done} מתוך {activePlayersLength}'**
  String votedOf(Object done, Object activePlayersLength);

  /// No description provided for @passDeviceTo.
  ///
  /// In he, this message translates to:
  /// **'העבירו את המכשיר ל{currentName}'**
  String passDeviceTo(Object currentName);

  /// No description provided for @noOneElseLooking.
  ///
  /// In he, this message translates to:
  /// **'אף אחד אחר לא מסתכל על המסך.'**
  String get noOneElseLooking;

  /// No description provided for @onlyPlayerLooking.
  ///
  /// In he, this message translates to:
  /// **'רק {currentName} מסתכל/ת על המסך.'**
  String onlyPlayerLooking(Object currentName);

  /// No description provided for @gotItHide.
  ///
  /// In he, this message translates to:
  /// **'הבנתי — הסתירו'**
  String get gotItHide;

  /// No description provided for @localImpostorTip.
  ///
  /// In he, this message translates to:
  /// **'הקשיבו לרמזים, השתלבו ונסו לגלות את המילה.'**
  String get localImpostorTip;

  /// No description provided for @localCitizenTip.
  ///
  /// In he, this message translates to:
  /// **'בתור שלכם אומרים בקול רמז של מילה אחת.'**
  String get localCitizenTip;

  /// No description provided for @startRound1.
  ///
  /// In he, this message translates to:
  /// **'מתחילים סיבוב 1'**
  String get startRound1;

  /// No description provided for @startRoundN.
  ///
  /// In he, this message translates to:
  /// **'התחלת סיבוב {round}'**
  String startRoundN(Object round);

  /// No description provided for @everyoneKnowsRoles.
  ///
  /// In he, this message translates to:
  /// **'כולם יודעים מי הם'**
  String get everyoneKnowsRoles;

  /// No description provided for @anotherRound.
  ///
  /// In he, this message translates to:
  /// **'סיבוב נוסף'**
  String get anotherRound;

  /// No description provided for @placeDevice.
  ///
  /// In he, this message translates to:
  /// **'מניחים את המכשיר במקום שכולם רואים.'**
  String get placeDevice;

  /// No description provided for @impostorStillAmong.
  ///
  /// In he, this message translates to:
  /// **'המתחזה עדיין ביניכם. סדר התורות הוגרל מחדש.'**
  String get impostorStillAmong;

  /// No description provided for @turnOrderThisRound.
  ///
  /// In he, this message translates to:
  /// **'סדר התורות בסיבוב זה'**
  String get turnOrderThisRound;

  /// No description provided for @startsFirst.
  ///
  /// In he, this message translates to:
  /// **'מתחיל/ה'**
  String get startsFirst;

  /// No description provided for @spectator.
  ///
  /// In he, this message translates to:
  /// **'צופה'**
  String get spectator;

  /// No description provided for @hintRuleLocal.
  ///
  /// In he, this message translates to:
  /// **'רמז של מילה אחת, בלי לחזור על רמז קודם ובלי לומר את המילה עצמה.'**
  String get hintRuleLocal;

  /// No description provided for @roundCategory.
  ///
  /// In he, this message translates to:
  /// **'סיבוב {round} · {category}'**
  String roundCategory(Object round, Object category);

  /// No description provided for @hintSaid.
  ///
  /// In he, this message translates to:
  /// **'הרמז נאמר'**
  String get hintSaid;

  /// No description provided for @turnOf.
  ///
  /// In he, this message translates to:
  /// **'התור של {speakerName}'**
  String turnOf(Object speakerName);

  /// No description provided for @sayHintAloud.
  ///
  /// In he, this message translates to:
  /// **'אומרים בקול רמז של מילה אחת'**
  String get sayHintAloud;

  /// No description provided for @turnOrder.
  ///
  /// In he, this message translates to:
  /// **'סדר התורות'**
  String get turnOrder;

  /// No description provided for @now.
  ///
  /// In he, this message translates to:
  /// **'עכשיו'**
  String get now;

  /// No description provided for @nextUp.
  ///
  /// In he, this message translates to:
  /// **'הבא בתור'**
  String get nextUp;

  /// No description provided for @noHintSaid.
  ///
  /// In he, this message translates to:
  /// **'לא נאמר רמז'**
  String get noHintSaid;

  /// No description provided for @said.
  ///
  /// In he, this message translates to:
  /// **'אמר/ה'**
  String get said;

  /// No description provided for @waiting.
  ///
  /// In he, this message translates to:
  /// **'ממתין/ה'**
  String get waiting;

  /// No description provided for @hintsSpokenAloud.
  ///
  /// In he, this message translates to:
  /// **'הרמזים נאמרים בקול — אין הקלדה ואין לוח רמזים.'**
  String get hintsSpokenAloud;

  /// No description provided for @passDeviceVote.
  ///
  /// In he, this message translates to:
  /// **'מעבירים את המכשיר בין השחקנים. אל תגלו למי הצבעתם.'**
  String get passDeviceVote;

  /// No description provided for @tie.
  ///
  /// In he, this message translates to:
  /// **'יש תיקו'**
  String get tie;

  /// No description provided for @tieCandidates.
  ///
  /// In he, this message translates to:
  /// **'{tieCandidatesLength} מועמדים קיבלו {tiedVotes, plural, =1{קול אחד} other{{tiedVotes} קולות}}'**
  String tieCandidates(Object tieCandidatesLength, int tiedVotes);

  /// No description provided for @startRevote.
  ///
  /// In he, this message translates to:
  /// **'מתחילים הצבעה חוזרת'**
  String get startRevote;

  /// No description provided for @thenPassNext.
  ///
  /// In he, this message translates to:
  /// **'אחר כך מעבירים את המכשיר לשחקן הבא'**
  String get thenPassNext;

  /// No description provided for @youreCaught.
  ///
  /// In he, this message translates to:
  /// **'{impostorName}, נתפסת'**
  String youreCaught(Object impostorName);

  /// No description provided for @guessWinsLocal.
  ///
  /// In he, this message translates to:
  /// **'ניחוש נכון של המילה הסודית מעניק לך את הניצחון. יש ניסיון אחד.'**
  String get guessWinsLocal;

  /// No description provided for @onlyPlayerLookingNoDot.
  ///
  /// In he, this message translates to:
  /// **'רק {impostorName} מסתכל/ת על המסך'**
  String onlyPlayerLookingNoDot(Object impostorName);

  /// No description provided for @localReasonGuessed.
  ///
  /// In he, this message translates to:
  /// **'המתחזה נתפס וניחש נכון את המילה.'**
  String get localReasonGuessed;

  /// No description provided for @localReasonMissed.
  ///
  /// In he, this message translates to:
  /// **'המתחזה נתפס ולא ניחש את המילה.'**
  String get localReasonMissed;

  /// No description provided for @theImpostor.
  ///
  /// In he, this message translates to:
  /// **'המתחזה'**
  String get theImpostor;

  /// No description provided for @howItEnded.
  ///
  /// In he, this message translates to:
  /// **'איך זה נגמר'**
  String get howItEnded;

  /// No description provided for @whoWasEliminated.
  ///
  /// In he, this message translates to:
  /// **'מי הודח במהלך המשחק'**
  String get whoWasEliminated;

  /// No description provided for @localNoStats.
  ///
  /// In he, this message translates to:
  /// **'משחק במכשיר אחד אינו משנה את הסטטיסטיקה בפרופיל.'**
  String get localNoStats;

  /// No description provided for @playerRound.
  ///
  /// In he, this message translates to:
  /// **'{playerName} · סיבוב {round}'**
  String playerRound(Object playerName, Object round);

  /// No description provided for @hiddenNextPlayer.
  ///
  /// In he, this message translates to:
  /// **'הסתרתי — לשחקן הבא'**
  String get hiddenNextPlayer;

  /// No description provided for @voteSaved.
  ///
  /// In he, this message translates to:
  /// **'ההצבעה נשמרה'**
  String get voteSaved;

  /// No description provided for @choiceHidden.
  ///
  /// In he, this message translates to:
  /// **'הבחירה הוסתרה מהמסך. אף אחד לא יראה למי הצבעת.'**
  String get choiceHidden;

  /// No description provided for @votingAgainSecret.
  ///
  /// In he, this message translates to:
  /// **'{meName} מצביע/ה שוב · הבחירה תישאר סודית'**
  String votingAgainSecret(Object meName);

  /// No description provided for @votingSecret.
  ///
  /// In he, this message translates to:
  /// **'{meName} מצביע/ה · הבחירה תישאר סודית'**
  String votingSecret(Object meName);

  /// No description provided for @ifTieAgain.
  ///
  /// In he, this message translates to:
  /// **'אם גם עכשיו יהיה תיקו — אף אחד לא יודח ומתחיל סיבוב רמזים חדש.'**
  String get ifTieAgain;

  /// No description provided for @screenClearsNext.
  ///
  /// In he, this message translates to:
  /// **'אחרי האישור המסך יתנקה לפני ההעברה לשחקן הבא.'**
  String get screenClearsNext;

  /// No description provided for @playerN.
  ///
  /// In he, this message translates to:
  /// **'שחקן {seat}'**
  String playerN(Object seat);

  /// No description provided for @everyPlayerNeedsName.
  ///
  /// In he, this message translates to:
  /// **'לכל שחקן צריך להיות שם'**
  String get everyPlayerNeedsName;

  /// No description provided for @namesMustDiffer.
  ///
  /// In he, this message translates to:
  /// **'לכל שחקן צריך להיות שם שונה'**
  String get namesMustDiffer;

  /// No description provided for @continueToSettings.
  ///
  /// In he, this message translates to:
  /// **'המשך להגדרות'**
  String get continueToSettings;

  /// No description provided for @whoIsPlaying.
  ///
  /// In he, this message translates to:
  /// **'מי משחק?'**
  String get whoIsPlaying;

  /// No description provided for @oneDevicePassed.
  ///
  /// In he, this message translates to:
  /// **'מכשיר אחד עובר בין כולם. הרמזים נאמרים בקול.'**
  String get oneDevicePassed;

  /// No description provided for @tapAvatarToChange.
  ///
  /// In he, this message translates to:
  /// **'לחיצה על אווטאר מחליפה אותו באחד שלא בשימוש.'**
  String get tapAvatarToChange;

  /// No description provided for @fewerPlayers.
  ///
  /// In he, this message translates to:
  /// **'פחות שחקנים'**
  String get fewerPlayers;

  /// No description provided for @nPlayers.
  ///
  /// In he, this message translates to:
  /// **'{count} שחקנים'**
  String nPlayers(Object count);

  /// No description provided for @morePlayers.
  ///
  /// In he, this message translates to:
  /// **'עוד שחקנים'**
  String get morePlayers;

  /// No description provided for @gameSettings.
  ///
  /// In he, this message translates to:
  /// **'הגדרות המשחק'**
  String get gameSettings;

  /// No description provided for @start.
  ///
  /// In he, this message translates to:
  /// **'מתחילים'**
  String get start;

  /// No description provided for @timeForEachHint.
  ///
  /// In he, this message translates to:
  /// **'זמן לכל רמז'**
  String get timeForEachHint;

  /// No description provided for @noTimer.
  ///
  /// In he, this message translates to:
  /// **'ללא טיימר'**
  String get noTimer;

  /// No description provided for @summary.
  ///
  /// In he, this message translates to:
  /// **'סיכום'**
  String get summary;

  /// No description provided for @players.
  ///
  /// In he, this message translates to:
  /// **'שחקנים'**
  String get players;

  /// No description provided for @impostors.
  ///
  /// In he, this message translates to:
  /// **'מתחזים'**
  String get impostors;

  /// No description provided for @oneImpostor.
  ///
  /// In he, this message translates to:
  /// **'מתחזה אחד'**
  String get oneImpostor;

  /// No description provided for @voting.
  ///
  /// In he, this message translates to:
  /// **'הצבעה'**
  String get voting;

  /// No description provided for @privateVoteOnDevice.
  ///
  /// In he, this message translates to:
  /// **'הצבעה פרטית במכשיר'**
  String get privateVoteOnDevice;

  /// No description provided for @onlineChoiceSubtitle.
  ///
  /// In he, this message translates to:
  /// **'שני מצבים, אותו משחק. אפשר להצטרף לשחקנים אחרים או לפתוח חדר לחברים.'**
  String get onlineChoiceSubtitle;

  /// No description provided for @quickGame.
  ///
  /// In he, this message translates to:
  /// **'משחק מהיר'**
  String get quickGame;

  /// No description provided for @quickGameSubtitle.
  ///
  /// In he, this message translates to:
  /// **'בוחרים קטגוריות ומצטרפים לשחקנים ברשת.'**
  String get quickGameSubtitle;

  /// No description provided for @players4to8.
  ///
  /// In he, this message translates to:
  /// **'4–8 שחקנים'**
  String get players4to8;

  /// No description provided for @privateRoomSubtitle.
  ///
  /// In he, this message translates to:
  /// **'יוצרים חדר ושולחים קוד, או מצטרפים לחדר קיים.'**
  String get privateRoomSubtitle;

  /// No description provided for @youDecideStart.
  ///
  /// In he, this message translates to:
  /// **'אתם קובעים מתי מתחילים'**
  String get youDecideStart;

  /// No description provided for @adLabel.
  ///
  /// In he, this message translates to:
  /// **'פרסומת'**
  String get adLabel;

  /// No description provided for @adFailed.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו להציג מודעה עד הסוף, ולכן ״{widgetName}״ לא נפתחה. אפשר לנסות שוב מאוחר יותר או לבחור אפשרות אחרת.'**
  String adFailed(Object widgetName);

  /// No description provided for @purchasesUnavailableLater.
  ///
  /// In he, this message translates to:
  /// **'הרכישות אינן זמינות כרגע. אנא נסו שוב מאוחר יותר.'**
  String get purchasesUnavailableLater;

  /// No description provided for @pricesFailed.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו לטעון את המחירים מהחנות. בדקו את החיבור לאינטרנט ונסו שוב.'**
  String get pricesFailed;

  /// No description provided for @purchaseCancelled.
  ///
  /// In he, this message translates to:
  /// **'הרכישה בוטלה. לא בוצע חיוב.'**
  String get purchaseCancelled;

  /// No description provided for @purchaseFailed.
  ///
  /// In he, this message translates to:
  /// **'הרכישה לא הושלמה ולא בוצע חיוב. בדקו את החיבור לאינטרנט ונסו שוב.'**
  String get purchaseFailed;

  /// No description provided for @purchasePending.
  ///
  /// In he, this message translates to:
  /// **'הרכישה ממתינה לאישור. ״{widgetName}״ תיפתח ברגע שהתשלום יאושר.'**
  String purchasePending(Object widgetName);

  /// No description provided for @restoredOther.
  ///
  /// In he, this message translates to:
  /// **'הרכישות שוחזרו, אבל ״{widgetName}״ לא נמצאה ביניהן.'**
  String restoredOther(Object widgetName);

  /// No description provided for @purchasesUnavailableRestore.
  ///
  /// In he, this message translates to:
  /// **'הרכישות אינן זמינות כרגע. אפשר לשחזר רכישות קודמות.'**
  String get purchasesUnavailableRestore;

  /// No description provided for @categoryLockedTitle.
  ///
  /// In he, this message translates to:
  /// **'״{widgetName}״ נעולה'**
  String categoryLockedTitle(Object widgetName);

  /// No description provided for @chooseHowToUnlock.
  ///
  /// In he, this message translates to:
  /// **'בחרו איך לפתוח אותה'**
  String get chooseHowToUnlock;

  /// No description provided for @perMonth.
  ///
  /// In he, this message translates to:
  /// **'לחודש'**
  String get perMonth;

  /// No description provided for @oneTimePayment.
  ///
  /// In he, this message translates to:
  /// **'תשלום אחד'**
  String get oneTimePayment;

  /// No description provided for @watchAd.
  ///
  /// In he, this message translates to:
  /// **'צפייה במודעה'**
  String get watchAd;

  /// No description provided for @adUnlocksNextGame.
  ///
  /// In he, this message translates to:
  /// **'פותחת את ״{widgetName}״ למשחק הבא בלבד'**
  String adUnlocksNextGame(Object widgetName);

  /// No description provided for @watchAgainIn.
  ///
  /// In he, this message translates to:
  /// **'אפשר לצפות שוב בעוד {value}'**
  String watchAgainIn(Object value);

  /// No description provided for @free.
  ///
  /// In he, this message translates to:
  /// **'חינם'**
  String get free;

  /// No description provided for @oneGame.
  ///
  /// In he, this message translates to:
  /// **'משחק אחד'**
  String get oneGame;

  /// No description provided for @durationHours.
  ///
  /// In he, this message translates to:
  /// **'{h} שע׳'**
  String durationHours(Object h);

  /// No description provided for @durationMinutes.
  ///
  /// In he, this message translates to:
  /// **'{min} דק׳'**
  String durationMinutes(Object min);

  /// No description provided for @durationAnd.
  ///
  /// In he, this message translates to:
  /// **' ו־'**
  String get durationAnd;

  /// No description provided for @premiumLifetime.
  ///
  /// In he, this message translates to:
  /// **'פרימיום לכל החיים'**
  String get premiumLifetime;

  /// No description provided for @onlyCategory.
  ///
  /// In he, this message translates to:
  /// **'רק ״{widgetName}״'**
  String onlyCategory(Object widgetName);

  /// No description provided for @premiumMonthlyDesc.
  ///
  /// In he, this message translates to:
  /// **'כל הקטגוריות ותכונות הפרימיום, בלי פרסומות — כל עוד המנוי פעיל'**
  String get premiumMonthlyDesc;

  /// No description provided for @premiumLifetimeDesc.
  ///
  /// In he, this message translates to:
  /// **'כל הקטגוריות, גם אלה שיתווספו בעתיד, ותכונות הפרימיום. בלי פרסומות לתמיד'**
  String get premiumLifetimeDesc;

  /// No description provided for @categoryForeverDesc.
  ///
  /// In he, this message translates to:
  /// **'פתוחה לתמיד · הפרסומות נשארות'**
  String get categoryForeverDesc;

  /// No description provided for @purchasesRestoredTitle.
  ///
  /// In he, this message translates to:
  /// **'הרכישות שוחזרו'**
  String get purchasesRestoredTitle;

  /// No description provided for @categoryOpenAgain.
  ///
  /// In he, this message translates to:
  /// **'״{widgetName}״ פתוחה שוב במכשיר הזה.'**
  String categoryOpenAgain(Object widgetName);

  /// No description provided for @categoryOpenNextGame.
  ///
  /// In he, this message translates to:
  /// **'״{widgetName}״ פתוחה למשחק הבא'**
  String categoryOpenNextGame(Object widgetName);

  /// No description provided for @thanksForWatching.
  ///
  /// In he, this message translates to:
  /// **'תודה שצפיתם. אחרי המשחק הבא הקטגוריה תינעל שוב.'**
  String get thanksForWatching;

  /// No description provided for @welcomePremium.
  ///
  /// In he, this message translates to:
  /// **'ברוכים הבאים לפרימיום'**
  String get welcomePremium;

  /// No description provided for @monthlyActive.
  ///
  /// In he, this message translates to:
  /// **'המנוי החודשי פעיל. אפשר לנהל או לבטל אותו בהגדרות המנויים בחנות.'**
  String get monthlyActive;

  /// No description provided for @lifetimeWithMonthly.
  ///
  /// In he, this message translates to:
  /// **'הכול פתוח לתמיד — כולל קטגוריות שיתווספו בעתיד. המנוי החודשי שלכם עדיין פעיל; אפשר לבטל אותו בהגדרות המנויים בחנות.'**
  String get lifetimeWithMonthly;

  /// No description provided for @lifetimeUnlocked.
  ///
  /// In he, this message translates to:
  /// **'הכול פתוח לתמיד — כולל קטגוריות שיתווספו בעתיד.'**
  String get lifetimeUnlocked;

  /// No description provided for @categoryUnlocked.
  ///
  /// In he, this message translates to:
  /// **'״{widgetName}״ נפתחה!'**
  String categoryUnlocked(Object widgetName);

  /// No description provided for @categoryYoursForever.
  ///
  /// In he, this message translates to:
  /// **'הקטגוריה שלכם לתמיד. הפרסומות ממשיכות להופיע.'**
  String get categoryYoursForever;

  /// No description provided for @allCategoriesOpen.
  ///
  /// In he, this message translates to:
  /// **'כל הקטגוריות פתוחות'**
  String get allCategoriesOpen;

  /// No description provided for @premiumFeaturesActive.
  ///
  /// In he, this message translates to:
  /// **'תכונות הפרימיום פעילות'**
  String get premiumFeaturesActive;

  /// No description provided for @noBannersNoAds.
  ///
  /// In he, this message translates to:
  /// **'בלי באנרים ובלי מודעות במסך מלא'**
  String get noBannersNoAds;

  /// No description provided for @startPlaying.
  ///
  /// In he, this message translates to:
  /// **'מתחילים לשחק'**
  String get startPlaying;

  /// No description provided for @chooseCategoryN.
  ///
  /// In he, this message translates to:
  /// **'בוחרים ב״{widgetName}״'**
  String chooseCategoryN(Object widgetName);

  /// No description provided for @loadingAd.
  ///
  /// In he, this message translates to:
  /// **'טוענים מודעה…'**
  String get loadingAd;

  /// No description provided for @adDisclosure.
  ///
  /// In he, this message translates to:
  /// **'״{widgetName}״ תיפתח אחרי צפייה מלאה במודעה, למשחק הבא בלבד. אפשר לפתוח כך קטגוריה פעם בארבע שעות.'**
  String adDisclosure(Object widgetName);

  /// No description provided for @loadingPrices.
  ///
  /// In he, this message translates to:
  /// **'טוענים מחירים…'**
  String get loadingPrices;

  /// No description provided for @connectingStore.
  ///
  /// In he, this message translates to:
  /// **'מתחברים לחנות…'**
  String get connectingStore;

  /// No description provided for @pricesInStoreCurrency.
  ///
  /// In he, this message translates to:
  /// **'המחירים מוצגים במטבע של חשבון החנות שלכם.'**
  String get pricesInStoreCurrency;

  /// No description provided for @continueInStore.
  ///
  /// In he, this message translates to:
  /// **'ממשיכים בחלון התשלום של החנות. אין לסגור את האפליקציה.'**
  String get continueInStore;

  /// No description provided for @subscriptionDisclosure.
  ///
  /// In he, this message translates to:
  /// **'המנוי מתחדש אוטומטית ב־{p} בכל חודש עד לביטול. אפשר לבטל בכל עת בהגדרות המנויים בחנות, לפחות 24 שעות לפני מועד החידוש.'**
  String subscriptionDisclosure(Object p);

  /// No description provided for @categoryPurchaseDisclosure.
  ///
  /// In he, this message translates to:
  /// **'תשלום אחד של {p} דרך החנות. ״{widgetName}״ נשארת פתוחה לתמיד; הפרסומות ממשיכות להופיע.'**
  String categoryPurchaseDisclosure(Object p, Object widgetName);

  /// No description provided for @premiumPurchaseDisclosure.
  ///
  /// In he, this message translates to:
  /// **'תשלום אחד של {p} דרך החנות. בלי מנוי ובלי חיובים נוספים.'**
  String premiumPurchaseDisclosure(Object p);

  /// No description provided for @joinPremium.
  ///
  /// In he, this message translates to:
  /// **'הצטרפות לפרימיום'**
  String get joinPremium;

  /// No description provided for @buyPrice.
  ///
  /// In he, this message translates to:
  /// **'קנייה · {p}'**
  String buyPrice(Object p);

  /// No description provided for @playerEliminated.
  ///
  /// In he, this message translates to:
  /// **'{eliminatedName} הודח/ה'**
  String playerEliminated(Object eliminatedName);

  /// No description provided for @role.
  ///
  /// In he, this message translates to:
  /// **'התפקיד'**
  String get role;

  /// No description provided for @wordStaysSecret.
  ///
  /// In he, this message translates to:
  /// **'המילה נשארת סודית — המשחק ממשיך.'**
  String get wordStaysSecret;

  /// No description provided for @stillInGame.
  ///
  /// In he, this message translates to:
  /// **'נשארו במשחק'**
  String get stillInGame;

  /// No description provided for @previousHint.
  ///
  /// In he, this message translates to:
  /// **'הרמז הקודם · {nickname}'**
  String previousHint(Object nickname);

  /// No description provided for @roundLabel.
  ///
  /// In he, this message translates to:
  /// **'סבב {round}'**
  String roundLabel(Object round);

  /// No description provided for @youWereEliminated.
  ///
  /// In he, this message translates to:
  /// **'הודחתם מהמשחק'**
  String get youWereEliminated;

  /// No description provided for @spectatorExplain.
  ///
  /// In he, this message translates to:
  /// **'אתם ממשיכים לצפות ולהגיב, בלי רמזים והצבעות. התוצאה שלכם היא של הקבוצה שלכם.'**
  String get spectatorExplain;

  /// No description provided for @secretWord.
  ///
  /// In he, this message translates to:
  /// **'המילה הסודית'**
  String get secretWord;

  /// No description provided for @wordNotShown.
  ///
  /// In he, this message translates to:
  /// **'המילה לא מוצגת לכם — רק הקטגוריה.'**
  String get wordNotShown;

  /// No description provided for @votingOpensAuto.
  ///
  /// In he, this message translates to:
  /// **'מסך ההצבעה נפתח אוטומטית'**
  String get votingOpensAuto;

  /// No description provided for @allHintsSent.
  ///
  /// In he, this message translates to:
  /// **'כל הרמזים נשלחו'**
  String get allHintsSent;

  /// No description provided for @toVoting.
  ///
  /// In he, this message translates to:
  /// **'עוברים להצבעה'**
  String get toVoting;

  /// No description provided for @wordWas.
  ///
  /// In he, this message translates to:
  /// **'המילה הייתה'**
  String get wordWas;

  /// No description provided for @theGuess.
  ///
  /// In he, this message translates to:
  /// **'הניחוש'**
  String get theGuess;

  /// No description provided for @rounds.
  ///
  /// In he, this message translates to:
  /// **'סבבים'**
  String get rounds;

  /// No description provided for @voteBreakdown.
  ///
  /// In he, this message translates to:
  /// **'חלוקת הקולות'**
  String get voteBreakdown;

  /// No description provided for @playAgain.
  ///
  /// In he, this message translates to:
  /// **'משחק נוסף'**
  String get playAgain;

  /// No description provided for @openFreeCount.
  ///
  /// In he, this message translates to:
  /// **'{count} פתוחות בחינם'**
  String openFreeCount(Object count);

  /// No description provided for @openCount.
  ///
  /// In he, this message translates to:
  /// **'{count} פתוחות'**
  String openCount(Object count);

  /// No description provided for @rewardRefused.
  ///
  /// In he, this message translates to:
  /// **'אפשר לפתוח קטגוריה בצפייה במודעה פעם בארבע שעות, ולכן ״{name}״ לא נפתחה.'**
  String rewardRefused(Object name);

  /// No description provided for @watchAgainInSentence.
  ///
  /// In he, this message translates to:
  /// **' אפשר לצפות שוב בעוד {time}.'**
  String watchAgainInSentence(Object time);

  /// No description provided for @phoneLanguage.
  ///
  /// In he, this message translates to:
  /// **'שפת הטלפון'**
  String get phoneLanguage;

  /// No description provided for @roomLanguageMismatch.
  ///
  /// In he, this message translates to:
  /// **'שפת החדר: {language}. כדי להצטרף, מחליפים שפה בהגדרות.'**
  String roomLanguageMismatch(Object language);

  /// No description provided for @guessTheWord.
  ///
  /// In he, this message translates to:
  /// **'ניחוש המילה'**
  String get guessTheWord;

  /// No description provided for @whoIsImpostor.
  ///
  /// In he, this message translates to:
  /// **'מי המתחזה?'**
  String get whoIsImpostor;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'he':
      return AppLocalizationsHe();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
