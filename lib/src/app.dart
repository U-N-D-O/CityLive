import 'package:flutter/material.dart';

import 'features/home/nuuk_home_page.dart';

class NuukCityLiveApp extends StatelessWidget {
  const NuukCityLiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nuuk City Live',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006D77),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F3EE),
        textTheme: ThemeData.light().textTheme.apply(
          fontFamily: 'Georgia',
          bodyColor: const Color(0xFF14213D),
          displayColor: const Color(0xFF14213D),
        ),
      ),
      home: const NuukHomePage(),
    );
  }
}
