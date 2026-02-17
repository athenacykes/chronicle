import 'package:flutter/material.dart';

import '../presentation/common/chronicle_home_screen.dart';

class ChronicleApp extends StatelessWidget {
  const ChronicleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chronicle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D6A4F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const ChronicleHomeScreen(),
    );
  }
}
