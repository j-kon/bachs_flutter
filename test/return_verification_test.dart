import 'package:bachs_flutter/bachs_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = BachsCheckoutSession(
      id: 'chk_1',
      checkoutUrl: Uri.parse('https://checkout.bachs.io/c/1'),
      status: 'open');
  final payment = BachsPaymentResult(orderId: 'order_1', session: session);
  BachsFlutter sdk(BachsPaymentState state) => BachsFlutter(
        createSession: (_) async => session,
        verifyStatus: (order, checkout) async => BachsPaymentStatus(
            orderId: order, checkoutId: checkout, state: state),
        returnUrlMatcher: BachsReturnUrlMatcher(
            successUrl: Uri.parse('https://shop.example/thanks'),
            cancelUrl: Uri.parse('https://shop.example/cancel')),
      );

  test('success navigation remains pending until backend confirms', () async {
    final result = await sdk(BachsPaymentState.pending).verifyReturn(
        Uri.parse('https://shop.example/thanks?checkout_id=chk_1'), payment);
    expect(result.isPaid, false);
    expect(result.returnKind, BachsReturnKind.successRedirect);
  });
  test('cancel navigation cannot override a paid backend status', () async {
    final result = await sdk(BachsPaymentState.paid)
        .verifyReturn(Uri.parse('https://shop.example/cancel'), payment);
    expect(result.isPaid, true);
    expect(result.returnKind, BachsReturnKind.cancellationRedirect);
  });
  test('verified cancellation, failure and expiry remain distinct', () async {
    for (final state in [
      BachsPaymentState.cancelled,
      BachsPaymentState.failed,
      BachsPaymentState.expired
    ]) {
      final result = await sdk(state).verifyPayment(payment);
      expect(result.status!.state, state);
      expect(result.isPaid, false);
    }
  });
  test('rejects unrelated links and mismatched checkout identifiers', () async {
    for (final link in [
      'https://evil.example/thanks',
      'https://shop.example/thanks?checkout_id=chk_other'
    ]) {
      await expectLater(
          sdk(BachsPaymentState.paid).verifyReturn(Uri.parse(link), payment),
          throwsA(isA<BachsSdkException>()));
    }
  });
  test('closed instance cannot start or verify payments', () async {
    final instance = sdk(BachsPaymentState.pending)..close();
    await expectLater(
        instance.verifyPayment(payment), throwsA(isA<BachsSdkException>()));
    await expectLater(instance.startCheckout(BachsPaymentRequest(orderId: 'x')),
        throwsA(isA<BachsSdkException>()));
  });
}
