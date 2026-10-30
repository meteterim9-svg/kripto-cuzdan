import 'package:flutter/material.dart';

import 'screens.dart';
import 'theme.dart';

void main() => runApp(const OrvexaApp());

class OrvexaApp extends StatelessWidget {
  const OrvexaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orvexa',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Gate(),
    );
  }
}
