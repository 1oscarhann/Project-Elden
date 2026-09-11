# Save API

FastAPI + Neon Postgres. Four endpoints and a health check (SPEC §7). This is
build-order step 7 — it is not on the critical path for proving the game fun,
and the client works fully without it.

## Run locally

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # fill in DATABASE_URL and JWT_SECRET
psql "$DATABASE_URL" -f schema.sql
uvicorn main:app --reload
```

## Deploy (Render)

- Build: `pip install -r requirements.txt`
- Start: `uvicorn main:app --host 0.0.0.0 --port $PORT`
- Env: `DATABASE_URL`, `JWT_SECRET`, `ALLOWED_ORIGINS`

Then point the client at it:

```gdscript
SaveManager.api_base_url = "https://your-api.onrender.com"
```

**Cold starts.** A sleeping free-tier instance takes tens of seconds to wake,
which will look like the game is broken if login is on the boot path. It isn't:
`SaveManager` boots from the local save and syncs in the background. If you want
to paper over it anyway, ping `/healthz` on a schedule.

## Endpoints

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| `GET`  | `/healthz` | — | liveness |
| `POST` | `/register` | — | returns a bearer token |
| `POST` | `/login` | — | rate limited per IP+username |
| `POST` | `/save` | bearer | upserts one slot, 256 KB cap |
| `GET`  | `/load?slot_index=N` | bearer | 404 if the slot is empty |

## Notes

- Passwords are argon2id. Unknown usernames still pay a hash so the response
  time doesn't leak account existence.
- Ownership is enforced by `account_id` in the `WHERE` clause — the client
  never names a row id.
- Rate limiting is in-process, so it resets on deploy and is per-instance.
  Move it to Postgres or Redis before running more than one dyno.
- Saves are client-authoritative and trivially forgeable. Fine for
  single-player; do not build a leaderboard on them.
