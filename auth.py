from __future__ import annotations

import asyncio
import hashlib
import os
import re
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit, urlunsplit
from uuid import uuid4

from dotenv import load_dotenv

load_dotenv()

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pwdlib import PasswordHash
from sqlalchemy import DateTime, ForeignKey, Integer, String, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite+aiosqlite:///./luma_auth.db")
engine_connect_args: dict = {}
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql+asyncpg://", 1)
elif DATABASE_URL.startswith("postgresql://"):
    DATABASE_URL = DATABASE_URL.replace(
        "postgresql://",
        "postgresql+asyncpg://",
        1,
    )

if "asyncpg" in DATABASE_URL:
    parsed_db_url = urlsplit(DATABASE_URL)
    query_params = dict(
        param.split("=", 1) for param in parsed_db_url.query.split("&") if "=" in param
    )
    if (
        query_params.get("sslmode") in {"require", "verify-ca", "verify-full"}
        or query_params.get("ssl") in {"true", "require"}
        or "neon.tech" in parsed_db_url.netloc
    ):
        engine_connect_args["ssl"] = True
    clean_query = "&".join(
        f"{k}={v}" for k, v in query_params.items()
        if k not in {"sslmode", "channel_binding", "ssl"}
    )
    DATABASE_URL = urlunsplit((
        parsed_db_url.scheme,
        parsed_db_url.netloc,
        parsed_db_url.path,
        clean_query,
        parsed_db_url.fragment,
    ))

SESSION_COOKIE = "luma_session"
SESSION_LIFETIME = timedelta(days=30)
LOGIN_WINDOW = timedelta(minutes=15)
MAX_LOGIN_ATTEMPTS = 8
COOKIE_SECURE_SETTING = os.getenv("COOKIE_SECURE")
COOKIE_SECURE = (
    COOKIE_SECURE_SETTING.casefold() == "true"
    if COOKIE_SECURE_SETTING is not None
    else bool(os.getenv("VERCEL") or os.getenv("VERCEL_ENV"))
)
COOKIE_SAMESITE_SETTING = os.getenv("COOKIE_SAMESITE", "lax").casefold()
COOKIE_SAMESITE = (
    COOKIE_SAMESITE_SETTING
    if COOKIE_SAMESITE_SETTING in {"lax", "strict", "none"}
    else "lax"
)

_default_origins = [
    "http://127.0.0.1:8765",
    "http://localhost:8765",
    "http://127.0.0.1:8000",
    "http://localhost:8000",
]
_env_origins = os.getenv("ALLOWED_ORIGINS")
if _env_origins:
    ALLOWED_ORIGINS = {o.strip().rstrip("/") for o in _env_origins.split(",") if o.strip()}
else:
    ALLOWED_ORIGINS = {o.strip().rstrip("/") for o in _default_origins if o.strip()}

if os.getenv("FRONTEND_URL"):
    ALLOWED_ORIGINS.add(os.getenv("FRONTEND_URL").strip().rstrip("/"))

engine = create_async_engine(DATABASE_URL, connect_args=engine_connect_args, pool_pre_ping=True)
SessionFactory = async_sessionmaker(engine, expire_on_commit=False)
password_hasher = PasswordHash.recommended()
DUMMY_PASSWORD_HASH = password_hasher.hash(secrets.token_urlsafe(32))
router = APIRouter(prefix="/api/auth", tags=["authentication"])


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    full_name: Mapped[str] = mapped_column(String(100), nullable=False)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(512), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class AuthSession(Base):
    __tablename__ = "auth_sessions"

    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True, nullable=False)


class LoginAttempt(Base):
    __tablename__ = "login_attempts"

    email_digest: Mapped[str] = mapped_column(String(64), primary_key=True)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False)
    window_started_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=100)
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=12, max_length=128)

    @field_validator("full_name")
    @classmethod
    def normalize_name(cls, value: str) -> str:
        value = " ".join(value.split())
        if not value:
            raise ValueError("Full name is required.")
        return value

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        value = value.strip().casefold()
        if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value) is None:
            raise ValueError("Enter a valid email address.")
        return value


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        value = value.strip().casefold()
        if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value) is None:
            raise ValueError("Enter a valid email address.")
        return value


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    full_name: str
    email: str


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _email_digest(email: str) -> str:
    return hashlib.sha256(email.encode("utf-8")).hexdigest()


def _ensure_same_origin(request: Request) -> None:
    origin = request.headers.get("origin")
    if origin is None:
        return
    parsed_origin = urlsplit(origin)
    if (
        parsed_origin.scheme == request.url.scheme
        and parsed_origin.netloc == request.url.netloc
    ):
        return
    origin_base = f"{parsed_origin.scheme}://{parsed_origin.netloc}".rstrip("/")
    if origin_base in ALLOWED_ORIGINS:
        return
    if parsed_origin.netloc.endswith(".vercel.app") and parsed_origin.scheme in {"http", "https"}:
        return
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="This request could not be verified.",
    )


def _set_session_cookie(response: Response, token: str) -> None:
    response.set_cookie(
        key=SESSION_COOKIE,
        value=token,
        max_age=int(SESSION_LIFETIME.total_seconds()),
        httponly=True,
        secure=COOKIE_SECURE or (COOKIE_SAMESITE == "none"),
        samesite=COOKIE_SAMESITE,
        path="/",
    )


async def initialize_database() -> None:
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)


async def require_user(request: Request) -> User:
    if request.method not in {"GET", "HEAD", "OPTIONS"}:
        _ensure_same_origin(request)
    token = request.cookies.get(SESSION_COOKIE)
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required.",
        )
    async with SessionFactory() as db:
        user = await db.scalar(
            select(User)
            .join(AuthSession, AuthSession.user_id == User.id)
            .where(
                AuthSession.token_hash == _token_hash(token),
                AuthSession.expires_at > _utcnow(),
            )
        )
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required.",
        )
    return user


async def _add_session(db: AsyncSession, user_id: str) -> str:
    token = secrets.token_urlsafe(32)
    db.add(
        AuthSession(
            token_hash=_token_hash(token),
            user_id=user_id,
            expires_at=_utcnow() + SESSION_LIFETIME,
        )
    )
    return token


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(
    data: RegisterRequest,
    request: Request,
    response: Response,
) -> User:
    _ensure_same_origin(request)
    hashed_password = await asyncio.to_thread(password_hasher.hash, data.password)
    token: str
    try:
        async with SessionFactory.begin() as db:
            user = User(
                full_name=data.full_name,
                email=data.email,
                password_hash=hashed_password,
                created_at=_utcnow(),
            )
            db.add(user)
            await db.flush()
            token = await _add_session(db, user.id)
    except IntegrityError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Unable to create an account with this email. Try logging in instead.",
        ) from exc
    _set_session_cookie(response, token)
    return user


@router.post("/login", response_model=UserResponse)
async def login(
    data: LoginRequest,
    request: Request,
    response: Response,
) -> User:
    _ensure_same_origin(request)
    now = _utcnow()
    digest = _email_digest(data.email)
    outcome = "invalid"
    user: User | None = None
    token: str | None = None
    async with SessionFactory.begin() as db:
        attempt = await db.get(LoginAttempt, digest)
        if attempt and now - attempt.window_started_at >= LOGIN_WINDOW:
            await db.delete(attempt)
            attempt = None
        if attempt and attempt.attempts >= MAX_LOGIN_ATTEMPTS:
            outcome = "rate_limited"
        else:
            user = await db.scalar(select(User).where(User.email == data.email))
            stored_hash = user.password_hash if user else DUMMY_PASSWORD_HASH
            password_matches = await asyncio.to_thread(
                password_hasher.verify,
                data.password,
                stored_hash,
            )
            if user and password_matches:
                if attempt:
                    await db.delete(attempt)
                token = await _add_session(db, user.id)
                outcome = "success"
            elif attempt:
                attempt.attempts += 1
            else:
                db.add(
                    LoginAttempt(
                        email_digest=digest,
                        attempts=1,
                        window_started_at=now,
                    )
                )
    if outcome == "rate_limited":
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many sign-in attempts. Please try again later.",
        )
    if outcome != "success" or user is None or token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Email or password is incorrect.",
        )
    _set_session_cookie(response, token)
    return user


@router.get("/me", response_model=UserResponse)
async def current_user(user: User = Depends(require_user)) -> User:
    return user


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(request: Request) -> Response:
    _ensure_same_origin(request)
    token = request.cookies.get(SESSION_COOKIE)
    if token:
        async with SessionFactory.begin() as db:
            session = await db.get(AuthSession, _token_hash(token))
            if session:
                await db.delete(session)
    response = Response(status_code=status.HTTP_204_NO_CONTENT)
    response.delete_cookie(
        key=SESSION_COOKIE,
        httponly=True,
        secure=COOKIE_SECURE or (COOKIE_SAMESITE == "none"),
        samesite=COOKIE_SAMESITE,
        path="/",
    )
    return response
