import 'package:bachs_server/bachs_server.dart';
import 'package:test/test.dart';

void main() {
  test('merchant can configure catalog cart, override and payment corridors',
      () {
    final request = CreateCheckoutRequest(
      productCart: const [
        BachsLineItem(
            productId: 'prod_first',
            quantity: 2,
            priceOverride: {'price_type': 'fixed', 'amount': '19.00'}),
        BachsLineItem(productId: 'prod_second'),
      ],
      customer: const BachsCustomerDetails(email: 'test@example.com'),
      billingCurrency: 'USD',
      paymentMethodTypes: const ['USD_CARD'],
      customerCreation: 'always',
    );
    final json = request.toJson();
    expect((json['product_cart'] as List).length, 2);
    expect((json['product_cart'] as List).first['pricing']['amount'], '19.00');
    expect(json['payment_method_types'], ['USD_CARD']);
    expect(json['customer_creation'], 'always');
    expect(json['billing_currency'], 'USD');
  });
  test('merchant raw amount is independent of catalog products', () {
    final request = CreateCheckoutRequest(
      pricing: const BachsPricing(currency: 'NGN', amount: '1000.00'),
      reference: 'merchant_order',
    );
    expect(request.toJson()['pricing']['currency'], 'NGN');
    expect(request.toJson().containsKey('product_cart'), isFalse);
  });
  test('invalid customer creation rejected', () {
    expect(
        () => CreateCheckoutRequest(
              pricing: const BachsPricing(currency: 'USD', amount: '1.00'),
              customerCreation: 'never',
            ),
        throwsArgumentError);
  });
}
