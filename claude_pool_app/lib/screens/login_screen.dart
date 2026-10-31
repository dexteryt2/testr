import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:uuid/uuid.dart';
import '../db/session_store.dart';
import '../core/xray_manager.dart';
import '../core/subscription.dart';

const _uuid = Uuid();

class LoginScreen extends StatefulWidget {
  final String accountId;
  final String label;
  final String email;
  final String country;

  const LoginScreen({
    super.key,
    required this.accountId,
    required this.label,
    required this.email,
    required this.country,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  InAppWebViewController? _wvc;
  bool _loading = true;
  bool _loggedIn = false;
  String _status = 'بارگذاری صفحه لاگین...';
  int _progress = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('لاگین — ${widget.label}'),
        actions: [
          if (_loggedIn)
            TextButton.icon(
              onPressed: _extractAndSave,
              icon: const Icon(Icons.check_circle),
              label: const Text('ذخیره'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _wvc?.reload(),
          ),
        ],
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          // Status bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: _loggedIn ? Colors.green.withOpacity(0.1) : cs.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(
                _loggedIn ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: _loggedIn ? Colors.green : cs.outline,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_status,
                  style: TextStyle(fontSize: 12,
                      color: _loggedIn ? Colors.green : cs.outline))),
            ]),
          ),

          // WebView
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri('https://claude.ai/login'),
              ),
              initialSettings: InAppWebViewSettings(
                userAgent:
                    'Mozilla/5.0 (Linux; Android 14; 23117RA66G) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/124.0.0.0 Mobile Safari/537.36',
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                cacheEnabled: true,
                clearCache: false,
                thirdPartyCookiesEnabled: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              ),
              onWebViewCreated: (c) => _wvc = c,
              onProgressChanged: (_, p) => setState(() {
                _progress = p;
                _loading = p < 100;
              }),
              onLoadStop: (_, url) async {
                _loading = false;
                await _checkLoginStatus(url.toString());
              },
              onLoadError: (_, url, code, msg) {
                setState(() {
                  _loading = false;
                  _status = 'خطا: $msg';
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkLoginStatus(String url) async {
    try {
      // Check if we're on claude.ai (not login page anymore)
      final isOnClaude = url.contains('claude.ai') &&
          !url.contains('/login') &&
          !url.contains('accounts.google');

      if (isOnClaude) {
        // Check for session cookie
        final manager = CookieManager.instance();
        final cookies = await manager.getCookies(
            url: WebUri('https://claude.ai'));
        final hasSession = cookies.any((c) =>
            c.name == 'sessionKeyV3LC' || c.name == 'sessionKeyLC');

        if (hasSession) {
          setState(() {
            _loggedIn = true;
            _status = '✓ لاگین موفق! روی "ذخیره" بزن.';
          });
          // Auto-save
          await _extractAndSave();
          return;
        }
      }

      setState(() {
        _status = _loggedIn
            ? '✓ لاگین موفق!'
            : 'با حساب Google وارد شو...';
      });
    } catch (e) {
      setState(() => _status = 'خطا در بررسی: $e');
    }
  }

  Future<void> _extractAndSave() async {
    setState(() => _status = 'در حال استخراج session...');

    try {
      final manager = CookieManager.instance();
      final rawCookies = await manager.getCookies(
          url: WebUri('https://claude.ai'));

      final cookies = <String, String>{
        for (final c in rawCookies) c.name: c.value,
      };

      if (!cookies.containsKey('sessionKeyV3LC') &&
          !cookies.containsKey('sessionKeyLC')) {
        setState(() => _status = '✗ Session cookie پیدا نشد');
        return;
      }

      // Get org_id from JS or cookie
      String orgId = cookies['lastActiveOrg'] ?? '';
      if (orgId.isEmpty) {
        try {
          final js = await _wvc?.evaluateJavascript(
              source: '''
                (function() {
                  try {
                    const key = Object.keys(localStorage)
                      .find(k => k.includes('org') || k.includes('organization'));
                    if (key) return localStorage.getItem(key);
                  } catch(e) {}
                  return '';
                })()
              ''');
          if (js != null && js.toString().isNotEmpty) {
            orgId = js.toString().replaceAll('"', '');
          }
        } catch (_) {}
      }

      // Try bootstrap API to get org_id
      if (orgId.isEmpty) {
        try {
          final js = await _wvc?.evaluateJavascript(source: '''
            (async function() {
              const r = await fetch('/edge-api/bootstrap', {
                headers: {'anthropic-client-platform': 'web_claude_ai'}
              });
              const d = await r.json();
              const m = d?.account?.memberships;
              if (m && m.length > 0) return m[0].organization.uuid;
              return '';
            })()
          ''');
          if (js != null) orgId = js.toString().replaceAll('"', '');
        } catch (_) {}
      }

      // Get or create device_id
      String deviceId = '';
      try {
        final js = await _wvc?.evaluateJavascript(
            source: "localStorage.getItem('anthropic-device-id') || ''");
        deviceId = js?.toString().replaceAll('"', '') ?? '';
      } catch (_) {}
      if (deviceId.isEmpty) deviceId = _uuid.v4();

      // Save to DB
      final store = SessionStore();
      await store.addAccount(widget.accountId, '',
          label: widget.label,
          email: widget.email,
          country: widget.country);
      await store.saveSession(widget.accountId, cookies, orgId, deviceId);

      // Start Xray if we have a proxy config
      await _startProxy();

      setState(() {
        _loggedIn = true;
        _status = '✓ Session ذخیره شد! (org: ${orgId.substring(0, min(8, orgId.length))}...)';
      });

      if (mounted) {
        await Future.delayed(const Duration(seconds: 1));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _status = '✗ خطا: $e');
    }
  }

  Future<void> _startProxy() async {
    try {
      final store = SessionStore();
      final configs = await store.getHealthyConfigs(widget.country);
      if (configs.isEmpty) return;

      final allAccounts = await store.getAllAccounts();
      final idx = allAccounts.indexWhere((a) => a['id'] == widget.accountId);
      final port = 10808 + (idx >= 0 ? idx : 0);

      await XrayManager.instance.start(
        widget.accountId,
        configs.first,
        port: port,
      );
      await store.updateAccountPort(widget.accountId, port);
    } catch (_) {
      // Proxy optional — app works without it too
    }
  }

  int min(int a, int b) => a < b ? a : b;
}
