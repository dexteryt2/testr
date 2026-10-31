import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const String _base = 'https://claude.ai';
const _uuid = Uuid();
final _rng = Random();

const Map<String, String> _fixedHeaders = {
  'anthropic-client-sha': 'd9cd50cc93',
  'anthropic-client-version': '1.0.0',
  'anthropic-client-build': '1793386237',
  'anthropic-client-platform': 'web_claude_ai',
  'anthropic-client-capabilities': 'streaming_response',
  'x-app-locale': 'en-US',
  'origin': 'https://claude.ai',
  'referer': 'https://claude.ai/',
};

const List<String> _userAgents = [
  'Mozilla/5.0 (Linux; Android 14; 23117RA66G) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
  'Mozilla/5.0 (Linux; Android 13; Redmi Note 13 Pro) AppleWebKit/537.36 Chrome/123.0.0.0 Mobile Safari/537.36',
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/124.0.0.0 Mobile Safari/537.36',
];

class ClaudeResult {
  final bool ok;
  final String? text;
  final String? error;
  final int tokensEst;
  final bool rateLimited;
  final bool sessionExpired;
  final int retryAfter;

  const ClaudeResult._({
    required this.ok, this.text, this.error,
    this.tokensEst = 0, this.rateLimited = false,
    this.sessionExpired = false, this.retryAfter = 60,
  });

  factory ClaudeResult.success(String text) => ClaudeResult._(
      ok: true, text: text, tokensEst: max(1, text.length ~/ 4));
  factory ClaudeResult.failure(String error,
      {bool rateLimited = false, bool sessionExpired = false, int retryAfter = 60}) =>
      ClaudeResult._(ok: false, error: error,
          rateLimited: rateLimited, sessionExpired: sessionExpired, retryAfter: retryAfter);
}

class ClaudeClient {
  final String accountId;
  final Map<String, String> cookies;
  final String orgId;
  final String deviceId;

  ClaudeClient({
    required this.accountId,
    required this.cookies,
    required this.orgId,
    required this.deviceId,
  });

  Map<String, String> _headers() => {
    ..._fixedHeaders,
    'anthropic-device-id': deviceId,
    'user-agent': _userAgents[_rng.nextInt(_userAgents.length)],
    'content-type': 'application/json',
    'accept': 'text/event-stream, application/json',
    'cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
  };

  Future<String?> createConversation() async {
    final url = Uri.parse('$_base/api/organizations/$orgId/chat_conversations');
    try {
      final resp = await http.post(url,
          headers: _headers(),
          body: jsonEncode({'uuid': _uuid.v4(),
            'name': 'conv_${DateTime.now().millisecondsSinceEpoch}'}))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return jsonDecode(resp.body)['uuid'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<ClaudeResult> sendMessage(String convId, String text,
      {String model = 'claude-3-5-sonnet-20241022'}) async {
    final url = Uri.parse(
        '$_base/api/organizations/$orgId/chat_conversations/$convId/completion');
    try {
      final resp = await http.post(url,
          headers: _headers(),
          body: jsonEncode({
            'prompt': text,
            'model': model,
            'timezone': 'Europe/Berlin',
            'attachments': [],
            'files': [],
            'rendering_mode': 'raw',
            'request_raw_response': true,
            'parent_message_uuid': _uuid.v4(),
          })).timeout(const Duration(seconds: 90));

      if (resp.statusCode == 429) {
        final retry = int.tryParse(resp.headers['retry-after'] ?? '') ?? 60;
        return ClaudeResult.failure('rate_limited', rateLimited: true, retryAfter: retry);
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return ClaudeResult.failure('session_expired', sessionExpired: true);
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return ClaudeResult.failure('http_${resp.statusCode}');
      }
      return ClaudeResult.success(_parseSse(resp.body));
    } catch (e) {
      return ClaudeResult.failure(e.toString());
    }
  }

  String _parseSse(String body) {
    final buf = StringBuffer();
    for (final line in body.split('\n')) {
      if (!line.startsWith('data:')) continue;
      final raw = line.substring(5).trim();
      if (raw == '[DONE]' || raw.isEmpty) continue;
      try {
        final chunk = jsonDecode(raw) as Map<String, dynamic>;
        buf.write(chunk['completion'] as String? ??
            (chunk['delta'] as Map?)?.entries
                .where((e) => e.key == 'text')
                .map((e) => e.value as String)
                .firstOrNull ?? '');
      } catch (_) {}
    }
    return buf.toString();
  }

  Future<bool> testSession() async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/edge-api/bootstrap'), headers: _headers())
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
