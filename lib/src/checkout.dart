import 'package:url_launcher/url_launcher.dart';

import 'checkout_session.dart';
import 'models.dart';
import 'mobile_security.dart';

/// Thrown when a checkout URL is unsafe or the platform cannot launch it.
class BachsCheckoutException extends BachsSdkException {
  const BachsCheckoutException(super.message) : super(code: 'CHECKOUT_LAUNCH');
  @override
  String toString() => 'BachsCheckoutException: $message';
}

/// Injectable callback to make launching checkout easy to test.
typedef CheckoutUrlLauncher = Future<bool> Function(Uri url);

/// Opens Bachs hosted checkout using the device's external browser.
///
/// This SDK deliberately does not collect card information or call privileged
/// Bachs API endpoints. Its only input is an HTTPS URL created by your backend.
/// A successful launch is NOT proof that a payment succeeded.
class BachsCheckout {
  BachsCheckout({
    CheckoutUrlLauncher? launcher,
    Set<String> allowedHosts = const <String>{},
  })  : _launcher = launcher ?? _launchExternally,
        _allowedHosts =
            Set.unmodifiable(allowedHosts.map((h) => h.toLowerCase()));

  final CheckoutUrlLauncher _launcher;
  final Set<String> _allowedHosts;

  static Future<bool> _launchExternally(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  /// True for Bachs' checkout host, or an explicitly permitted custom host.
  /// Custom domains must be HTTPS, and are an opt-in for integrators.
  bool isAllowedCheckoutUrl(Uri url) {
    if (url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.host.isEmpty ||
        url.port != 443) {
      return false;
    }
    final host = url.host.toLowerCase();
    try {
      rejectMobileSecrets(url.toString());
    } on ArgumentError {
      return false;
    }
    return host == 'checkout.bachs.io' ||
        host == 'sandbox-checkout.bachs.io' ||
        _allowedHosts.contains(host);
  }

  /// Launches a server-created session. Do not infer a payment result here.
  Future<void> launch(BachsCheckoutSession session) async {
    if (!isAllowedCheckoutUrl(session.checkoutUrl)) {
      throw const BachsCheckoutException(
          'Checkout URL is not a trusted HTTPS host');
    }
    if (session.expiresAt != null &&
        !session.expiresAt!.isAfter(DateTime.now())) {
      throw const BachsCheckoutException('Checkout session has expired');
    }
    try {
      final launched = await _launcher(session.checkoutUrl);
      if (!launched) {
        throw const BachsCheckoutException('Unable to open checkout');
      }
    } on BachsCheckoutException {
      rethrow;
    } catch (_) {
      // Do not leak platform-specific URI or other potentially sensitive data.
      throw const BachsCheckoutException('Unable to open checkout');
    }
  }
}
