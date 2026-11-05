import 'dart:async';
import 'package:bachs_flutter/bachs_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('button prevents duplicate creation and verifies again on resume',
      (tester) async {
    final gate = Completer<BachsCheckoutSession>();
    var creations = 0;
    var state = BachsPaymentState.pending;
    final results = <BachsPaymentResult>[];
    final sdk = BachsFlutter(
        createSession: (_) {
          creations++;
          return gate.future;
        },
        verifyStatus: (order, checkout) async => BachsPaymentStatus(
            orderId: order, checkoutId: checkout, state: state),
        checkout: BachsCheckout(launcher: (_) async => true));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BachsCheckoutButton(
      bachs: sdk,
      request: BachsPaymentRequest(orderId: 'order'),
      onPaymentResult: results.add,
      child: const Text('Buy book'),
    ))));
    await tester.tap(find.text('Buy book'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    gate.complete(BachsCheckoutSession(
        id: 'chk',
        checkoutUrl: Uri.parse('https://sandbox-checkout.bachs.io/c/test'),
        status: 'open'));
    await tester.pumpAndSettle();
    expect(creations, 1);
    expect(results.single.isPaid, false);
    state = BachsPaymentState.paid;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(results.last.isPaid, true);
    expect(creations, 1);
  });

  testWidgets('button reports launch failure without payment callback',
      (tester) async {
    final errors = <Object>[];
    final sdk = BachsFlutter(
        createSession: (_) async => BachsCheckoutSession(
            id: 'chk',
            checkoutUrl: Uri.parse('https://checkout.bachs.io/c/t'),
            status: 'open'),
        checkout: BachsCheckout(launcher: (_) async => false));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BachsCheckoutButton(
      bachs: sdk,
      request: BachsPaymentRequest(orderId: 'order'),
      onPaymentResult: (_) => fail('No result after launch failure'),
      onError: errors.add,
    ))));
    await tester.tap(find.text('Pay with Bachs'));
    await tester.pumpAndSettle();
    expect(errors.single, isA<BachsCheckoutException>());
  });
}
