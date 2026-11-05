/// Public, non-secret fields returned by your backend after creating a session.
///
/// Pass this model to the Flutter client. Backend-only customer data and
/// Bachs API credentials must not be serialized into a mobile response.
class BachsCheckoutSession {
  const BachsCheckoutSession({
    required this.id,
    required this.checkoutUrl,
    required this.status,
    this.expiresAt,
  });

  final String id;
  final Uri checkoutUrl;
  final String status;
  final DateTime? expiresAt;

  factory BachsCheckoutSession.fromJson(Map<String, dynamic> json) {
    final id = json['checkout_id'];
    final url = json['checkout_url'];
    final status = json['status'];
    if (id is! String || id.isEmpty ||
        url is! String || url.isEmpty ||
        status is! String || status.isEmpty) {
      throw const FormatException('Invalid checkout session response');
    }
    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null || !parsedUrl.hasAuthority) {
      throw const FormatException('Invalid checkout_url');
    }
    final expires = json['expires_at'];
    return BachsCheckoutSession(
      id: id,
      checkoutUrl: parsedUrl,
      status: status,
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'checkout_id': id,
        'checkout_url': checkoutUrl.toString(),
        'status': status,
        if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
      };
}
