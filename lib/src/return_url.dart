/// Checkout return is a navigation hint, NOT a verified payment outcome.
enum BachsReturnKind { successRedirect, cancellationRedirect, unrelated }

/// Matches deep/universal links against your server-configured return URLs.
///
/// Wire [classify] into the app's existing deep link listener. The app must
/// check payment completion with its backend after any return, and the backend
/// must fulfill orders only after authenticated verification/webhooks.
class BachsReturnUrlMatcher {
  const BachsReturnUrlMatcher({required this.successUrl, required this.cancelUrl});

  final Uri successUrl;
  final Uri cancelUrl;

  BachsReturnKind classify(Uri incoming) {
    if (_matches(successUrl, incoming)) {
      return BachsReturnKind.successRedirect;
    }
    if (_matches(cancelUrl, incoming)) {
      return BachsReturnKind.cancellationRedirect;
    }
    return BachsReturnKind.unrelated;
  }

  /// Prevent path-prefix confusion (/success-fake), host confusion, and
  /// changing configured query parameters while allowing checkout_id appended
  /// by Bachs to the success redirect.
  bool _matches(Uri expected, Uri incoming) {
    if (expected.scheme != incoming.scheme ||
        expected.host != incoming.host ||
        expected.port != incoming.port ||
        expected.path != incoming.path ||
        expected.userInfo != incoming.userInfo) {
      return false;
    }
    for (final entry in expected.queryParameters.entries) {
      if (incoming.queryParameters[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  /// Bachs appends checkout_id to a successful redirect. Always verify on the
  /// backend that this ID belongs to the signed-in user's expected order.
  String? checkoutIdFrom(Uri incoming) {
    if (classify(incoming) != BachsReturnKind.successRedirect) {
      return null;
    }
    final id = incoming.queryParameters['checkout_id'];
    return id == null || id.isEmpty ? null : id;
  }
}
