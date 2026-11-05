from __future__ import annotations

import asyncio
import base64
import hashlib
import io
import logging
import os
from pathlib import Path
import re
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit, urlunsplit
from uuid import uuid4

from dotenv import load_dotenv
import httpx
from PIL import Image, ImageOps

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
    profile_image_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    custom_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    bio: Mapped[str | None] = mapped_column(String(250), nullable=True)
    avatar_emoji: Mapped[str | None] = mapped_column(String(32), nullable=True)
    avatar_color_hex: Mapped[str | None] = mapped_column(String(16), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    updated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


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


def _clear_session_cookie(response: Response) -> None:
    secure, samesite = _get_cookie_attributes()
    response.delete_cookie(
        key=SESSION_COOKIE,
        httponly=True,
        secure=secure,
        samesite=samesite,
        path="/",
    )


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
    data: GoogleLoginRequest,
    request: Request,
    response: Response,
) -> User:
    _ensure_same_origin(request)
    raw_token = data.get_token()
    idinfo = await verify_google_id_token(raw_token)

    email = idinfo.get("email")
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Google account does not contain a verified email address.",
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


class ForgotPasswordRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)


@router.post("/forgot-password")
async def forgot_password(data: ForgotPasswordRequest) -> dict:
    normalized_email = data.email.lower().strip()
    return {"message": f"If an account exists for {normalized_email}, a password reset link has been sent."}


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
    _clear_session_cookie(response)
    return response


user_router = APIRouter(prefix="/api/user", tags=["user"])

AVATARS_DIR = Path(__file__).resolve().parent / "static" / "avatars"
AVATARS_DIR.mkdir(parents=True, exist_ok=True)


@router.get("/profile", response_model=UserResponse)
@user_router.get("/profile", response_model=UserResponse)
async def get_user_profile(user: User = Depends(require_user)) -> User:
    return user


@router.put("/profile", response_model=UserResponse)
@user_router.put("/profile", response_model=UserResponse)
async def update_user_profile(
    data: UpdateProfileRequest,
    user: User = Depends(require_user),
) -> User:
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
            db_user.profile_image_url = data.profile_image_url.strip() if data.profile_image_url.strip() else None
        db_user.updated_at = _utcnow()
        await db.flush()
        return db_user


@router.post("/profile/photo", response_model=UserResponse)
@user_router.post("/profile/photo", response_model=UserResponse)
async def upload_profile_photo(
    payload: UploadPhotoPayload,
    user: User = Depends(require_user),
) -> User:
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

    for old_file in AVATARS_DIR.glob(f"avatar_{user.id}_*"):
        try:
            old_file.unlink(missing_ok=True)
        except Exception:
            pass

    filename = f"avatar_{user.id}_{int(datetime.now(timezone.utc).timestamp())}_{secrets.token_hex(4)}.jpg"
    dest_path = AVATARS_DIR / filename
    try:
        img.save(dest_path, format="JPEG", quality=88, optimize=True)
    except Exception:
        raise HTTPException(status_code=500, detail="Failed to save avatar image.")

    profile_url = f"/static/avatars/{filename}"
    async with SessionFactory.begin() as db:
        db_user = await db.get(User, user.id)
        if db_user is None:
            raise HTTPException(status_code=404, detail="User not found.")
        db_user.profile_image_url = profile_url
        db_user.updated_at = _utcnow()
        await db.flush()
        return db_user


@router.delete("/profile/photo", response_model=UserResponse)
@user_router.delete("/profile/photo", response_model=UserResponse)
async def delete_profile_photo(user: User = Depends(require_user)) -> User:
    for old_file in AVATARS_DIR.glob(f"avatar_{user.id}_*"):
        try:
            old_file.unlink(missing_ok=True)
        except Exception:
            pass

    async with SessionFactory.begin() as db:
        db_user = await db.get(User, user.id)
        if db_user is None:
            raise HTTPException(status_code=404, detail="User not found.")
        db_user.profile_image_url = None
        db_user.updated_at = _utcnow()
        await db.flush()
        return db_user


@router.delete("/profile", response_model=UserResponse)
@user_router.delete("/profile", response_model=UserResponse)
async def reset_profile(user: User = Depends(require_user)) -> User:
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
        db_user.profile_image_url = None
        db_user.updated_at = _utcnow()
        await db.flush()
        return db_user


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
