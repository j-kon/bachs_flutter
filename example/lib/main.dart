import 'package:bachs_flutter/bachs_flutter.dart';
import 'package:flutter/material.dart';

/// Demo has NO secret keys. Configure only the URL of YOUR OWN backend.
const backendUrl = String.fromEnvironment(
  'BACHS_MERCHANT_BACKEND', defaultValue: 'http://127.0.0.1:8080');

void main() => runApp(const MerchantExampleApp());

class MerchantExampleApp extends StatelessWidget {
  const MerchantExampleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bachs Flutter: Developer Integration',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const MerchantExamplePage(),
      );
}

class MerchantExamplePage extends StatefulWidget {
  const MerchantExamplePage({super.key});
  @override
  State<MerchantExamplePage> createState() => _MerchantExamplePageState();
}

class _MerchantExamplePageState extends State<MerchantExamplePage> {
  late final BachsBackendAdapter backend;
  late final BachsFlutter bachs;
  final catalog = const {
    'starter': 'Starter · NGN 1,000',
    'business': 'Business · NGN 5,000',
    'global': 'Global · USD 10',
  };
  String sku = 'starter';
  String message = 'Select a merchant product to start checkout.';
  bool busy = false;
  String? orderId;
  BachsCheckoutSession? session;

  @override
  void initState() {
    super.initState();
    backend = BachsBackendAdapter(
      baseUrl: Uri.parse(backendUrl),
      // Opt-in ONLY for loopback simulator/emulator development.
      allowInsecureLoopback: true,
      // Production: tokenProvider: () async => auth.currentAccessToken,
    );
    bachs = BachsFlutter(
      createSession: backend.createSession,
      verifyStatus: backend.checkStatus,
      returnUrlMatcher: BachsReturnUrlMatcher(
        successUrl: Uri.parse('https://your-domain.example/pay/success'),
        cancelUrl: Uri.parse('https://your-domain.example/pay/cancel'),
      ),
    );
  }

  @override
  void dispose() {
    backend.close();
    super.dispose();
  }

  Future<void> _start() async {
    if (busy) return;
    setState(() { busy = true; message = 'Creating checkout on merchant server…'; });
    try {
      final newOrderId = 'demo_${DateTime.now().microsecondsSinceEpoch}';
      final created = await bachs.startCheckout(BachsCheckoutRequest(
        orderId: newOrderId,
        context: {'sku': sku},
      ));
      if (!mounted) return;
      setState(() {
        orderId = newOrderId;
        session = created;
        message = 'Checkout opened. Payment is unverified until the backend confirms it.';
      });
    } catch (error) {
      if (mounted) setState(() => message = 'Checkout failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _check() async {
    final id = orderId;
    final active = session;
    if (busy || id == null || active == null) return;
    setState(() { busy = true; message = 'Checking verified merchant order status…'; });
    try {
      final result = await bachs.checkPayment(orderId: id, checkoutId: active.id);
      if (!mounted) return;
      setState(() => message = switch (result.state) {
        BachsPaymentState.paid => 'Payment confirmed by your merchant backend.',
        BachsPaymentState.pending => 'Still pending. Await a verified Bachs webhook.',
        BachsPaymentState.failed => 'Payment failed.',
        BachsPaymentState.cancelled => 'Payment cancelled.',
        BachsPaymentState.expired => 'Checkout expired.',
      });
    } catch (error) {
      if (mounted) setState(() => message = 'Could not check status: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Bachs Flutter SDK')),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 60),
              const SizedBox(height: 16),
              Text('Merchant integration example',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text('Each developer owns their backend, Bachs keys, products and webhooks. The mobile SDK only launches sessions and reads merchant-verified status.',
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              const Text('Choose a product'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4,
                children: [for (final item in catalog.entries)
                  ChoiceChip(label: Text(item.value),
                    selected: sku == item.key,
                    onSelected: busy ? null : (_) => setState(() => sku = item.key),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: busy ? null : _start,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Pay with Bachs')),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: busy || session == null ? null : _check,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Check verified payment status')),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (busy) const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              const Text('Sandbox example only. Do not use the local reference backend for real payments.',
                textAlign: TextAlign.center),
            ],
          ),
        ))),
      );
}
