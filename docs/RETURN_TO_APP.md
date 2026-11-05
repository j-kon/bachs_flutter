# Return to app and payment recovery

A browser launch is not a payment. Neither is a success or cancellation redirect.
Keep the active `BachsPaymentResult` returned by `pay`, and verify its order and
checkout IDs against your authenticated backend on resume.

## Button integration

`BachsCheckoutButton` with `onPaymentResult` observes app lifecycle and checks
status on resume. It retains the active session while mounted, blocks duplicate
taps, and lets users tap **Check payment status** when confirmation is pending.
It does not register your domain with Android or iOS. No automatic infinite
polling is performed.

## Custom UI

Configure the matcher when constructing `BachsFlutter`:

```dart
final bachs = BachsFlutter(
  config: BachsConfig(checkoutEndpoint: 'https://api.myapp.com/payments/checkout'),
  returnUrlMatcher: BachsReturnUrlMatcher(
    successUrl: Uri.parse('https://myapp.com/pay/success'),
    cancelUrl: Uri.parse('https://myapp.com/pay/cancel'),
  ),
);
```

Supply authentication through `tokenProvider` for protected endpoints. Configure
those same HTTPS return URLs on the server. The example uses `app_links` to pass
incoming links to `await bachs.verifyReturn(uri, activeResult)`. Only a matching
link for the active checkout can trigger this verification. Unknown links throw
`UNRELATED_RETURN`; route them normally in the rest of your app.

`result.returnKind` describes navigation. `result.status` describes trusted
backend state. A cancellation redirect can still have paid status if a payment
completed concurrently. Closing the browser may produce no link; verify on app
resume or an explicit **Check status** action.

See the [example's Android and iOS setup](../example/README.md#return-to-the-app)
for manifests, Associated Domains and domain verification files. Register an
HTTPS domain you control; the SDK cannot configure application signing or domain
ownership for you. Test real universal/app links on each target device.

## Process death and retries

The button and example keep sessions in memory. A production app should restore
orders and checkout IDs from authenticated account history after process death.
Never construct paid state from redirect parameters. Call `checkPayment` with
the restored IDs, or reconstruct a `BachsPaymentResult` with the server's session
and use `verifyPayment`. Browser-close cancellation is inherently unverified.

If creation times out, the provider write may already have succeeded. Keep the
same logical order ID; let the backend reuse its durable idempotency key or
reconcile the existing checkout. For a status outage, retain the launched result
and call `verifyPayment` again; do not create a second checkout.
