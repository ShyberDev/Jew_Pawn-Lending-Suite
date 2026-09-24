import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Talks to a Frappe server. Authentication uses the `sid` session cookie
/// obtained from `/api/method/login` (the same login the desk uses).
class ApiClient {
  String baseUrl;
  String? sid;

  ApiClient({required this.baseUrl, this.sid});

  Uri _u(String path) {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    if (sid != null && sid!.isNotEmpty) h['Cookie'] = 'sid=$sid';
    return h;
  }

  static String _errorMessage(http.Response resp) {
    try {
      final body = jsonDecode(resp.body);
      if (body is Map) {
        if (body['exception'] != null) {
          return body['exception'].toString();
        }
        final raw = body['_server_messages'];
        if (raw != null) {
          final list = raw is String ? jsonDecode(raw) : raw;
          if (list is List && list.isNotEmpty) {
            final first = list.first;
            final parsed = first is String ? jsonDecode(first) : first;
            if (parsed is Map && parsed['message'] != null) {
              return parsed['message'].toString();
            }
            return first.toString();
          }
        }
        if (body['message'] != null) return body['message'].toString();
      }
    } catch (_) {/* fall through */}
    return 'HTTP ${resp.statusCode}';
  }

  void _captureSid(http.Response resp) {
    final raw = resp.headers['set-cookie'];
    if (raw == null) return;
    final match = RegExp(r'sid=([^;,\s]+)').firstMatch(raw);
    if (match != null) sid = match.group(1);
  }

  Future<Map<String, dynamic>> login(String usr, String pwd) async {
    final resp = await http.post(_u('/api/method/login'),
        headers: _headers(), body: {'usr': usr, 'pwd': pwd});
    if (resp.statusCode != 200) {
      throw ApiException(_errorMessage(resp), statusCode: resp.statusCode);
    }
    _captureSid(resp);
    return (jsonDecode(resp.body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> syncCall(
      String method, Map<String, dynamic> args) async {
    final resp = await http.post(
      _u('/api/method/pawn_shop.api.sync.$method'),
      headers: _headers(json: true),
      body: jsonEncode(args),
    );
    if (resp.statusCode != 200) {
      throw ApiException(_errorMessage(resp), statusCode: resp.statusCode);
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['message'] is Map) {
      return (decoded['message'] as Map).cast<String, dynamic>();
    }
    return (decoded as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> registerDevice(String name,
          {String platform = 'android'}) =>
      syncCall('register_device', {'device_name': name, 'platform': platform});

  Future<Map<String, dynamic>> pull(
          {String? since, List<String>? doctypes, int limit = 200}) =>
      syncCall('pull', {
        'since': since,
        'doctypes': doctypes,
        'limit': limit,
      });

  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> mutations,
          {String? device}) =>
      syncCall('push', {'mutations': mutations, 'device': device});

  Future<Map<String, dynamic>> status({String? device}) =>
      syncCall('status', {'device': device});

  /// Upload a photo and attach it to [doctype]/[docname].
  Future<void> uploadFile({
    required String filePath,
    required String filename,
    String? doctype,
    String? docname,
  }) async {
    final req = http.MultipartRequest('POST', _u('/api/method/upload_file'));
    req.headers.addAll(_headers());
    req.files.add(await http.MultipartFile.fromPath('file', filePath,
        filename: filename));
    if (doctype != null) req.fields['doctype'] = doctype;
    if (docname != null) req.fields['docname'] = docname;
    req.fields['is_private'] = '1';
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw ApiException(_errorMessage(resp), statusCode: resp.statusCode);
    }
  }
}
