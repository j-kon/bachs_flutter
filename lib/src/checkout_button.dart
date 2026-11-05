import 'package:flutter/material.dart';

import 'checkout_flow.dart';
import 'checkout_session.dart';
import 'models.dart';

/// Optional reusable button for developers who want a ready-to-use widget.
///
/// It handles button loading state and safe session launch, but never claims
/// payment success. Listen for backend status separately with checkPayment().
class BachsCheckoutButton extends StatefulWidget {
  const BachsCheckoutButton({
    super.key,
    required this.bachs,
    required this.request,
    this.onCheckoutLaunched,
    this.onError,
    this.label = 'Pay with Bachs',
    this.enabled = true,
  });

  final BachsFlutter bachs;
  final BachsCheckoutRequest request;
  final ValueChanged<BachsCheckoutSession>? onCheckoutLaunched;
  final ValueChanged<Object>? onError;
  final String label;
  final bool enabled;

  @override
  State<BachsCheckoutButton> createState() => _BachsCheckoutButtonState();
}

class _BachsCheckoutButtonState extends State<BachsCheckoutButton> {
  bool _loading = false;

  Future<void> _start() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final session = await widget.bachs.startCheckout(widget.request);
      if (mounted) widget.onCheckoutLaunched?.call(session);
    } catch (error) {
      if (mounted) {
        if (widget.onError != null) {
          widget.onError!(error);
        } else {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Unable to start checkout')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: _loading || !widget.enabled ? null : _start,
        icon: _loading
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.open_in_browser),
        label: Text(_loading ? 'Opening checkout…' : widget.label),
      );
}
