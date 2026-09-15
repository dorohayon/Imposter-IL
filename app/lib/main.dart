import 'package:flutter/material.dart';

import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ImposterApp());
}

class ImposterApp extends StatelessWidget {
  const ImposterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'מי המתחזה?',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const OnboardingScreen(),
    );
  }
}
