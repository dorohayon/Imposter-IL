import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

/// Bump this value whenever a material Terms/Privacy change requires renewed
/// acknowledgement. The acknowledgement is deliberately device-local: the
/// product has no account system and no legal-consent profile on the server.
const legalVersion = '1.0';
const legalAcceptedVersionKey = 'legal.acceptedVersion';

/// Public copies for App Store Connect / Google Play and for people who want
/// to read the documents without installing the app. GitHub Pages publishes
/// the contents of /legal after this feature reaches main.
const privacyPolicyUrl =
    'https://dorohayon.github.io/Imposter-IL/privacy/';
const termsOfUseUrl = 'https://dorohayon.github.io/Imposter-IL/terms/';

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
    await widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'לפני שמתחילים',
      showBack: false,
      bottom: PrimaryButton(
        label: _busy ? 'שומרים...' : 'אישור והמשך',
        onPressed: _checked && !_busy ? _submit : null,
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
                'קראתי ואני מסכים/ה לתנאי השימוש ומאשר/ת שקראתי את מדיניות הפרטיות.',
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'גרסת מסמכים 1.0 · 17.09.2026',
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
          'גרסה 1.0 · בתוקף מ־17 בספטמבר 2026\n\nהשימוש ב״מי המתחזה?״ כפוף לתנאים הבאים. אם אינכם בגיל שמאפשר לכם להסכים לתנאים במקום מגוריכם, השתמשו במשחק רק באישור ובהשגחת הורה או אפוטרופוס.',
      sections: [
        _LegalSection(
          '1. השירות',
          '״מי המתחזה?״ הוא משחק חברתי מקוון. אין צורך בחשבון. אתם בוחרים כינוי ואווטאר ומקבלים מזהה אורח זמני לצורך המשחק.',
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
          '5. זמינות ושינויים',
          'השירות ניתן כפי שהוא ובהתאם לזמינות. אנחנו רשאים לתקן באגים, לשנות כללים ותוכן, להגביל גרסאות ישנות או להפסיק חלקים מהשירות. כששינוי מהותי בתנאים דורש הסכמה מחודשת, האפליקציה תציג את הגרסה החדשה לפני המשך המשחק.',
        ),
        _LegalSection(
          '6. קניין רוחני',
          'השם, העיצוב, הקוד, האיורים ותוכן המשחק שייכים לבעליהם ומוגנים לפי הדין החל. אין להעתיק, להפיץ, לבצע הנדסה לאחור או להשתמש בנכסי המשחק מעבר למה שמותר בדין או ברישיונות החלים.',
        ),
        _LegalSection(
          '7. אחריות',
          'במידה המרבית המותרת לפי דין, אין התחייבות שהשירות יהיה רציף או נטול שגיאות. אין בתנאים כדי לגרוע מזכויות צרכניות שלא ניתן לוותר עליהן לפי הדין החל.',
        ),
        _LegalSection(
          '8. פרטיות ויצירת קשר',
          'מדיניות הפרטיות היא חלק מהשימוש בשירות ומתארת את עיבוד המידע. כתובת תמיכה ייעודית תפורסם באפליקציה ובדף הציבורי לפני הגשה לחנויות.',
        ),
      ],
      publicUrl: termsOfUseUrl,
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
          'גרסה 1.0 · בתוקף מ־17 בספטמבר 2026\n\nהמדיניות מתארת את המידע שבו ״מי המתחזה?״ משתמש כדי להפעיל משחקים, לשמור העדפות ולהגן על שחקנים.',
      sections: [
        _LegalSection(
          '1. מידע שנשמר במכשיר',
          'האפליקציה שומרת במכשיר את מזהה ה־session וה־player הזמניים, הכינוי והאווטאר, ניצחונות והפסדים, הגדרות רטט ותגובות, גרסת המסמכים שאושרה ורשימת מזהי שחקנים שדיווחתם עליהם כדי להסתיר את התוכן שלהם. מחיקת האפליקציה או נתוניה עשויה למחוק מידע זה.',
        ),
        _LegalSection(
          '2. מידע שנשלח לשרת',
          'כדי להפעיל משחקים השרת מקבל מזהה שחקן ו־session, כינוי, אווטאר, כתובת IP לצורכי אבטחה והגבלת קצב, חברות בחדרים ובמשחקים, קטגוריות שנבחרו, רמזים, תגובות, הצבעות, ניחושים ודיווחים. אין צורך בשם אמיתי, מספר טלפון או כתובת דוא״ל כדי לשחק.',
        ),
        _LegalSection(
          '3. איך משתמשים במידע',
          'המידע משמש להפעלת matchmaking וחדרים, סנכרון המשחק בזמן אמת, חיבור מחדש, אכיפת כללי המשחק, מניעת abuse, טיפול בדיווחים, אבטחה, איתור תקלות ומדידת בריאות השרת.',
        ),
        _LegalSection(
          '4. מה שחקנים אחרים רואים',
          'שחקנים באותו משחק יכולים לראות את הכינוי והאווטאר שלכם, רמזים ששלחתם, מצב החיבור ומידע משחק הנדרש להצבעה ולתוצאה. המילה הסודית אינה נשלחת למתחזה לפני שלב התוצאה.',
        ),
        _LegalSection(
          '5. שמירה ומחיקה',
          'מצב המשחק והחדרים נשמר בזיכרון השרת ולא במסד נתונים קבוע. session מנותק שאינו נמצא בחדר נמחק לאחר תקופת חוסר פעילות של עד 24 שעות, וחדר ריק נסגר לאחר 30 דקות. אתחול שרת מוחק את מצב המשחק שבזיכרון. לוגים תפעוליים עשויים להישמר לצורכי אבטחה ואבחון ולכלול מזהי שחקן בדויים ומטא־דאטה של דיווחים.',
        ),
        _LegalSection(
          '6. שירותים חיצוניים',
          'תשתית אירוח ורשת עשויה לעבד מידע טכני הנדרש להעברת התעבורה. בגרסה 1.0 אין SDK פרסום, אין מכירת מידע אישי ואין SDK צד שלישי ל־analytics או crash reporting. אם יתווסף שירות כזה, המדיניות ורישומי החנויות יעודכנו לפי הצורך.',
        ),
        _LegalSection(
          '7. ילדים ופרטים אישיים',
          'המשחק אינו מבקש שם אמיתי או פרטי קשר. אין לכתוב בכינוי או ברמז מידע אישי שלכם או של אחרים. משתמשים שאינם בגיל המתאים להסכמה עצמאית במקום מגוריהם צריכים להשתמש במשחק באישור ובהשגחת הורה או אפוטרופוס.',
        ),
        _LegalSection(
          '8. בחירה ושליטה',
          'אפשר לשנות כינוי ואווטאר, לכבות רטט או תגובות, לדווח על שחקן ולנקות את רשימת השחקנים שהוסתרו. מחיקת נתוני האפליקציה מסירה את המידע המקומי. מאחר שאין חשבון קבוע, אין מנגנון שחזור של נתונים מקומיים.',
        ),
        _LegalSection(
          '9. יצירת קשר ושינויים',
          'כתובת תמיכה ופרטיות ייעודית תפורסם כאן ובאפליקציה לפני הגשה לחנויות. שינוי מהותי במדיניות יקבל גרסה חדשה; אם נדרשת הסכמה מחודשת, האפליקציה תציג אותה לפני המשך המשחק.',
        ),
      ],
      publicUrl: privacyPolicyUrl,
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
        trailing: const Icon(Icons.chevron_left_rounded),
      ),
    );
  }
}

class _LegalDocument extends StatelessWidget {
  const _LegalDocument({
    required this.title,
    required this.intro,
    required this.sections,
    required this.publicUrl,
  });

  final String title;
  final String intro;
  final List<_LegalSection> sections;
  final String publicUrl;

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
              'עותק ציבורי: $publicUrl',
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
