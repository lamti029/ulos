import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_page.dart';

class UlosApp extends StatelessWidget {
  const UlosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ULOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashPage(),
    );
  }
}
