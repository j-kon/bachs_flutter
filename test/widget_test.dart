import 'package:bachs_flutter/bachs_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('checkout button calls merchant provider and launch callback',
      (tester) async {
    final session = BachsCheckoutSession(
      id: 'chk_a',
      checkoutUrl: Uri.parse('https://checkout.bachs.io/c/a'),
      status: 'open',
    );
    var sessionsCreated = 0;
    var launches = 0;
    final bachs = BachsFlutter(
      createSession: (request) async {
        sessionsCreated++;
        expect(request.orderId, 'order_9');
        return session;
      },
      checkout: BachsCheckout(launcher: (url) async {
        expect(url.host, 'checkout.bachs.io');
        return true;
      }),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BachsCheckoutButton(
      bachs: bachs,
      request: BachsCheckoutRequest(orderId: 'order_9'),
      onCheckoutLaunched: (value) {
        expect(value.id, 'chk_a');
        launches++;
      },
    ))));
    await tester.tap(find.text('Pay with Bachs'));
    await tester.pumpAndSettle();
    expect(sessionsCreated, 1);
    expect(launches, 1);
  });
}
