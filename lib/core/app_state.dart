import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../db/session_store.dart';
import 'claude_client.dart';
import 'subscription.dart';
import 'xray_manager.dart';

const int kTokenBudget = 40000;
const _uuid = Uuid();

enum PoolMode { exhaustion, roundRobin, random }

class PoolAccount {
  final String id;
  final String label;
  final ClaudeClient client;

  bool active = true;
  int tokensUsed = 0;
  int requestsCount = 0;
  DateTime? rateLimitedUntil;
  String? currentConvId;

  PoolAccount({required this.id, required this.label, required this.client});

  bool get isAvailable {
    if (!active) return false;
    if (rateLimitedUntil != null && DateTime.now().isBefore(rateLimitedUntil!)) {
      return false;
    }
    return true;
  }

  bool get hasBudget => tokensUsed < kTokenBudget;
  double get usagePct => (tokensUsed / kTokenBudget * 100).clamp(0, 100);

  void markRateLimited([int seconds = 300]) {
    rateLimitedUntil = DateTime.now().add(Duration(seconds: seconds));
  }
}

class ChatMessage {
  final String role;
  final String text;
  final String? accountUsed;
  final bool accountSwitched;
  final DateTime time;

  ChatMessage({
    required this.role,
    required this.text,
    this.accountUsed,
    this.accountSwitched = false,
  }) : time = DateTime.now();
}

class AppState extends ChangeNotifier {
  final SessionStore store = SessionStore();

  List<PoolAccount> accounts = [];
  List<ChatMessage> chatHistory = [];

  PoolMode mode = PoolMode.exhaustion;
  String preferredCountry = 'DE';
  bool isSending = false;
  bool isSyncing = false;
  bool isCheckingHealth = false;
  int aliveCount = 0;
  int deadCount = 0;
  String? lastError;
  String? lastSyncInfo;

  int _rrIndex = 0;
  int _exhaustionIndex = 0;
  final _rng = Random();

  // ── Init ────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await _loadAccounts();
    notifyListeners();
  }

  Future<void> _loadAccounts() async {
    accounts.clear();
    final sessions = await store.getAllSessions();
    for (final sess in sessions) {
      final client = ClaudeClient(
        accountId: sess['account_id'] as String,
        cookies: sess['cookies'] as Map<String, String>,
        orgId: sess['org_id'] as String? ?? '',
        deviceId: sess['device_id'] as String? ?? _uuid.v4(),
        proxyPort: sess['proxy_port'] as int?,
      );
      accounts.add(PoolAccount(
        id: sess['account_id'] as String,
        label: sess['label'] as String? ?? sess['account_id'] as String,
        client: client,
      )
        ..tokensUsed = sess['tokens_used'] as int? ?? 0
        ..requestsCount = sess['requests_count'] as int? ?? 0);
    }
  }

  Future<void> reloadAccounts() async {
    await _loadAccounts();
    notifyListeners();
  }

  // ── Account picking ──────────────────────────────────────────────────────────

  PoolAccount? _pick() {
    final avail = accounts.where((a) => a.isAvailable).toList();
    if (avail.isEmpty) return null;

    switch (mode) {
      case PoolMode.random:
        return avail[_rng.nextInt(avail.length)];

      case PoolMode.roundRobin:
        for (var i = 0; i < accounts.length; i++) {
          final idx = (_rrIndex + i) % accounts.length;
          if (accounts[idx].isAvailable) {
            _rrIndex = (idx + 1) % accounts.length;
            return accounts[idx];
          }
        }
        return null;

      case PoolMode.exhaustion:
        while (_exhaustionIndex < accounts.length) {
          final acc = accounts[_exhaustionIndex];
          if (acc.isAvailable && acc.hasBudget) return acc;
          _exhaustionIndex++;
        }
        _exhaustionIndex = 0;
        return avail.firstOrNull;
    }
  }

  // ── Send message ─────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    chatHistory.add(ChatMessage(role: 'user', text: text));
    isSending = true;
    lastError = null;
    notifyListeners();

    final prevId = chatHistory
        .where((m) => m.role == 'assistant' && m.accountUsed != null)
        .lastOrNull
        ?.accountUsed;

    for (var attempt = 0; attempt <= accounts.length; attempt++) {
      final acc = _pick();
      if (acc == null) {
        lastError = 'همه حساب‌ها ناموجودند';
        break;
      }

      final isSwitch = prevId != null && acc.id != prevId;

      // Ensure conversation
      acc.currentConvId ??= await acc.client.createConversation();
      if (acc.currentConvId == null) {
        acc.active = false;
        continue;
      }

      // On switch, start new conv and inject full history
      if (isSwitch) {
        acc.currentConvId = await acc.client.createConversation();
        if (acc.currentConvId == null) { acc.active = false; continue; }
      }

      final prompt = isSwitch ? _buildContextPrompt(text) : text;

      final result = await acc.client.sendMessage(
        acc.currentConvId!,
        prompt,
      );

      if (result.ok) {
        acc.tokensUsed += result.tokensEst;
        acc.requestsCount++;
        await store.recordUsage(acc.id, result.tokensEst);

        if (mode == PoolMode.exhaustion && !acc.hasBudget) {
          _exhaustionIndex++;
        }

        chatHistory.add(ChatMessage(
          role: 'assistant',
          text: result.text!,
          accountUsed: acc.label,
          accountSwitched: isSwitch,
        ));
        break;
      }

      if (result.rateLimited) {
        acc.markRateLimited(result.retryAfter);
        await store.markRateLimited(
            acc.id, acc.rateLimitedUntil!.toIso8601String());
        if (mode == PoolMode.exhaustion) _exhaustionIndex++;
        continue;
      }

      if (result.sessionExpired) {
        acc.active = false;
        await store.invalidateSession(acc.id);
        continue;
      }

      lastError = result.error;
    }

    if (lastError != null) {
      chatHistory.add(ChatMessage(role: 'error', text: lastError!));
    }

    isSending = false;
    notifyListeners();
  }

  String _buildContextPrompt(String newText) {
    final msgs = chatHistory
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList();
    if (msgs.isEmpty) return newText;
    final buf = StringBuffer(
        'The following is our conversation so far. Continue naturally.\n---\n');
    for (final m in msgs) {
      buf.writeln('${m.role == "user" ? "Human" : "Assistant"}: ${m.text}');
    }
    buf.writeln('---\nHuman: $newText\nAssistant:');
    return buf.toString();
  }

  void clearChat() {
    chatHistory.clear();
    // Reset conv IDs so new convs are created
    for (final acc in accounts) acc.currentConvId = null;
    notifyListeners();
  }

  // ── Subscription ─────────────────────────────────────────────────────────────

  Future<void> syncSubscription(String url) async {
    isSyncing = true;
    lastError = null;
    notifyListeners();
    try {
      final uris = await fetchSubscription(url);
      final grouped = groupByCountry(uris);
      int total = 0;
      for (final e in grouped.entries) {
        for (final uri in e.value) {
          await store.upsertConfig(uri, e.key);
          total++;
        }
      }
      lastSyncInfo = '$total کانفیگ از ${grouped.length} کشور';
    } catch (e) {
      lastError = e.toString();
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  Future<bool> addManualConfig(String uri) async {
    if (!uri.startsWith('vless://')) return false;
    final country = detectCountry(uri);
    await store.upsertConfig(uri, country);
    notifyListeners();
    return true;
  }

  // ── Health check ──────────────────────────────────────────────────────────────

  Future<void> runHealthCheck() async {
    isCheckingHealth = true;
    aliveCount = 0;
    deadCount = 0;
    notifyListeners();
    final configs = await store.getAllConfigs();
    for (final cfg in configs) {
      final uri = cfg['uri'] as String;
      final result = await _tcpCheck(uri);
      await store.updateConfigHealth(uri, result.$2, result.$1);
      result.$1 ? aliveCount++ : deadCount++;
    }
    isCheckingHealth = false;
    notifyListeners();
  }

  Future<(bool, int)> _tcpCheck(String uri) async {
    try {
      final parsed = Uri.tryParse(uri);
      if (parsed == null) return (false, 9999);
      final host = parsed.host;
      final port = parsed.port > 0 ? parsed.port : 443;
      final start = DateTime.now();
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 5));
      socket.destroy();
      return (true, DateTime.now().difference(start).inMilliseconds);
    } catch (_) {
      return (false, 9999);
    }
  }

  // ── Account management ────────────────────────────────────────────────────────

  Future<void> deleteAccount(String id) async {
    await XrayManager.instance.stop(id);
    await store.deleteAccount(id);
    accounts.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void setMode(PoolMode m) {
    mode = m;
    _exhaustionIndex = 0;
    _rrIndex = 0;
    notifyListeners();
  }

  // ── Status ────────────────────────────────────────────────────────────────────

  int get availableCount => accounts.where((a) => a.isAvailable).length;
  int get totalTokensUsed => accounts.fold(0, (s, a) => s + a.tokensUsed);
}
