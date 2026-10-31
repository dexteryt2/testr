import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_state.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state,
      child: ClaudePoolApp(prefs: prefs)));
}

class ClaudePoolApp extends StatefulWidget {
  final SharedPreferences prefs;
  const ClaudePoolApp({super.key, required this.prefs});
  @override State<ClaudePoolApp> createState() => _ClaudePoolAppState();
}

class _ClaudePoolAppState extends State<ClaudePoolApp> {
  late bool _dark;
  late Locale _locale;

  @override
  void initState() {
    super.initState();
    _dark = widget.prefs.getBool('dark') ?? true;
    _locale = Locale(widget.prefs.getString('lang') ?? 'fa');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claude Pool',
      debugShowCheckedModeBanner: false,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: _locale,
      supportedLocales: const [Locale('fa'), Locale('en')],
      home: HomeScreen(
        onTheme: (v) { setState(() => _dark = v);
          widget.prefs.setBool('dark', v); },
        onLocale: (l) { setState(() => _locale = l);
          widget.prefs.setString('lang', l.languageCode); },
        isDark: _dark, locale: _locale,
      ),
    );
  }

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF6C63FF),
      brightness: b,
      fontFamily: 'Vazirmatn',
      scaffoldBackgroundColor: dark ? const Color(0xFF0F0F14) : const Color(0xFFF5F5FA),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF1A1A24) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF0F0F14) : const Color(0xFFF5F5FA),
        elevation: 0, centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF1A1A24) : Colors.white,
        indicatorColor: const Color(0xFF6C63FF).withOpacity(0.2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF252530) : const Color(0xFFEEEEF8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C63FF), foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
