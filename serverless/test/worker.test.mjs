import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { generateKeyPair, exportJWK, SignJWT } from "jose";
import worker from "../src/index.mjs";
const { privateKey, publicKey } = await generateKeyPair("RS256");
const jwk = { ...(await exportJWK(publicKey)), kid: "test", alg: "RS256" };
let db, env, upstream, realFetch, creates;
const token = (sub = "alice", audience = "shop") =>
  new SignJWT({})
    .setProtectedHeader({ alg: "RS256", kid: "test" })
    .setSubject(sub)
    .setIssuer("https://auth.example")
    .setAudience(audience)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(privateKey);
const request = async (
  path = "/checkout",
  body = { order_id: "order-1", context: { product_id: "book", quantity: 2 } },
  sub = "alice",
) =>
  worker.fetch(
    new Request("https://worker.example" + path, {
      method: body ? "POST" : "GET",
      headers: {
        authorization: "Bearer " + (await token(sub)),
        "content-type": "application/json",
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    }),
    env,
  );
function bind(sql, values = []) {
  return {
    bind(...v) {
      return bind(sql, v);
    },
    async first() {
      return db.prepare(sql).get(...values) ?? null;
    },
    async run() {
      return {
        meta: { changes: Number(db.prepare(sql).run(...values).changes) },
      };
    },
  };
}
beforeEach(() => {
  db = new DatabaseSync(":memory:");
  db.exec(
    readFileSync(new URL("../migrations/0001.sql", import.meta.url), "utf8"),
  );
  env = {
    DB: {
      prepare: (sql) => bind(sql),
      async batch(stmts) {
        db.exec("BEGIN");
        try {
          const r = [];
          for (const s of stmts) r.push(await s.run());
          db.exec("COMMIT");
          return r;
        } catch (e) {
          db.exec("ROLLBACK");
          throw e;
        }
      },
    },
    AUTH_ISSUER: "https://auth.example",
    AUTH_AUDIENCE: "shop",
    AUTH_JWKS_URL: "https://auth.example/jwks",
    BACHS_SECRET_KEY: "sk_sandbox_test",
    BACHS_WEBHOOK_SECRET: "whsec_test",
    BACHS_ORGANIZATION_ID: "acct_test",
    CATALOG_JSON: JSON.stringify({
      book: { amount: "12.50", currency: "USD", max_quantity: 5 },
    }),
    SUCCESS_URL: "https://shop.example/done",
    CANCEL_URL: "https://shop.example/cancel",
    ALLOWED_ORIGINS: "https://shop.example",
  };
  creates = [];
  upstream = async (url, init) => {
    creates.push(JSON.parse(init.body));
    return Response.json({
      checkout_id: "chk_1",
      checkout_url: "https://checkout.bachs.io/test",
      expires_at: "2027-01-01T00:00:00Z",
      status: "open",
    });
  };
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) =>
    String(url).includes("/jwks")
      ? Response.json({ keys: [jwk] })
      : upstream(url, init);
});
afterEach(() => {
  globalThis.fetch = realFetch;
  db.close();
});
async function webhook(event, offset = 0, tamper = false) {
  const body = JSON.stringify({
    id: "evt_1",
    created_at: new Date().toISOString(),
    organization_id: "acct_test",
    type: "collection.succeeded",
    data: {
      checkout_id: "chk_1",
      status: "SUCCEEDED",
      amount: "25.00",
      currency: "USD",
      reference: "order-1",
    },
    ...event,
  });
  const t = Math.floor(Date.now() / 1000) + offset;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(env.BACHS_WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = Buffer.from(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(t + "." + body),
    ),
  ).toString("hex");
  return worker.fetch(
    new Request("https://worker.example/webhooks/bachs", {
      method: "POST",
      headers: {
        "x-bachs-signature-v2": `t=${t},v1=${"0".repeat(64)},v1=${sig}`,
      },
      body: body + (tamper ? " " : ""),
    }),
    env,
  );
}
test("requires valid JWT audience and authentication", async () => {
  assert.equal(
    (
      await worker.fetch(
        new Request("https://worker.example/checkout", { method: "POST" }),
        env,
      )
    ).status,
    401,
  );
  const r = await worker.fetch(
    new Request("https://worker.example/checkout", {
      method: "POST",
      headers: { authorization: "Bearer " + (await token("alice", "other")) },
    }),
    env,
  );
  assert.equal(r.status, 401);
});
test("prices from catalog, persists mapping, and returns same checkout on retry", async () => {
  const a = await request();
  assert.equal(a.status, 200);
  assert.equal((await a.json()).checkout_id, "chk_1");
  assert.equal(creates[0].pricing.amount, "25.00");
  assert.equal((await request()).status, 200);
  assert.equal(creates.length, 1);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM orders").get().n, 1);
});
test("rejects price tampering and invalid quantity", async () => {
  for (const context of [
    { product_id: "book", quantity: 1, amount: "0.01" },
    { product_id: "book", quantity: 0 },
    { product_id: "unknown", quantity: 1 },
  ])
    assert.equal(
      (await request("/checkout", { order_id: "x", context })).status,
      400,
    );
});
test("enforces owner and immutable cart on create and status", async () => {
  await request();
  assert.equal((await request("/checkout", undefined, "bob")).status, 404);
  assert.equal(
    (
      await request("/checkout", {
        order_id: "order-1",
        context: { product_id: "book", quantity: 1 },
      })
    ).status,
    409,
  );
  assert.equal(
    (
      await request(
        "/checkout-status?order_id=order-1&checkout_id=chk_1",
        null,
        "bob",
      )
    ).status,
    404,
  );
  assert.equal(
    (
      await request(
        "/checkout-status?order_id=order-1&checkout_id=chk_wrong",
        null,
      )
    ).status,
    404,
  );
});
test("unknown write outcomes never create again automatically", async () => {
  upstream = async () => {
    throw Error("lost response");
  };
  assert.equal((await request()).status, 503);
  assert.equal((await request()).status, 409);
  assert.equal(db.prepare("SELECT phase FROM orders").get().phase, "creating");
});
test("paid status requires exact server-owned charge and order details", async () => {
  await request();
  const valid = {
    checkout_id: "chk_1",
    status: "SUCCEEDED",
    amount: "25.00",
    currency: "USD",
    reference: "order-1",
  };
  for (const [eventId, override] of [
    ["evt_wrong_amount", { amount: "24.99" }],
    ["evt_wrong_currency", { currency: "NGN" }],
    ["evt_wrong_reference", { reference: "other-order" }],
    ["evt_no_reference", { reference: null }],
    ["evt_no_amount", { amount: null }],
  ]) {
    const response = await webhook({
      id: eventId,
      data: { ...valid, ...override },
    });
    assert.equal(response.status, 503, eventId);
    assert.equal(
      db.prepare("SELECT status FROM orders").get().status,
      "pending",
    );
  }
  assert.equal(db.prepare("SELECT COUNT(*) n FROM events").get().n, 0);
  assert.equal((await webhook({ id: "evt_valid" })).status, 200);
  assert.equal(db.prepare("SELECT status FROM orders").get().status, "paid");
});

test("verified webhook deduplicates and paid never regresses", async () => {
  await request();
  assert.equal((await webhook({})).status, 200);
  assert.equal((await webhook({})).status, 200);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM events").get().n, 1);
  await webhook({ id: "evt_2", type: "checkout.expired" });
  const r = await request(
    "/checkout-status?order_id=order-1&checkout_id=chk_1",
    null,
  );
  assert.equal((await r.json()).status, "paid");
});
test("rejects modified, stale and wrong organization webhooks", async () => {
  await request();
  assert.equal((await webhook({}, 0, true)).status, 400);
  assert.equal((await webhook({}, -301)).status, 400);
  assert.equal((await webhook({ organization_id: "acct_other" })).status, 400);
  assert.equal(db.prepare("SELECT status FROM orders").get().status, "pending");
});
test("completed without paid and failed attempt do not fulfil", async () => {
  await request();
  await webhook({ type: "checkout.completed" });
  await webhook({ id: "evt_2", type: "collection.failed" });
  assert.equal(db.prepare("SELECT status FROM orders").get().status, "pending");
});
test("concurrent creates reserve once and never make a second provider checkout", async () => {
  let release;
  const gate = new Promise((r) => (release = r));
  upstream = async (url, init) => {
    creates.push(JSON.parse(init.body));
    await gate;
    return Response.json({
      checkout_id: "chk_1",
      checkout_url: "https://checkout.bachs.io/test",
      expires_at: "2027-01-01T00:00:00Z",
      status: "open",
    });
  };
  const first = request();
  while (!creates.length) await new Promise((r) => setTimeout(r, 1));
  assert.equal((await request()).status, 409);
  release();
  assert.equal((await first).status, 200);
  assert.equal(creates.length, 1);
});
test("early webhook is retried until durable checkout mapping exists", async () => {
  assert.equal((await webhook({})).status, 503);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM events").get().n, 0);
  await request();
  assert.equal((await webhook({})).status, 200);
});
test("event insertion failure rolls status update back", async () => {
  await request();
  db.exec(
    "CREATE TRIGGER reject_event BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT, 'disk failure'); END;",
  );
  assert.equal((await webhook({})).status, 500);
  assert.equal(db.prepare("SELECT status FROM orders").get().status, "pending");
  db.exec("DROP TRIGGER reject_event");
  assert.equal((await webhook({})).status, 200);
});
test("refuses live keys by default and blocks browser origins", async () => {
  env.BACHS_SECRET_KEY = "sk_live_test";
  assert.equal((await request()).status, 503);
  const response = await worker.fetch(
    new Request("https://worker.example/checkout", {
      method: "OPTIONS",
      headers: { Origin: "https://evil.example" },
    }),
    env,
  );
  assert.equal(response.status, 403);
});

test("checkout response is open while trusted order status stays pending", async () => {
  const created = await (await request()).json();
  assert.equal(created.status, "open");
  const pending = await (
    await request("/checkout-status?order_id=order-1&checkout_id=chk_1", null)
  ).json();
  assert.equal(pending.status, "pending");
});
