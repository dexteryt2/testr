import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  void _scrollToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final cs = Theme.of(context).colorScheme;
    if (state.chatHistory.isNotEmpty) _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: Text(fa ? 'چت' : 'Chat'),
        actions: [
          // Mode chip
          Padding(padding: const EdgeInsets.only(right: 4),
            child: PopupMenuButton<PoolMode>(
              initialValue: state.mode,
              onSelected: state.setMode,
              child: Chip(
                avatar: const Icon(Icons.tune, size: 14),
                label: Text(_modeLabel(state.mode, fa), style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
              ),
              itemBuilder: (_) => [
                _modeItem(PoolMode.exhaustion, fa ? 'Exhaustion' : 'Exhaustion',
                    fa ? 'یک اکانت تا تموم شدن توکن' : 'Use one until tokens run out'),
                _modeItem(PoolMode.roundRobin, 'Round Robin',
                    fa ? 'چرخش یکسان' : 'Distribute evenly'),
                _modeItem(PoolMode.random, fa ? 'تصادفی' : 'Random',
                    fa ? 'انتخاب تصادفی' : 'Pick randomly'),
              ],
            )),
          if (state.chatHistory.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: state.clearChat),
        ],
      ),
      body: Column(children: [
        // Pool bar
        if (state.accounts.isNotEmpty)
          Container(
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              Icon(Icons.circle, size: 8,
                color: state.availableCount > 0 ? Colors.greenAccent : cs.error),
              const SizedBox(width: 8),
              Text('${state.availableCount}/${state.accounts.length}  •  '
                  '${state.totalTokensUsed} tokens',
                style: TextStyle(fontSize: 11, color: cs.outline)),
              const Spacer(),
              ...state.accounts.take(8).map((a) => Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Tooltip(message: '${a.label}: ${a.usagePct.toStringAsFixed(0)}%',
                  child: Container(width: 6, height: 20,
                    decoration: BoxDecoration(
                      color: cs.outline.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(3)),
                    child: FractionallySizedBox(
                      heightFactor: (a.usagePct / 100).clamp(0.0, 1.0),
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: a.isAvailable ? cs.primary : cs.error,
                          borderRadius: BorderRadius.circular(3))))))))
            ])),

        // Messages
        Expanded(child: state.chatHistory.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.auto_awesome, size: 72, color: cs.primary.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text(state.accounts.isEmpty
                    ? (fa ? 'ابتدا یه حساب اضافه کن' : 'Add an account first')
                    : (fa ? 'پیام بفرست...' : 'Send a message...'),
                  style: TextStyle(color: cs.outline, fontSize: 16)),
              ]))
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                itemCount: state.chatHistory.length,
                itemBuilder: (ctx, i) {
                  final msg = state.chatHistory[i];
                  return Column(children: [
                    if (msg.accountSwitched && msg.role == 'assistant')
                      _SwitchBadge(account: msg.accountUsed ?? '', fa: fa),
                    _Bubble(msg: msg, fa: fa),
                  ]);
                })),

        // Typing
        if (state.isSending)
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(children: [
              SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
              const SizedBox(width: 10),
              Text(fa ? 'در حال تایپ...' : 'Typing...',
                style: TextStyle(fontSize: 12, color: cs.outline)),
            ])),

        // Input
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
                blurRadius: 10, offset: const Offset(0, -4))]),
          child: SafeArea(top: false, child: Row(children: [
            Expanded(child: TextField(
              controller: _ctrl, maxLines: 4, minLines: 1,
              textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
              decoration: InputDecoration(
                hintText: fa ? 'پیام بنویسید...' : 'Type a message...',
                hintTextDirection: fa ? TextDirection.rtl : TextDirection.ltr),
            )),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: state.isSending || state.accounts.isEmpty ? null : () {
                final t = _ctrl.text.trim();
                if (t.isEmpty) return;
                _ctrl.clear();
                state.sendMessage(t);
              },
              icon: const Icon(Icons.send_rounded)),
          ])),
        ),
      ]),
    );
  }

  String _modeLabel(PoolMode m, bool fa) => switch (m) {
    PoolMode.exhaustion => fa ? 'تموم‌کن' : 'Exhaust',
    PoolMode.roundRobin => 'RR',
    PoolMode.random => fa ? 'تصادفی' : 'Rand',
  };

  PopupMenuItem<PoolMode> _modeItem(PoolMode m, String title, String sub) =>
    PopupMenuItem(value: m, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(sub, style: const TextStyle(fontSize: 11)),
      ]));
}

class _SwitchBadge extends StatelessWidget {
  final String account; final bool fa;
  const _SwitchBadge({required this.account, required this.fa});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(height: 1, width: 40, color: cs.outline.withOpacity(0.3)),
        const SizedBox(width: 8),
        Icon(Icons.swap_horiz, size: 14, color: cs.primary),
        const SizedBox(width: 6),
        Text(fa ? 'انتقال به $account' : 'Switched to $account',
          style: TextStyle(fontSize: 11, color: cs.primary)),
        const SizedBox(width: 8),
        Container(height: 1, width: 40, color: cs.outline.withOpacity(0.3)),
      ]));
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg; final bool fa;
  const _Bubble({required this.msg, required this.fa});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = msg.role == 'user';
    final isErr = msg.role == 'error';
    return Padding(padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(radius: 16, backgroundColor: cs.primaryContainer,
              child: Icon(Icons.auto_awesome, size: 16, color: cs.primary)),
            const SizedBox(width: 8),
          ],
          Flexible(child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isErr ? cs.errorContainer : isUser ? cs.primary : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18))),
                child: SelectableText(msg.text,
                  style: TextStyle(
                    color: isUser ? cs.onPrimary : cs.onSurface, height: 1.55),
                  textDirection: fa ? TextDirection.rtl : TextDirection.ltr)),
              if (msg.accountUsed != null)
                Padding(padding: const EdgeInsets.only(top: 3, left: 4),
                  child: Text('${fa ? "از طریق" : "via"} ${msg.accountUsed}',
                    style: TextStyle(fontSize: 10, color: cs.outline))),
            ])),
          if (isUser) const SizedBox(width: 8),
        ]));
  }
}
