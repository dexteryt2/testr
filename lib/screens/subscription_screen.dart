import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _urlCtrl = TextEditingController();
  final _manualCtrl = TextEditingController();
  String? _manualStatus;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tabs.dispose(); _urlCtrl.dispose(); _manualCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(fa ? 'پروکسی' : 'Proxy'),
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: fa ? 'لینک ساب' : 'Sub Link'),
          Tab(text: fa ? 'دستی' : 'Manual'),
        ]),
      ),
      body: TabBarView(controller: _tabs, children: [

        // ── Sub Link ─────────────────────────────────────────────────────────
        ListView(padding: const EdgeInsets.all(20), children: [
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.link, color: cs.primary), const SizedBox(width: 10),
              Text(fa ? 'لینک سابسکریپشن VLESS' : 'VLESS Subscription URL',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
            const SizedBox(height: 16),
            TextField(controller: _urlCtrl, textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: 'https://...')),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: state.isSyncing || _urlCtrl.text.isEmpty ? null
                  : () => state.syncSubscription(_urlCtrl.text.trim()),
              icon: state.isSyncing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync),
              label: Text(state.isSyncing
                  ? (fa ? 'در حال دریافت...' : 'Syncing...')
                  : (fa ? 'دریافت کانفیگ‌ها' : 'Fetch Configs')))),
            if (state.lastSyncInfo != null) ...[
              const SizedBox(height: 14),
              Container(padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('✓ ${state.lastSyncInfo}',
                  style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold))),
            ],
            if (state.lastError != null)
              Container(margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(state.lastError!, style: TextStyle(color: cs.onErrorContainer))),
          ]))),
          const SizedBox(height: 16),
          // Health check
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.health_and_safety_outlined, color: cs.primary),
              const SizedBox(width: 10),
              Text(fa ? 'بررسی سلامت' : 'Health Check',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
            const SizedBox(height: 12),
            if (state.isCheckingHealth) ...[
              LinearProgressIndicator(borderRadius: BorderRadius.circular(8)),
              const SizedBox(height: 8),
              Text('✓ ${state.aliveCount}  ✗ ${state.deadCount}',
                style: TextStyle(fontSize: 12, color: cs.outline)),
            ] else ...[
              if (state.aliveCount > 0 || state.deadCount > 0)
                Row(children: [
                  _StatChip('✓ ${state.aliveCount}', Colors.green),
                  const SizedBox(width: 8),
                  _StatChip('✗ ${state.deadCount}', cs.error),
                ]),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: state.runHealthCheck,
                icon: const Icon(Icons.radar),
                label: Text(fa ? 'شروع ping' : 'Run Ping Check'))),
            ],
          ]))),
        ]),

        // ── Manual ──────────────────────────────────────────────────────────
        ListView(padding: const EdgeInsets.all(20), children: [
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.edit_note, color: cs.primary), const SizedBox(width: 10),
              Text(fa ? 'ورود دستی VLESS' : 'Manual VLESS Entry',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
            const SizedBox(height: 6),
            Text(fa ? 'یک کانفیگ vless:// مستقیم وارد کن'
                : 'Paste a single vless:// config URI',
              style: TextStyle(fontSize: 12, color: cs.outline)),
            const SizedBox(height: 16),
            TextField(controller: _manualCtrl, maxLines: 5,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'vless://uuid@host:port?...',
                hintStyle: TextStyle(color: cs.outline, fontSize: 11))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _manualCtrl.text.startsWith('vless://') ? () async {
                final ok = await context.read<AppState>()
                    .addManualConfig(_manualCtrl.text.trim());
                setState(() {
                  _manualStatus = ok
                      ? (fa ? '✓ کانفیگ اضافه شد' : '✓ Config added')
                      : (fa ? '✗ فرمت نادرست' : '✗ Invalid format');
                  if (ok) _manualCtrl.clear();
                });
              } : null,
              icon: const Icon(Icons.add),
              label: Text(fa ? 'اضافه کن' : 'Add Config'))),
            if (_manualStatus != null) ...[
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _manualStatus!.startsWith('✓')
                      ? cs.primaryContainer : cs.errorContainer,
                  borderRadius: BorderRadius.circular(12)),
                child: Text(_manualStatus!, style: TextStyle(
                  color: _manualStatus!.startsWith('✓')
                      ? cs.onPrimaryContainer : cs.onErrorContainer))),
            ],
          ]))),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fa ? 'مثال فرمت:' : 'Format example:',
              style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8)),
              child: const SelectableText(
                'vless://uuid@host.com:443?security=tls&sni=host.com&type=ws&path=%2F#Name',
                style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
                textDirection: TextDirection.ltr)),
          ]))),
        ]),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label; final Color color;
  const _StatChip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Chip(
    label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    side: BorderSide(color: color.withOpacity(0.4)),
    backgroundColor: color.withOpacity(0.1), padding: EdgeInsets.zero);
}
