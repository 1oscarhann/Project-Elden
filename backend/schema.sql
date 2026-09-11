-- Neon Postgres schema (SPEC §7). Deliberately dumb: one JSON blob per save.
--
-- Differences from the spec sheet, both deliberate (see docs/REVIEW.md):
--   * UNIQUE (account_id, slot_index) — without it one account can hold five
--     rows for slot 0 and /load returns whichever the planner feels like.
--   * an index on account_id, which every load hits.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS accounts (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    username      text UNIQUE NOT NULL,
    password_hash text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS save_slots (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    slot_index int  NOT NULL CHECK (slot_index >= 0 AND slot_index < 8),
    data       jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT save_slots_account_slot_key UNIQUE (account_id, slot_index)
);

CREATE INDEX IF NOT EXISTS save_slots_account_id_idx ON save_slots (account_id);
