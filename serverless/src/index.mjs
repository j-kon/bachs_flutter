import { createRemoteJWKSet, jwtVerify } from "jose";

const encoder = new TextEncoder();
const jwksCache = new Map();
class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
  }
}
const fail = (status, code) => {
  throw new HttpError(status, code);
};
const object = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const id = (value) =>
  typeof value === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(value);
const json = (value) =>
  Response.json(value, { headers: { "Cache-Control": "no-store" } });

async function authenticate(request, env) {
  const match = /^Bearer (\S+)$/.exec(
    request.headers.get("Authorization") ?? "",
  );
  if (!match) fail(401, "unauthorized");
  if (
    !env.AUTH_ISSUER ||
    !env.AUTH_AUDIENCE ||
    !env.AUTH_JWKS_URL?.startsWith("https://")
  )
    fail(503, "auth_not_configured");
  let keys = jwksCache.get(env.AUTH_JWKS_URL);
  if (!keys) {
    keys = createRemoteJWKSet(new URL(env.AUTH_JWKS_URL), {
      timeoutDuration: 5000,
    });
    jwksCache.set(env.AUTH_JWKS_URL, keys);
  }
  try {
    const { payload } = await jwtVerify(match[1], keys, {
      issuer: env.AUTH_ISSUER,
      audience: env.AUTH_AUDIENCE,
      algorithms: ["RS256", "ES256"],
      requiredClaims: ["sub", "exp", "iat"],
    });
    if (!payload.sub || payload.sub.length > 256) fail(401, "unauthorized");
    return payload.sub;
  } catch {
    fail(401, "unauthorized");
  }
}

async function rawBody(request, maxBytes) {
  const reader = request.body?.getReader();
  if (!reader) fail(400, "missing_body");
  const chunks = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > maxBytes) {
      await reader.cancel();
      fail(413, "body_too_large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}
function parse(bytes) {
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    fail(400, "invalid_json");
  }
}
function providerBase(env) {
  const mode = env.BACHS_ENVIRONMENT ?? "sandbox";
  if (mode !== "sandbox" && mode !== "live") fail(503, "invalid_environment");
  if (mode === "live" && env.ALLOW_LIVE_PAYMENTS !== "true")
    fail(503, "live_not_enabled");
  const prefix = mode === "live" ? "sk_live_" : "sk_sandbox_";
  if (
    !env.BACHS_SECRET_KEY?.startsWith(prefix) ||
    env.BACHS_SECRET_KEY.length <= prefix.length
  )
    fail(503, "invalid_key_environment");
  return mode === "live"
    ? "https://api.bachs.io"
    : "https://sandbox-api.bachs.io";
}
function publicCheckout(row) {
  return {
    checkout_id: row.checkout_id,
    checkout_url: row.checkout_url,
    status: row.status === "pending" ? "open" : row.status,
    expires_at: row.expires_at,
  };
}
async function checkout(request, env, owner) {
  const body = parse(await rawBody(request, 8192));
  if (
    !object(body) ||
    Object.keys(body).some((k) => !["order_id", "context"].includes(k)) ||
    !id(body.order_id) ||
    !object(body.context)
  )
    fail(400, "invalid_order");
  const { product_id, quantity } = body.context;
  if (
    Object.keys(body.context).some(
      (k) => !["product_id", "quantity"].includes(k),
    ) ||
    !id(product_id) ||
    !Number.isInteger(quantity) ||
    quantity < 1 ||
    quantity > 99
  )
    fail(400, "invalid_cart");
  let row = await env.DB.prepare("SELECT * FROM orders WHERE order_id = ?")
    .bind(body.order_id)
    .first();
  if (row) return existing(row, owner, product_id, quantity);
  const catalog = JSON.parse(env.CATALOG_JSON ?? "{}");
  const product = Object.hasOwn(catalog, product_id)
    ? catalog[product_id]
    : null;
  if (!object(product) || quantity > product.max_quantity)
    fail(400, "unknown_product_or_quantity");
  // This starter intentionally accepts only two-decimal USD/NGN prices.
  if (
    !["USD", "NGN"].includes(product.currency) ||
    !/^[0-9]{1,10}\.[0-9]{2}$/.test(product.amount) ||
    !Number.isInteger(product.max_quantity)
  )
    fail(503, "invalid_catalog");
  const total = BigInt(product.amount.replace(".", "")) * BigInt(quantity);
  if (total <= 0n) fail(503, "invalid_catalog");
  const amount = `${total / 100n}.${(total % 100n).toString().padStart(2, "0")}`;
  for (const url of [env.SUCCESS_URL, env.CANCEL_URL]) {
    if (!url || new URL(url).protocol !== "https:")
      fail(503, "invalid_return_url");
  }
  const base = providerBase(env);
  const providerBody = JSON.stringify({
    pricing: { currency: product.currency, amount },
    reference: body.order_id,
    metadata: { order_id: body.order_id },
    success_url: env.SUCCESS_URL,
    cancel_url: env.CANCEL_URL,
    expires_in_minutes: 30,
  });
  const key = crypto.randomUUID();
  const inserted = await env.DB.prepare(
    "INSERT OR IGNORE INTO orders (order_id,owner,product_id,quantity,request_json,idempotency_key) VALUES (?,?,?,?,?,?)",
  )
    .bind(body.order_id, owner, product_id, quantity, providerBody, key)
    .run();
  if (!inserted.meta.changes) {
    row = await env.DB.prepare("SELECT * FROM orders WHERE order_id = ?")
      .bind(body.order_id)
      .first();
    return existing(row, owner, product_id, quantity);
  }
  // Never automatically resend a write: even an error can have an unknown outcome.
  try {
    const response = await fetch(`${base}/v1/checkout-sessions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.BACHS_SECRET_KEY}`,
        "Content-Type": "application/json",
        "Idempotency-Key": key,
      },
      body: providerBody,
      redirect: "error",
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) fail(503, "checkout_needs_reconciliation");
    const created = await response.json();
    const url = new URL(created.checkout_url);
    const allowedHost = [
      "checkout.bachs.io",
      "sandbox-checkout.bachs.io",
    ].includes(url.hostname);
    if (
      created.status !== "open" ||
      !id(created.checkout_id) ||
      url.protocol !== "https:" ||
      !allowedHost ||
      url.username ||
      url.password ||
      url.port ||
      !Number.isFinite(Date.parse(created.expires_at))
    )
      fail(503, "invalid_provider_response");
    await env.DB.prepare(
      "UPDATE orders SET phase='ready',checkout_id=?,checkout_url=?,expires_at=? WHERE order_id=?",
    )
      .bind(created.checkout_id, url.href, created.expires_at, body.order_id)
      .run();
    return json(
      publicCheckout(
        await env.DB.prepare("SELECT * FROM orders WHERE order_id=?")
          .bind(body.order_id)
          .first(),
      ),
    );
  } catch {
    fail(503, "checkout_needs_reconciliation");
  }
}
function existing(row, owner, product, quantity) {
  if (!row || row.owner !== owner) fail(404, "order_not_found");
  if (row.product_id !== product || row.quantity !== quantity)
    fail(409, "order_cart_changed");
  if (row.phase !== "ready") fail(409, "checkout_needs_reconciliation");
  return json(publicCheckout(row));
}
async function status(url, env, owner) {
  const order = url.searchParams.get("order_id"),
    checkoutId = url.searchParams.get("checkout_id");
  if (!id(order) || !id(checkoutId)) fail(400, "invalid_identifiers");
  const row = await env.DB.prepare(
    "SELECT * FROM orders WHERE order_id=? AND checkout_id=? AND owner=?",
  )
    .bind(order, checkoutId, owner)
    .first();
  if (!row) fail(404, "order_not_found");
  return json({
    order_id: row.order_id,
    checkout_id: row.checkout_id,
    status: row.status,
  });
}
async function webhook(request, env) {
  if (!env.BACHS_WEBHOOK_SECRET || !env.BACHS_ORGANIZATION_ID)
    fail(503, "webhook_not_configured");
  const raw = await rawBody(request, 262144);
  const parts = (request.headers.get("X-Bachs-Signature-V2") ?? "")
    .split(",")
    .map((x) => x.trim());
  const timestamps = parts.filter((x) => x.startsWith("t="));
  const timestamp = timestamps[0]?.slice(2);
  if (
    timestamps.length !== 1 ||
    !/^\d{1,12}$/.test(timestamp ?? "") ||
    Math.abs(Date.now() / 1000 - Number(timestamp)) > 300
  )
    fail(400, "invalid_signature");
  const prefix = encoder.encode(`${timestamp}.`);
  const message = new Uint8Array(prefix.length + raw.length);
  message.set(prefix);
  message.set(raw, prefix.length);
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(env.BACHS_WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  let valid = false;
  for (const part of parts.filter((x) => /^v1=[a-fA-F0-9]{64}$/.test(x))) {
    const bytes = Uint8Array.from(part.slice(3).match(/../g), (x) =>
      parseInt(x, 16),
    );
    if (await crypto.subtle.verify("HMAC", key, bytes, message)) valid = true;
  }
  if (!valid) fail(400, "invalid_signature");
  const event = parse(raw);
  if (
    !object(event) ||
    !id(event.id) ||
    typeof event.type !== "string" ||
    !object(event.data) ||
    event.organization_id !== env.BACHS_ORGANIZATION_ID ||
    event.account
  )
    fail(400, "invalid_event");
  if (
    await env.DB.prepare("SELECT event_id FROM events WHERE event_id=?")
      .bind(event.id)
      .first()
  )
    return json({ received: true });
  const checkoutId = event.data.checkout_id;
  const next =
    event.type === "collection.succeeded" &&
    ["SUCCEEDED", "OVERPAID"].includes(event.data.status)
      ? "paid"
      : event.type === "checkout.expired"
        ? "expired"
        : null;
  const statements = [];
  if (next && id(checkoutId)) {
    const row = await env.DB.prepare(
      "SELECT order_id,request_json FROM orders WHERE checkout_id=?",
    )
      .bind(checkoutId)
      .first();
    // A webhook can race the checkout response. Ask Bachs to retry, never lose it.
    if (!row) fail(503, "checkout_mapping_not_ready");
    if (next === "paid") {
      let pricing;
      try {
        pricing = JSON.parse(row.request_json).pricing;
      } catch {
        fail(503, "stored_checkout_needs_reconciliation");
      }
      // The original Bachs request stores the expected charge amount/currency.
      // Mismatches, including FX-currency payments, require reconciliation.
      // Never infer payment from a signed event for a different amount/order.
      if (
        !object(pricing) ||
        typeof pricing.amount !== "string" ||
        typeof pricing.currency !== "string" ||
        event.data.reference !== row.order_id ||
        event.data.amount !== pricing.amount ||
        event.data.currency !== pricing.currency
      )
        fail(503, "payment_needs_reconciliation");
    }
    statements.push(
      env.DB.prepare(
        "UPDATE orders SET status=? WHERE checkout_id=? AND status != 'paid' AND NOT EXISTS (SELECT 1 FROM events WHERE event_id=?)",
      ).bind(next, checkoutId, event.id),
    );
  }
  statements.push(
    env.DB.prepare(
      "INSERT OR IGNORE INTO events (event_id,checkout_id,event_type) VALUES (?,?,?)",
    ).bind(
      event.id,
      typeof checkoutId === "string" ? checkoutId : null,
      event.type,
    ),
  );
  // D1 batch is transactional: status and replay marker commit together.
  await env.DB.batch(statements);
  return json({ received: true });
}
export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin");
    const allowed = (env.ALLOWED_ORIGINS ?? "")
      .split(",")
      .map((x) => x.trim())
      .includes(origin);
    let response;
    try {
      const url = new URL(request.url);
      if (url.pathname === "/webhooks/bachs" && request.method === "POST")
        response = await webhook(request, env);
      else {
        if (origin && !allowed) fail(403, "origin_not_allowed");
        if (request.method === "OPTIONS")
          response = new Response(null, { status: 204 });
        else if (url.pathname === "/checkout" && request.method === "POST")
          response = await checkout(
            request,
            env,
            await authenticate(request, env),
          );
        else if (
          url.pathname === "/checkout-status" &&
          request.method === "GET"
        )
          response = await status(url, env, await authenticate(request, env));
        else fail(404, "not_found");
      }
    } catch (error) {
      response = Response.json(
        { code: error instanceof HttpError ? error.message : "internal_error" },
        { status: error instanceof HttpError ? error.status : 500 },
      );
    }
    response.headers.set("Cache-Control", "no-store");
    response.headers.set("Vary", "Origin");
    if (origin && allowed) {
      response.headers.set("Access-Control-Allow-Origin", origin);
      response.headers.set(
        "Access-Control-Allow-Methods",
        "POST, GET, OPTIONS",
      );
      response.headers.set(
        "Access-Control-Allow-Headers",
        "Authorization, Content-Type",
      );
    }
    return response;
  },
};
