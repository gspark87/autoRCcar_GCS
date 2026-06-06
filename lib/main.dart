// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ros2/gcs_controller.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => GcsController(host: 'localhost', port: 9090),
      child: const GcsApp(),
    ),
  );
}

class GcsApp extends StatelessWidget {
  const GcsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutoRCCar GCS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      ),
      home: const MainScreen(),
    );
  }
}
