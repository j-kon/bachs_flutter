import 'mobile_security.dart';

/// Developer-side input: an order already authenticated and priced by YOUR
/// backend. The optional [context] is *untrusted* on the server.
class BachsCheckoutRequest {
  BachsCheckoutRequest({
    required this.orderId,
    Map<String, dynamic> context = const {},
  }) : context = Map.unmodifiable(context) {
    rejectMobileSecrets(orderId);
    rejectMobileSecrets(context);
    if (orderId.trim().isEmpty || orderId.length > 128) {
      throw ArgumentError.value(
          orderId, 'orderId', 'Must contain 1-128 characters');
    }
  }

  final String orderId;
  final Map<String, dynamic> context;

  Map<String, dynamic> toJson() => {
        'order_id': orderId,
        if (context.isNotEmpty) 'context': context,
      };
}

/// Payment state established by the merchant's authenticated backend, which
/// verifies signed Bachs webhooks and/or reconciles with the Bachs API.
enum BachsPaymentState { pending, paid, failed, cancelled, expired }

class BachsPaymentStatus {
  const BachsPaymentStatus({
    required this.orderId,
    required this.checkoutId,
    required this.state,
  });

  final String orderId;
  final String checkoutId;
  final BachsPaymentState state;
  bool get isPaid => state == BachsPaymentState.paid;

  factory BachsPaymentStatus.fromJson(Map<String, dynamic> json) {
    final orderId = json['order_id'];
    final checkoutId = json['checkout_id'];
    final value = json['status'];
    if (orderId is! String ||
        orderId.isEmpty ||
        checkoutId is! String ||
        checkoutId.isEmpty ||
        value is! String) {
      throw const FormatException('Invalid merchant payment-status response');
    }
    final state = switch (value.toLowerCase()) {
      'pending' => BachsPaymentState.pending,
      'paid' => BachsPaymentState.paid,
      'failed' => BachsPaymentState.failed,
      'cancelled' => BachsPaymentState.cancelled,
      'expired' => BachsPaymentState.expired,
      _ => throw const FormatException('Unknown merchant payment status'),
    };
    return BachsPaymentStatus(
      orderId: orderId,
      checkoutId: checkoutId,
      state: state,
    );
  }
}

class BachsSdkException implements Exception {
  const BachsSdkException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;
  @override
  String toString() =>
      'BachsSdkException($message, code: $code, status: $statusCode)';
}

/// Convenience request. Product/quantity are suggestions; the server owns prices.
class BachsPaymentRequest extends BachsCheckoutRequest {
  final String? productId;
  final int quantity;

  BachsPaymentRequest(
      {required super.orderId, this.productId, this.quantity = 1})
      : super(context: {
          if (productId != null) 'product_id': productId,
          'quantity': quantity,
        }) {
    if (quantity < 1 || quantity > 99) {
      throw ArgumentError('quantity must be between 1 and 99');
    }
    final product = productId;
    if (product != null && (product.trim().isEmpty || product.length > 128)) {
      throw ArgumentError('productId must contain 1-128 characters');
    }
  }
}
