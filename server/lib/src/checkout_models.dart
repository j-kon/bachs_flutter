/// Decimal monetary amount; keep money as a string, never a double.
class BachsPricing {
  const BachsPricing({
    required this.currency,
    required this.amount,
    this.currencyOptions = const {},
  });

  final String currency;
  final String amount;
  final Map<String, String> currencyOptions;

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'amount': amount,
        if (currencyOptions.isNotEmpty) 'currency_options': currencyOptions,
      };
}

class BachsLineItem {
  const BachsLineItem({required this.productId, this.quantity = 1,
    this.priceOverride});

  final String productId;
  final int quantity;
  /// Provider-defined item price override. May be a fixed or custom price.
  /// Construct this on your trusted backend, never from mobile input.
  final Map<String, dynamic>? priceOverride;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'quantity': quantity,
        if (priceOverride != null) 'pricing': priceOverride,
      };
}

class BachsCustomerDetails {
  const BachsCustomerDetails({this.email, this.name, this.customerId})
      : assert(email != null || customerId != null);

  final String? email;
  final String? name;
  final String? customerId;

  Map<String, dynamic> toJson() => {
        if (email != null) 'email': email,
        if (name != null) 'name': name,
        if (customerId != null) 'customer_id': customerId,
      };
}

/// A one-time checkout request. One and only one price source is mandatory.
class CreateCheckoutRequest {
  CreateCheckoutRequest({
    this.productCart,
    this.pricing,
    this.customer,
    this.successUrl,
    this.cancelUrl,
    this.reference,
    this.metadata,
    this.expiresInMinutes,
    this.billingCurrency,
    this.paymentMethodTypes,
    this.customerCreation,
  }) {
    if ((productCart != null) == (pricing != null)) {
      throw ArgumentError('Provide exactly one of productCart or pricing');
    }
    if (productCart != null && (productCart!.isEmpty || productCart!.length > 20 ||
        productCart!.any((item) => item.productId.isEmpty || item.quantity < 1))) {
      throw ArgumentError('productCart must contain 1-20 valid items');
    }
    if (pricing != null &&
        (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(pricing!.amount) ||
            !RegExp(r'[1-9]').hasMatch(pricing!.amount))) {
      throw ArgumentError('pricing.amount must be a positive decimal string');
    }
    if (reference != null && (reference!.isEmpty || reference!.length > 128)) {
      throw ArgumentError('reference must be between 1 and 128 characters');
    }
    if (customerCreation != null &&
        customerCreation != 'if_required' && customerCreation != 'always') {
      throw ArgumentError('customerCreation must be if_required or always');
    }
    if (paymentMethodTypes != null && paymentMethodTypes!.isEmpty) {
      throw ArgumentError('paymentMethodTypes cannot be empty');
    }
    if (expiresInMinutes != null &&
        (expiresInMinutes! < 1 || expiresInMinutes! > 1440)) {
      throw ArgumentError('expiresInMinutes must be between 1 and 1440');
    }
  }

  final List<BachsLineItem>? productCart;
  final BachsPricing? pricing;
  final BachsCustomerDetails? customer;
  final Uri? successUrl;
  final Uri? cancelUrl;
  final String? reference;
  final Map<String, dynamic>? metadata;
  final int? expiresInMinutes;
  final String? billingCurrency;
  final List<String>? paymentMethodTypes;
  final String? customerCreation;

  Map<String, dynamic> toJson() => {
        if (productCart != null)
          'product_cart': productCart!.map((e) => e.toJson()).toList(),
        if (pricing != null) 'pricing': pricing!.toJson(),
        if (customer != null) 'customer': customer!.toJson(),
        if (successUrl != null) 'success_url': successUrl.toString(),
        if (cancelUrl != null) 'cancel_url': cancelUrl.toString(),
        if (reference != null) 'reference': reference,
        if (metadata != null) 'metadata': metadata,
        if (expiresInMinutes != null) 'expires_in_minutes': expiresInMinutes,
        if (billingCurrency != null) 'billing_currency': billingCurrency,
        if (paymentMethodTypes != null) 'payment_method_types': paymentMethodTypes,
        if (customerCreation != null) 'customer_creation': customerCreation,
      };
}

/// Response from the Bachs POST /v1/checkout-sessions API.
class CreatedCheckout {
  const CreatedCheckout({
    required this.id,
    required this.checkoutUrl,
    required this.status,
    this.reference,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final Uri checkoutUrl;
  final String status;
  final String? reference;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  factory CreatedCheckout.fromJson(Map<String, dynamic> json) {
    final id = json['checkout_id'];
    final url = json['checkout_url'];
    final status = json['status'];
    if (id is! String || id.isEmpty ||
        url is! String || Uri.tryParse(url)?.hasAuthority != true ||
        status is! String || status.isEmpty) {
      throw const FormatException('Invalid Bachs checkout response');
    }
    final createdAt = json['created_at'];
    final expiresAt = json['expires_at'];
    return CreatedCheckout(
      id: id,
      checkoutUrl: Uri.parse(url),
      status: status,
      reference: json['reference'] is String ? json['reference'] as String : null,
      createdAt: createdAt is String ? DateTime.tryParse(createdAt) : null,
      expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt) : null,
    );
  }

  /// Safe subset that can be forwarded to the Flutter client.
  Map<String, dynamic> toPublicJson() => {
        'checkout_id': id,
        'checkout_url': checkoutUrl.toString(),
        'status': status,
        if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
      };
}

/// Minimal typed view of the retrieval response; includes raw data for forward
/// compatibility with optional Bachs fields.
class RetrievedCheckout {
  const RetrievedCheckout({required this.id, required this.status,
    required this.paymentStatus, required this.data});

  final String id;
  final String status;
  final String? paymentStatus;
  final Map<String, dynamic> data;

  bool get isCompletedAndPaid => status.toLowerCase() == 'completed' &&
      paymentStatus?.toLowerCase() == 'succeeded';

  factory RetrievedCheckout.fromJson(Map<String, dynamic> json) {
    if (json['checkout_id'] is! String || json['status'] is! String) {
      throw const FormatException('Invalid retrieved checkout response');
    }
    return RetrievedCheckout(
      id: json['checkout_id'] as String,
      status: json['status'] as String,
      paymentStatus: json['payment_status'] is String
          ? json['payment_status'] as String : null,
      data: json,
    );
  }
}
