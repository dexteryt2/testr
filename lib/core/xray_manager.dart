import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class XrayManager {
  static final XrayManager instance = XrayManager._();
  XrayManager._();

  final Map<String, Process> _procs = {};
  final Map<String, int> _ports = {};
  String? _xrayPath;
  static const int _basePort = 10808;

  Future<String> get xrayPath async {
    if (_xrayPath != null) return _xrayPath!;
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/xray';
    _xrayPath = path;
    final file = File(path);
    if (!await file.exists()) {
      final data = await rootBundle.load('assets/xray-arm64-v8a');
      await file.writeAsBytes(data.buffer.asUint8List());
      await Process.run('chmod', ['+x', path]);
    }
    return path;
  }

  Map<String, dynamic> _buildConfig(String vlessUri, int port) {
    final parsed = Uri.parse(vlessUri);
    final params = Uri.splitQueryString(parsed.query);
    String p(String k, [String d = '']) => params[k] ?? d;

    final network = p('type', 'tcp');
    final security = p('security', 'none');
    final stream = <String, dynamic>{'network': network, 'security': security};

    if (security == 'tls') {
      stream['tlsSettings'] = {
        'serverName': p('sni', parsed.host),
        'allowInsecure': false,
        'fingerprint': p('fp', 'chrome'),
      };
    } else if (security == 'reality') {
      stream['realitySettings'] = {
        'serverName': p('sni', parsed.host),
        'fingerprint': p('fp', 'chrome'),
        'publicKey': p('pbk'),
        'shortId': p('sid'),
      };
    }
    if (network == 'ws') {
      stream['wsSettings'] = {
        'path': p('path', '/'),
        'headers': {'Host': p('host', parsed.host)},
      };
    } else if (network == 'grpc') {
      stream['grpcSettings'] = {'serviceName': p('serviceName'), 'multiMode': false};
    }

    final user = <String, dynamic>{
      'id': parsed.userInfo,
      'encryption': 'none',
    };
    final flow = p('flow');
    if (flow.isNotEmpty) user['flow'] = flow;

    return {
      'log': {'loglevel': 'warning'},
      'inbounds': [{
        'tag': 'socks',
        'port': port,
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': true},
        'sniffing': {'enabled': true, 'destOverride': ['http', 'tls']},
      }],
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {'vnext': [{'address': parsed.host,
            'port': parsed.port > 0 ? parsed.port : 443,
            'users': [user]}]},
          'streamSettings': stream,
          'mux': {'enabled': false},
        },
        {'protocol': 'freedom', 'tag': 'direct'},
        {'protocol': 'blackhole', 'tag': 'block',
         'settings': {'response': {'type': 'http'}}},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [{'outboundTag': 'block', 'port': '443', 'network': 'udp'}],
      },
      'dns': {'servers': ['1.1.1.1', '8.8.8.8']},
    };
  }

  Future<int> start(String accountId, String vlessUri, {int? port}) async {
    await stop(accountId);
    final p = port ?? (_basePort + _procs.length);
    final xray = await xrayPath;
    final dir = await getApplicationSupportDirectory();
    final cfgFile = File('${dir.path}/xray_$accountId.json');
    await cfgFile.writeAsString(jsonEncode(_buildConfig(vlessUri, p)));

    final proc = await Process.start(xray, ['run', '-c', cfgFile.path]);
    _procs[accountId] = proc;
    _ports[accountId] = p;
    await Future.delayed(const Duration(milliseconds: 800));
    return p;
  }

  Future<void> stop(String accountId) async {
    _procs[accountId]?.kill();
    _procs.remove(accountId);
    _ports.remove(accountId);
  }

  Future<void> stopAll() async {
    for (final id in List.from(_procs.keys)) await stop(id);
  }

  int? port(String accountId) => _ports[accountId];
  bool isRunning(String accountId) =>
      _procs[accountId]?.exitCode == null;
}
