import 'dart:convert';

/// Defense in depth: this cannot identify every possible credential format.
void rejectMobileSecrets(Object? value) {
  final text = value is String ? value : jsonEncode(value);
  if (RegExp(r'sk_sandbox_|sk_live_|whsec_', caseSensitive: false)
      .hasMatch(text)) {
    throw ArgumentError('Bachs secret keys belong only on your server');
  }
}
