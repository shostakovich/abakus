-- The former shared-expenses app's database, as its migrations created it, with data that covers every table.
CREATE TABLE IF NOT EXISTS "participants" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL COLLATE NOCASE CONSTRAINT participants_name_check CHECK (length(trim(name)) > 0), "archived_at" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE UNIQUE INDEX "participants_name_index" ON "participants" ("name");
CREATE TABLE IF NOT EXISTS "categories" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL COLLATE NOCASE CONSTRAINT categories_name_check CHECK (length(trim(name)) > 0), "position" INTEGER DEFAULT 0 NOT NULL, "archived_at" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE UNIQUE INDEX "categories_name_index" ON "categories" ("name");
CREATE TABLE IF NOT EXISTS "settings" ("id" INTEGER CONSTRAINT settings_id_check CHECK (id = 1) PRIMARY KEY, "group_name" TEXT NOT NULL, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS "recurring_expenses" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "template" TEXT NOT NULL, "frequency" TEXT NOT NULL CONSTRAINT recurring_expenses_frequency_check CHECK (frequency IN ('weekly', 'monthly', 'yearly')), "start_date" TEXT NOT NULL, "next_date" TEXT NOT NULL, "active" INTEGER DEFAULT true NOT NULL CONSTRAINT recurring_expenses_active_check CHECK (active IN (0, 1)), "created_by_id" INTEGER CONSTRAINT "recurring_expenses_created_by_id_fkey" REFERENCES "participants"("id"), "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE INDEX "recurring_expenses_next_date_index" ON "recurring_expenses" ("next_date") WHERE active = 1;
CREATE TABLE IF NOT EXISTS "expenses" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "title" TEXT NOT NULL, "title_folded" TEXT NOT NULL, "date" TEXT NOT NULL, "category_id" INTEGER CONSTRAINT "expenses_category_id_fkey" REFERENCES "categories"("id"), "paid_by_id" INTEGER NOT NULL CONSTRAINT "expenses_paid_by_id_fkey" REFERENCES "participants"("id"), "notes" TEXT DEFAULT '' NOT NULL, "notes_folded" TEXT DEFAULT '' NOT NULL, "reimbursement" INTEGER DEFAULT false NOT NULL CONSTRAINT expenses_reimbursement_check CHECK (reimbursement IN (0, 1)), "split_mode" TEXT NOT NULL CONSTRAINT expenses_split_mode_check CHECK (split_mode IN ('equal', 'shares', 'percent', 'amount')), "amount_cents" INTEGER NOT NULL CONSTRAINT expenses_amount_cents_check CHECK (amount_cents > 0), "original_amount" INTEGER NOT NULL, "original_currency" TEXT DEFAULT 'EUR' NOT NULL, "fx_rate" REAL DEFAULT 1.0 NOT NULL, "fx_source" TEXT CONSTRAINT expenses_fx_source_check CHECK (fx_source IN ('ecb', 'manual')), "recurring_expense_id" INTEGER CONSTRAINT "expenses_recurring_expense_id_fkey" REFERENCES "recurring_expenses"("id") ON DELETE SET NULL, "deleted_at" TEXT, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE INDEX "expenses_date_index" ON "expenses" (date DESC, id DESC) WHERE deleted_at IS NULL;
CREATE INDEX "expenses_paid_by_id_index" ON "expenses" ("paid_by_id");
CREATE INDEX "expenses_category_id_index" ON "expenses" ("category_id");
CREATE UNIQUE INDEX "expenses_recurring_expense_id_date_index" ON "expenses" ("recurring_expense_id", "date") WHERE recurring_expense_id IS NOT NULL;
CREATE TABLE IF NOT EXISTS "expense_shares" ("expense_id" INTEGER NOT NULL CONSTRAINT "expense_shares_expense_id_fkey" REFERENCES "expenses"("id") ON DELETE CASCADE, "participant_id" INTEGER NOT NULL CONSTRAINT "expense_shares_participant_id_fkey" REFERENCES "participants"("id"), "weight" INTEGER NOT NULL, "amount_cents" INTEGER NOT NULL, PRIMARY KEY ("expense_id","participant_id")) WITHOUT ROWID;
CREATE INDEX "expense_shares_participant_id_index" ON "expense_shares" ("participant_id");
CREATE TABLE IF NOT EXISTS "activities" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "actor_id" INTEGER CONSTRAINT "activities_actor_id_fkey" REFERENCES "participants"("id"), "action" TEXT NOT NULL CONSTRAINT activities_action_check CHECK (action IN ('expense_created', 'expense_updated', 'expense_deleted', 'settings_updated', 'recurring_created', 'recurring_deleted')), "expense_id" INTEGER CONSTRAINT "activities_expense_id_fkey" REFERENCES "expenses"("id"), "details" TEXT DEFAULT ('{}') NOT NULL, "inserted_at" TEXT NOT NULL);
CREATE INDEX "activities_expense_id_index" ON "activities" ("expense_id");
CREATE TABLE IF NOT EXISTS "fx_rates" ("currency" TEXT NOT NULL, "source" TEXT NOT NULL CONSTRAINT fx_rates_source_check CHECK (source IN ('ecb', 'manual')), "date" TEXT NOT NULL, "rate" REAL NOT NULL CONSTRAINT fx_rates_rate_check CHECK (rate > 0), PRIMARY KEY ("currency","source","date")) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS "ynab_connections" ("participant_id" INTEGER NOT NULL PRIMARY KEY CONSTRAINT "ynab_connections_participant_id_fkey" REFERENCES "participants"("id"), "token" TEXT, "plan_id" TEXT, "account_id" TEXT, "start_date" TEXT, "connected_at" TEXT, "last_run_at" TEXT, "last_synced_at" TEXT, "summary" TEXT, "error" TEXT, "token_invalid" INTEGER DEFAULT false NOT NULL CONSTRAINT ynab_connections_token_invalid_check CHECK (token_invalid IN (0, 1)), "retry_at" TEXT, "backoff_seconds" INTEGER DEFAULT 0 NOT NULL, "inserted_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS "ynab_category_mappings" ("participant_id" INTEGER NOT NULL CONSTRAINT "ynab_category_mappings_participant_id_fkey" REFERENCES "participants"("id"), "category_id" INTEGER NOT NULL CONSTRAINT "ynab_category_mappings_category_id_fkey" REFERENCES "categories"("id"), "ynab_category_id" TEXT NOT NULL, PRIMARY KEY ("participant_id","category_id")) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS "ynab_transactions" ("expense_id" INTEGER NOT NULL CONSTRAINT "ynab_transactions_expense_id_fkey" REFERENCES "expenses"("id"), "participant_id" INTEGER NOT NULL CONSTRAINT "ynab_transactions_participant_id_fkey" REFERENCES "participants"("id"), "ynab_transaction_id" TEXT, "state" TEXT DEFAULT 'unknown' NOT NULL CONSTRAINT ynab_transactions_state_check CHECK (state IN ('unknown', 'synced', 'pending', 'retarget', 'failed', 'delete_failed')), "fingerprint" TEXT, "synced_at" TEXT, "last_error" TEXT, PRIMARY KEY ("expense_id","participant_id")) WITHOUT ROWID;
CREATE INDEX "ynab_transactions_participant_id_index" ON "ynab_transactions" ("participant_id");

INSERT INTO participants VALUES
  (1, 'Anna', NULL, '2024-02-01T09:00:00.000000Z', '2024-02-01T09:00:00.000000Z'),
  (2, 'Ben', NULL, '2024-02-01T09:05:00.000000Z', '2024-02-01T09:05:00.000000Z'),
  (5, 'Cleo', '2025-06-30T12:00:00.000000Z', '2024-03-01T10:00:00.000000Z', '2025-06-30T12:00:00.000000Z');

INSERT INTO categories VALUES
  (1, 'Lebensmittel', 10, NULL, '2024-02-01T08:00:00.000000Z', '2024-02-01T08:00:00.000000Z'),
  (2, 'Restaurant', 20, NULL, '2024-02-01T08:00:00.000000Z', '2024-02-01T08:00:00.000000Z'),
  (4, 'Miete & Nebenkosten', 40, NULL, '2024-02-01T08:00:00.000000Z', '2024-02-01T08:00:00.000000Z'),
  (10, 'Sonstiges', 1000, NULL, '2024-02-01T08:00:00.000000Z', '2024-02-01T08:00:00.000000Z'),
  (11, 'Katze', 50, '2025-01-01T00:00:00.000000Z', '2024-05-01T08:00:00.000000Z', '2025-01-01T00:00:00.000000Z');

INSERT INTO settings VALUES (1, 'WG Sonnenblick', '2024-02-01T08:00:00.000000Z', '2024-02-02T08:00:00.000000Z');

INSERT INTO recurring_expenses VALUES
  (3, '{"title":"Miete","category_id":4,"paid_by_id":1,"notes":"","reimbursement":false,"split_mode":"percent","amount_cents":120000,"original_amount":120000,"original_currency":"EUR","fx_rate":null,"fx_source":null,"parts":[{"participant_id":1,"weight":6000},{"participant_id":2,"weight":4000}]}',
   'monthly', '2026-09-01', '2026-11-01', 1, 1, '2026-09-01T07:00:00.000000Z', '2026-10-01T07:00:00.000000Z');

INSERT INTO expenses VALUES
  (7, 'Rewe', 'rewe', '2026-09-15', 1, 1, '', '', 0, 'equal', 3000, 3000, 'EUR', 1.0, NULL, NULL, NULL, '2026-09-15T17:00:00.000000Z', '2026-09-15T17:00:00.000000Z'),
  (9, 'Miete', 'miete', '2026-10-01', 4, 1, '', '', 0, 'percent', 120000, 120000, 'EUR', 1.0, NULL, 3, NULL, '2026-10-01T07:00:00.000000Z', '2026-10-01T07:00:00.000000Z'),
  (12, 'Rückzahlung', 'rückzahlung', '2026-10-02', NULL, 2, 'Überweisung', 'überweisung', 1, 'equal', 4200, 4200, 'EUR', 1.0, NULL, NULL, NULL, '2026-10-02T18:00:00.000000Z', '2026-10-02T18:00:00.000000Z'),
  (13, 'Kino', 'kino', '2026-10-03', 2, 2, '', '', 0, 'equal', 2400, 2400, 'EUR', 1.0, NULL, NULL, '2026-10-04T09:00:00.000000Z', '2026-10-03T21:00:00.000000Z', '2026-10-04T09:00:00.000000Z'),
  (15, 'Diner NYC', 'diner nyc', '2026-10-05', 2, 1, 'Urlaub', 'urlaub', 0, 'shares', 4450, 5000, 'USD', 1.1236, 'ecb', NULL, NULL, '2026-10-06T08:00:00.000000Z', '2026-10-06T08:00:00.000000Z');

INSERT INTO expense_shares VALUES
  (7, 1, 1, 1500), (7, 2, 1, 1500),
  (9, 1, 6000, 72000), (9, 2, 4000, 48000),
  (12, 1, 0, 4200),
  (13, 1, 1, 1200), (13, 2, 1, 1200),
  (15, 1, 2, 2967), (15, 2, 1, 1483);

INSERT INTO activities VALUES
  (1, NULL, 'settings_updated', NULL, '{"text":"Person „Anna“ hinzugefügt"}', '2024-02-01T09:00:00.000000Z'),
  (30, 1, 'expense_created', 7, '{"title":"Rewe","amount_cents":3000}', '2026-09-15T17:00:00.000000Z'),
  (31, 2, 'expense_deleted', 13, '{"title":"Kino","amount_cents":2400}', '2026-10-04T09:00:00.000000Z'),
  (32, 1, 'expense_updated', 15, '{"title":"Diner NYC","amount_cents":4450,"changes":[{"field":"Notiz","old":"","new":"Urlaub"}]}', '2026-10-06T08:30:00.000000Z');

INSERT INTO fx_rates VALUES ('USD', 'ecb', '2026-10-05', 1.1236), ('USD', 'manual', '2026-10-01', 1.15);

INSERT INTO ynab_connections VALUES
  (1, 'secret-token-123', 'plan-1', 'acc-geteilt', '2026-09-01', '2026-09-01T10:00:00.000000Z', '2026-10-06T09:00:00.000000Z', '2026-10-06T09:00:00.000000Z', '0 neu · 1 geändert · 0 gelöscht', NULL, 0, NULL, 0, '2026-09-01T10:00:00.000000Z', '2026-10-06T09:00:00.000000Z');

INSERT INTO ynab_category_mappings VALUES (1, 1, 'cat-food'), (1, 4, 'cat-rent');

INSERT INTO ynab_transactions VALUES
  (7, 1, 'ynab-7', 'synced', '77f57959a88afc4c444f0d59e0e04893', '2026-09-15T17:01:00.000000Z', NULL),
  (9, 1, 'ynab-9', 'synced', '517c4a626446ceae16a6c254ccbd93e6', '2026-10-01T07:01:00.000000Z', NULL),
  (15, 1, 'ynab-15', 'synced', 'b8721a32f1fb25a3122ec614aa2e846c', '2026-10-06T09:00:00.000000Z', NULL);
