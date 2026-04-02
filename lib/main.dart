import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // <-- Adicione isso
import 'package:premium_ui_kit/premium_ui_kit.dart';
import 'presentation/home/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env"); // <-- Carrega as chaves antes de tudo
  runApp(const SpotifaiApp());
}

class SpotifaiApp extends StatelessWidget {
  const SpotifaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'SpotifAI',
          theme: ThemeData.light(), // Substitua pelo código do seu tema claro atual
          darkTheme: ThemeData.dark(), // Substitua pelo código do seu tema escuro atual
          themeMode: ThemeMode.system, // A MÁGICA ACONTECE AQUI
          home: const HomeScreen(),
        );
      },
    );
  }
}
