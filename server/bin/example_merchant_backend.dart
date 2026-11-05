/// LOCAL DEVELOPMENT EXAMPLE, NOT A PRODUCTION PAYMENT BACKEND.
///
/// Replace the in-memory order store, authorization, and demo catalog with
/// the merchant's authenticated order database before public deployment.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bachs_server/bachs_server.dart';

class _Order {
  _Order({required this.id, required this.sku, required this.pricing});
  final String id;
  final String sku;
  final BachsPricing pricing;
  CreatedCheckout? checkout;
  String status = 'pending';
}

Future<void> main() async {
  final key = Platform.environment['BACHS_API_KEY'];
  final webhookSecret = Platform.environment['BACHS_WEBHOOK_SECRET'];
  final success = Platform.environment['BACHS_SUCCESS_URL'];
  final cancel = Platform.environment['BACHS_CANCEL_URL'];
  if (key == null || key.isEmpty || success == null || cancel == null ||
      success.isEmpty || cancel.isEmpty) {
    stderr.writeln('Set BACHS_API_KEY, BACHS_SUCCESS_URL and BACHS_CANCEL_URL.');
    exitCode = 64;
    return;
  }
  final rawCatalog = jsonDecode(File(Platform.environment['BACHS_CATALOG_FILE'] ??
          'config/catalog.json').readAsStringSync());
  if (rawCatalog is! Map<String, dynamic>) {
    throw const FormatException('Catalog should contain SKU -> pricing');
  }
  final catalog = <String, BachsPricing>{};
  for (final entry in rawCatalog.entries) {
    final value = entry.value;
    if (value is! Map<String, dynamic> ||
        value['currency'] is! String || value['amount'] is! String) {
      throw const FormatException('Invalid catalog entry');
    }
    catalog[entry.key] = BachsPricing(
      currency: value['currency'] as String,
      amount: value['amount'] as String,
    );
  }
  final client = BachsClient(apiKey: key);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
  final orders = <String, _Order>{};
  final eventIds = <String>{};
  stdout.writeln('Local merchant backend: http://127.0.0.1:8080');
  stdout.writeln('SKU catalog: ${catalog.keys.join(', ')}');
  stdout.writeln('DEVELOPMENT ONLY: no user auth, database or durable deduplication.');
  await for (final req in server) {
    try {
      if (req.method == 'POST' && req.uri.path == '/checkout') {
        final raw = jsonDecode(await utf8.decoder.bind(req).join());
        if (raw is! Map<String, dynamic> ||
            raw['order_id'] is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(raw['order_id'] as String) ||
            raw['context'] is! Map<String, dynamic> ||
            (raw['context'] as Map<String, dynamic>)['sku'] is! String) {
          await _reply(req, 400, {'code': 'INVALID_ORDER'});
          continue;
        }
        final orderId = raw['order_id'] as String;
        final sku = (raw['context'] as Map<String, dynamic>)['sku'] as String;
        final price = catalog[sku];
        if (price == null) {
          await _reply(req, 400, {'code': 'UNKNOWN_SKU'});
          continue;
        }
        final existing = orders[orderId];
        if (existing != null && existing.sku != sku) {
          await _reply(req, 409, {'code': 'ORDER_CONFLICT'});
          continue;
        }
        final order = existing ?? _Order(id: orderId, sku: sku, pricing: price);
        orders[orderId] = order;
        // The amount and currency come from this trusted catalog, not JSON.
        order.checkout ??= await client.createCheckout(
          CreateCheckoutRequest(
            pricing: order.pricing,
            reference: orderId,
            metadata: {'order_id': orderId},
            successUrl: Uri.parse(success),
            cancelUrl: Uri.parse(cancel),
          ),
          idempotencyKey: 'checkout-$orderId',
        );
        await _reply(req, 201, order.checkout!.toPublicJson());
      } else if (req.method == 'GET' && req.uri.path == '/checkout-status') {
        final orderId = req.uri.queryParameters['order_id'];
        final checkoutId = req.uri.queryParameters['checkout_id'];
        final order = orders[orderId];
        if (order == null || order.checkout == null ||
            order.checkout!.id != checkoutId) {
          await _reply(req, 404, {'code': 'ORDER_NOT_FOUND'});
          continue;
        }
        await _reply(req, 200, {
          'order_id': order.id,
          'checkout_id': order.checkout!.id,
          'status': order.status,
        });
      } else if (req.method == 'POST' && req.uri.path == '/webhooks/bachs') {
        if (webhookSecret == null || webhookSecret.isEmpty) {
          await _reply(req, 503, {'code': 'WEBHOOK_NOT_CONFIGURED'});
          continue;
        }
        final bytes = await req.fold<List<int>>(<int>[],
            (acc, chunk) => acc..addAll(chunk));
        final headers = <String, String>{};
        req.headers.forEach((k, v) { if (v.isNotEmpty) headers[k] = v.first; });
        BachsWebhookEvent event;
        try {
          event = BachsWebhooks.constructEvent(
            rawBody: bytes, headers: headers, secret: webhookSecret);
        } on BachsWebhookException {
          await _reply(req, 400, {'code': 'INVALID_SIGNATURE'});
          continue;
        }
        if (!eventIds.add(event.id)) {
          await _reply(req, 200, {'received': true});
          continue;
        }
        final checkoutId = event.data['checkout_id'];
        _Order? matching;
        for (final order in orders.values) {
          if (order.checkout?.id == checkoutId) { matching = order; break; }
        }
        if (matching != null && matching.status != 'paid') {
          if (event.type == 'collection.succeeded' &&
              event.data['currency'] == matching.pricing.currency &&
              _sameAmount(event.data['amount'], matching.pricing.amount)) {
            matching.status = 'paid';
            stdout.writeln('Verified paid order: ${matching.id}');
          } else if (event.type == 'collection.failed') {
            matching.status = 'failed';
          } else if (event.type == 'checkout.expired') {
            matching.status = 'expired';
          }
        }
        await _reply(req, 200, {'received': true});
      } else {
        await _reply(req, 404, {'code': 'NOT_FOUND'});
      }
    } on BachsApiException catch (e) {
      stderr.writeln('Bachs API error: ${e.statusCode} ${e.code}');
      await _reply(req, 502, {'code': 'UPSTREAM_FAILED'});
    } on FormatException {
      await _reply(req, 400, {'code': 'INVALID_JSON'});
    } catch (e) {
      stderr.writeln('Backend error: ${e.runtimeType}');
      await _reply(req, 500, {'code': 'INTERNAL_ERROR'});
    }
  }
}

bool _sameAmount(Object? amount, String expected) {
  if (amount is! String) return false;
  String? normalized(String input) {
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(input)) return null;
    final parts = input.split('.');
    return '${BigInt.parse(parts[0])}.${parts.length > 1 ? parts[1].padRight(2, '0') : '00'}';
  }
  return normalized(amount) != null && normalized(amount) == normalized(expected);
}

Future<void> _reply(HttpRequest req, int status, Map<String, dynamic> payload) async {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(payload));
  await req.response.close();
}
