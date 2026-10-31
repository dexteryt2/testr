import 'package:flutter/material.dart';
import 'accounts_screen.dart';
import 'chat_screen.dart';
import 'subscription_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(bool) onTheme;
  final void Function(Locale) onLocale;
  final bool isDark;
  final Locale locale;
  const HomeScreen({super.key, required this.onTheme, required this.onLocale,
      required this.isDark, required this.locale});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 1;
  @override
  Widget build(BuildContext context) {
    final fa = widget.locale.languageCode == 'fa';
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        const AccountsScreen(),
        const ChatScreen(),
        const SubscriptionScreen(),
        SettingsScreen(onTheme: widget.onTheme, onLocale: widget.onLocale,
            isDark: widget.isDark, locale: widget.locale),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.manage_accounts_outlined),
              selectedIcon: const Icon(Icons.manage_accounts),
              label: fa ? 'حساب‌ها' : 'Accounts'),
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline),
              selectedIcon: const Icon(Icons.chat_bubble),
              label: fa ? 'چت' : 'Chat'),
          NavigationDestination(icon: const Icon(Icons.link_outlined),
              selectedIcon: const Icon(Icons.link),
              label: fa ? 'پروکسی' : 'Proxy'),
          NavigationDestination(icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: fa ? 'تنظیمات' : 'Settings'),
        ],
      ),
    );
  }
}
