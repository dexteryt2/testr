import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class SessionStore {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'claude_pool.db');
    return openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE proxy_configs (
          uri       TEXT PRIMARY KEY,
          country   TEXT NOT NULL,
          ping_ms   INTEGER DEFAULT 9999,
          alive     INTEGER DEFAULT 1,
          last_check TEXT
        )''');
      await db.execute('''
        CREATE TABLE accounts (
          id            TEXT PRIMARY KEY,
          label         TEXT,
          google_email  TEXT,
          country       TEXT DEFAULT 'DE',
          proxy_port    INTEGER,
          created_at    TEXT DEFAULT CURRENT_TIMESTAMP
        )''');
      await db.execute('''
        CREATE TABLE proxy_bindings (
          account_id  TEXT PRIMARY KEY,
          config_uri  TEXT NOT NULL,
          country     TEXT NOT NULL,
          bound_at    TEXT DEFAULT CURRENT_TIMESTAMP,
          last_used   TEXT
        )''');
      await db.execute('''
        CREATE TABLE claude_sessions (
          account_id      TEXT PRIMARY KEY,
          cookies_json    TEXT NOT NULL,
          org_id          TEXT,
          device_id       TEXT,
          tokens_used     INTEGER DEFAULT 0,
          requests_count  INTEGER DEFAULT 0,
          rate_limited_until TEXT,
          last_active     TEXT,
          valid           INTEGER DEFAULT 1
        )''');
    });
  }

  // ── Proxy configs ──────────────────────────────────────────────────────────

  Future<void> upsertConfig(String uri, String country) async {
    final d = await db;
    await d.insert('proxy_configs', {'uri': uri, 'country': country},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateConfigHealth(String uri, int pingMs, bool alive) async {
    final d = await db;
    await d.update('proxy_configs',
        {'ping_ms': pingMs, 'alive': alive ? 1 : 0, 'last_check': DateTime.now().toIso8601String()},
        where: 'uri = ?', whereArgs: [uri]);
  }

  Future<List<Map<String, dynamic>>> getAllConfigs() async {
    final d = await db;
    return d.query('proxy_configs', orderBy: 'ping_ms ASC');
  }

  Future<List<String>> getHealthyConfigs(String country, {int maxPing = 600}) async {
    final d = await db;
    final rows = await d.query('proxy_configs',
        columns: ['uri'],
        where: 'country = ? AND alive = 1 AND ping_ms <= ?',
        whereArgs: [country, maxPing],
        orderBy: 'ping_ms ASC');
    return rows.map((r) => r['uri'] as String).toList();
  }

  Future<Map<String, int>> getConfigCountByCountry() async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT country, COUNT(*) as cnt FROM proxy_configs GROUP BY country');
    return {for (var r in rows) r['country'] as String: r['cnt'] as int};
  }

  // ── Accounts ───────────────────────────────────────────────────────────────

  Future<void> addAccount(String id, String apiKey,
      {String label = '', String country = 'DE', String email = ''}) async {
    final d = await db;
    await d.insert('accounts',
        {'id': id, 'label': label, 'google_email': email, 'country': country},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateAccountPort(String id, int port) async {
    final d = await db;
    await d.update('accounts', {'proxy_port': port},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAccount(String id) async {
    final d = await db;
    await d.delete('accounts', where: 'id = ?', whereArgs: [id]);
    await d.delete('claude_sessions', where: 'account_id = ?', whereArgs: [id]);
    await d.delete('proxy_bindings', where: 'account_id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    final d = await db;
    return d.query('accounts', orderBy: 'created_at ASC');
  }

  Future<Map<String, dynamic>?> getAccount(String id) async {
    final d = await db;
    final rows = await d.query('accounts', where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  // ── Proxy bindings ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getBinding(String accountId) async {
    final d = await db;
    final rows = await d.query('proxy_bindings',
        where: 'account_id = ?', whereArgs: [accountId]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> bind(String accountId, String configUri, String country) async {
    final d = await db;
    await d.insert('proxy_bindings',
        {'account_id': accountId, 'config_uri': configUri, 'country': country,
         'bound_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> touchBinding(String accountId) async {
    final d = await db;
    await d.update('proxy_bindings',
        {'last_used': DateTime.now().toIso8601String()},
        where: 'account_id = ?', whereArgs: [accountId]);
  }

  // ── Claude sessions ────────────────────────────────────────────────────────

  Future<void> saveSession(String accountId, Map<String, String> cookies,
      String orgId, String deviceId) async {
    final d = await db;
    await d.insert('claude_sessions', {
      'account_id': accountId,
      'cookies_json': jsonEncode(cookies),
      'org_id': orgId,
      'device_id': deviceId,
      'valid': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getSession(String accountId) async {
    final d = await db;
    final rows = await d.query('claude_sessions',
        where: 'account_id = ? AND valid = 1', whereArgs: [accountId]);
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first);
    row['cookies'] = Map<String, String>.from(
        jsonDecode(row['cookies_json'] as String));
    return row;
  }

  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT cs.*, a.label, a.google_email, a.country, a.proxy_port
      FROM claude_sessions cs
      JOIN accounts a ON a.id = cs.account_id
      WHERE cs.valid = 1
      ORDER BY cs.tokens_used ASC
    ''');
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['cookies'] = Map<String, String>.from(
          jsonDecode(m['cookies_json'] as String));
      return m;
    }).toList();
  }

  Future<void> recordUsage(String accountId, int tokens) async {
    final d = await db;
    await d.rawUpdate('''
      UPDATE claude_sessions
      SET tokens_used = tokens_used + ?,
          requests_count = requests_count + 1,
          last_active = ?
      WHERE account_id = ?
    ''', [tokens, DateTime.now().toIso8601String(), accountId]);
  }

  Future<void> invalidateSession(String accountId) async {
    final d = await db;
    await d.update('claude_sessions', {'valid': 0},
        where: 'account_id = ?', whereArgs: [accountId]);
  }

  Future<void> markRateLimited(String accountId, String until) async {
    final d = await db;
    await d.update('claude_sessions', {'rate_limited_until': until},
        where: 'account_id = ?', whereArgs: [accountId]);
  }
}
