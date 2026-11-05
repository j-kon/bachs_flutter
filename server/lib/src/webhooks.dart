import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Verified Bachs event. Fields not yet known to the SDK are preserved.
class BachsWebhookEvent {
  BachsWebhookEvent._(this.id, this.type, this.data, this.raw);
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final Map<String, dynamic> raw;
}

class BachsWebhookException implements Exception {
  const BachsWebhookException(this.message);
  final String message;
  @override
  String toString() => 'BachsWebhookException: $message';
}

/// Verifies both V2 (recommended) and legacy Bachs signatures.
///
/// The signature is HMAC-SHA256 over UTF8("timestamp.") + raw request bytes.
/// Supports V2 multi-signature rotation, rejects stale timestamps, and uses a
/// constant-time digest comparison. Verify BEFORE parsing JSON or fulfilling.
class BachsWebhooks {
  const BachsWebhooks._();

  static BachsWebhookEvent constructEvent({
    required List<int> rawBody,
    required Map<String, String> headers,
    required String secret,
    Duration tolerance = const Duration(minutes: 5),
    DateTime? now,
  }) {
    if (secret.isEmpty) throw const BachsWebhookException('Missing signing secret');
    final lowercase = <String, String>{
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
    final v2 = lowercase['x-bachs-signature-v2'];
    String? timestamp;
    List<String> signatures;
    if (v2 != null && v2.isNotEmpty) {
      final parts = v2.split(',').map((e) => e.trim()).toList();
      final tValues = parts.where((e) => e.startsWith('t=')).toList();
      if (tValues.length != 1) {
        throw const BachsWebhookException('Invalid signature timestamp');
      }
      timestamp = tValues.single.substring(2);
      signatures = parts.where((e) => e.startsWith('v1='))
          .map((e) => e.substring(3)).toList();
    } else {
      timestamp = lowercase['x-bachs-timestamp'];
      signatures = [if (lowercase['x-bachs-signature'] != null)
        lowercase['x-bachs-signature']!];
    }
    final ts = int.tryParse(timestamp ?? '');
    if (ts == null || ts < 0 || signatures.isEmpty ||
        tolerance.isNegative) {
      throw const BachsWebhookException('Missing or invalid webhook signature');
    }
    final currentSeconds = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    if ((currentSeconds - ts).abs() > tolerance.inSeconds) {
      throw const BachsWebhookException('Webhook timestamp outside tolerance');
    }
    final bytes = [...utf8.encode('$ts.'), ...rawBody];
    final digest = Hmac(sha256, utf8.encode(secret)).convert(bytes).bytes;
    if (!signatures.any((signature) => _constantTimeEqual(digest, signature))) {
      throw const BachsWebhookException('Webhook signature verification failed');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(rawBody));
    } on FormatException {
      throw const BachsWebhookException('Malformed webhook JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['id'] is! String || (decoded['id'] as String).isEmpty ||
        decoded['type'] is! String ||
        decoded['data'] is! Map<String, dynamic>) {
      throw const BachsWebhookException('Invalid webhook event envelope');
    }
    return BachsWebhookEvent._(
      decoded['id'] as String,
      decoded['type'] as String,
      decoded['data'] as Map<String, dynamic>,
      decoded,
    );
  }

  static bool _constantTimeEqual(List<int> expected, String provided) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(provided)) return false;
    // Equal-length digests; ensure comparison doesn't exit on first mismatch.
    final incoming = <int>[];
    for (var i = 0; i < provided.length; i += 2) {
      incoming.add(int.parse(provided.substring(i, i + 2), radix: 16));
    }
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected[i] ^ incoming[i];
    }
    return diff == 0;
  }
}
