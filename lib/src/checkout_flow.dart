import 'dart:async';
import 'package:http/http.dart' as http;
import 'backend_adapter.dart';
import 'config.dart';

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
  factory BachsFlutter({
    BachsConfig? config,
    BachsSessionProvider? createSession,
    BachsStatusProvider? verifyStatus,
    BachsCheckout? checkout,
    BachsReturnUrlMatcher? returnUrlMatcher,
    http.Client? httpClient,
  }) {
    if ((config == null) == (createSession == null) ||
        (config != null && verifyStatus != null) ||
        (config == null && httpClient != null)) {
      throw ArgumentError('Provide config OR createSession/verifyStatus');
    }
    BachsBackendAdapter? adapter;
    if (config != null) {
      adapter = BachsBackendAdapter(
        baseUrl: Uri.parse(config.checkoutEndpoint.origin),
        createPath: config.checkoutEndpoint.path,
        statusPath: config.statusEndpoint.path,
        tokenProvider: config.tokenProvider,
        timeout: config.timeout,
        allowInsecureLoopback: config.allowInsecureLoopback,
        httpClient: httpClient,
      );
    }
    return BachsFlutter._(
      createSession: adapter?.createSession ?? createSession,
      verifyStatus: adapter?.checkStatus ?? verifyStatus,
      checkout: checkout ?? BachsCheckout(),
      returnUrlMatcher: returnUrlMatcher,
      adapter: adapter,
    );
  }

  /// Open an existing checkout URL without a backend. No payment confirmation.
  factory BachsFlutter.hosted(
          {BachsCheckout? checkout, BachsReturnUrlMatcher? returnUrlMatcher}) =>
      BachsFlutter._(
        checkout: checkout ?? BachsCheckout(),
        returnUrlMatcher: returnUrlMatcher,
      );

  BachsFlutter._({
    BachsSessionProvider? createSession,
    BachsStatusProvider? verifyStatus,
    required BachsCheckout checkout,
    BachsReturnUrlMatcher? returnUrlMatcher,
    BachsBackendAdapter? adapter,
  })  : _createSession = createSession,
        _verifyStatus = verifyStatus,
        _checkout = checkout,
        _returnUrlMatcher = returnUrlMatcher,
        _adapter = adapter;

  final BachsBackendAdapter? _adapter;
  bool _closed = false;

  void _ensureOpen() {
    if (_closed) {
      throw const BachsSdkException('SDK instance has been closed',
          code: 'CLOSED');
    }
  }

  /// Close owned HTTP resources. Caller-injected clients remain caller-owned.
  void close() {
    _closed = true;
    _adapter?.close();
  }

  final BachsSessionProvider? _createSession;
  final BachsStatusProvider? _verifyStatus;
  final BachsCheckout _checkout;
  final BachsReturnUrlMatcher? _returnUrlMatcher;

  /// Creates a checkout via the merchant backend and opens the hosted URL.
  /// Returning here ONLY proves the browser launched, not that a payment paid.
  Future<BachsCheckoutSession> startCheckout(
      BachsCheckoutRequest request) async {
    _ensureOpen();
    final provider = _createSession;
    if (provider == null) {
      throw const BachsSdkException(
          'Dynamic checkout requires a merchant endpoint',
          code: 'INVALID_CONFIG');
    }
    final session = await provider(request);
    if (session.status.toLowerCase() != 'open') {
      throw const BachsSdkException('Backend did not return an open checkout');
    }
    await _checkout.launch(session);
    return session;
  }

  /// Opens a trusted hosted checkout link. Does not imply payment success.
  Future<void> openCheckoutUrl(Uri url) async {
    _ensureOpen();
    await _checkout
        .launch(BachsCheckoutSession(id: '', checkoutUrl: url, status: 'open'));
  }

  /// Creates, launches, then checks status (usually pending).
  /// Verification failures retain the session so callers can retry safely.
  /// Use verifyPayment on app resume or verifyReturn on a matching app link.
  Future<BachsPaymentResult> pay(BachsCheckoutRequest request) async {
    final session = await startCheckout(request);
    final result =
        BachsPaymentResult(orderId: request.orderId, session: session);
    if (_verifyStatus == null) return result;
    try {
      return await verifyPayment(result);
    } on BachsSdkException catch (error) {
      return BachsPaymentResult(
          orderId: request.orderId, session: session, verificationError: error);
    }
  }

  Future<BachsPaymentResult> verifyPayment(BachsPaymentResult payment) async =>
      BachsPaymentResult(
        orderId: payment.orderId,
        session: payment.session,
        status: await checkPayment(
            orderId: payment.orderId, checkoutId: payment.session.id),
        returnKind: payment.returnKind,
      );

  /// A cancel URL is a navigation hint; only the backend decides payment state.
  Future<BachsPaymentResult> verifyReturn(
      Uri incoming, BachsPaymentResult payment) async {
    final navigation = handleReturn(incoming);
    if (navigation.kind == BachsReturnKind.unrelated ||
        (navigation.checkoutId != null &&
            navigation.checkoutId != payment.session.id)) {
      throw const BachsSdkException('Return link does not match this checkout',
          code: 'UNRELATED_RETURN');
    }
    final verified = await verifyPayment(payment);
    return BachsPaymentResult(
        orderId: verified.orderId,
        session: verified.session,
        status: verified.status,
        returnKind: navigation.kind);
  }

  /// Return-link classification. Register app_links, Universal Links or App
  /// Links within the merchant's Flutter app; then pass its incoming URI here.
  BachsReturnResult handleReturn(Uri incoming) {
    _ensureOpen();
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
    _ensureOpen();
    final provider = _verifyStatus;
    if (provider == null) {
      throw const BachsSdkException('Configure verifyStatus first');
    }
    late BachsPaymentStatus result;
    try {
      result = await provider(orderId, checkoutId);
    } on BachsSdkException {
      rethrow;
    } on TimeoutException {
      throw const BachsSdkException('Payment verification timed out',
          code: 'TIMEOUT');
    } on http.ClientException {
      throw const BachsSdkException('Payment verification unavailable',
          code: 'NETWORK');
    } on FormatException {
      throw const BachsSdkException('Invalid payment verification response',
          code: 'INVALID_RESPONSE');
    } catch (_) {
      throw const BachsSdkException('Payment verification unavailable',
          code: 'VERIFICATION_FAILED');
    }
    if (result.orderId != orderId || result.checkoutId != checkoutId) {
      throw const BachsSdkException(
          'Payment status does not match this checkout');
    }
    return result;
  }
}

/// A launched session and its latest trusted status, if available.
/// A null status means unverified, not paid or cancelled.
class BachsPaymentResult {
  const BachsPaymentResult({
    required this.orderId,
    required this.session,
    this.status,
    this.verificationError,
    this.returnKind,
  });
  final String orderId;
  final BachsCheckoutSession session;
  final BachsPaymentStatus? status;
  final BachsSdkException? verificationError;
  final BachsReturnKind? returnKind;
  bool get isPaid => status?.isPaid == true;
}
