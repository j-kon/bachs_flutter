import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'checkout_models.dart';

enum BachsEnvironment { sandbox, production }

class BachsApiException implements Exception {
  const BachsApiException(
      {required this.statusCode, this.code, this.detail, this.retryAfter});
  final int statusCode;
  final String? code;
  final String? detail;
  final Duration? retryAfter;

  @override
  String toString() =>
      'BachsApiException(statusCode: $statusCode, code: $code, detail: $detail)';
}

/// Server-side client. Never instantiate with a secret from a Flutter app.
///
/// Uses environment-specific Bachs hosts, validates key prefixes, injects an
/// HTTP client for testing, and never automatically retries writes.
class BachsClient {
  BachsClient({
    required String apiKey,
    this.environment = BachsEnvironment.sandbox,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  })  : _apiKey = apiKey,
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _baseUrl = Uri.parse(environment == BachsEnvironment.sandbox
            ? 'https://sandbox-api.bachs.io'
            : 'https://api.bachs.io') {
    final expectedPrefix =
        environment == BachsEnvironment.sandbox ? 'sk_sandbox_' : 'sk_live_';
    if (!apiKey.startsWith(expectedPrefix) ||
        apiKey.length <= expectedPrefix.length) {
      throw ArgumentError('API key does not match the configured environment');
    }
  }

  final String _apiKey;
  final Uri _baseUrl;
  final http.Client _httpClient;
  final bool _ownsClient;
  final BachsEnvironment environment;
  final Duration timeout;

  /// Close only the client created by this instance. Injected clients are
  /// owned by their callers and remain open.
  void close() {
    if (_ownsClient) _httpClient.close();
  }

  Future<CreatedCheckout> createCheckout(CreateCheckoutRequest request,
      {required String idempotencyKey}) async {
    final json = await _request('POST', '/v1/checkout-sessions',
        body: request.toJson(), idempotencyKey: idempotencyKey);
    return CreatedCheckout.fromJson(json);
  }

  Future<RetrievedCheckout> retrieveCheckout(String checkoutId) async =>
      RetrievedCheckout.fromJson(await _request('GET',
          '/v1/checkout-sessions/${Uri.encodeComponent(_safeId(checkoutId))}'));

  /// Convenience endpoints. These return full provider JSON because fields
  /// evolve across Bachs releases. Use only from trusted server code.
  Future<Map<String, dynamic>> listProducts({int? limit}) =>
      _request('GET', '/v1/products',
          query: {if (limit != null) 'limit': '$limit'});

  Future<Map<String, dynamic>> retrieveProduct(String productId) => _request(
      'GET', '/v1/products/${Uri.encodeComponent(_safeId(productId))}');

  Future<Map<String, dynamic>> listPayments({int? limit}) =>
      _request('GET', '/v1/payments',
          query: {if (limit != null) 'limit': '$limit'});

  Future<Map<String, dynamic>> retrievePayment(String paymentId) => _request(
      'GET', '/v1/payments/${Uri.encodeComponent(_safeId(paymentId))}');

  static String _safeId(String value) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains('?') ||
        value.contains('#')) {
      throw ArgumentError('Invalid resource identifier');
    }
    return value;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> query = const {},
    String? idempotencyKey,
  }) async {
    if (idempotencyKey != null && method != 'POST' && method != 'PATCH') {
      throw ArgumentError('Idempotency keys are only valid for POST/PATCH');
    }
    if (idempotencyKey != null &&
        (idempotencyKey.isEmpty ||
            idempotencyKey.contains('\n') ||
            idempotencyKey.contains('\r'))) {
      throw ArgumentError('Invalid idempotency key');
    }
    final uri = _baseUrl.replace(
      path: '${_baseUrl.path.replaceAll(RegExp(r'/$'), '')}$path',
      queryParameters: query.isEmpty ? null : query,
    );
    final req = http.Request(method, uri);
    req.headers.addAll({
      'Authorization': 'Bearer $_apiKey',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    });
    if (body != null) req.body = jsonEncode(body);
    http.StreamedResponse streamed;
    String content;
    try {
      streamed = await _httpClient.send(req).timeout(timeout);
      content = await streamed.stream.bytesToString().timeout(timeout);
    } on TimeoutException {
      // Outcome of POST could be uncertain: caller must reconcile and reuse key.
      throw const BachsApiException(
          statusCode: 0,
          code: 'TIMEOUT',
          detail: 'Request timed out; operation outcome may be unknown');
    } on http.ClientException {
      throw const BachsApiException(
          statusCode: 0,
          code: 'NETWORK_ERROR',
          detail: 'Network failure; operation outcome may be unknown');
    }
    dynamic decoded;
    try {
      decoded = content.isEmpty ? <String, dynamic>{} : jsonDecode(content);
    } on FormatException {
      throw BachsApiException(
          statusCode: streamed.statusCode,
          code: 'INVALID_RESPONSE',
          detail: 'Non-JSON response from Bachs');
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final error =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      final retryAfter = int.tryParse(streamed.headers['retry-after'] ?? '');
      throw BachsApiException(
        statusCode: streamed.statusCode,
        code: error['error_code'] is String
            ? error['error_code'] as String
            : null,
        detail: error['detail'] is String
            ? error['detail'] as String
            : 'Bachs request failed',
        retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw BachsApiException(
          statusCode: streamed.statusCode,
          code: 'INVALID_RESPONSE',
          detail: 'Expected a JSON object');
    }
    return decoded;
  }
}
