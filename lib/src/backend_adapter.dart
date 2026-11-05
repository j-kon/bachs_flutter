import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'checkout_session.dart';
import 'models.dart';
import 'mobile_security.dart';

/// An optional HTTP adapter for merchants that expose the documented contract.
///
/// Existing backends may ignore this and pass their own closures directly to
/// BachsFlutter(createSession: ..., verifyStatus: ...). No Bachs secret is ever
/// accepted by this class.
typedef MerchantTokenProvider = Future<String?> Function();

class BachsBackendAdapter {
  BachsBackendAdapter({
    required Uri baseUrl,
    this.createPath = '/checkout',
    this.statusPath = '/checkout-status',
    this.tokenProvider,
    this.timeout = const Duration(seconds: 20),
    this.allowInsecureLoopback = false,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl,
        _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null {
    rejectMobileSecrets(baseUrl.toString());
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive');
    }
    if (!_isSafeBaseUrl(baseUrl, allowInsecureLoopback)) {
      throw ArgumentError(
          'Backend URL must be HTTPS (or opt-in loopback HTTP)');
    }
    for (final path in [createPath, statusPath]) {
      if (!path.startsWith('/') ||
          path.startsWith('//') ||
          path.contains('?') ||
          path.contains('#')) {
        throw ArgumentError.value(path, 'path', 'Use an absolute path only');
      }
    }
  }

  final Uri _baseUrl;
  final String createPath;
  final String statusPath;
  final MerchantTokenProvider? tokenProvider;
  final Duration timeout;
  final bool allowInsecureLoopback;
  final http.Client _client;
  final bool _ownsClient;

  static bool _isSafeBaseUrl(Uri uri, bool allowLoopback) {
    if (uri.userInfo.isNotEmpty ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    if (uri.scheme == 'https') return true;
    if (!allowLoopback || uri.scheme != 'http') return false;
    return uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1' ||
        uri.host == '10.0.2.2';
  }

  Uri _endpoint(String path, [Map<String, String>? query]) {
    final prefix = _baseUrl.path.replaceFirst(RegExp(r'/$'), '');
    return _baseUrl.replace(path: '$prefix$path', queryParameters: query);
  }

  Future<Map<String, String>> _headers() async {
    final token = await tokenProvider?.call();
    try {
      rejectMobileSecrets(token);
    } on ArgumentError {
      throw const BachsSdkException(
          'Bachs secrets cannot be used as merchant user tokens',
          code: 'INVALID_CONFIG');
    }
    if (token != null && (token.contains('\r') || token.contains('\n'))) {
      throw const BachsSdkException('Invalid merchant auth token');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _decode(Future<http.Response> operation) async {
    http.Response response;
    try {
      response = await operation.timeout(timeout);
    } on TimeoutException {
      throw const BachsSdkException('Merchant backend timed out',
          code: 'TIMEOUT');
    } on http.ClientException {
      throw const BachsSdkException('Merchant backend unavailable',
          code: 'NETWORK');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw BachsSdkException('Merchant backend returned invalid JSON',
          statusCode: response.statusCode, code: 'INVALID_RESPONSE');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map ? decoded : const {};
      // Avoid echoing potentially sensitive backend detail messages.
      throw BachsSdkException('Merchant checkout request failed',
          statusCode: response.statusCode,
          code: error['code'] is String ? error['code'] as String : null);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BachsSdkException(
          'Merchant backend must return a JSON object',
          code: 'INVALID_RESPONSE');
    }
    return decoded;
  }

  Future<BachsCheckoutSession> createSession(
      BachsCheckoutRequest request) async {
    final body = jsonEncode(request.toJson());
    try {
      rejectMobileSecrets(body);
    } on ArgumentError {
      throw const BachsSdkException('Bachs secrets cannot be sent from Flutter',
          code: 'INVALID_REQUEST');
    }
    final headers = await _headers();
    final json = await _decode(
        _send('POST', _endpoint(createPath), headers, body: body));
    try {
      return BachsCheckoutSession.fromJson(json);
    } on FormatException {
      throw const BachsSdkException('Invalid checkout session response',
          code: 'INVALID_RESPONSE');
    }
  }

  Future<BachsPaymentStatus> checkStatus(
      String orderId, String checkoutId) async {
    final headers = await _headers();
    final json = await _decode(_send(
        'GET',
        _endpoint(statusPath, {'order_id': orderId, 'checkout_id': checkoutId}),
        headers));
    late BachsPaymentStatus result;
    try {
      result = BachsPaymentStatus.fromJson(json);
    } on FormatException {
      throw const BachsSdkException('Invalid payment status response',
          code: 'INVALID_RESPONSE');
    }
    if (result.orderId != orderId || result.checkoutId != checkoutId) {
      throw const BachsSdkException('Backend returned mismatched order status');
    }
    return result;
  }

  Future<http.Response> _send(
      String method, Uri uri, Map<String, String> headers,
      {String? body}) async {
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll(headers);
    if (body != null) request.body = body;
    return http.Response.fromStream(await _client.send(request));
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
