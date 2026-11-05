import 'dart:convert';

import 'package:bachs_server/bachs_server.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'whsec_test_signing_secret';
  final zeroSignature = List.filled(64, '0').join();
  final invalidSignature = List.filled(64, 'f').join();
  const timestamp = 1792670400; // Deterministic time, not the machine clock.
  final now =
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
  final payload = utf8.encode(jsonEncode({
    'id': 'evt_123',
    'type': 'checkout.completed',
    'data': {'checkout_id': 'chk_123'},
  }));

  String signature(List<int> bytes, [String key = secret]) =>
      Hmac(sha256, utf8.encode(key))
          .convert([...utf8.encode('$timestamp.'), ...bytes]).toString();

  test('accepts valid V2 signature and multiple v1 values during rotation', () {
    final event = BachsWebhooks.constructEvent(
      rawBody: payload,
      headers: {
        'X-Bachs-Signature-V2':
            't=$timestamp,v1=$zeroSignature,v1=${signature(payload)}'
      },
      secret: secret,
      now: now,
    );
    expect(event.id, 'evt_123');
    expect(event.type, 'checkout.completed');
  });

  test('accepts valid legacy signature and timestamp', () {
    final event = BachsWebhooks.constructEvent(
      rawBody: payload,
      headers: {
        'X-Bachs-Timestamp': '$timestamp',
        'X-Bachs-Signature': signature(payload),
      },
      secret: secret,
      now: now,
    );
    expect(event.data['checkout_id'], 'chk_123');
  });

  test('rejects modified raw body', () {
    expect(
        () => BachsWebhooks.constructEvent(
              rawBody: [...payload, 32],
              headers: {
                'X-Bachs-Signature-V2': 't=$timestamp,v1=${signature(payload)}'
              },
              secret: secret,
              now: now,
            ),
        throwsA(isA<BachsWebhookException>()));
  });

  test('rejects stale timestamp', () {
    expect(
        () => BachsWebhooks.constructEvent(
              rawBody: payload,
              headers: {
                'X-Bachs-Signature-V2': 't=$timestamp,v1=${signature(payload)}'
              },
              secret: secret,
              now: now.add(const Duration(minutes: 6)),
            ),
        throwsA(isA<BachsWebhookException>()));
  });

  test('rejects invalid signature', () {
    expect(
        () => BachsWebhooks.constructEvent(
              rawBody: payload,
              headers: {
                'X-Bachs-Signature-V2': 't=$timestamp,v1=$invalidSignature'
              },
              secret: secret,
              now: now,
            ),
        throwsA(isA<BachsWebhookException>()));
  });

  test('rejects malformed JSON after valid HMAC', () {
    final invalid = utf8.encode('{oops');
    expect(
        () => BachsWebhooks.constructEvent(
              rawBody: invalid,
              headers: {
                'X-Bachs-Signature-V2': 't=$timestamp,v1=${signature(invalid)}'
              },
              secret: secret,
              now: now,
            ),
        throwsA(isA<BachsWebhookException>()));
  });
}
