import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/server.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

/// Bump this value whenever a material Terms/Privacy change requires renewed
/// acknowledgement. The acknowledgement is deliberately device-local: the
/// product has no account system and no legal-consent profile on the server.
const legalVersion = '1.1';
const legalDate = '23 בספטמבר 2026';
const legalAcceptedVersionKey = 'legal.acceptedVersion';

/// Public copies for App Store Connect / Google Play and for anyone who wants
/// to read the documents without installing the app. The game server serves
/// them from the host it already has a certificate for: GitHub Pages cannot
/// publish a private repository without a paid plan, and a second host would
/// be one more thing to keep in step with these screens.
const privacyPath = '/privacy/';
const termsPath = '/terms/';

/// The public address of a document on whichever server this build talks to.
Uri publicLegalUrl(String path) => defaultServerUrl().resolve(path);

class LegalGate extends StatefulWidget {
  const LegalGate({required this.child, super.key});

  final Widget child;

  @override
  State<LegalGate> createState() => _LegalGateState();
}

class _LegalGateState extends State<LegalGate> {
  bool? _accepted;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _accepted = prefs.getString(legalAcceptedVersionKey) == legalVersion;
    });
  }

  Future<void> _accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(legalAcceptedVersionKey, legalVersion);
    if (!mounted) return;
    setState(() => _accepted = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_accepted!) return widget.child;
    return LegalConsentScreen(onAccepted: _accept);
  }
}

class LegalConsentScreen extends StatefulWidget {
  const LegalConsentScreen({required this.onAccepted, super.key});

  final Future<void> Function() onAccepted;

  @override
  State<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends State<LegalConsentScreen> {
  bool _checked = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_checked || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAccepted();
    } finally {
      // The gate is the way into the app. If saving failed, the button has to
      // come back rather than leave the player stuck on "שומרים...".
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'לפני שמתחילים',
      showBack: false,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pinned with the button it enables: in the scrolling body it fell
          // below the fold on a small phone, leaving a disabled button with
          // nothing on screen to explain it.
          Material(
            color: AppColors.cream.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(16),
            child: CheckboxListTile(
              value: _checked,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _checked = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.turquoise,
              checkColor: AppColors.night,
              title: const Text(
                'קראתי ואני מסכים/ה לתנאי השימוש ומאשר/ת שקראתי את מדיניות '
                'הפרטיות.',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.35),
              ),
            ),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: _busy ? 'שומרים...' : 'אישור והמשך',
            onPressed: _checked && !_busy ? _submit : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 72,
            color: AppColors.turquoise,
          ),
          const SizedBox(height: 18),
          Text(
            'משחק הוגן מתחיל בכללים ברורים',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'במשחק כותבים כינויים ורמזים ששחקנים אחרים יכולים לראות. '
            'אנחנו מסננים תוכן לא מתאים ומאפשרים לדווח ולהסתיר שחקנים.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          _LegalLink(
            title: 'תנאי שימוש',
            subtitle: 'כללי המשחק, תוכן אסור ודיווחים',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _LegalLink(
            title: 'מדיניות פרטיות',
            subtitle: 'איזה מידע נשמר, איפה ולכמה זמן',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'גרסת מסמכים $legalVersion · $legalDate',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocument(
      title: 'תנאי שימוש',
      intro:
          'גרסה $legalVersion · בתוקף מ־$legalDate\n\nהשימוש ב״מי המתחזה?״ כפוף לתנאים הבאים. המשחק מתאים מגיל 6 ומעלה. מי שטרם מלאו לו 13 יכול לשחק רק באישור ובהשגחה של הורה או אפוטרופוס, שמסכים לתנאים בשמו. אם מלאו לכם 13 אך אינכם בגיל שמאפשר לכם להסכים לתנאים במקום מגוריכם, השתמשו במשחק רק באישור ובהשגחת הורה או אפוטרופוס.',
      sections: [
        _LegalSection(
          '1. השירות',
          '״מי המתחזה?״ הוא משחק חברתי מקוון המופעל על ידי Imposter IL (imposteril36@gmail.com). אין צורך בחשבון. אתם בוחרים כינוי ואווטאר ומקבלים מזהה אורח זמני לצורך המשחק.',
        ),
        _LegalSection(
          '2. כללי התנהגות ותוכן',
          'אין לפרסם בכינוי או ברמז תוכן מיני מפורש, איומים, דברי שנאה, השפלה או הטרדה, תוכן בלתי חוקי, התחזות לאדם אחר, פרטים אישיים של אדם אחר או תוכן שנועד לפגוע בשחקנים. אין לנסות לעקוף את מסנני התוכן או לנצל לרעה את השרת, החדרים, מנגנון הדיווח או המשחק.',
        ),
        _LegalSection(
          '3. תוכן של שחקנים',
          'כינויים ורמזים שכתבתם מוצגים לשחקנים אחרים במשחק. אתם אחראים לתוכן שאתם שולחים. המשחק רשאי לסרב לתוכן, להסתירו או להפסיק גישה במקרה של הפרת הכללים. שחקנים יכולים לדווח על תוכן ולהסתיר תוכן של שחקן שדווח במכשיר שלהם.',
        ),
        _LegalSection(
          '4. משחקים, תוצאות וסטטיסטיקה',
          'המשחק עשוי להסתיים עקב ניתוק, תקלה או תחזוקה. ניצחונות והפסדים נשמרים במכשיר בלבד ואינם חשבון, דירוג או נכס שניתן לשחזר לאחר מחיקת האפליקציה או מעבר מכשיר.',
        ),
        _LegalSection(
          '5. רכישות, מנויים ופרסומות',
          'שלוש קטגוריות פתוחות בחינם. את שאר הקטגוריות אפשר לפתוח ברכישה של קטגוריה אחת לתמיד, במנוי פרימיום חודשי או ברכישת פרימיום לכל החיים. פרימיום פותח את כל הקטגוריות, גם כאלה שיתווספו, ומסיר את הפרסומות; רכישת קטגוריה בודדת אינה מסירה פרסומות. התשלום, החיוב, החידוש וההחזרים מתבצעים דרך App Store או Google Play, בכפוף לתנאים שלהם ובמחיר שהחנות מציגה במטבע של חשבונכם. המנוי החודשי מתחדש אוטומטית בכל חודש עד לביטול. אפשר לבטל אותו בכל עת בהגדרות המנויים בחנות, לפחות 24 שעות לפני מועד החידוש, והגישה נשארת עד סוף התקופה ששולמה. רכישה שהוחזרה או בוטלה בחנות מפסיקה לפתוח את מה שפתחה. רכישות שייכות לחשבון החנות ולא למכשיר, ואפשר לשחזר אותן בכל מכשיר עם אותו חשבון באמצעות ״שחזור רכישות״. למי שאין לו פרימיום מוצגות פרסומות של צד שלישי במסכים שמחוץ למשחק ואחרי משחק שהסתיים. במכשירי Apple חל גם הסכם הרישיון הסטנדרטי של Apple למשתמש קצה (EULA). אין באמור כדי לגרוע מזכויות שלכם לפי דיני הגנת הצרכן החלים, לרבות ביטול עסקה.',
        ),
        _LegalSection(
          '6. זמינות ושינויים',
          'השירות ניתן כפי שהוא ובהתאם לזמינות. מפעיל השירות רשאי לתקן באגים, לשנות כללים ותוכן, להגביל גרסאות ישנות או להפסיק חלקים מהשירות. כששינוי מהותי בתנאים דורש הסכמה מחודשת, האפליקציה תציג את הגרסה החדשה לפני המשך המשחק.',
        ),
        _LegalSection(
          '7. קניין רוחני',
          'השם, העיצוב, הקוד, האיורים ותוכן המשחק שייכים לבעליהם ומוגנים לפי הדין החל. אין להעתיק, להפיץ, לבצע הנדסה לאחור או להשתמש בנכסי המשחק מעבר למה שמותר בדין או ברישיונות החלים.',
        ),
        _LegalSection(
          '8. אחריות',
          'במידה המרבית המותרת לפי דין, אין התחייבות שהשירות יהיה רציף או נטול שגיאות. אין בתנאים כדי לגרוע מזכויות צרכניות שלא ניתן לוותר עליהן לפי הדין החל.',
        ),
        _LegalSection(
          '9. פרטיות',
          'מדיניות הפרטיות מתארת את המידע שבו השירות משתמש ואת תקופות השמירה והיא חלק מהשימוש בשירות.',
        ),
        _LegalSection(
          '10. שינויים בתנאים',
          'שינוי מהותי יקבל גרסת מסמכים חדשה. האפליקציה שומרת במכשיר את גרסת התנאים שאושרה ויכולה לדרוש אישור מחדש לגרסה חדשה.',
        ),
        _LegalSection(
          '11. דין וסמכות שיפוט',
          'על תנאים אלה חלים דיני מדינת ישראל, וסמכות השיפוט הבלעדית נתונה לבתי המשפט המוסמכים במחוז תל אביב־יפו. אין באמור כדי לגרוע מזכותכם לתבוע במקום מגוריכם כאשר הדין החל עליכם מקנה לכם זכות כזו.',
        ),
        _LegalSection(
          '12. יצירת קשר',
          'Imposter IL · imposteril36@gmail.com\nלתמיכה, לדיווח על תוכן פוגעני ולכל שאלה על התנאים האלה.',
        ),
      ],
      publicPath: termsPath,
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocument(
      title: 'מדיניות פרטיות',
      intro:
          'גרסה $legalVersion · בתוקף מ־$legalDate\n\nהמדיניות מתארת את המידע שבו ״מי המתחזה?״ משתמש כדי להפעיל משחקים, לשמור העדפות ולהגן על שחקנים.',
      sections: [
        _LegalSection(
          '1. מי אנחנו',
          'המשחק ״מי המתחזה?״ מופעל על ידי Imposter IL, והמדיניות הזאת חלה על האפליקציה ועל השרת שמפעיל אותה. לפניות בנושא פרטיות: imposteril36@gmail.com.',
        ),
        _LegalSection(
          '2. מידע שנשמר במכשיר',
          'האפליקציה שומרת במכשיר את מזהה ה־session וה־player הזמניים, הכינוי והאווטאר, ניצחונות והפסדים, הגדרות רטט ותגובות, גרסת המסמכים שאושרה ורשימת מזהי שחקנים שדיווחתם עליהם כדי להסתיר את התוכן שלהם. מחיקת האפליקציה או נתוניה עשויה למחוק מידע זה. לאחר רכישה נשמרים גם הקטגוריות והפרימיום שבבעלותכם ומועד התוקף של המנוי, כדי שיישארו פתוחים גם בלי חיבור, וכן הגדרות הפרסומות שהתקבלו מהשרת ומועד המודעה האחרונה במסך מלא.',
        ),
        _LegalSection(
          '3. מידע שנשלח לשרת',
          'כדי להפעיל משחקים השרת מקבל מזהה שחקן ו־session, כינוי, אווטאר, כתובת IP לצורכי אבטחה והגבלת קצב, חברות בחדרים ובמשחקים, קטגוריות שנבחרו, רמזים, תגובות, הצבעות, ניחושים ודיווחים. אין צורך בשם אמיתי, מספר טלפון או כתובת דוא״ל כדי לשחק. כדי לפתוח ברשת קטגוריות שרכשתם, האפליקציה שולחת לשרת את ההוכחה שהחנות מספקת לרכישה — עסקה חתומה של Apple או אסימון רכישה של Google, הכוללים את מזהה המוצר, מזהה העסקה ומועדיה. השרת מאמת אותה מול Apple או Google. אנחנו לא מקבלים את פרטי התשלום שלכם.',
        ),
        _LegalSection(
          '4. מטרות השימוש',
          'המידע משמש להפעלת matchmaking וחדרים, סנכרון המשחק בזמן אמת, חיבור מחדש, אכיפת כללי המשחק, מניעת abuse, טיפול בדיווחים, אבטחה, איתור תקלות ומדידת בריאות השרת. המידע משמש גם לאימות רכישות ולאכיפת הקטגוריות הפתוחות, ולהצגת פרסומות למי שאין לו פרימיום.',
        ),
        _LegalSection(
          '5. מה שחקנים אחרים רואים',
          'שחקנים באותו משחק יכולים לראות את הכינוי והאווטאר שלכם, רמזים ששלחתם, מצב החיבור ומידע משחק הנדרש להצבעה ולתוצאה. המילה הסודית אינה נשלחת למתחזה לפני שלב התוצאה.',
        ),
        _LegalSection(
          '6. שמירה ומחיקה',
          'מצב המשחק והחדרים נשמר בזיכרון השרת ולא במסד נתונים קבוע. session מנותק שאינו נמצא בחדר נמחק לאחר תקופת חוסר פעילות של עד 24 שעות, וחדר ריק נסגר לאחר 30 דקות. אתחול שרת מוחק את מצב המשחק שבזיכרון. לוגים תפעוליים עשויים להישמר לצורכי אבטחה ואבחון ולכלול מזהי שחקן בדויים ומטא־דאטה של דיווחים. תוצאת אימות הרכישות נשמרת בזיכרון השרת לצד ה־session בלבד ונמחקת איתו.',
        ),
        _LegalSection(
          '7. שירותים חיצוניים',
          'השרת מתארח ב־Google Cloud Platform (Cloud Run, אזור us-central1), וגוגל מעבדת מידע טכני הנדרש להעברת התעבורה ולשמירת הלוגים התפעוליים, כמעבדת מידע מטעמנו ובכפוף להתחייבויות אבטחה ופרטיות ברמה זהה או טובה יותר מזו שמתוארת כאן. התשלומים מתבצעים ב־App Store של Apple וב־Google Play, לפי מדיניות הפרטיות שלהם. למי שאין לו פרימיום מוצגות פרסומות של Google AdMob. AdMob עשויה לאסוף מזהי מכשיר ומזהה פרסום, כתובת IP, מידע על אינטראקציה עם מודעות, מידע אבחון וביצועים, לצורך הצגת מודעות, מדידתן ומניעת הונאה, לפי מדיניות הפרסום של Google (policies.google.com/technologies/ads). במקומות שבהם הדין מחייב, ובהם האיחוד האירופי ובריטניה, מתבקשת הסכמתכם לפני פרסום מותאם אישית; ב־iPhone לא נעשה שימוש במזהה הפרסום ללא הרשאתכם. אין מכירת מידע אישי, ואין SDK צד שלישי ל־analytics או crash reporting. אם יתווסף שירות כזה, המדיניות ורישומי החנויות יעודכנו.',
        ),
        _LegalSection(
          '8. ילדים ופרטים אישיים',
          'המשחק אינו מבקש שם אמיתי או פרטי קשר. אין לכתוב בכינוי או ברמז מידע אישי שלכם או של אחרים. התוכן מתאים מגיל 6 ומעלה. ילדים שטרם מלאו להם 13 יכולים לשחק רק באישור ובהשגחה של הורה או אפוטרופוס, שמאשר בשמם את התנאים ואת המדיניות הזאת. איננו אוספים ביודעין מידע מילד מתחת לגיל 13 ללא אישור כזה, ואם ייוודע לנו על כך נמחק את המידע הקשור אליו. המודעות מוגבלות לתוכן בדירוג שמתאים לקהל רחב.',
        ),
        _LegalSection(
          '9. בחירה ושליטה',
          'אפשר לשנות כינוי ואווטאר, לכבות רטט או תגובות, לדווח על שחקן ולנקות את רשימת השחקנים שהוסתרו. מחיקת נתוני האפליקציה מסירה את המידע המקומי. מאחר שאין חשבון קבוע, אין מנגנון שחזור של נתונים מקומיים. אפשר גם לשנות את העדפות הפרטיות לפרסומות בהגדרות, כשהדין מחייב, לסרב להרשאת מעקב ב־iPhone או לאפס את מזהה הפרסום בהגדרות המכשיר. פרימיום מסיר את כל הפרסומות.',
        ),
        _LegalSection(
          '10. הזכויות שלכם',
          'לפי חוק הגנת הפרטיות התשמ״א־1981 ותיקון 13 לו, ובמקומות שבהם חל ה־GDPR, יש לכם זכות לעיין במידע שנשמר עליכם, לבקש את תיקונו, למחוק אותו, להגביל או להתנגד לעיבודו ולקבלו בפורמט נגיש. מאחר שאין חשבון, נדרש מזהה השחקן או ה־session שמופיע במסך ההגדרות כדי לאתר מידע שקשור אליכם. לבקשה כתבו ל־imposteril36@gmail.com; נענה בתוך 30 יום. מרבית המידע נמחק ממילא מאליו — מצב המשחק בסיום המשחק, session לאחר 24 שעות והלוגים לאחר 30 יום.',
        ),
        _LegalSection(
          '11. אבטחה',
          'התעבורה בגרסאות הפצה נועדה לעבור בחיבור מוצפן. השרת מפעיל מגבלות קצב, מגבלות גודל הודעה וסינון תוכן כדי להפחית שימוש לרעה. אין מערכת שיכולה להבטיח אבטחה מוחלטת.',
        ),
        _LegalSection(
          '12. שינויים במדיניות',
          'שינוי מהותי במדיניות יקבל גרסה חדשה. כאשר נדרשת הסכמה מחודשת, האפליקציה תציג את הגרסה החדשה לפני המשך המשחק.',
        ),
        _LegalSection(
          '13. יצירת קשר',
          'Imposter IL · imposteril36@gmail.com\nלפניות בנושא פרטיות, בקשות למימוש זכויות ודיווח על תוכן פוגעני. נשתדל להשיב בתוך 30 יום.',
        ),
      ],
      publicPath: privacyPath,
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        onTap: onTap,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _LegalDocument extends StatelessWidget {
  const _LegalDocument({
    required this.title,
    required this.intro,
    required this.sections,
    required this.publicPath,
  });

  final String title;
  final String intro;
  final List<_LegalSection> sections;
  final String publicPath;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            intro,
            style: const TextStyle(color: AppColors.muted, height: 1.55),
          ),
          const SizedBox(height: 20),
          for (final section in sections) ...[
            Text(
              section.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(section.body, style: const TextStyle(height: 1.55)),
            const SizedBox(height: 18),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cream.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              'עותק ציבורי: ${publicLegalUrl(publicPath)}',
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection(this.title, this.body);

  final String title;
  final String body;
}
