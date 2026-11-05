import 'backend_adapter.dart';
import 'mobile_security.dart';

/// Public merchant endpoints and user authentication. Never a Bachs API key.
class BachsConfig {
  BachsConfig({
    required String checkoutEndpoint,
    String? statusEndpoint,
    this.tokenProvider,
    this.timeout = const Duration(seconds: 20),
    this.allowInsecureLoopback = false,
  })  : checkoutEndpoint = _endpoint(checkoutEndpoint, allowInsecureLoopback),
        statusEndpoint = _endpoint(statusEndpoint ?? '$checkoutEndpoint-status',
            allowInsecureLoopback) {
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive');
    }
    if (this.checkoutEndpoint.origin != this.statusEndpoint.origin) {
      throw ArgumentError('Checkout and status endpoints must share an origin');
    }
  }

  final Uri checkoutEndpoint;
  final Uri statusEndpoint;
  final MerchantTokenProvider? tokenProvider;
  final Duration timeout;
  final bool allowInsecureLoopback;

  static Uri _endpoint(String value, bool allowLoopback) {
    rejectMobileSecrets(value);
    final uri = Uri.tryParse(value);
    final loopback = uri != null &&
        allowLoopback &&
        uri.scheme == 'http' &&
        const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !loopback) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isEmpty ||
        uri.path == '/') {
      throw ArgumentError(
          'Use an HTTPS endpoint with a path and no credentials, query or fragment');
    }
    return uri;
  }
}
