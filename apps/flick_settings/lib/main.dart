import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const FlickSettingsApp());
}

class FlickSettingsApp extends StatelessWidget {
  const FlickSettingsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Settings',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
