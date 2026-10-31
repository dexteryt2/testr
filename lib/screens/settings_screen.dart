import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/xray_manager.dart';

class SettingsScreen extends StatelessWidget {
  final void Function(bool) onTheme;
  final void Function(Locale) onLocale;
  final bool isDark; final Locale locale;
  const SettingsScreen({super.key, required this.onTheme, required this.onLocale,
      required this.isDark, required this.locale});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final fa = locale.languageCode == 'fa';
    final cs = Theme.of(context).colorScheme;
    final isFaLocale = locale.languageCode == 'fa';

    return Scaffold(
      appBar: AppBar(title: Text(fa ? 'تنظیمات' : 'Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        _Header(fa ? 'ظاهر' : 'Appearance'),
        Card(child: Column(children: [
          SwitchListTile(
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: cs.primary),
            title: Text(fa ? 'حالت تاریک' : 'Dark Mode'),
            value: isDark, onChanged: onTheme),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.language, color: cs.primary),
            title: Text(fa ? 'زبان' : 'Language'),
            trailing: ToggleButtons(
              borderRadius: BorderRadius.circular(10),
              isSelected: [isFaLocale, !isFaLocale],
              onPressed: (i) => onLocale(Locale(i == 0 ? 'fa' : 'en')),
              children: const [
                Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('فا')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('EN')),
              ]),
          ),
        ])),

        const SizedBox(height: 16),
        _Header(fa ? 'تنظیمات پول' : 'Pool Settings'),
        Card(child: Column(children: [
          ListTile(
            leading: Icon(Icons.swap_horiz, color: cs.primary),
            title: Text(fa ? 'حالت توزیع' : 'Mode'),
            trailing: DropdownButton<PoolMode>(
              value: state.mode, underline: const SizedBox(),
              items: [
                DropdownMenuItem(value: PoolMode.exhaustion,
                  child: Text(fa ? 'Exhaustion' : 'Exhaustion')),
                DropdownMenuItem(value: PoolMode.roundRobin, child: const Text('Round Robin')),
                DropdownMenuItem(value: PoolMode.random,
                  child: Text(fa ? 'تصادفی' : 'Random')),
              ],
              onChanged: (v) { if (v != null) state.setMode(v); }),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.account_balance_wallet_outlined, color: cs.primary),
            title: Text(fa ? 'وضعیت پول' : 'Pool Status'),
            subtitle: Text(
              '${state.availableCount}/${state.accounts.length} '
              '${fa ? "حساب" : "accounts"}  •  '
              '${state.totalTokensUsed} ${fa ? "توکن کل" : "total tokens"}',
              style: const TextStyle(fontSize: 12)),
          ),
        ])),

        const SizedBox(height: 16),
        _Header('Xray'),
        Card(child: Column(children: [
          ListTile(
            leading: Icon(Icons.router, color: cs.primary),
            title: const Text('Xray Engine'),
            subtitle: Text(
              '${XrayManager.instance.isRunning("") ? "Running" : "Idle"}',
              style: const TextStyle(fontSize: 12)),
            trailing: OutlinedButton(
              onPressed: () => XrayManager.instance.stopAll(),
              child: Text(fa ? 'توقف همه' : 'Stop All')),
          ),
        ])),

        const SizedBox(height: 16),
        _Header(fa ? 'تست' : 'Test'),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: state.accounts.isEmpty ? null : () async {
              if (state.accounts.isEmpty) return;
              final acc = state.accounts.first;
              final ok = await acc.client.testSession();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                    ? '✓ Session ${acc.label} فعاله'
                    : '✗ Session منقضی شده — دوباره لاگین کن'),
                  backgroundColor: ok ? Colors.green : cs.error));
              }
            },
            icon: const Icon(Icons.wifi_tethering),
            label: Text(fa ? 'تست اولین session' : 'Test First Session'))),
        ]))),

        const SizedBox(height: 16),
        _Header(fa ? 'منطقه خطر' : 'Danger'),
        Card(child: ListTile(
          leading: Icon(Icons.delete_forever, color: cs.error),
          title: Text(fa ? 'پاک کردن تاریخچه چت' : 'Clear Chat History',
            style: TextStyle(color: cs.error)),
          onTap: () {
            state.clearChat();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(fa ? 'پاک شد' : 'Cleared')));
          })),

        const SizedBox(height: 32),
        Center(child: Text('claude-pool v1.0.0',
            style: TextStyle(fontSize: 12, color: cs.outline))),
        const SizedBox(height: 20),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  const _Header(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
    child: Text(title, style: TextStyle(fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary)));
}
