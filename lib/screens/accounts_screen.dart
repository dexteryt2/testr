import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../db/session_store.dart';
import 'login_screen.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(fa ? 'حساب‌ها' : 'Accounts'),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12),
            child: Chip(
              backgroundColor: cs.primaryContainer,
              label: Text('${state.availableCount}/${state.accounts.length}',
                style: TextStyle(color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold, fontSize: 12)),
              avatar: Icon(Icons.circle, size: 8, color:
                state.availableCount > 0 ? Colors.greenAccent : cs.error),
            )),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, state, fa),
        icon: const Icon(Icons.add), label: Text(fa ? 'لاگین جدید' : 'New Login'),
      ),
      body: state.accounts.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.no_accounts, size: 72, color: cs.outline),
              const SizedBox(height: 16),
              Text(fa ? 'هنوز حسابی نداری\nدکمه + بزن و با Google لاگین کن'
                  : 'No accounts yet\nTap + to login with Google',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.outline, height: 1.6)),
            ]))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: state.accounts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _AccountCard(
                  acc: state.accounts[i], fa: fa, state: state)),
    );
  }

  void _showAddDialog(BuildContext ctx, AppState state, bool fa) {
    final idCtrl = TextEditingController(
        text: 'acc_${(state.accounts.length + 1).toString().padLeft(2, '0')}');
    final labelCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String country = 'DE';

    showDialog(context: ctx, builder: (context) => AlertDialog(
      title: Text(fa ? 'افزودن حساب' : 'Add Account'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: idCtrl,
          decoration: InputDecoration(labelText: fa ? 'شناسه (acc_01)' : 'ID')),
        const SizedBox(height: 12),
        TextField(controller: labelCtrl,
          decoration: InputDecoration(labelText: fa ? 'نام (اختیاری)' : 'Label (optional)')),
        const SizedBox(height: 12),
        TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: fa ? 'ایمیل Google' : 'Google email')),
        const SizedBox(height: 12),
        StatefulBuilder(builder: (ctx2, ss) => DropdownButtonFormField<String>(
          value: country,
          decoration: InputDecoration(labelText: fa ? 'کشور پروکسی' : 'Proxy Country'),
          items: ['DE','NL','FR','AT','CH','US','GB','JP','SG']
              .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => ss(() => country = v!),
        )),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text(fa ? 'لغو' : 'Cancel')),
        ElevatedButton(
          onPressed: () async {
            if (idCtrl.text.isEmpty) return;
            Navigator.pop(context);
            // Register in DB first
            await state.store.addAccount(idCtrl.text.trim(), '',
              label: labelCtrl.text.trim().isEmpty ? idCtrl.text : labelCtrl.text.trim(),
              email: emailCtrl.text.trim(),
              country: country);
            // Open login screen
            if (ctx.mounted) {
              final ok = await Navigator.push<bool>(ctx, MaterialPageRoute(
                builder: (_) => LoginScreen(
                  accountId: idCtrl.text.trim(),
                  label: labelCtrl.text.trim().isEmpty ? idCtrl.text.trim() : labelCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  country: country,
                )));
              if (ok == true) await state.reloadAccounts();
            }
          },
          child: Text(fa ? 'بعدی: لاگین' : 'Next: Login'),
        ),
      ],
    ));
  }
}

class _AccountCard extends StatelessWidget {
  final PoolAccount acc;
  final bool fa;
  final AppState state;
  const _AccountCard({required this.acc, required this.fa, required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [
        Container(width: 10, height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle,
            color: acc.isAvailable ? Colors.greenAccent : cs.error)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(acc.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 3),
          Text(acc.id, style: TextStyle(fontSize: 11, color: cs.outline)),
        ])),
        IconButton(icon: Icon(Icons.delete_outline, color: cs.error),
          onPressed: () => _confirmDelete(context)),
      ]),
      const SizedBox(height: 12),
      // Token progress bar
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(fa ? 'توکن مصرفی' : 'Tokens used',
            style: TextStyle(fontSize: 11, color: cs.outline)),
          Text('${acc.tokensUsed} / $kTokenBudget (${acc.usagePct.toStringAsFixed(0)}%)',
            style: TextStyle(fontSize: 11, color: cs.outline)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: acc.usagePct / 100,
            minHeight: 6,
            backgroundColor: cs.outline.withOpacity(0.15),
            color: acc.usagePct > 80 ? cs.error : cs.primary,
          )),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _Chip(label: '${fa ? "درخواست" : "req"}: ${acc.requestsCount}',
          color: cs.primary),
        const SizedBox(width: 8),
        _Chip(label: acc.isAvailable ? (fa ? 'فعال' : 'Active') : (fa ? 'محدود' : 'Limited'),
          color: acc.isAvailable ? Colors.greenAccent.shade700 : cs.error),
      ]),
    ])));
  }

  void _confirmDelete(BuildContext ctx) {
    final fa = Localizations.localeOf(ctx).languageCode == 'fa';
    showDialog(context: ctx, builder: (c) => AlertDialog(
      title: Text(fa ? 'حذف حساب' : 'Delete Account'),
      content: Text(fa ? 'مطمئنی؟ session حذف میشه.' : 'Sure? Session will be removed.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(fa ? 'لغو' : 'Cancel')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () { Navigator.pop(c); state.deleteAccount(acc.id); },
          child: Text(fa ? 'حذف' : 'Delete')),
      ],
    ));
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)));
}
