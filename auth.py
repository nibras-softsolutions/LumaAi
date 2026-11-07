from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import io
import json
import logging
import os
from pathlib import Path
import re
import secrets
import time
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit, urlunsplit
from uuid import uuid4

from dotenv import load_dotenv
import httpx
from PIL import Image, ImageOps

from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

load_dotenv()

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator
from pwdlib import PasswordHash
from pwdlib.hashers.bcrypt import BcryptHasher
from pwdlib.hashers.argon2 import Argon2Hasher
from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, delete, func, select
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

logger = logging.getLogger("auth")

SESSION_COOKIE = "luma_session"
SESSION_LIFETIME = timedelta(days=30)
LOGIN_WINDOW = timedelta(minutes=15)
MAX_LOGIN_ATTEMPTS = 8


def is_production_environment() -> bool:
    """Detect whether the application is running in a production or deployed cloud environment.

    Checks:
    - Render platform (RENDER='true', RENDER_SERVICE_ID, RENDER_INSTANCE_ID, RENDER_EXTERNAL_HOSTNAME)
    - Vercel platform (VERCEL='1'/'true', VERCEL_ENV in {'production', 'preview'})
    - Standard application environment variables (ENVIRONMENT, ENV, APP_ENV, FASTAPI_ENV in {'production', 'prod', 'staging', 'live'})
    """
    # 1. Render platform detection (Render automatically sets RENDER="true" on all deployed services)
    if os.getenv("RENDER", "").strip().casefold() in {"true", "1"}:
        return True
    if any(
        os.getenv(k)
        for k in (
            "RENDER_SERVICE_ID",
            "RENDER_INSTANCE_ID",
            "RENDER_EXTERNAL_HOSTNAME",
            "RENDER_EXTERNAL_URL",
        )
    ):
        return True

    # 2. Vercel platform detection
    if os.getenv("VERCEL", "").strip().casefold() in {"true", "1"}:
        return True
    if os.getenv("VERCEL_ENV", "").strip().casefold() in {"production", "preview"}:
        return True

    # 3. Standard environment variable conventions
    for env_key in ("ENVIRONMENT", "ENV", "APP_ENV", "FASTAPI_ENV"):
        val = os.getenv(env_key, "").strip().casefold()
        if val in {"production", "prod", "staging", "live"}:
            return True

    return False


def get_cookie_samesite() -> str:
    """Return the validated SameSite policy for session cookies ('lax', 'strict', or 'none')."""
    setting = os.getenv("COOKIE_SAMESITE")
    if setting is not None:
        val = setting.strip().casefold()
        if val in {"lax", "strict", "none"}:
            return val
    mod_val = globals().get("COOKIE_SAMESITE")
    if isinstance(mod_val, str) and mod_val.casefold() in {"lax", "strict", "none"}:
        return mod_val.casefold()
    return "lax"


def is_cookie_secure() -> bool:
    """Determine whether session cookies must be marked with the Secure flag.

    Security rules:
    1. If running in production (Render, Vercel, or production ENV), Secure is ALWAYS
       enforced (True). An unsafe setting such as COOKIE_SECURE=false in production is
       explicitly overridden and logged as a warning to prevent misconfiguration.
    2. If COOKIE_SAMESITE is 'none', Secure is ALWAYS enforced (browsers reject SameSite=None
       without Secure).
    3. In local development / non-production, COOKIE_SECURE defaults to False to allow
       localhost HTTP development, but can be opted into via COOKIE_SECURE=true.
    """
    samesite = get_cookie_samesite()
    if samesite == "none":
        return True

    in_prod = is_production_environment()
    raw_setting = os.getenv("COOKIE_SECURE")

    if in_prod:
        if raw_setting is not None and raw_setting.strip().casefold() in {"false", "0", "no", "off"}:
            logger.warning(
                "SECURITY WARNING: COOKIE_SECURE is set to %r in a production environment. "
                "Overriding to Secure=True to protect session cookies from transmission over unencrypted HTTP.",
                raw_setting,
            )
        return True

    if raw_setting is not None:
        return raw_setting.strip().casefold() in {"true", "1", "yes", "on"}

    module_secure = globals().get("COOKIE_SECURE")
    if module_secure is True:
        return True

    return False


def _get_cookie_attributes() -> tuple[bool, str]:
    """Resolve active (secure, samesite) settings, enforcing production security guarantees."""
    secure = is_cookie_secure()
    samesite = get_cookie_samesite()
    if samesite == "none":
        secure = True
    return secure, samesite


COOKIE_SECURE = is_cookie_secure()
COOKIE_SAMESITE = get_cookie_samesite()

_default_origins = [
    "http://127.0.0.1:8765",
    "http://localhost:8765",
    "http://127.0.0.1:8000",
    "http://localhost:8000",
    "https://luma-ai-bay.vercel.app",
    "https://luma-ai.vercel.app",
    "https://lumaai-j0u3.onrender.com",
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
password_hasher = PasswordHash((BcryptHasher(rounds=12), Argon2Hasher()))
DUMMY_PASSWORD_HASH = password_hasher.hash(secrets.token_urlsafe(32))

_seen_nonces: dict[str, float] = {}
_signing_keys_cache: dict[str, tuple[str, str, datetime]] = {}
NONCE_EXPIRATION_SECONDS = 300
CSRF_COOKIE = "luma_csrf_token"

router = APIRouter(prefix="/api/auth", tags=["authentication"])


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    full_name: Mapped[str] = mapped_column(String(100), nullable=False)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(512), nullable=False)
    profile_image_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    profile_image_data: Mapped[str | None] = mapped_column(Text, nullable=True)
    custom_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    bio: Mapped[str | None] = mapped_column(String(250), nullable=True)
    avatar_emoji: Mapped[str | None] = mapped_column(String(32), nullable=True)
    avatar_color_hex: Mapped[str | None] = mapped_column(String(16), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    updated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class ConversationModel(Base):
    __tablename__ = "chat_conversations"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: str(uuid4()))
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False, default="New Conversation")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)


class ChatMessageModel(Base):
    __tablename__ = "chat_messages"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=lambda: str(uuid4()))
    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("chat_conversations.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    role: Mapped[str] = mapped_column(String(20), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="complete")
    image_attachment: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)


class CustomCharacterModel(Base):
    __tablename__ = "custom_characters"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    system_prompt: Mapped[str] = mapped_column(String(4000), nullable=False)
    avatar_emoji: Mapped[str] = mapped_column(String(32), nullable=False, default="✨")
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


class SigningKeyModel(Base):
    __tablename__ = "signing_keys"

    key_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    secret: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)


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


GOOGLE_IOS_CLIENT_ID = os.getenv(
    "GOOGLE_IOS_CLIENT_ID",
    "172474086048-ke3r4ekgdm0vcak48j1bvqqb6msrmubh.apps.googleusercontent.com",
).strip()
GOOGLE_WEB_CLIENT_ID = os.getenv(
    "GOOGLE_WEB_CLIENT_ID",
    "172474086048-02bpfth3nc9md882lhc22bkfl2raojpd.apps.googleusercontent.com",
).strip()
ALLOWED_GOOGLE_AUDIENCES = {GOOGLE_IOS_CLIENT_ID, GOOGLE_WEB_CLIENT_ID}


class GoogleLoginRequest(BaseModel):
    id_token: str | None = None
    idToken: str | None = None

    @field_validator("id_token", "idToken", mode="before")
    @classmethod
    def clean_token(cls, v: str | None) -> str | None:
        if isinstance(v, str):
            v = v.strip()
            return v if v else None
        return v

    def get_token(self) -> str:
        token = self.id_token or self.idToken
        if not token:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Google ID token is required.",
            )
        return token


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    full_name: str
    email: str
    profile_image_url: str | None = None
    custom_name: str | None = None
    bio: str | None = None
    avatar_emoji: str | None = None
    avatar_color_hex: str | None = None
    updated_at: datetime | None = None


class UpdateProfileRequest(BaseModel):
    custom_name: str | None = None
    bio: str | None = None
    avatar_emoji: str | None = None
    avatar_color_hex: str | None = None
    profile_image_url: str | None = None


class UploadPhotoPayload(BaseModel):
    image: str


class CustomCharacterSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    system_prompt: str
    avatar_emoji: str = "✨"
    created_at: datetime | None = None


class CreateCustomCharacterPayload(BaseModel):
    id: str | None = None
    name: str = Field(min_length=1, max_length=100)
    system_prompt: str = Field(min_length=1, max_length=4000)
    avatar_emoji: str = Field(default="✨", max_length=32)


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
    secure, samesite = _get_cookie_attributes()
    response.set_cookie(
        key=SESSION_COOKIE,
        value=token,
        max_age=int(SESSION_LIFETIME.total_seconds()),
        httponly=True,
        secure=secure,
        samesite=samesite,
        path="/",
    )
    csrf_token = secrets.token_urlsafe(32)
    response.set_cookie(
        key=CSRF_COOKIE,
        value=csrf_token,
        max_age=int(SESSION_LIFETIME.total_seconds()),
        httponly=False,
        secure=secure,
        samesite=samesite,
        path="/",
    )


def _clear_session_cookie(response: Response) -> None:
    secure, samesite = _get_cookie_attributes()
    response.delete_cookie(
        key=SESSION_COOKIE,
        httponly=True,
        secure=secure,
        samesite=samesite,
        path="/",
    )
    response.delete_cookie(
        key=CSRF_COOKIE,
        httponly=False,
        secure=secure,
        samesite=samesite,
        path="/",
    )


def _verify_csrf(request: Request) -> None:
    if request.method in {"GET", "HEAD", "OPTIONS"}:
        return
    _ensure_same_origin(request)
    if SESSION_COOKIE in request.cookies:
        csrf_cookie = request.cookies.get(CSRF_COOKIE)
        csrf_header = request.headers.get("x-csrf-token")
        if csrf_header:
            if not csrf_cookie or not hmac.compare_digest(csrf_cookie, csrf_header):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="CSRF token validation failed.",
                )


def _prune_nonces_and_keys():
    now_ts = time.time()
    expired_nonces = [n for n, ts in _seen_nonces.items() if now_ts - ts > NONCE_EXPIRATION_SECONDS]
    for n in expired_nonces:
        _seen_nonces.pop(n, None)

    now_dt = _utcnow()
    expired_keys = [k for k, (_, _, exp) in _signing_keys_cache.items() if exp <= now_dt]
    for k in expired_keys:
        _signing_keys_cache.pop(k, None)


def _revoke_user_signing_keys(user_id: str):
    to_remove = [k for k, (uid, _, _) in _signing_keys_cache.items() if uid == user_id]
    for k in to_remove:
        _signing_keys_cache.pop(k, None)


def _validate_image_magic_bytes(data: bytes) -> str:
    if len(data) < 12:
        raise HTTPException(status_code=400, detail="File too small to be a valid image.")
    if data.startswith(b"\xFF\xD8\xFF"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp"
    raise HTTPException(
        status_code=400,
        detail="Invalid file type. Only JPEG, PNG, and WebP images are permitted.",
    )


def compute_request_signature(
    secret: str,
    method: str,
    path: str,
    timestamp: str | int,
    nonce: str,
    body: bytes | str | None = None,
) -> str:
    if isinstance(body, str):
        body_bytes = body.encode("utf-8")
    elif body is None:
        body_bytes = b""
    else:
        body_bytes = body

    body_hash = hashlib.sha256(body_bytes).hexdigest()
    canonical = f"{method.upper()}\n{path}\n{str(timestamp)}\n{nonce}\n{body_hash}"
    return hmac.new(secret.encode("utf-8"), canonical.encode("utf-8"), hashlib.sha256).hexdigest()


async def verify_request_signature(
    request: Request,
    user: User,
    required: bool = False,
) -> tuple[str, str] | None:
    signature = request.headers.get("x-signature")
    timestamp_str = request.headers.get("x-timestamp")
    nonce = request.headers.get("x-nonce")
    key_id = request.headers.get("x-key-id")

    if not signature and not timestamp_str and not nonce and not key_id:
        if not required:
            return None
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Request integrity signature required. Missing X-Signature, X-Timestamp, X-Nonce, or X-Key-Id.",
        )

    if not (signature and timestamp_str and nonce and key_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Incomplete request integrity headers. X-Signature, X-Timestamp, X-Nonce, and X-Key-Id are all required.",
        )

    _prune_nonces_and_keys()

    try:
        if timestamp_str.isdigit() or (timestamp_str.startswith("-") and timestamp_str[1:].isdigit()):
            ts = float(timestamp_str)
        else:
            ts = datetime.fromisoformat(timestamp_str.replace("Z", "+00:00")).timestamp()
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid X-Timestamp header format.",
        )

    now_ts = time.time()
    if abs(now_ts - ts) > NONCE_EXPIRATION_SECONDS:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Request signature timestamp expired or skewed beyond tolerance (max 300s).",
        )

    if nonce in _seen_nonces:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Replay attack detected: nonce has already been used.",
        )

    secret: str | None = None
    if key_id in _signing_keys_cache:
        k_user_id, k_secret, k_exp = _signing_keys_cache[key_id]
        if k_user_id == user.id and k_exp > _utcnow():
            secret = k_secret

    if secret is None:
        async with SessionFactory() as db:
            db_key = await db.get(SigningKeyModel, key_id)
            if db_key and db_key.user_id == user.id and db_key.expires_at > _utcnow():
                secret = db_key.secret
                _signing_keys_cache[key_id] = (db_key.user_id, db_key.secret, db_key.expires_at)

    if secret is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Signing key is invalid, expired, or revoked.",
        )

    body_bytes = await request.body()
    body_hash = hashlib.sha256(body_bytes).hexdigest()
    canonical = f"{request.method.upper()}\n{request.url.path}\n{timestamp_str}\n{nonce}\n{body_hash}"

    expected_sig = hmac.new(
        secret.encode("utf-8"),
        canonical.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    if not hmac.compare_digest(signature.lower(), expected_sig.lower()):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid request signature. Request tampering detected.",
        )

    _seen_nonces[nonce] = now_ts
    return key_id, secret


def sign_response(response: Response, secret: str, nonce: str) -> None:
    now_ts = str(int(_utcnow().timestamp()))
    body_bytes = getattr(response, "body", b"")
    body_hash = hashlib.sha256(body_bytes).hexdigest()
    canonical = f"RESPONSE\n{now_ts}\n{nonce}\n{body_hash}"
    sig = hmac.new(secret.encode("utf-8"), canonical.encode("utf-8"), hashlib.sha256).hexdigest()
    response.headers["X-Response-Timestamp"] = now_ts
    response.headers["X-Response-Nonce"] = nonce
    response.headers["X-Response-Signature"] = sig


# ==============================================================================
# Application-Layer Encryption & Anti-Replay System (RSA-OAEP + AES-256-GCM)
# ==============================================================================
_SERVER_ENCRYPTION_PRIVATE_KEY: rsa.RSAPrivateKey | None = None
_SERVER_ENCRYPTION_PUBLIC_KEY_PEM: str | None = None


def get_server_encryption_key_pair() -> tuple[rsa.RSAPrivateKey, str]:
    global _SERVER_ENCRYPTION_PRIVATE_KEY, _SERVER_ENCRYPTION_PUBLIC_KEY_PEM
    if _SERVER_ENCRYPTION_PRIVATE_KEY is not None and _SERVER_ENCRYPTION_PUBLIC_KEY_PEM is not None:
        return _SERVER_ENCRYPTION_PRIVATE_KEY, _SERVER_ENCRYPTION_PUBLIC_KEY_PEM

    env_pem = os.getenv("SERVER_ENCRYPTION_PRIVATE_KEY_PEM")
    if env_pem:
        try:
            _SERVER_ENCRYPTION_PRIVATE_KEY = serialization.load_pem_private_key(
                env_pem.encode("utf-8"),
                password=None,
            )
        except Exception:
            _SERVER_ENCRYPTION_PRIVATE_KEY = None

    if _SERVER_ENCRYPTION_PRIVATE_KEY is None:
        _SERVER_ENCRYPTION_PRIVATE_KEY = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )

    _SERVER_ENCRYPTION_PUBLIC_KEY_PEM = _SERVER_ENCRYPTION_PRIVATE_KEY.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode("utf-8")

    return _SERVER_ENCRYPTION_PRIVATE_KEY, _SERVER_ENCRYPTION_PUBLIC_KEY_PEM


def decrypt_request_envelope(body_bytes: bytes) -> tuple[dict, bytes | None]:
    """
    Inspects request body. If encrypted envelope is present, decrypts ephemeral AES key
    via RSA-OAEP SHA-256, decrypts payload with AES-256-GCM, validates timestamp & nonce
    for replay protection, and returns (payload_dict, aes_key).
    If body is standard unencrypted JSON, returns (parsed_json_dict, None).
    """
    if not body_bytes:
        return {}, None
    try:
        data = json.loads(body_bytes.decode("utf-8"))
    except Exception:
        return {}, None

    if not isinstance(data, dict) or not data.get("encrypted"):
        return data, None

    enc_key_b64 = data.get("enc_key")
    iv_b64 = data.get("iv")
    ciphertext_b64 = data.get("ciphertext")

    if not (enc_key_b64 and iv_b64 and ciphertext_b64):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Malformed encrypted payload envelope.",
        )

    priv_key, _ = get_server_encryption_key_pair()

    try:
        enc_key_bytes = base64.b64decode(enc_key_b64)
        client_aes_key = priv_key.decrypt(
            enc_key_bytes,
            padding.OAEP(
                mgf=padding.MGF1(algorithm=hashes.SHA256()),
                algorithm=hashes.SHA256(),
                label=None,
            ),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to decrypt request key. Invalid encryption parameters.",
        ) from exc

    try:
        iv_bytes = base64.b64decode(iv_b64)
        ciphertext_bytes = base64.b64decode(ciphertext_b64)
        aesgcm = AESGCM(client_aes_key)
        decrypted_bytes = aesgcm.decrypt(iv_bytes, ciphertext_bytes, None)
        inner_data = json.loads(decrypted_bytes.decode("utf-8"))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to decrypt request ciphertext. Tampering or key mismatch.",
        ) from exc

    # Anti-Replay Check (Nonce & Timestamp)
    now_ts = time.time()
    req_timestamp = inner_data.get("timestamp")
    req_nonce = inner_data.get("nonce")

    if req_timestamp is not None:
        try:
            ts_val = float(req_timestamp)
            if abs(now_ts - ts_val) > NONCE_EXPIRATION_SECONDS:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Encrypted request expired. Please resubmit.",
                )
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid timestamp in encrypted request.",
            )

    if req_nonce:
        _prune_nonces_and_keys()
        if req_nonce in _seen_nonces:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Replay attack detected: nonce has already been used.",
            )
        _seen_nonces[req_nonce] = now_ts

    payload_content = inner_data.get("payload")
    if isinstance(payload_content, dict):
        clean_payload = payload_content
    else:
        clean_payload = {k: v for k, v in inner_data.items() if k not in {"timestamp", "nonce"}}

    return clean_payload, client_aes_key


def encrypt_response_envelope(
    content_dict: dict,
    aes_key: bytes | None,
    status_code: int = 200,
) -> JSONResponse:
    """
    Encrypts response payload with AES-256-GCM using client's ephemeral AES key.
    If no aes_key is provided, returns standard JSONResponse.
    """
    if aes_key is None:
        return JSONResponse(content=content_dict, status_code=status_code)

    try:
        iv = os.urandom(12)
        aesgcm = AESGCM(aes_key)
        json_bytes = json.dumps(content_dict).encode("utf-8")
        ciphertext = aesgcm.encrypt(iv, json_bytes, None)

        envelope = {
            "encrypted": True,
            "iv": base64.b64encode(iv).decode("utf-8"),
            "ciphertext": base64.b64encode(ciphertext).decode("utf-8"),
        }
        return JSONResponse(
            content=envelope,
            status_code=status_code,
            headers={"X-Encrypted-Response": "1"},
        )
    except Exception:
        return JSONResponse(content=content_dict, status_code=status_code)


@router.get("/encryption-key")
async def get_encryption_key() -> dict:
    _, pub_pem = get_server_encryption_key_pair()
    return {
        "algorithm": "RSA-OAEP-256",
        "format": "SPKI",
        "public_key": pub_pem,
        "key_id": "luma_srv_enc_v1",
    }


async def initialize_database() -> None:
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

        def _migrate(sync_conn):
            from sqlalchemy import inspect, text
            inspector = inspect(sync_conn)
            table_names = inspector.get_table_names()
            if "users" in table_names:
                cols = {col["name"] for col in inspector.get_columns("users")}
                is_pg = sync_conn.dialect.name == "postgresql"
                ts_type = "TIMESTAMP WITH TIME ZONE" if is_pg else "DATETIME"
                to_add = [
                    ("profile_image_url", "VARCHAR(512)"),
                    ("profile_image_data", "TEXT"),
                    ("custom_name", "VARCHAR(100)"),
                    ("bio", "VARCHAR(250)"),
                    ("avatar_emoji", "VARCHAR(32)"),
                    ("avatar_color_hex", "VARCHAR(16)"),
                    ("updated_at", ts_type),
                ]
                for col_name, col_type in to_add:
                    if col_name not in cols:
                        try:
                            with sync_conn.begin_nested():
                                if is_pg:
                                    sync_conn.execute(text(f"ALTER TABLE users ADD COLUMN IF NOT EXISTS {col_name} {col_type}"))
                                else:
                                    sync_conn.execute(text(f"ALTER TABLE users ADD COLUMN {col_name} {col_type}"))
                        except Exception:
                            pass
        await connection.run_sync(_migrate)


async def require_user(request: Request) -> User:
    if request.method not in {"GET", "HEAD", "OPTIONS"}:
        _verify_csrf(request)
    token = request.cookies.get(SESSION_COOKIE)
    if not token:
        auth_header = request.headers.get("authorization")
        if auth_header and auth_header.lower().startswith("bearer "):
            token = auth_header[7:].strip()
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
    request: Request,
    response: Response,
) -> User | Response:
    _ensure_same_origin(request)
    raw_body = await request.body()
    payload_dict, aes_key = decrypt_request_envelope(raw_body)
    try:
        data = RegisterRequest(**payload_dict)
    except ValidationError as exc:
        raise RequestValidationError(exc.errors())

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

    if aes_key is not None:
        user_resp = _sync_user_profile_url(user).model_dump(mode="json")
        res = encrypt_response_envelope(user_resp, aes_key, status_code=status.HTTP_201_CREATED)
        _set_session_cookie(res, token)
        return res

    _set_session_cookie(response, token)
    return user


async def verify_google_id_token(token: str) -> dict:
    # 1. Attempt verification via google-auth if installed
    try:
        from google.oauth2 import id_token
        from google.auth.transport import requests as google_requests

        idinfo = await asyncio.to_thread(
            id_token.verify_oauth2_token,
            token,
            google_requests.Request(),
        )
        aud = idinfo.get("aud")
        if isinstance(aud, (list, tuple, set)):
            if not any(a in ALLOWED_GOOGLE_AUDIENCES for a in aud):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail=f"Google ID token audience '{aud}' not allowed.",
                )
        elif aud not in ALLOWED_GOOGLE_AUDIENCES:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Google ID token audience '{aud}' not allowed.",
            )
        iss = idinfo.get("iss")
        if iss not in {"accounts.google.com", "https://accounts.google.com"}:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid Google ID token issuer.",
            )
        return idinfo
    except ImportError:
        pass
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Google ID token verification failed: {exc}",
        )

    # 2. Direct verification with Google tokeninfo endpoint
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"id_token": token},
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Unable to reach Google for token verification.",
            ) from exc

    if resp.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Google ID token verification failed.",
        )

    idinfo = resp.json()
    aud = idinfo.get("aud")
    if isinstance(aud, (list, tuple, set)):
        if not any(a in ALLOWED_GOOGLE_AUDIENCES for a in aud):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Google ID token audience '{aud}' not allowed.",
            )
    elif aud not in ALLOWED_GOOGLE_AUDIENCES:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Google ID token audience '{aud}' not allowed.",
        )
    iss = idinfo.get("iss")
    if iss not in {"accounts.google.com", "https://accounts.google.com"}:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Google ID token issuer.",
        )
    exp = int(idinfo.get("exp", 0))
    if exp < int(datetime.now(timezone.utc).timestamp()):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Google ID token has expired.",
        )
    return idinfo


@router.post("/google", response_model=UserResponse)
async def google_login(
    request: Request,
    response: Response,
) -> User | Response:
    _ensure_same_origin(request)
    raw_body = await request.body()
    payload_dict, aes_key = decrypt_request_envelope(raw_body)
    try:
        data = GoogleLoginRequest(**payload_dict)
    except ValidationError as exc:
        raise RequestValidationError(exc.errors())

    raw_token = data.get_token()
    idinfo = await verify_google_id_token(raw_token)

    email = idinfo.get("email")
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Google account does not contain a verified email address.",
        )
    email_verified = idinfo.get("email_verified")
    if email_verified is not None and str(email_verified).lower() not in {"true", "1"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Google account email is not verified.",
        )
    email = email.strip().casefold()
    full_name = idinfo.get("name") or email.split("@")[0]
    full_name = " ".join(full_name.split())[:100]
    if not full_name:
        full_name = "Google User"

    token: str
    user: User | None = None
    async with SessionFactory.begin() as db:
        user = await db.scalar(select(User).where(User.email == email))
        picture = idinfo.get("picture")
        if user is None:
            # First-time Google user: create user record with dummy secure password hash
            dummy_password = await asyncio.to_thread(password_hasher.hash, secrets.token_urlsafe(32))
            user = User(
                full_name=full_name,
                email=email,
                password_hash=dummy_password,
                profile_image_url=picture,
                created_at=_utcnow(),
            )
            db.add(user)
            await db.flush()
        else:
            if not user.profile_image_url and picture:
                user.profile_image_url = picture
        token = await _add_session(db, user.id)

    if aes_key is not None:
        user_resp = _sync_user_profile_url(user).model_dump(mode="json")
        res = encrypt_response_envelope(user_resp, aes_key, status_code=status.HTTP_200_OK)
        _set_session_cookie(res, token)
        return res

    _set_session_cookie(response, token)
    return user


@router.post("/login", response_model=UserResponse)
async def login(
    request: Request,
    response: Response,
) -> User | Response:
    _ensure_same_origin(request)
    raw_body = await request.body()
    payload_dict, aes_key = decrypt_request_envelope(raw_body)
    try:
        data = LoginRequest(**payload_dict)
    except ValidationError as exc:
        raise RequestValidationError(exc.errors())

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
            valid, new_hash = await asyncio.to_thread(
                password_hasher.verify_and_update,
                data.password,
                stored_hash,
            )
            if user and valid:
                if new_hash:
                    user.password_hash = new_hash
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

    if aes_key is not None:
        user_resp = _sync_user_profile_url(user).model_dump(mode="json")
        res = encrypt_response_envelope(user_resp, aes_key, status_code=status.HTTP_200_OK)
        _set_session_cookie(res, token)
        return res

    _set_session_cookie(response, token)
    return user


def _sync_user_profile_url(user: User) -> UserResponse:
    url = user.profile_image_url
    if user.profile_image_data and url:
        base_url = url.split("?")[0]
        ts = int(user.updated_at.timestamp()) if user.updated_at else 1
        url = f"{base_url}?v={ts}"
    return UserResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        profile_image_url=url,
        custom_name=user.custom_name,
        bio=user.bio,
        avatar_emoji=user.avatar_emoji,
        avatar_color_hex=user.avatar_color_hex,
        updated_at=user.updated_at,
    )


@router.get("/me", response_model=UserResponse)
async def current_user(user: User = Depends(require_user)) -> User:
    return _sync_user_profile_url(user)


class ForgotPasswordRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)


@router.post("/forgot-password")
async def forgot_password(request: Request) -> Response:
    raw_body = await request.body()
    payload_dict, aes_key = decrypt_request_envelope(raw_body)
    try:
        data = ForgotPasswordRequest(**payload_dict)
    except ValidationError as exc:
        raise RequestValidationError(exc.errors())

    normalized_email = data.email.lower().strip()
    result = {"message": f"If an account exists for {normalized_email}, a password reset link has been sent."}
    return encrypt_response_envelope(result, aes_key, status_code=status.HTTP_200_OK)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(request: Request) -> Response:
    _ensure_same_origin(request)
    token = request.cookies.get(SESSION_COOKIE)
    if not token:
        auth_header = request.headers.get("authorization")
        if auth_header and auth_header.lower().startswith("bearer "):
            token = auth_header[7:].strip()
    if token:
        async with SessionFactory.begin() as db:
            session = await db.get(AuthSession, _token_hash(token))
            if session:
                user_id = session.user_id
                await db.delete(session)
                await db.execute(delete(SigningKeyModel).where(SigningKeyModel.user_id == user_id))
                _revoke_user_signing_keys(user_id)
    response = Response(status_code=status.HTTP_204_NO_CONTENT)
    _clear_session_cookie(response)
    return response


class SigningKeyResponse(BaseModel):
    key_id: str
    signing_secret: str
    expires_at: str
    algorithm: str = "HMAC-SHA256"


@router.post("/signing-key", response_model=SigningKeyResponse)
async def obtain_signing_key(user: User = Depends(require_user)) -> dict:
    key_id = f"key_{uuid4().hex}"
    secret = secrets.token_hex(32)
    expires_at = _utcnow() + timedelta(hours=24)
    async with SessionFactory.begin() as db:
        db.add(
            SigningKeyModel(
                key_id=key_id,
                user_id=user.id,
                secret=secret,
                created_at=_utcnow(),
                expires_at=expires_at,
            )
        )
    _signing_keys_cache[key_id] = (user.id, secret, expires_at)
    return {
        "key_id": key_id,
        "signing_secret": secret,
        "expires_at": expires_at.isoformat(),
        "algorithm": "HMAC-SHA256",
    }


user_router = APIRouter(prefix="/api/user", tags=["user"])

AVATARS_DIR = Path(__file__).resolve().parent / "static" / "avatars"
AVATARS_DIR.mkdir(parents=True, exist_ok=True)


@router.get("/profile", response_model=UserResponse)
@user_router.get("/profile", response_model=UserResponse)
async def get_user_profile(user: User = Depends(require_user)) -> User:
    return _sync_user_profile_url(user)


@router.put("/profile", response_model=UserResponse)
@user_router.put("/profile", response_model=UserResponse)
async def update_user_profile(
    data: UpdateProfileRequest,
    request: Request,
    response: Response,
    user: User = Depends(require_user),
) -> User:
    key_info = await verify_request_signature(request, user, required=False)
    now = _utcnow()
    ts = int(now.timestamp())
    async with SessionFactory.begin() as db:
        db_user = await db.get(User, user.id)
        if db_user is None:
            raise HTTPException(status_code=404, detail="User not found.")
        if data.custom_name is not None:
            db_user.custom_name = data.custom_name.strip() if data.custom_name.strip() else None
        if data.bio is not None:
            db_user.bio = data.bio.strip() if data.bio.strip() else None
        if data.avatar_emoji is not None:
            db_user.avatar_emoji = data.avatar_emoji.strip() if data.avatar_emoji.strip() else None
        if data.avatar_color_hex is not None:
            db_user.avatar_color_hex = data.avatar_color_hex.strip() if data.avatar_color_hex.strip() else None
        if data.profile_image_url is not None:
            clean_url = data.profile_image_url.strip()
            if clean_url.startswith("data:image/"):
                db_user.profile_image_data = clean_url
                db_user.profile_image_url = f"/api/user/profile/avatar/{user.id}"
            else:
                db_user.profile_image_url = clean_url if clean_url else None
        db_user.updated_at = now
        await db.flush()
        if key_info:
            sign_response(response, key_info[1], request.headers.get("x-nonce", ""))
        return _sync_user_profile_url(db_user)


@router.get("/avatar/{user_id}", include_in_schema=False)
@user_router.get("/profile/avatar/{user_id}", include_in_schema=False)
@user_router.get("/avatar/{user_id}", include_in_schema=False)
async def get_user_avatar(user_id: str, request: Request, v: str | None = None) -> Response:
    async with SessionFactory.begin() as db:
        user = await db.get(User, user_id)
        if not user or not user.profile_image_data:
            # Fallback to local file if available
            for f in AVATARS_DIR.glob(f"avatar_{user_id}_*"):
                try:
                    data = f.read_bytes()
                    etag = hashlib.sha256(data).hexdigest()
                    if request.headers.get("if-none-match") == f'"{etag}"':
                        return Response(status_code=304, headers={"ETag": f'"{etag}"', "Cache-Control": "private, no-cache, must-revalidate"})
                    return Response(
                        content=data,
                        media_type="image/jpeg",
                        headers={
                            "Cache-Control": "private, no-cache, must-revalidate",
                            "ETag": f'"{etag}"',
                        },
                    )
                except Exception:
                    pass
            raise HTTPException(status_code=404, detail="Avatar not found.")

        raw_b64 = user.profile_image_data.strip()
        if "," in raw_b64:
            raw_b64 = raw_b64.split(",", 1)[1]
        try:
            image_bytes = base64.b64decode(raw_b64)
        except Exception:
            raise HTTPException(status_code=500, detail="Corrupted avatar data.")

        etag = hashlib.sha256(image_bytes).hexdigest()
        if request.headers.get("if-none-match") == f'"{etag}"':
            return Response(status_code=304, headers={"ETag": f'"{etag}"', "Cache-Control": "private, no-cache, must-revalidate"})

        return Response(
            content=image_bytes,
            media_type="image/jpeg",
            headers={
                "Cache-Control": "private, no-cache, must-revalidate",
                "ETag": f'"{etag}"',
            },
        )


@router.post("/profile/photo", response_model=UserResponse)
@user_router.post("/profile/photo", response_model=UserResponse)
async def upload_profile_photo(
    payload: UploadPhotoPayload,
    request: Request = None,  # type: ignore[assignment]
    response: Response = None,  # type: ignore[assignment]
    user: User = Depends(require_user),
) -> User:
    key_info = None
    if request is not None:
        key_info = await verify_request_signature(request, user, required=False)

    raw_data = payload.image.strip()
    if not raw_data:
        raise HTTPException(status_code=400, detail="Image data is required.")

    if "," in raw_data:
        raw_data = raw_data.split(",", 1)[1]

    try:
        image_bytes = base64.b64decode(raw_data)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 image data.")

    if len(image_bytes) > 5 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image file too large (max 5MB).")

    _validate_image_magic_bytes(image_bytes)
    Image.MAX_IMAGE_PIXELS = 10_000_000

    try:
        img = Image.open(io.BytesIO(image_bytes))
        img = ImageOps.exif_transpose(img)
        img = img.convert("RGB")
        w, h = img.size
        min_dim = min(w, h)
        left = (w - min_dim) // 2
        top = (h - min_dim) // 2
        img = img.crop((left, top, left + min_dim, top + min_dim))
        img.thumbnail((512, 512), Image.Resampling.LANCZOS)
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Unsupported or corrupted image file.") from exc

    # Encode directly to JPEG bytes and store base64 in PostgreSQL
    buffer = io.BytesIO()
    img.save(buffer, format="JPEG", quality=85, optimize=True)
    jpeg_bytes = buffer.getvalue()
    b64_stored = base64.b64encode(jpeg_bytes).decode("ascii")

    now = _utcnow()
    ts = int(now.timestamp())
    profile_url = f"/api/user/profile/avatar/{user.id}"

    # Also keep a local cache file if folder is writable
    try:
        AVATARS_DIR.mkdir(parents=True, exist_ok=True)
        filename = f"avatar_{user.id}_{ts}_{secrets.token_hex(4)}.jpg"
        for old_file in AVATARS_DIR.glob(f"avatar_{user.id}_*"):
            old_file.unlink(missing_ok=True)
        dest_path = AVATARS_DIR / filename
        dest_path.write_bytes(jpeg_bytes)
    except Exception:
        pass

    async with SessionFactory.begin() as db:
        db_user = await db.get(User, user.id)
        if db_user is None:
            raise HTTPException(status_code=404, detail="User not found.")
        db_user.profile_image_data = b64_stored
        db_user.profile_image_url = profile_url
        db_user.updated_at = now
        await db.flush()
        if key_info and response is not None and request is not None:
            sign_response(response, key_info[1], request.headers.get("x-nonce", ""))
        return _sync_user_profile_url(db_user)


@router.delete("/profile/photo", response_model=UserResponse)
@user_router.delete("/profile/photo", response_model=UserResponse)
async def delete_profile_photo(
    request: Request = None,  # type: ignore[assignment]
    response: Response = None,  # type: ignore[assignment]
    user: User = Depends(require_user),
) -> User:
    key_info = None
    if request is not None:
        key_info = await verify_request_signature(request, user, required=False)

    for old_file in AVATARS_DIR.glob(f"avatar_{user.id}_*"):
        try:
            old_file.unlink(missing_ok=True)
        except Exception:
            pass

    async with SessionFactory.begin() as db:
        db_user = await db.get(User, user.id)
        if db_user is None:
            raise HTTPException(status_code=404, detail="User not found.")
        db_user.profile_image_data = None
        db_user.profile_image_url = None
        db_user.updated_at = _utcnow()
        await db.flush()
        if key_info and response is not None and request is not None:
            sign_response(response, key_info[1], request.headers.get("x-nonce", ""))
        return _sync_user_profile_url(db_user)


@router.delete("/profile", response_model=UserResponse)
@user_router.delete("/profile", response_model=UserResponse)
async def reset_profile(
    request: Request = None,  # type: ignore[assignment]
    response: Response = None,  # type: ignore[assignment]
    user: User = Depends(require_user),
) -> User:
    key_info = None
    if request is not None:
        key_info = await verify_request_signature(request, user, required=False)

    for old_file in AVATARS_DIR.glob(f"avatar_{user.id}_*"):
        try:
            old_file.unlink(missing_ok=True)
        except Exception:
            pass

    async with SessionFactory.begin() as db:
        db_user = await db.get(User, user.id)
        if db_user is None:
            raise HTTPException(status_code=404, detail="User not found.")
        db_user.custom_name = None
        db_user.bio = None
        db_user.avatar_emoji = None
        db_user.avatar_color_hex = None
        db_user.profile_image_data = None
        db_user.profile_image_url = None
        db_user.updated_at = _utcnow()
        await db.flush()
        if key_info and response is not None and request is not None:
            sign_response(response, key_info[1], request.headers.get("x-nonce", ""))
        return _sync_user_profile_url(db_user)


@router.get("/characters", response_model=list[CustomCharacterSchema])
@user_router.get("/characters", response_model=list[CustomCharacterSchema])
async def list_custom_characters(user: User = Depends(require_user)) -> list[CustomCharacterModel]:
    async with SessionFactory() as db:
        result = await db.scalars(
            select(CustomCharacterModel)
            .where(CustomCharacterModel.user_id == user.id)
            .order_by(CustomCharacterModel.created_at.desc())
        )
        return list(result.all())


@router.post("/characters", response_model=CustomCharacterSchema, status_code=201)
@user_router.post("/characters", response_model=CustomCharacterSchema, status_code=201)
async def create_custom_character(
    payload: CreateCustomCharacterPayload,
    user: User = Depends(require_user),
) -> CustomCharacterModel:
    char_id = payload.id if payload.id else str(uuid4())
    async with SessionFactory.begin() as db:
        existing = await db.get(CustomCharacterModel, char_id)
        if existing:
            if existing.user_id != user.id:
                raise HTTPException(status_code=403, detail="Character belongs to another user.")
            existing.name = payload.name.strip()
            existing.system_prompt = payload.system_prompt.strip()
            existing.avatar_emoji = payload.avatar_emoji.strip() or "✨"
            await db.flush()
            return existing

        new_char = CustomCharacterModel(
            id=char_id,
            user_id=user.id,
            name=payload.name.strip(),
            system_prompt=payload.system_prompt.strip(),
            avatar_emoji=payload.avatar_emoji.strip() or "✨",
            created_at=_utcnow(),
        )
        db.add(new_char)
        await db.flush()
        return new_char


@router.put("/characters/{char_id}", response_model=CustomCharacterSchema)
@user_router.put("/characters/{char_id}", response_model=CustomCharacterSchema)
async def update_custom_character(
    char_id: str,
    payload: CreateCustomCharacterPayload,
    user: User = Depends(require_user),
) -> CustomCharacterModel:
    async with SessionFactory.begin() as db:
        char = await db.get(CustomCharacterModel, char_id)
        if char is None or char.user_id != user.id:
            raise HTTPException(status_code=404, detail="Character not found.")
        char.name = payload.name.strip()
        char.system_prompt = payload.system_prompt.strip()
        char.avatar_emoji = payload.avatar_emoji.strip() or "✨"
        await db.flush()
        return char


@router.delete("/characters/{char_id}", status_code=204)
@user_router.delete("/characters/{char_id}", status_code=204)
async def delete_custom_character(
    char_id: str,
    user: User = Depends(require_user),
) -> Response:
    async with SessionFactory.begin() as db:
        char = await db.get(CustomCharacterModel, char_id)
        if char and char.user_id == user.id:
            await db.delete(char)
    return Response(status_code=204)


# ---------------------------------------------------------
# Chat Conversation & Message Persistence Router
# ---------------------------------------------------------
chat_router = APIRouter(prefix="/api/chat", tags=["chat"])


def _format_dt(dt: datetime | None) -> str:
    if not dt:
        return _utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    if dt.tzinfo is not None:
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


@chat_router.get("/conversations")
async def list_conversations(user: User = Depends(require_user)) -> list[dict]:
    """Retrieve all conversations and their full message history for the authenticated user from the database."""
    async with SessionFactory.begin() as db:
        stmt = (
            select(ConversationModel)
            .where(ConversationModel.user_id == user.id)
            .order_by(ConversationModel.updated_at.desc())
        )
        convs = (await db.scalars(stmt)).all()
        result = []
        for conv in convs:
            msg_stmt = (
                select(ChatMessageModel)
                .where(ChatMessageModel.conversation_id == conv.id)
                .order_by(ChatMessageModel.created_at.asc())
            )
            msgs = (await db.scalars(msg_stmt)).all()
            messages_list = []
            for m in msgs:
                img = None
                if m.image_attachment:
                    try:
                        img = json.loads(m.image_attachment)
                    except Exception:
                        pass
                messages_list.append({
                    "id": m.id,
                    "role": m.role,
                    "content": m.content,
                    "status": m.status,
                    "imageAttachment": img,
                    "createdAt": _format_dt(m.created_at),
                })
            result.append({
                "id": conv.id,
                "title": conv.title,
                "messages": messages_list,
                "createdAt": _format_dt(conv.created_at),
                "updatedAt": _format_dt(conv.updated_at),
            })
        return result


@chat_router.get("/conversations/latest")
async def get_latest_conversation(user: User = Depends(require_user)) -> dict | None:
    """Retrieve the single most recently updated conversation for the user, with full messages."""
    async with SessionFactory.begin() as db:
        stmt = (
            select(ConversationModel)
            .where(ConversationModel.user_id == user.id)
            .order_by(ConversationModel.updated_at.desc())
            .limit(1)
        )
        conv = (await db.scalars(stmt)).first()
        if not conv:
            return None
        msg_stmt = (
            select(ChatMessageModel)
            .where(ChatMessageModel.conversation_id == conv.id)
            .order_by(ChatMessageModel.created_at.asc())
        )
        msgs = (await db.scalars(msg_stmt)).all()
        messages_list = []
        for m in msgs:
            img = None
            if m.image_attachment:
                try:
                    img = json.loads(m.image_attachment)
                except Exception:
                    pass
            messages_list.append({
                "id": m.id,
                "role": m.role,
                "content": m.content,
                "status": m.status,
                "imageAttachment": img,
                "createdAt": _format_dt(m.created_at),
            })
        return {
            "id": conv.id,
            "title": conv.title,
            "messages": messages_list,
            "createdAt": _format_dt(conv.created_at),
            "updatedAt": _format_dt(conv.updated_at),
        }


@chat_router.get("/sync/poll")
async def poll_sync_status(
    since: str | None = None,
    current_id: str | None = None,
    user: User = Depends(require_user),
) -> dict:
    """Lightweight polling endpoint to detect cross-device updates."""
    async with SessionFactory.begin() as db:
        stmt = (
            select(ConversationModel)
            .where(ConversationModel.user_id == user.id)
            .order_by(ConversationModel.updated_at.desc())
            .limit(1)
        )
        latest_conv = (await db.scalars(stmt)).first()
        if not latest_conv:
            return {
                "has_updates": False,
                "latest_conversation_id": None,
                "latest_updated_at": None,
                "message_count": 0,
            }

        latest_updated_str = _format_dt(latest_conv.updated_at)
        target_conv_id = current_id if current_id else latest_conv.id

        # Count messages for target conversation
        msg_count_stmt = select(func.count(ChatMessageModel.id)).where(
            ChatMessageModel.conversation_id == target_conv_id
        )
        msg_count = (await db.scalar(msg_count_stmt)) or 0

        has_updates = False
        if not since:
            has_updates = True
        else:
            try:
                since_dt = datetime.fromisoformat(since.replace("Z", "+00:00")).replace(tzinfo=None)
                if latest_conv.updated_at > since_dt:
                    has_updates = True
            except Exception:
                has_updates = True

        return {
            "has_updates": has_updates,
            "latest_conversation_id": latest_conv.id,
            "latest_updated_at": latest_updated_str,
            "message_count": msg_count,
        }


@chat_router.post("/conversations")
async def save_conversation(payload: dict, user: User = Depends(require_user)) -> dict:
    """Save or update a conversation and its messages directly in the database."""
    conv_id = str(payload.get("id") or uuid4())
    title = (payload.get("title") or "New Conversation")[:255]
    messages_data = payload.get("messages", [])
    now = _utcnow()

    c_str = payload.get("created_at") or payload.get("createdAt")
    u_str = payload.get("updated_at") or payload.get("updatedAt")
    try:
        conv_created = datetime.fromisoformat(str(c_str).replace("Z", "+00:00")).replace(tzinfo=None) if c_str else now
    except Exception:
        conv_created = now

    try:
        conv_updated = datetime.fromisoformat(str(u_str).replace("Z", "+00:00")).replace(tzinfo=None) if u_str else now
    except Exception:
        conv_updated = now

    async with SessionFactory.begin() as db:
        conv = await db.get(ConversationModel, conv_id)
        if not conv:
            conv = ConversationModel(
                id=conv_id,
                user_id=user.id,
                title=title,
                created_at=conv_created,
                updated_at=conv_updated,
            )
            db.add(conv)
        else:
            if conv.user_id != user.id:
                raise HTTPException(status_code=403, detail="Not authorized to edit this conversation.")
            conv.title = title
            conv.updated_at = conv_updated

        # Delete existing messages and re-insert for idempotent sync
        await db.execute(delete(ChatMessageModel).where(ChatMessageModel.conversation_id == conv_id))

        for m in messages_data:
            msg_id = str(m.get("id") or uuid4())
            role = m.get("role", "user")
            content = m.get("content", "")
            status_val = m.get("status", "complete")
            img_att = m.get("imageAttachment") or m.get("image_attachment")
            img_str = json.dumps(img_att) if img_att else None
            m_time = m.get("createdAt") or m.get("created_at")
            try:
                msg_dt = datetime.fromisoformat(str(m_time).replace("Z", "+00:00")).replace(tzinfo=None) if m_time else now
            except Exception:
                msg_dt = now

            db_msg = ChatMessageModel(
                id=msg_id,
                conversation_id=conv_id,
                user_id=user.id,
                role=role,
                content=content,
                status=status_val,
                image_attachment=img_str,
                created_at=msg_dt,
            )
            db.add(db_msg)
        await db.flush()

    return {"status": "saved", "id": conv_id, "title": title}


@chat_router.get("/conversations/{conversation_id}")
async def get_conversation(conversation_id: str, user: User = Depends(require_user)) -> dict:
    """Retrieve a single conversation and its messages from the database."""
    async with SessionFactory.begin() as db:
        conv = await db.get(ConversationModel, conversation_id)
        if not conv or conv.user_id != user.id:
            raise HTTPException(status_code=404, detail="Conversation not found.")
        msg_stmt = (
            select(ChatMessageModel)
            .where(ChatMessageModel.conversation_id == conv.id)
            .order_by(ChatMessageModel.created_at.asc())
        )
        msgs = (await db.scalars(msg_stmt)).all()
        messages_list = []
        for m in msgs:
            img = None
            if m.image_attachment:
                try:
                    img = json.loads(m.image_attachment)
                except Exception:
                    pass
            messages_list.append({
                "id": m.id,
                "role": m.role,
                "content": m.content,
                "status": m.status,
                "imageAttachment": img,
                "createdAt": _format_dt(m.created_at),
            })
        return {
            "id": conv.id,
            "title": conv.title,
            "messages": messages_list,
            "createdAt": _format_dt(conv.created_at),
            "updatedAt": _format_dt(conv.updated_at),
        }


@chat_router.delete("/conversations/{conversation_id}")
async def delete_conversation(conversation_id: str, user: User = Depends(require_user)) -> dict:
    """Delete a conversation from the database."""
    async with SessionFactory.begin() as db:
        conv = await db.get(ConversationModel, conversation_id)
        if conv and conv.user_id == user.id:
            await db.delete(conv)
            await db.flush()
    return {"status": "deleted", "id": conversation_id}


@chat_router.delete("/conversations")
async def clear_all_conversations(
    request: Request = None,  # type: ignore[assignment]
    response: Response = None,  # type: ignore[assignment]
    user: User = Depends(require_user),
) -> dict:
    """Clear all conversations for the user from the database."""
    key_info = None
    if request is not None:
        key_info = await verify_request_signature(request, user, required=False)
    async with SessionFactory.begin() as db:
        await db.execute(delete(ConversationModel).where(ConversationModel.user_id == user.id))
        await db.flush()
    if key_info and response is not None and request is not None:
        sign_response(response, key_info[1], request.headers.get("x-nonce", ""))
    return {"status": "cleared"}


@chat_router.post("/sync")
async def sync_conversations_endpoint(payload: dict, user: User = Depends(require_user)) -> list[dict]:
    """Sync conversations between client and database, returning the up-to-date conversation list."""
    incoming = payload.get("conversations", [])
    for c in incoming:
        try:
            await save_conversation(c, user=user)
        except Exception:
            pass
    return await list_conversations(user=user)
