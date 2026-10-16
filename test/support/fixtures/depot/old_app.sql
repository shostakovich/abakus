-- The former portfolio app's database, as its migrations created it, with data that covers every table.
CREATE TABLE IF NOT EXISTS "users" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "email" TEXT NOT NULL COLLATE NOCASE, "passkey_handle" BLOB NOT NULL, "confirmed_at" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "benchmark_id" INTEGER CONSTRAINT "users_benchmark_id_fkey" REFERENCES "securities"("id") ON DELETE SET NULL, "paperless_url" TEXT, "paperless_token" TEXT, "paperless_tag" TEXT, "paperless_polled_at" TEXT);
CREATE UNIQUE INDEX "users_email_index" ON "users" ("email");
CREATE UNIQUE INDEX "users_passkey_handle_index" ON "users" ("passkey_handle");
CREATE TABLE IF NOT EXISTS "users_tokens" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" INTEGER NOT NULL CONSTRAINT "users_tokens_user_id_fkey" REFERENCES "users"("id") ON DELETE CASCADE, "token" BLOB NOT NULL, "context" TEXT NOT NULL, "sent_to" TEXT, "authenticated_at" TEXT, "inserted_at" TEXT NOT NULL);
CREATE INDEX "users_tokens_user_id_index" ON "users_tokens" ("user_id");
CREATE UNIQUE INDEX "users_tokens_context_token_index" ON "users_tokens" ("context", "token");
CREATE TABLE IF NOT EXISTS "user_passkeys" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" INTEGER NOT NULL CONSTRAINT "user_passkeys_user_id_fkey" REFERENCES "users"("id") ON DELETE CASCADE, "credential_id" BLOB NOT NULL, "public_key" BLOB NOT NULL, "algorithm" INTEGER NOT NULL, "sign_count" INTEGER NOT NULL, "name" TEXT NOT NULL, "last_used_at" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE INDEX "user_passkeys_user_id_index" ON "user_passkeys" ("user_id");
CREATE UNIQUE INDEX "user_passkeys_credential_id_index" ON "user_passkeys" ("credential_id");
CREATE TABLE IF NOT EXISTS "attribute_types" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "pp_id" TEXT NOT NULL, "name" TEXT NOT NULL, "column_label" TEXT, "target" TEXT, "value_type" TEXT, "converter" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE UNIQUE INDEX "attribute_types_pp_id_target_index" ON "attribute_types" ("pp_id", "target");
CREATE TABLE IF NOT EXISTS "securities" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "isin" TEXT, "wkn" TEXT, "currency" TEXT, "note" TEXT, "retired" INTEGER DEFAULT false NOT NULL, "attributes" TEXT DEFAULT ('{}') NOT NULL, "pp_feed" TEXT, "pp_ticker" TEXT, "quote_feed" TEXT DEFAULT 'manual' NOT NULL, "symbol" TEXT, "quote_feed_set_by_user" INTEGER DEFAULT false NOT NULL, "latest_date" TEXT, "latest_close" INTEGER, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "latest_at" TEXT, "fetched_at" TEXT, "checked_at" TEXT, "fetch_error" TEXT, "source" TEXT DEFAULT 'pp_import' NOT NULL);
CREATE INDEX "securities_isin_index" ON "securities" ("isin");
CREATE TABLE IF NOT EXISTS "pp_security_links" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" INTEGER NOT NULL CONSTRAINT "pp_security_links_user_id_fkey" REFERENCES "users"("id") ON DELETE CASCADE, "security_id" INTEGER NOT NULL CONSTRAINT "pp_security_links_security_id_fkey" REFERENCES "securities"("id") ON DELETE CASCADE, "pp_uuid" TEXT NOT NULL, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE UNIQUE INDEX "pp_security_links_user_id_pp_uuid_index" ON "pp_security_links" ("user_id", "pp_uuid");
CREATE INDEX "pp_security_links_security_id_index" ON "pp_security_links" ("security_id");
CREATE TABLE IF NOT EXISTS "prices" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "security_id" INTEGER NOT NULL CONSTRAINT "prices_security_id_fkey" REFERENCES "securities"("id") ON DELETE CASCADE, "date" TEXT NOT NULL, "close" INTEGER NOT NULL, "source" TEXT NOT NULL);
CREATE UNIQUE INDEX "prices_security_id_date_index" ON "prices" ("security_id", "date");
CREATE TABLE IF NOT EXISTS "accounts" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" INTEGER NOT NULL CONSTRAINT "accounts_user_id_fkey" REFERENCES "users"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "currency" TEXT NOT NULL, "note" TEXT, "retired" INTEGER DEFAULT false NOT NULL, "attributes" TEXT DEFAULT ('{}') NOT NULL, "pp_uuid" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE UNIQUE INDEX "accounts_user_id_pp_uuid_index" ON "accounts" ("user_id", "pp_uuid");
CREATE TABLE IF NOT EXISTS "portfolios" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" INTEGER NOT NULL CONSTRAINT "portfolios_user_id_fkey" REFERENCES "users"("id") ON DELETE CASCADE, "reference_account_id" INTEGER CONSTRAINT "portfolios_reference_account_id_fkey" REFERENCES "accounts"("id") ON DELETE SET NULL, "name" TEXT NOT NULL, "note" TEXT, "retired" INTEGER DEFAULT false NOT NULL, "attributes" TEXT DEFAULT ('{}') NOT NULL, "pp_uuid" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "depot_number" TEXT);
CREATE UNIQUE INDEX "portfolios_user_id_pp_uuid_index" ON "portfolios" ("user_id", "pp_uuid");
CREATE TABLE IF NOT EXISTS "transactions" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" INTEGER NOT NULL CONSTRAINT "transactions_user_id_fkey" REFERENCES "users"("id") ON DELETE CASCADE, "type" TEXT NOT NULL, "date_time" TEXT NOT NULL, "portfolio_id" INTEGER CONSTRAINT "transactions_portfolio_id_fkey" REFERENCES "portfolios"("id") ON DELETE CASCADE, "account_id" INTEGER CONSTRAINT "transactions_account_id_fkey" REFERENCES "accounts"("id") ON DELETE CASCADE, "other_portfolio_id" INTEGER CONSTRAINT "transactions_other_portfolio_id_fkey" REFERENCES "portfolios"("id") ON DELETE CASCADE, "other_account_id" INTEGER CONSTRAINT "transactions_other_account_id_fkey" REFERENCES "accounts"("id") ON DELETE CASCADE, "security_id" INTEGER CONSTRAINT "transactions_security_id_fkey" REFERENCES "securities"("id") ON DELETE RESTRICT, "shares" INTEGER, "amount" INTEGER NOT NULL, "currency" TEXT NOT NULL, "ex_date" TEXT, "note" TEXT, "source" TEXT NOT NULL, "pp_uuid" TEXT, "pp_other_uuid" TEXT, "pp_source" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "receipt_id" INTEGER CONSTRAINT "transactions_receipt_id_fkey" REFERENCES "receipts"("id") ON DELETE SET NULL);
CREATE UNIQUE INDEX "transactions_user_id_pp_uuid_index" ON "transactions" ("user_id", "pp_uuid");
CREATE INDEX "transactions_portfolio_id_index" ON "transactions" ("portfolio_id");
CREATE INDEX "transactions_account_id_index" ON "transactions" ("account_id");
CREATE INDEX "transactions_security_id_index" ON "transactions" ("security_id");
CREATE TABLE IF NOT EXISTS "transaction_units" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "transaction_id" INTEGER NOT NULL CONSTRAINT "transaction_units_transaction_id_fkey" REFERENCES "transactions"("id") ON DELETE CASCADE, "type" TEXT NOT NULL, "amount" INTEGER NOT NULL, "currency" TEXT NOT NULL, "fx_amount" INTEGER, "fx_currency" TEXT, "fx_rate" DECIMAL);
CREATE INDEX "transaction_units_transaction_id_index" ON "transaction_units" ("transaction_id");
CREATE TABLE IF NOT EXISTS "savings_plans" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" INTEGER NOT NULL CONSTRAINT "savings_plans_user_id_fkey" REFERENCES "users"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "note" TEXT, "type" TEXT NOT NULL, "security_id" INTEGER CONSTRAINT "savings_plans_security_id_fkey" REFERENCES "securities"("id") ON DELETE RESTRICT, "portfolio_id" INTEGER CONSTRAINT "savings_plans_portfolio_id_fkey" REFERENCES "portfolios"("id") ON DELETE CASCADE, "account_id" INTEGER CONSTRAINT "savings_plans_account_id_fkey" REFERENCES "accounts"("id") ON DELETE CASCADE, "auto_generate" INTEGER DEFAULT false NOT NULL, "start" TEXT NOT NULL, "interval" INTEGER NOT NULL, "amount" INTEGER NOT NULL, "fees" INTEGER DEFAULT 0 NOT NULL, "taxes" INTEGER DEFAULT 0 NOT NULL, "attributes" TEXT DEFAULT ('{}') NOT NULL, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE INDEX "savings_plans_user_id_index" ON "savings_plans" ("user_id");
CREATE TABLE IF NOT EXISTS "savings_plan_transactions" ("savings_plan_id" INTEGER NOT NULL CONSTRAINT "savings_plan_transactions_savings_plan_id_fkey" REFERENCES "savings_plans"("id") ON DELETE CASCADE, "transaction_id" INTEGER NOT NULL CONSTRAINT "savings_plan_transactions_transaction_id_fkey" REFERENCES "transactions"("id") ON DELETE CASCADE);
CREATE UNIQUE INDEX "savings_plan_transactions_savings_plan_id_transaction_id_index" ON "savings_plan_transactions" ("savings_plan_id", "transaction_id");
CREATE TABLE IF NOT EXISTS "taxonomies" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" INTEGER NOT NULL CONSTRAINT "taxonomies_user_id_fkey" REFERENCES "users"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "source" TEXT, "dimensions" TEXT DEFAULT ('[]') NOT NULL, "pp_id" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE UNIQUE INDEX "taxonomies_user_id_pp_id_index" ON "taxonomies" ("user_id", "pp_id");
CREATE TABLE IF NOT EXISTS "classifications" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "taxonomy_id" INTEGER NOT NULL CONSTRAINT "classifications_taxonomy_id_fkey" REFERENCES "taxonomies"("id") ON DELETE CASCADE, "parent_id" INTEGER CONSTRAINT "classifications_parent_id_fkey" REFERENCES "classifications"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "note" TEXT, "color" TEXT, "weight" INTEGER NOT NULL, "rank" INTEGER DEFAULT 0 NOT NULL, "pp_id" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE UNIQUE INDEX "classifications_taxonomy_id_pp_id_index" ON "classifications" ("taxonomy_id", "pp_id");
CREATE INDEX "classifications_parent_id_index" ON "classifications" ("parent_id");
CREATE TABLE IF NOT EXISTS "assignments" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "classification_id" INTEGER NOT NULL CONSTRAINT "assignments_classification_id_fkey" REFERENCES "classifications"("id") ON DELETE CASCADE, "security_id" INTEGER CONSTRAINT "assignments_security_id_fkey" REFERENCES "securities"("id") ON DELETE CASCADE, "account_id" INTEGER CONSTRAINT security_or_account CHECK ((security_id IS NULL) <> (account_id IS NULL)) CONSTRAINT "assignments_account_id_fkey" REFERENCES "accounts"("id") ON DELETE CASCADE, "weight" INTEGER NOT NULL, "rank" INTEGER DEFAULT 0 NOT NULL);
CREATE INDEX "assignments_classification_id_index" ON "assignments" ("classification_id");
CREATE TABLE IF NOT EXISTS "exchange_rates" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "currency" TEXT NOT NULL, "date" TEXT NOT NULL, "rate" DECIMAL NOT NULL);
CREATE UNIQUE INDEX "exchange_rates_currency_date_index" ON "exchange_rates" ("currency", "date");
CREATE TABLE IF NOT EXISTS "job_runs" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "ran_at" TEXT NOT NULL, "error" TEXT);
CREATE UNIQUE INDEX "job_runs_name_index" ON "job_runs" ("name");
CREATE TABLE IF NOT EXISTS "compositions" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "security_id" INTEGER NOT NULL CONSTRAINT "compositions_security_id_fkey" REFERENCES "securities"("id") ON DELETE CASCADE, "countries" TEXT NOT NULL, "sectors" TEXT NOT NULL, "fetched_at" TEXT NOT NULL);
CREATE UNIQUE INDEX "compositions_security_id_index" ON "compositions" ("security_id");
CREATE TABLE IF NOT EXISTS "divvy_diary_dividends" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "security_id" INTEGER NOT NULL CONSTRAINT "divvy_diary_dividends_security_id_fkey" REFERENCES "securities"("id") ON DELETE CASCADE, "ex_date" TEXT, "pay_date" TEXT NOT NULL, "per_share" INTEGER NOT NULL, "currency" TEXT NOT NULL, "fetched_at" TEXT NOT NULL);
CREATE INDEX "divvy_diary_dividends_security_id_pay_date_index" ON "divvy_diary_dividends" ("security_id", "pay_date");
CREATE TABLE IF NOT EXISTS "receipts" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" INTEGER NOT NULL CONSTRAINT "receipts_user_id_fkey" REFERENCES "users"("id") ON DELETE CASCADE, "sha256" TEXT NOT NULL, "filename" TEXT NOT NULL, "byte_size" INTEGER NOT NULL, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, "status" TEXT DEFAULT 'booked' NOT NULL, "text" TEXT, "fields" TEXT, "checks" TEXT, "bank_reference" TEXT, "paperless_id" INTEGER);
CREATE UNIQUE INDEX "receipts_user_id_sha256_index" ON "receipts" ("user_id", "sha256");
CREATE INDEX "transactions_receipt_id_index" ON "transactions" ("receipt_id");
CREATE INDEX "receipts_user_id_status_index" ON "receipts" ("user_id", "status");
CREATE INDEX "receipts_user_id_bank_reference_index" ON "receipts" ("user_id", "bank_reference");
CREATE INDEX "receipts_user_id_paperless_id_index" ON "receipts" ("user_id", "paperless_id");

INSERT INTO users VALUES
  (1, 'anna@example.com', X'00112233445566778899aabbccddeeff', '2026-10-08T18:10:00.000000Z', '2026-10-08T18:05:00.000000Z', '2026-10-12T09:00:00.000000Z', 2, 'https://paperless.example.com', 'token-anna', 'Depot', '2026-10-12T09:00:00.000000Z'),
  (3, 'Ben@Example.com', X'ffeeddccbbaa99887766554433221100', '2026-10-09T08:00:00.000000Z', '2026-10-09T07:55:00.000000Z', '2026-10-09T08:00:00.000000Z', NULL, NULL, NULL, NULL, NULL);

INSERT INTO users_tokens VALUES (1, 1, X'0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20', 'session', NULL, '2026-10-12T09:00:00.000000Z', '2026-10-12T09:00:00.000000Z');

INSERT INTO user_passkeys VALUES (1, 1, X'c0ffee', X'a5a5a5', -7, 3, 'Laptop', '2026-10-12T09:00:00.000000Z', '2026-10-08T18:10:00.000000Z', '2026-10-12T09:00:00.000000Z');

INSERT INTO attribute_types VALUES
  (1, 'logo', 'Logo', 'Logo', 'name.abuchen.portfolio.model.Security', 'java.lang.String', 'name.abuchen.portfolio.model.AttributeType$ImageConverter', '2026-10-08T19:00:00.000000Z', '2026-10-08T19:00:00.000000Z');

INSERT INTO securities VALUES
  (1, 'Vanguard FTSE All-World U.ETF', 'IE00BK5BQT80', 'A2PKXG', 'EUR', NULL, 0, '{}', 'YAHOO', 'VWCE.DE', 'yahoo', 'VWCE.DE', 0, '2026-10-12', 13512, '2026-10-08T19:00:00.000000Z', '2026-10-12T16:05:00.000000Z', '2026-10-12T15:30:00.000000Z', '2026-10-12T16:05:00.000000Z', '2026-10-12T16:05:00.000000Z', NULL, 'pp_import'),
  (2, 'iShares Core MSCI World', 'IE00B4L5Y983', 'A0RPWH', 'EUR', NULL, 0, '{}', NULL, NULL, 'yahoo', 'EUNL.DE', 1, '2026-10-12', 10234, '2026-10-08T19:00:00.000000Z', '2026-10-12T16:05:00.000000Z', '2026-10-12T15:30:00.000000Z', '2026-10-12T16:05:00.000000Z', '2026-10-12T16:05:00.000000Z', NULL, 'pp_import'),
  (4, 'Apple Inc.', 'US0378331005', '865985', 'USD', 'Einzelaktie', 0, '{"logo":"apple.png"}', NULL, NULL, 'manual', NULL, 0, NULL, NULL, '2026-10-09T08:10:00.000000Z', '2026-10-09T08:10:00.000000Z', NULL, NULL, NULL, NULL, 'manual');

INSERT INTO pp_security_links VALUES
  (1, 1, 1, 'pp-security-1', '2026-10-08T19:00:00.000000Z', '2026-10-08T19:00:00.000000Z'),
  (2, 1, 2, 'pp-security-2', '2026-10-08T19:00:00.000000Z', '2026-10-08T19:00:00.000000Z');

INSERT INTO prices VALUES
  (1, 1, '2026-10-09', 13400, 'yahoo'),
  (2, 1, '2026-10-12', 13512, 'yahoo'),
  (3, 2, '2026-10-12', 10234, 'yahoo'),
  (4, 4, '2026-10-02', 17250, 'manual');

INSERT INTO accounts VALUES
  (1, 1, 'Verrechnung', 'EUR', NULL, 0, '{}', 'pp-account-1', '2026-10-08T19:00:00.000000Z', '2026-10-08T19:00:00.000000Z'),
  (2, 3, 'Bens Konto', 'EUR', NULL, 0, '{}', NULL, '2026-10-09T08:05:00.000000Z', '2026-10-09T08:05:00.000000Z');

INSERT INTO portfolios VALUES
  (1, 1, 1, 'Langfristig', NULL, 0, '{}', 'pp-portfolio-1', '2026-10-08T19:00:00.000000Z', '2026-10-12T09:00:00.000000Z', '4472'),
  (3, 3, 2, 'Bens Depot', NULL, 0, '{}', NULL, '2026-10-09T08:05:00.000000Z', '2026-10-09T08:05:00.000000Z', NULL);

INSERT INTO receipts VALUES
  (1, 1, 'a7e1f6e59756f1cb2440ea200495f4e02025aa5f6523d34d8178bb1c9e840e37', 'Kauf VWCE.pdf', 33, '2026-10-01T18:00:00.000000Z', '2026-10-01T18:05:00.000000Z', 'booked', NULL, NULL, NULL, NULL, NULL),
  (2, 1, '1705d84339a3fafbd3dd623cc6d421ba21871df5d18731805d638653034fdfda', 'Sparplan Oktober.pdf', 34, '2026-10-12T09:00:00.000000Z', '2026-10-12T09:01:00.000000Z', 'ready', 'Wertpapierabrechnung Kauf', '{"kind":"purchase","date":"2026-10-01","isin":"IE00BK5BQT80","security_name":"Vanguard FTSE All-World U.ETF","shares":"93.207","price":"12.0699","fees":"0","taxes":null,"amount":"1125.00","depot_number":"4472","bank_reference":"SP-0001"}', '[]', 'SP0001', 17),
  (3, 3, 'a7e1f6e59756f1cb2440ea200495f4e02025aa5f6523d34d8178bb1c9e840e37', 'Kauf.pdf', 33, '2026-10-02T16:00:00.000000Z', '2026-10-02T16:00:00.000000Z', 'booked', NULL, NULL, NULL, NULL, NULL);

INSERT INTO transactions VALUES
  (5, 1, 'deposit', '2026-09-01T09:00:00', NULL, 1, NULL, NULL, NULL, NULL, 500000, 'EUR', NULL, NULL, 'pp_import', 'pp-transaction-5', NULL, 'Einzahlung', '2026-10-08T19:00:00.000000Z', '2026-10-08T19:00:00.000000Z', NULL),
  (6, 1, 'buy', '2026-10-01T12:00:00', 1, 1, NULL, NULL, 1, 9320700000, 112500, 'EUR', NULL, NULL, 'receipt', NULL, NULL, NULL, '2026-10-01T18:05:00.000000Z', '2026-10-01T18:05:00.000000Z', 1),
  (7, 3, 'buy', '2026-10-02T15:30:00', 3, 2, NULL, NULL, 4, 200000000, 32000, 'EUR', NULL, NULL, 'manual', NULL, NULL, NULL, '2026-10-02T16:00:00.000000Z', '2026-10-02T16:00:00.000000Z', 3),
  (8, 1, 'dividend', '2026-10-05T12:00:00', 1, 1, NULL, NULL, 1, 9320700000, 1234, 'EUR', '2026-09-25T00:00:00', 'Q3', 'manual', NULL, NULL, NULL, '2026-10-05T18:00:00.000000Z', '2026-10-05T18:00:00.000000Z', NULL),
  (9, 1, 'buy', '2026-09-15T12:00:00', 1, 1, NULL, NULL, 2, 48857000, 5000, 'EUR', NULL, NULL, 'pp_import', 'pp-transaction-9', NULL, 'Sparplan', '2026-10-08T19:00:00.000000Z', '2026-10-08T19:00:00.000000Z', NULL);

INSERT INTO transaction_units VALUES
  (1, 6, 'gross_value', 112500, 'EUR', NULL, NULL, NULL),
  (2, 7, 'gross_value', 31900, 'EUR', 34500, 'USD', 1.0815),
  (3, 7, 'fee', 100, 'EUR', NULL, NULL, NULL),
  (4, 8, 'tax', 300, 'EUR', NULL, NULL, NULL);

INSERT INTO savings_plans VALUES
  (2, 1, 'Sparplan MSCI World', NULL, 'purchase_or_delivery', 2, 1, 1, 0, '2026-09-15', 1, 5000, 0, 0, '{}', '2026-10-08T19:00:00.000000Z', '2026-10-08T19:00:00.000000Z');

INSERT INTO savings_plan_transactions VALUES (2, 9);

INSERT INTO taxonomies VALUES
  (1, 1, 'Anlageklassen', NULL, '["Anlageklasse"]', 'pp-taxonomy-1', '2026-10-08T19:00:00.000000Z', '2026-10-08T19:00:00.000000Z');

-- A child with a lower id than its parent, as a PP file may order them.
INSERT INTO classifications VALUES
  (7, 1, NULL, 'Anlageklassen', NULL, NULL, 10000, 0, 'pp-root', '2026-10-08T19:00:00.000000Z', '2026-10-08T19:00:00.000000Z'),
  (5, 1, 7, 'Aktien', NULL, '#1f77b4', 10000, 0, 'pp-equity', '2026-10-08T19:00:00.000000Z', '2026-10-08T19:00:00.000000Z');

INSERT INTO assignments VALUES
  (1, 5, 1, NULL, 10000, 0),
  (2, 7, NULL, 1, 10000, 1);

INSERT INTO exchange_rates VALUES
  (1, 'USD', '2026-10-09', 1.0823),
  (2, 'USD', '2026-10-12', 1.0791);

INSERT INTO job_runs VALUES (1, 'daily', '2026-10-12T16:05:00.000000Z', NULL);

INSERT INTO compositions VALUES
  (1, 1, '{"US":6200,"JP":550}', '{"Technology":2500}', '2026-10-10T08:00:00.000000Z');

INSERT INTO divvy_diary_dividends VALUES
  (1, 4, '2026-11-10', '2026-11-13', 26, 'USD', '2026-10-10T08:00:00.000000Z');
