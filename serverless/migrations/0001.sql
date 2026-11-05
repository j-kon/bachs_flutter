CREATE TABLE orders (
 order_id TEXT PRIMARY KEY,
 owner TEXT NOT NULL,
 product_id TEXT NOT NULL,
 quantity INTEGER NOT NULL,
 request_json TEXT NOT NULL,
 idempotency_key TEXT NOT NULL UNIQUE,
 phase TEXT NOT NULL DEFAULT 'creating',
 checkout_id TEXT UNIQUE,
 checkout_url TEXT,
 expires_at TEXT,
 status TEXT NOT NULL DEFAULT 'pending',
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE events (
 event_id TEXT PRIMARY KEY,
 checkout_id TEXT,
 event_type TEXT NOT NULL,
 received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
