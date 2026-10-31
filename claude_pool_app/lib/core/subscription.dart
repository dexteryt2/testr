import 'dart:convert';
import 'package:http/http.dart' as http;

const Map<String, List<String>> kCountryHints = {
  'DE': ['de','germany','deutsch','frankfurt','berlin','munich'],
  'NL': ['nl','netherlands','amsterdam'],
  'FR': ['fr','france','paris'],
  'AT': ['at','austria','wien','vienna'],
  'CH': ['ch','swiss','switzerland','zurich'],
  'BE': ['be','belgium','brussels'],
  'SE': ['se','sweden','stockholm'],
  'GB': ['gb','uk','england','london'],
  'US': ['us','usa','america','new-york','los-angeles'],
  'CA': ['ca','canada','toronto'],
  'JP': ['jp','japan','tokyo'],
  'SG': ['sg','singapore'],
  'HK': ['hk','hong-kong','hongkong'],
  'KR': ['kr','korea','seoul'],
};

const Map<String, List<String>> kFallbackRing = {
  'DE': ['AT','CH','NL','BE','FR','SE'],
  'NL': ['BE','DE','FR','GB'],
  'FR': ['BE','CH','DE','NL'],
  'AT': ['DE','CH'],
  'CH': ['AT','DE','FR'],
  'GB': ['NL','DE'],
  'US': ['CA'],
  'CA': ['US'],
  'JP': ['KR','SG','HK'],
  'SG': ['HK','JP'],
  'HK': ['SG','JP'],
};

String detectCountry(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return 'UNKNOWN';
  final remark = Uri.decodeComponent(parsed.fragment).toLowerCase();
  final host = (parsed.host).toLowerCase();
  final text = '$remark $host';
  for (final e in kCountryHints.entries) {
    for (final h in e.value) {
      if (text.contains(h)) return e.key;
    }
  }
  return 'UNKNOWN';
}

List<String> getFallbackChain(String country) =>
    [country, ...kFallbackRing[country] ?? []];

Future<List<String>> fetchSubscription(String url) async {
  final resp = await http.get(Uri.parse(url),
      headers: {'User-Agent': 'v2rayNG/1.8.20'})
      .timeout(const Duration(seconds: 15));
  if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
  final content = resp.body.trim();
  List<String> lines;
  try {
    final decoded = utf8.decode(base64.decode(base64.normalize(content)));
    lines = decoded.split('\n');
  } catch (_) {
    lines = content.split('\n');
  }
  return lines
      .map((l) => l.trim())
      .where((l) => l.startsWith('vless://'))
      .toList();
}

Map<String, List<String>> groupByCountry(List<String> uris) {
  final result = <String, List<String>>{};
  for (final uri in uris) {
    final c = detectCountry(uri);
    result.putIfAbsent(c, () => []).add(uri);
  }
  return result;
}
