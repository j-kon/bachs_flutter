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
    this.onPaymentResult,
    this.style,
    this.child,
    this.label = 'Pay with Bachs',
    this.enabled = true,
  });

  final BachsFlutter bachs;
  final BachsCheckoutRequest request;
  final ValueChanged<BachsCheckoutSession>? onCheckoutLaunched;
  final ValueChanged<Object>? onError;

  /// Called after launch and on resume with trusted status, when available.
  final ValueChanged<BachsPaymentResult>? onPaymentResult;
  final ButtonStyle? style;
  final Widget? child;
  final String label;
  final bool enabled;

  @override
  State<BachsCheckoutButton> createState() => _BachsCheckoutButtonState();
}

class _BachsCheckoutButtonState extends State<BachsCheckoutButton>
    with WidgetsBindingObserver {
  bool _loading = false;
  BachsPaymentResult? _payment;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(BachsCheckoutButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bachs != widget.bachs ||
        oldWidget.request.orderId != widget.request.orderId) {
      _generation++;
      _payment = null;
      _loading = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _payment != null &&
        widget.onPaymentResult != null &&
        !_loading &&
        !_payment!.isPaid) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final result = await widget.bachs.verifyPayment(_payment!);
      if (mounted && generation == _generation) {
        _payment = result;
        widget.onPaymentResult?.call(result);
      }
    } catch (error) {
      if (mounted && generation == _generation) _report(error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _report(Object error) {
    if (widget.onError != null) {
      widget.onError!(error);
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
            content: Text('Unable to check payment. Please try again.')),
      );
    }
  }

  Future<void> _start() async {
    if (_loading) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      // Keep legacy launch-only callbacks and behavior when no result is wanted.
      if (widget.onPaymentResult == null) {
        final session = await widget.bachs.startCheckout(widget.request);
        if (mounted && generation == _generation) {
          widget.onCheckoutLaunched?.call(session);
        }
      } else {
        final result = _payment == null
            ? await widget.bachs.pay(widget.request)
            : await widget.bachs.verifyPayment(_payment!);
        if (mounted && generation == _generation) {
          final firstLaunch = _payment == null;
          _payment = result;
          if (firstLaunch) widget.onCheckoutLaunched?.call(result.session);
          widget.onPaymentResult?.call(result);
        }
      }
    } catch (error) {
      if (mounted && generation == _generation) _report(error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        style: widget.style,
        onPressed: _loading || !widget.enabled || _payment?.isPaid == true
            ? null
            : _start,
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.open_in_browser),
        label: _loading
            ? const Text('Please wait…')
            : _payment != null
                ? const Text('Check payment status')
                : widget.child ?? Text(widget.label),
      );
}
