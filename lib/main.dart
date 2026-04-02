import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:premium_ui_kit/premium_ui_kit.dart';
import 'presentation/home/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Blindagem: Se o arquivo .env faltar na Cloudflare, o app avisa em vez de dar a Tela Cinza
  try {
    await dotenv.load(fileName: ".env"); 
  } catch (e) {
    debugPrint("⚠️ AVISO: Arquivo .env não encontrado. O Spotify pode falhar no login.");
  }
  
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
          title: 'Spotifai',
          debugShowCheckedModeBanner: false,
          
          // A sua arquitetura original restaurada:
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          
          home: const HomePage(),
        );
      },
    );
  }
}