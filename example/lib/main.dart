import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:bachs_flutter/bachs_flutter.dart';
import 'package:flutter/material.dart';

const checkoutEndpoint = String.fromEnvironment('BACHS_CHECKOUT_ENDPOINT');
const hostedCheckoutUrl = String.fromEnvironment('BACHS_HOSTED_CHECKOUT_URL');
const returnBase = String.fromEnvironment(
  'BACHS_RETURN_BASE',
  defaultValue: 'https://shop.example.com/pay',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final links = AppLinks();
  runApp(MerchantExampleApp(links: links.uriLinkStream));
}

/// Offline providers exercise the same SDK without moving money or opening URLs.
class SimulatedMerchant {
  BachsPaymentState state = BachsPaymentState.pending;
  bool unavailable = false;

  BachsFlutter createSdk() => BachsFlutter(
    createSession: (request) async => BachsCheckoutSession(
      id: 'simulated-${request.orderId}',
      checkoutUrl: Uri.parse('https://checkout.bachs.io/simulated'),
      status: 'open',
    ),
    verifyStatus: (orderId, checkoutId) async {
      if (unavailable) throw const BachsSdkException('Simulated outage');
      return BachsPaymentStatus(
        orderId: orderId,
        checkoutId: checkoutId,
        state: state,
      );
    },
    checkout: BachsCheckout(launcher: (_) async => true),
  );
}

class MerchantExampleApp extends StatelessWidget {
  const MerchantExampleApp({super.key, this.links});
  final Stream<Uri>? links;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Little Goods · Bachs Sandbox',
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xff145c49),
    ),
    home: ShopPage(links: links),
  );
}

class ShopPage extends StatefulWidget {
  const ShopPage({super.key, this.links});
  final Stream<Uri>? links;
  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> with WidgetsBindingObserver {
  final simulator = SimulatedMerchant();
  final token = TextEditingController();
  final order = TextEditingController();
  late final BachsFlutter sdk;
  StreamSubscription<Uri>? subscription;
  BachsPaymentResult? payment;
  bool busy = false;
  String product = 'notebook';
  int quantity = 1;
  String message = 'Choose something lovely for your desk.';
  bool get simulated => checkoutEndpoint.isEmpty;
  bool get locked => busy || payment != null;
  static const products = {
    'notebook': ('Linen notebook', 2500),
    'mug': ('Studio mug', 4500),
    'tote': ('Everyday tote', 6000),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sdk = simulated
        ? simulator.createSdk()
        : BachsFlutter(
            config: BachsConfig(
              checkoutEndpoint: checkoutEndpoint,
              tokenProvider: () async =>
                  token.text.trim().isEmpty ? null : token.text.trim(),
            ),
            returnUrlMatcher: BachsReturnUrlMatcher(
              successUrl: Uri.parse('$returnBase/success'),
              cancelUrl: Uri.parse('$returnBase/cancel'),
            ),
          );
    subscription = widget.links?.listen(
      _onReturn,
      onError: (_) {
        if (mounted)
          setState(
            () => message = 'Could not read return link. Tap Check status.',
          );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && payment != null && !busy)
      _verify();
  }

  Future<void> _onReturn(Uri uri) async {
    if (simulated) return;
    if (payment == null) {
      setState(
        () => message =
            'No active checkout on this device. Restore your order from your merchant account before checking payment.',
      );
      return;
    }
    if (busy) return;
    await _run(() async {
      payment = await sdk.verifyReturn(uri, payment!);
      _showStatus();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      message =
          'We could not complete that request. Check your connection and try again. Your payment is not confirmed.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pay() => _run(() async {
    if (!simulated &&
        (token.text.trim().isEmpty || order.text.trim().isEmpty)) {
      message =
          'Enter a merchant order ID and your short-lived user login token.';
      return;
    }
    simulator.state = BachsPaymentState.pending;
    payment = await sdk.pay(
      BachsPaymentRequest(
        orderId: simulated
            ? 'demo-${DateTime.now().microsecondsSinceEpoch}'
            : order.text.trim(),
        productId: product,
        quantity: quantity,
      ),
    );
    message = simulated
        ? 'SIMULATED: pending. No money moved.'
        : 'Checkout opened. Payment is not confirmed. Return here to check status.';
    if (payment!.status != null) _showStatus();
  });

  void _showStatus() {
    final state = payment?.status?.state;
    if (simulated) {
      message = 'SIMULATED: ${state?.name ?? 'pending'}. No money moved.';
    } else {
      message = switch (state) {
        BachsPaymentState.paid => 'Payment confirmed by your merchant backend.',
        BachsPaymentState.cancelled =>
          'Checkout cancelled. No confirmed payment.',
        BachsPaymentState.failed =>
          'Payment failed. Contact the merchant if you were charged.',
        BachsPaymentState.expired => 'Checkout expired. Start a new order.',
        _ =>
          'Payment pending. Check again after the merchant receives confirmation.',
      };
    }
  }

  Future<void> _verify() => _run(() async {
    if (payment == null) return;
    payment = await sdk.verifyPayment(payment!);
    _showStatus();
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    sdk.close();
    token.dispose();
    order.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Little Goods')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              simulated
                  ? 'SIMULATED DEMO · NO REAL PAYMENTS'
                  : 'LIVE SANDBOX · TEST PAYMENTS ONLY',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Good things for everyday.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final item in products.entries)
                  ChoiceChip(
                    label: Text('${item.value.$1} · ₦${item.value.$2}'),
                    selected: product == item.key,
                    onSelected: locked
                        ? null
                        : (_) => setState(() => product = item.key),
                  ),
              ],
            ),
            Row(
              children: [
                const Text('Quantity'),
                IconButton(
                  onPressed: locked || quantity == 1
                      ? null
                      : () => setState(() => quantity--),
                  icon: const Icon(Icons.remove),
                ),
                Text('$quantity'),
                IconButton(
                  onPressed: locked || quantity == 5
                      ? null
                      : () => setState(() => quantity++),
                  icon: const Icon(Icons.add),
                ),
                const Spacer(),
                Text('₦${products[product]!.$2 * quantity}'),
              ],
            ),
            const Text(
              'Prices shown are illustrative. The merchant server validates the order and owns the final price.',
            ),
            if (!simulated) ...[
              TextField(
                controller: order,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Merchant-created sandbox order ID',
                ),
              ),
              TextField(
                controller: token,
                enabled: !busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Short-lived user login token (memory only)',
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: locked ? null : _pay,
              child: const Text('Pay with Bachs'),
            ),
            if (payment != null) ...[
              OutlinedButton(
                onPressed: busy ? null : _verify,
                child: const Text('Check status'),
              ),
              if (simulated)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final state in [
                      BachsPaymentState.pending,
                      BachsPaymentState.paid,
                      BachsPaymentState.cancelled,
                      BachsPaymentState.failed,
                      BachsPaymentState.expired,
                    ])
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                simulator.state = state;
                                simulator.unavailable = false;
                                _verify();
                              },
                        child: Text('Simulate ${state.name}'),
                      ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              simulator.unavailable = true;
                              _verify();
                            },
                      child: const Text('Simulate network error'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              simulator.unavailable = false;
                              _verify();
                            },
                      child: const Text('Restore connection'),
                    ),
                  ],
                ),
              if (payment!.status != null &&
                  payment!.status!.state != BachsPaymentState.pending)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          payment = null;
                          message = 'Choose your next item.';
                        }),
                  child: const Text('Shop again'),
                ),
            ],
            if (!simulated && hostedCheckoutUrl.isNotEmpty)
              TextButton(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                        await sdk.openCheckoutUrl(Uri.parse(hostedCheckoutUrl));
                        message =
                            'Hosted checkout opened. This URL-only launch cannot confirm payment; check the order with your merchant.';
                      }),
                child: const Text('Open existing sandbox checkout URL'),
              ),
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(message)),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
  );
}
