import 'package:bachs_checkout_example/main.dart';
import 'package:bachs_flutter/bachs_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'checkout locks cart and simulated paid result never claims real payment',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MerchantExampleApp());
      expect(find.textContaining('SIMULATED'), findsWidgets);
      await tester.tap(find.text('Pay with Bachs'));
      await tester.pumpAndSettle();
      final products = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(products.every((chip) => chip.onSelected == null), isTrue);
      await tester.tap(find.text('Simulate paid'));
      await tester.pumpAndSettle();
      expect(find.text('SIMULATED: paid. No money moved.'), findsOneWidget);
    },
  );
  test(
    'simulated SDK verifies the original order and preserves it after an outage',
    () async {
      final merchant = SimulatedMerchant();
      final sdk = merchant.createSdk();
      addTearDown(sdk.close);
      final payment = await sdk.pay(
        BachsPaymentRequest(orderId: 'order-42', productId: 'mug', quantity: 2),
      );
      expect(payment.isPaid, isFalse);
      merchant.unavailable = true;
      await expectLater(
        sdk.verifyPayment(payment),
        throwsA(isA<BachsSdkException>()),
      );
      merchant.unavailable = false;
      merchant.state = BachsPaymentState.paid;
      final verified = await sdk.verifyPayment(payment);
      expect(verified.isPaid, isTrue);
      expect(verified.status!.orderId, 'order-42');
      expect(verified.status!.checkoutId, payment.session.id);
    },
  );
  testWidgets('status outage retains checkout and restoration permits retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MerchantExampleApp());
    await tester.tap(find.text('Pay with Bachs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simulate network error'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your payment is not confirmed.'),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => chip.onSelected == null),
      isTrue,
    );
    await tester.tap(find.text('Restore connection'));
    await tester.pumpAndSettle();
    expect(find.text('SIMULATED: pending. No money moved.'), findsOneWidget);
  });
  for (final state in ['pending', 'cancelled', 'failed']) {
    testWidgets('shows simulated $state honestly', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MerchantExampleApp());
      await tester.tap(find.text('Pay with Bachs'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Simulate $state'));
      await tester.tap(find.text('Simulate $state'));
      await tester.pumpAndSettle();
      expect(find.text('SIMULATED: $state. No money moved.'), findsOneWidget);
    });
  }
}
