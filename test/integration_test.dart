import 'dart:convert';

import 'package:bachs_flutter/bachs_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final openSession = BachsCheckoutSession.fromJson({
    'checkout_id': 'chk_t',
    'checkout_url': 'https://checkout.bachs.io/c/test',
    'status': 'open',
  });

  test('two merchants use independent providers and different orders', () async {
    final orders = <String>[];
    final first = BachsFlutter(
      createSession: (r) async { orders.add('A:${r.orderId}'); return openSession; },
      checkout: BachsCheckout(launcher: (_) async => true),
    );
    final second = BachsFlutter(
      createSession: (r) async { orders.add('B:${r.orderId}'); return openSession; },
      checkout: BachsCheckout(launcher: (_) async => true),
    );
    await first.startCheckout(BachsCheckoutRequest(orderId: 'order_a'));
    await second.startCheckout(BachsCheckoutRequest(orderId: 'order_b'));
    expect(orders, ['A:order_a', 'B:order_b']);
  });

  test('developer order context is dynamic, and only order id required', () {
    final request = BachsCheckoutRequest(orderId: 'abc', context: {'sku': 'pro'});
    expect(request.toJson(), {'order_id': 'abc', 'context': {'sku': 'pro'}});
    expect(() => BachsCheckoutRequest(orderId: ''), throwsArgumentError);
  });

  test('return redirect cannot be mistaken for a verified payment', () async {
    final sdk = BachsFlutter(
      createSession: (_) async => openSession,
      returnUrlMatcher: BachsReturnUrlMatcher(
        successUrl: Uri.parse('https://merchant.example/thanks'),
        cancelUrl: Uri.parse('https://merchant.example/cancel')),
    );
    final result = sdk.handleReturn(Uri.parse(
        'https://merchant.example/thanks?checkout_id=chk_t'));
    expect(result.kind, BachsReturnKind.successRedirect);
    expect(result.checkoutId, 'chk_t');
    await expectLater(sdk.checkPayment(orderId: 'a', checkoutId: 'chk_t'),
        throwsA(isA<BachsSdkException>()));
  });

  test('rejects mismatched merchant verified status', () async {
    final sdk = BachsFlutter(
      createSession: (_) async => openSession,
      verifyStatus: (_, __) async => const BachsPaymentStatus(
        orderId: 'another', checkoutId: 'chk_t', state: BachsPaymentState.paid),
    );
    await expectLater(sdk.checkPayment(orderId: 'expected', checkoutId: 'chk_t'),
        throwsA(isA<BachsSdkException>()));
  });

  test('backend adapter injects merchant auth and serializes dynamic context', () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response(jsonEncode({
        'checkout_id': 'chk_t',
        'checkout_url': 'https://checkout.bachs.io/c/test',
        'status': 'open',
      }), 201);
    });
    final backend = BachsBackendAdapter(
      baseUrl: Uri.parse('https://merchant.example/api'),
      httpClient: client,
      tokenProvider: () async => 'user-session-token',
    );
    final session = await backend.createSession(BachsCheckoutRequest(
      orderId: 'order_123', context: {'sku': 'starter'}));
    expect(captured.url.toString(), 'https://merchant.example/api/checkout');
    expect(captured.headers['Authorization'], 'Bearer user-session-token');
    expect(jsonDecode(captured.body)['context']['sku'], 'starter');
    expect(session.id, 'chk_t');
    backend.close();
  });

  test('backend adapter rejects non-loopback HTTP and does not accept API keys', () {
    expect(() => BachsBackendAdapter(baseUrl: Uri.parse('http://merchant.example')),
        throwsArgumentError);
    expect(() => BachsBackendAdapter(
      baseUrl: Uri.parse('http://127.0.0.1:8080')),
        throwsArgumentError);
    final backend = BachsBackendAdapter(
      baseUrl: Uri.parse('http://127.0.0.1:8080'),
      allowInsecureLoopback: true);
    backend.close();
  });

  test('backend adapter rejects checkout id mismatch on status query', () async {
    final backend = BachsBackendAdapter(
      baseUrl: Uri.parse('https://merchant.example'),
      httpClient: MockClient((_) async => http.Response(jsonEncode({
        'order_id': 'order_A', 'checkout_id': 'chk_DIFFERENT', 'status': 'paid'
      }), 200)),
    );
    await expectLater(backend.checkStatus('order_A', 'chk_EXPECTED'),
        throwsA(isA<BachsSdkException>()));
    backend.close();
  });

  test('status response parses paid and rejects unknown values', () {
    final paid = BachsPaymentStatus.fromJson({
      'order_id': 'a', 'checkout_id': 'c', 'status': 'paid',
    });
    expect(paid.isPaid, isTrue);
    expect(() => BachsPaymentStatus.fromJson({
      'order_id': 'a', 'checkout_id': 'c', 'status': 'redirected',
    }), throwsFormatException);
  });
}
