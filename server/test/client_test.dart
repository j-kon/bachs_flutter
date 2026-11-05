import 'dart:async';
import 'dart:convert';

import 'package:bachs_server/bachs_server.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('environment-key mismatch rejected', () {
    expect(() => BachsClient(apiKey: 'sk_live_dummy'), throwsArgumentError);
    expect(
        () => BachsClient(
            apiKey: 'sk_sandbox_dummy',
            environment: BachsEnvironment.production),
        throwsArgumentError);
  });

  test('raw pricing and product cart are exclusive', () {
    expect(() => CreateCheckoutRequest(), throwsArgumentError);
    expect(
        () => CreateCheckoutRequest(
              pricing: const BachsPricing(currency: 'USD', amount: '10.00'),
              productCart: const [BachsLineItem(productId: 'prod_test')],
            ),
        throwsArgumentError);
    final request = CreateCheckoutRequest(
      pricing: const BachsPricing(currency: 'USD', amount: '10.00'),
      customer: const BachsCustomerDetails(email: 'user@example.com'),
    );
    expect(request.toJson()['pricing']['amount'], '10.00');
    expect(request.toJson().containsKey('product_cart'), isFalse);
  });

  test('create checkout sets auth, idempotency and exact body', () async {
    late http.Request captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
          jsonEncode({
            'checkout_id': 'chk_123',
            'checkout_url': 'https://checkout.bachs.io/c/xyz',
            'status': 'open',
            'created_at': '2026-10-22T12:00:00Z',
            'expires_at': '2026-10-22T13:00:00Z',
          }),
          201);
    });
    final client = BachsClient(apiKey: 'sk_sandbox_test_key', httpClient: mock);
    final checkout = await client.createCheckout(
      CreateCheckoutRequest(
        productCart: const [BachsLineItem(productId: 'prod_test')],
        reference: 'order_123',
      ),
      idempotencyKey: 'checkout-order_123',
    );
    expect(captured.url.host, 'sandbox-api.bachs.io');
    expect(captured.method, 'POST');
    String? headerValue(String name) {
      for (final entry in captured.headers.entries) {
        if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
      }
      return null;
    }

    expect(headerValue('Authorization'), 'Bearer sk_sandbox_test_key');
    expect(headerValue('Idempotency-Key'), 'checkout-order_123');
    expect(jsonDecode(captured.body)['product_cart'][0]['product_id'],
        'prod_test');
    expect(checkout.toPublicJson()['checkout_url'],
        'https://checkout.bachs.io/c/xyz');
    expect(checkout.toPublicJson().containsKey('reference'), isFalse);
    client.close();
  });

  test('retrieval can establish completed and paid', () async {
    final client = BachsClient(
        apiKey: 'sk_sandbox_test_key',
        httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              'checkout_id': 'chk_paid',
              'status': 'completed',
              'payment_status': 'succeeded',
            }),
            200)));
    final result = await client.retrieveCheckout('chk_paid');
    expect(result.isCompletedAndPaid, isTrue);
  });

  test('http error preserves safe code and retry-after', () async {
    final client = BachsClient(
        apiKey: 'sk_sandbox_test_key',
        httpClient: MockClient((request) async => http.Response(
            '{"error_code":"TOO_MANY_REQUESTS","detail":"Rate limit exceeded"}',
            429,
            headers: {'retry-after': '12'})));
    try {
      await client.listProducts();
      fail('Expected an API error');
    } on BachsApiException catch (e) {
      expect(e.statusCode, 429);
      expect(e.code, 'TOO_MANY_REQUESTS');
      expect(e.retryAfter, const Duration(seconds: 12));
      expect('$e'.contains('sk_sandbox_test_key'), isFalse);
    }
  });

  test('response body timeout is mapped without retrying', () async {
    var sends = 0;
    final body = StreamController<List<int>>();
    final client = BachsClient(
      apiKey: 'sk_sandbox_test_key',
      timeout: const Duration(milliseconds: 10),
      httpClient: MockClient.streaming((request, stream) async {
        sends++;
        return http.StreamedResponse(body.stream, 200);
      }),
    );
    await expectLater(
        client.listProducts(),
        throwsA(
            isA<BachsApiException>().having((e) => e.code, 'code', 'TIMEOUT')));
    expect(sends, 1);
    await body.close();
  });

  test('response body network failure is mapped without leaking credentials',
      () async {
    final client = BachsClient(
      apiKey: 'sk_sandbox_test_key',
      httpClient: MockClient.streaming((request, stream) async =>
          http.StreamedResponse(
              Stream<List<int>>.error(
                  http.ClientException('sensitive transport detail')),
              200)),
    );
    await expectLater(
        client.listProducts(),
        throwsA(isA<BachsApiException>()
            .having((e) => e.code, 'code', 'NETWORK_ERROR')
            .having((e) => e.toString(), 'safe message',
                isNot(contains('sensitive transport detail')))));
  });

  test('timeout does not silently retry a write', () async {
    var count = 0;
    final client = BachsClient(
      apiKey: 'sk_sandbox_test_key',
      timeout: const Duration(milliseconds: 20),
      httpClient: MockClient((request) async {
        count++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.createCheckout(
          CreateCheckoutRequest(
              pricing: const BachsPricing(currency: 'USD', amount: '10.00')),
          idempotencyKey: 'same-operation'),
      throwsA(isA<BachsApiException>()),
    );
    expect(count, 1);
  });
}

// Additional generic request options are tested in request_options_test.dart.
