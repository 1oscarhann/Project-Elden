"""Save-file API for the game client (SPEC §4, §7).

Four endpoints and a health check. All game logic is client-side; this service
exists so a browser save survives a cleared cache.

Security posture, since the spec called this "a glorified save file": the blob
is harmless, but the accounts table is not — people reuse passwords. So:
argon2id hashing, short-lived signed tokens, login rate limiting, a hard blob
size cap, and ownership checked on every slot access. See docs/REVIEW.md; if
you would rather not own credentials at all, the anonymous-save-id option
described there removes this whole surface.
"""

from __future__ import annotations

import os
import time
import uuid
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
import psycopg
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field, field_validator

DATABASE_URL = os.environ.get("DATABASE_URL", "")
JWT_SECRET = os.environ.get("JWT_SECRET", "")
JWT_ALGORITHM = "HS256"
TOKEN_TTL = timedelta(hours=int(os.environ.get("TOKEN_TTL_HOURS", "12")))

# Must match SaveFormat.MAX_BLOB_BYTES on the client.
MAX_BLOB_BYTES = 256 * 1024
MAX_SLOT_INDEX = 8

LOGIN_WINDOW_SECONDS = 300
LOGIN_MAX_ATTEMPTS = 8

# Browser builds are served from a different origin than the API.
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get("ALLOWED_ORIGINS", "*").split(",")
    if origin.strip()
]

pool: ConnectionPool | None = None
hasher = PasswordHasher()
bearer = HTTPBearer(auto_error=True)

# In-memory, so it resets on deploy and is per-instance. Good enough for one
# Render dyno; move to Postgres or Redis before scaling out.
_login_attempts: dict[str, deque[float]] = defaultdict(deque)


@asynccontextmanager
async def lifespan(_: FastAPI):
    global pool
    if not DATABASE_URL:
        raise RuntimeError("DATABASE_URL is not set")
    if not JWT_SECRET or len(JWT_SECRET) < 32:
        raise RuntimeError("JWT_SECRET must be set and at least 32 characters")
    pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=8, kwargs={"autocommit": True})
    pool.wait(timeout=30)
    yield
    pool.close()


app = FastAPI(title="Project Elden save API", version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)


# --- Models -----------------------------------------------------------------

class Credentials(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=10, max_length=256)

    @field_validator("username")
    @classmethod
    def username_charset(cls, value: str) -> str:
        if not value.replace("_", "").replace("-", "").isalnum():
            raise ValueError("username must be alphanumeric, _ or -")
        return value.lower()


class TokenResponse(BaseModel):
    token: str
    expires_at: datetime


class SaveRequest(BaseModel):
    slot_index: int = Field(ge=0, lt=MAX_SLOT_INDEX)
    data: dict[str, Any]


class LoadResponse(BaseModel):
    slot_index: int
    data: dict[str, Any]
    updated_at: datetime


# --- Helpers ----------------------------------------------------------------

def _connection():
    if pool is None:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "database not ready")
    return pool.connection()


def _issue_token(account_id: uuid.UUID) -> TokenResponse:
    expires_at = datetime.now(timezone.utc) + TOKEN_TTL
    token = jwt.encode(
        {"sub": str(account_id), "exp": expires_at},
        JWT_SECRET,
        algorithm=JWT_ALGORITHM,
    )
    return TokenResponse(token=token, expires_at=expires_at)


def current_account(
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
) -> uuid.UUID:
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return uuid.UUID(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or expired token") from None


def _rate_limit(request: Request, username: str) -> None:
    client_host = request.client.host if request.client else "unknown"
    key = f"{client_host}:{username}"
    now = time.monotonic()
    attempts = _login_attempts[key]
    while attempts and now - attempts[0] > LOGIN_WINDOW_SECONDS:
        attempts.popleft()
    if len(attempts) >= LOGIN_MAX_ATTEMPTS:
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "too many attempts, wait a bit")
    attempts.append(now)


def _reject_oversized(data: dict[str, Any]) -> None:
    import json

    if len(json.dumps(data).encode("utf-8")) > MAX_BLOB_BYTES:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            f"save exceeds {MAX_BLOB_BYTES} bytes",
        )


# --- Endpoints --------------------------------------------------------------

@app.get("/healthz")
def healthz() -> dict[str, str]:
    # Also the endpoint to ping on a schedule if you want to keep the free-tier
    # instance from cold-starting on a player's first login.
    return {"status": "ok"}


@app.post("/register", response_model=TokenResponse)
def register(body: Credentials) -> TokenResponse:
    password_hash = hasher.hash(body.password)
    with _connection() as conn:
        try:
            row = conn.execute(
                "INSERT INTO accounts (username, password_hash) VALUES (%s, %s) RETURNING id",
                (body.username, password_hash),
            ).fetchone()
        except psycopg.errors.UniqueViolation:
            raise HTTPException(status.HTTP_409_CONFLICT, "username taken") from None
    return _issue_token(row[0])


@app.post("/login", response_model=TokenResponse)
def login(body: Credentials, request: Request) -> TokenResponse:
    _rate_limit(request, body.username)

    with _connection() as conn:
        row = conn.execute(
            "SELECT id, password_hash FROM accounts WHERE username = %s",
            (body.username,),
        ).fetchone()

    if row is None:
        # Spend the same time as a real verify so the response doesn't leak
        # whether the username exists.
        hasher.hash(body.password)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "bad credentials")

    account_id, password_hash = row
    try:
        hasher.verify(password_hash, body.password)
    except VerifyMismatchError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "bad credentials") from None

    if hasher.check_needs_rehash(password_hash):
        with _connection() as conn:
            conn.execute(
                "UPDATE accounts SET password_hash = %s WHERE id = %s",
                (hasher.hash(body.password), account_id),
            )

    return _issue_token(account_id)


@app.post("/save")
def save(body: SaveRequest, account_id: uuid.UUID = Depends(current_account)) -> dict[str, Any]:
    _reject_oversized(body.data)

    with _connection() as conn:
        row = conn.execute(
            """
            INSERT INTO save_slots (account_id, slot_index, data)
            VALUES (%s, %s, %s)
            ON CONFLICT ON CONSTRAINT save_slots_account_slot_key
            DO UPDATE SET data = EXCLUDED.data, updated_at = now()
            RETURNING updated_at
            """,
            (account_id, body.slot_index, psycopg.types.json.Jsonb(body.data)),
        ).fetchone()

    return {"ok": True, "slot_index": body.slot_index, "updated_at": row[0]}


@app.get("/load", response_model=LoadResponse)
def load(slot_index: int, account_id: uuid.UUID = Depends(current_account)) -> LoadResponse:
    if not 0 <= slot_index < MAX_SLOT_INDEX:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "bad slot index")

    with _connection() as conn:
        conn.row_factory = dict_row
        # account_id in the WHERE clause is the ownership check — never trust a
        # slot id handed in by the client.
        row = conn.execute(
            """
            SELECT slot_index, data, updated_at FROM save_slots
            WHERE account_id = %s AND slot_index = %s
            """,
            (account_id, slot_index),
        ).fetchone()

    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no save in that slot")
    return LoadResponse(**row)
