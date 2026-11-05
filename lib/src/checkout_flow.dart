import 'checkout.dart';
import 'checkout_session.dart';
import 'models.dart';
import 'return_url.dart';

/// Merchant-supplied function. Create a session on YOUR trusted backend.
typedef BachsSessionProvider = Future<BachsCheckoutSession> Function(
    BachsCheckoutRequest request);

/// Merchant-supplied function. Check status against YOUR authenticated backend.
typedef BachsStatusProvider = Future<BachsPaymentStatus> Function(
    String orderId, String checkoutId);

/// An app-link return is navigation, never payment confirmation.
class BachsReturnResult {
  const BachsReturnResult({required this.kind, this.checkoutId});
  final BachsReturnKind kind;
  final String? checkoutId;
}

/// Merchant-independent Flutter payment orchestrator.
///
/// The SDK has no concept of a global API key, fixed product or hard-coded
/// merchant. Each integrator injects their own session/status providers.
class BachsFlutter {
  BachsFlutter({
    required BachsSessionProvider createSession,
    BachsStatusProvider? verifyStatus,
    BachsCheckout? checkout,
    BachsReturnUrlMatcher? returnUrlMatcher,
  }) : _createSession = createSession,
       _verifyStatus = verifyStatus,
       _checkout = checkout ?? BachsCheckout(),
       _returnUrlMatcher = returnUrlMatcher;

  final BachsSessionProvider _createSession;
  final BachsStatusProvider? _verifyStatus;
  final BachsCheckout _checkout;
  final BachsReturnUrlMatcher? _returnUrlMatcher;

  /// Creates a checkout via the merchant backend and opens the hosted URL.
  /// Returning here ONLY proves the browser launched, not that a payment paid.
  Future<BachsCheckoutSession> startCheckout(BachsCheckoutRequest request) async {
    final session = await _createSession(request);
    if (session.status.toLowerCase() != 'open') {
      throw const BachsSdkException('Backend did not return an open checkout');
    }
    await _checkout.launch(session);
    return session;
  }

  /// Return-link classification. Register app_links, Universal Links or App
  /// Links within the merchant's Flutter app; then pass its incoming URI here.
  BachsReturnResult handleReturn(Uri incoming) {
    final matcher = _returnUrlMatcher;
    if (matcher == null) {
      throw const BachsSdkException('Configure returnUrlMatcher first');
    }
    return BachsReturnResult(
      kind: matcher.classify(incoming),
      checkoutId: matcher.checkoutIdFrom(incoming),
    );
  }

  /// Confirms the order's payment only through the merchant backend.
  Future<BachsPaymentStatus> checkPayment({
    required String orderId,
    required String checkoutId,
  }) async {
    final provider = _verifyStatus;
    if (provider == null) {
      throw const BachsSdkException('Configure verifyStatus first');
    }
    final result = await provider(orderId, checkoutId);
    if (result.orderId != orderId || result.checkoutId != checkoutId) {
      throw const BachsSdkException('Payment status does not match this checkout');
    }
    return result;
  }
}
