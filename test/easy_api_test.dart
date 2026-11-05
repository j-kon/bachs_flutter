import 'dart:async';
import 'dart:convert';

import 'package:bachs_flutter/bachs_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final session = {
    'checkout_id': 'chk_test',
    'checkout_url': 'https://sandbox-checkout.bachs.io/c/test',
    'status': 'open',
  };
  BachsFlutter configured(MockClient client, {Duration? timeout}) =>
      BachsFlutter(
        config: BachsConfig(
          checkoutEndpoint: 'https://merchant.example/payments/checkout',
          tokenProvider: () async => 'user-session',
          timeout: timeout ?? const Duration(seconds: 20),
        ),
        httpClient: client,
        checkout: BachsCheckout(launcher: (_) async => true),
      );

  test('configuration rejects unsafe endpoints and ambiguous initialization',
      () {
    for (final endpoint in [
      'http://merchant.example/checkout',
      'https://user:pass@merchant.example/checkout',
      'https://merchant.example/checkout?key=sk_live_example',
      'sk_sandbox_example',
    ]) {
      expect(
          () => BachsConfig(checkoutEndpoint: endpoint), throwsArgumentError);
    }
    expect(() => BachsFlutter(), throwsArgumentError);
    expect(
        () => BachsConfig(
            checkoutEndpoint: 'https://m.example/checkout',
            statusEndpoint: 'https://other.example/status'),
        throwsArgumentError);
    expect(
        () => BachsConfig(
            checkoutEndpoint: 'https://m.example/checkout',
            timeout: Duration.zero),
        throwsArgumentError);
  });

  test('pay creates, launches sandbox checkout and checks trusted status',
      () async {
    final calls = <http.Request>[];
    final sdk = configured(MockClient((request) async {
      calls.add(request);
      expect(request.headers['Authorization'], 'Bearer user-session');
      return http.Response(
          jsonEncode(request.method == 'POST'
              ? session
              : {
                  'order_id': 'order_1',
                  'checkout_id': 'chk_test',
                  'status': 'pending',
                }),
          200);
    }));
    final result = await sdk.pay(BachsPaymentRequest(
        orderId: 'order_1', productId: 'book', quantity: 2));
    expect(calls[0].url.path, '/payments/checkout');
    expect(jsonDecode(calls[0].body)['context'],
        {'product_id': 'book', 'quantity': 2});
    expect(calls[1].url.path, '/payments/checkout-status');
    expect(result.isPaid, false);
    expect(result.status!.state, BachsPaymentState.pending);
    sdk.close();
  });

  test('hosted-only mode opens checkout but cannot verify payment', () async {
    var opened = false;
    final sdk =
        BachsFlutter.hosted(checkout: BachsCheckout(launcher: (_) async {
      opened = true;
      return true;
    }));
    await sdk.openCheckoutUrl(Uri.parse('https://checkout.bachs.io/c/test'));
    expect(opened, true);
    await expectLater(sdk.pay(BachsPaymentRequest(orderId: 'x')),
        throwsA(isA<BachsSdkException>()));
  });

  test('rejects secrets as user tokens before any network call', () async {
    for (final token in [
      'sk_live_fixture',
      'sk_sandbox_fixture',
      'whsec_fixture'
    ]) {
      final sdk = BachsFlutter(
        config: BachsConfig(
            checkoutEndpoint: 'https://m.example/checkout',
            tokenProvider: () async => token),
        httpClient: MockClient((_) async => fail('Must not send secret')),
      );
      await expectLater(sdk.pay(BachsPaymentRequest(orderId: 'x')),
          throwsA(isA<BachsSdkException>()));
      sdk.close();
    }
  });

  test('malformed session is a typed SDK failure', () async {
    final sdk = configured(MockClient((_) async => http.Response('{}', 200)));
    await expectLater(
        sdk.pay(BachsPaymentRequest(orderId: 'x')),
        throwsA(isA<BachsSdkException>()
            .having((e) => e.code, 'code', 'INVALID_RESPONSE')));
  });

  test('network timeouts are typed and never automatically retry writes',
      () async {
    var calls = 0;
    final sdk = configured(MockClient((_) {
      calls++;
      return Completer<http.Response>().future;
    }), timeout: const Duration(milliseconds: 1));
    await expectLater(
        sdk.pay(BachsPaymentRequest(orderId: 'x')),
        throwsA(
            isA<BachsSdkException>().having((e) => e.code, 'code', 'TIMEOUT')));
    expect(calls, 1);
  });

  test('status failure retains launched session for later verification',
      () async {
    var healthy = false;
    final sdk = configured(MockClient((r) async => http.Response(
        jsonEncode(r.method == 'POST'
            ? session
            : healthy
                ? {
                    'order_id': 'x',
                    'checkout_id': 'chk_test',
                    'status': 'paid',
                  }
                : {'code': 'UNAVAILABLE'}),
        r.method == 'POST' || healthy ? 200 : 503)));
    final result = await sdk.pay(BachsPaymentRequest(orderId: 'x'));
    expect(result.status, isNull);
    expect(result.verificationError, isA<BachsSdkException>());
    healthy = true;
    expect((await sdk.verifyPayment(result)).isPaid, true);
  });

  test('quantity is validated and secrets cannot travel in request context',
      () {
    expect(() => BachsPaymentRequest(orderId: 'x', quantity: 0),
        throwsArgumentError);
    expect(() => BachsPaymentRequest(orderId: 'x', productId: ''),
        throwsArgumentError);
    expect(
        () => BachsCheckoutRequest(orderId: 'x', context: {
              'nested': ['sk_sandbox_fixture'],
            }),
        throwsArgumentError);
  });
  test('mutated nested request secrets are rejected before transport',
      () async {
    final nested = <String, dynamic>{'value': 'safe'};
    final request =
        BachsCheckoutRequest(orderId: 'x', context: {'nested': nested});
    nested['value'] = 'sk_live_fixture';
    final sdk = configured(MockClient((_) async => fail('Secret transmitted')));
    await expectLater(sdk.pay(request), throwsA(isA<BachsSdkException>()));
  });

  test('custom verifier errors retain the launched session for safe retry',
      () async {
    for (final error in [
      TimeoutException('timeout'),
      http.ClientException('network'),
      const FormatException('response'),
      StateError('provider failed')
    ]) {
      var created = 0;
      final sdk = BachsFlutter(
          createSession: (_) async {
            created++;
            return BachsCheckoutSession.fromJson(session);
          },
          verifyStatus: (_, __) async => throw error,
          checkout: BachsCheckout(launcher: (_) async => true));
      final payment = await sdk.pay(BachsPaymentRequest(orderId: 'x'));
      expect(payment.session.id, 'chk_test');
      expect(payment.verificationError, isA<BachsSdkException>());
      await expectLater(
          sdk.verifyPayment(payment), throwsA(isA<BachsSdkException>()));
      expect(created, 1);
    }
  });
}
