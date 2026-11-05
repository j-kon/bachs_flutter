import 'package:bachs_flutter/bachs_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = BachsCheckoutSession.fromJson({
    'checkout_id': 'chk_test',
    'checkout_url': 'https://checkout.bachs.io/c/abc',
    'status': 'open',
    'expires_at': '2099-01-01T00:00:00Z',
  });

  test('parses server checkout session', () {
    expect(session.id, 'chk_test');
    expect(session.checkoutUrl.host, 'checkout.bachs.io');
    expect(session.toJson()['status'], 'open');
  });

  test('launches trusted Bachs checkout URL', () async {
    Uri? launched;
    final sdk = BachsCheckout(launcher: (uri) async {
      launched = uri;
      return true;
    });
    await sdk.launch(session);
    expect(launched, session.checkoutUrl);
  });

  test('refuses http, credentials and lookalike checkout domains', () async {
    final sdk = BachsCheckout(launcher: (_) async => true);
    for (final url in [
      'http://checkout.bachs.io/c/abc',
      'https://checkout.bachs.io.attacker.example/c/abc',
      'https://bachs.io@attacker.example/c/abc',
    ]) {
      expect(sdk.isAllowedCheckoutUrl(Uri.parse(url)), isFalse);
    }
  });

  test('honors opt-in custom checkout host', () {
    final sdk = BachsCheckout(allowedHosts: {'payments.example.com'});
    expect(sdk.isAllowedCheckoutUrl(Uri.parse('https://payments.example.com/c/abc')), isTrue);
  });

  test('launcher returning false throws an explicit exception', () async {
    final sdk = BachsCheckout(launcher: (_) async => false);
    await expectLater(sdk.launch(session), throwsA(isA<BachsCheckoutException>()));
  });

  test('expired checkout is not launched', () async {
    final expired = BachsCheckoutSession(
      id: 'chk_old',
      checkoutUrl: Uri.parse('https://checkout.bachs.io/c/old'),
      status: 'open',
      expiresAt: DateTime.utc(2020),
    );
    await expectLater(BachsCheckout(launcher: (_) async => true).launch(expired),
        throwsA(isA<BachsCheckoutException>()));
  });

  test('return matcher distinguishes navigation from payment verification', () {
    final matcher = BachsReturnUrlMatcher(
      successUrl: Uri.parse('https://example.com/pay/success'),
      cancelUrl: Uri.parse('https://example.com/pay/cancel'),
    );
    final success = Uri.parse('https://example.com/pay/success?checkout_id=chk_1');
    expect(matcher.classify(success), BachsReturnKind.successRedirect);
    expect(matcher.checkoutIdFrom(success), 'chk_1');
    expect(matcher.classify(Uri.parse('https://example.com/pay/success-fake')),
        BachsReturnKind.unrelated);
    expect(matcher.classify(Uri.parse('https://evil.example.com/pay/success')),
        BachsReturnKind.unrelated);
    expect(matcher.classify(Uri.parse('https://example.com/pay/cancel')),
        BachsReturnKind.cancellationRedirect);
  });
}
