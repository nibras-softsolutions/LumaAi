
from __future__ import annotations

import json
import logging
import os
import re
import secrets
import time
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Literal
from urllib.parse import urlparse
from uuid import uuid4

import bleach
import httpx
from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from langchain_core.messages import AIMessage, AIMessageChunk, BaseMessage, HumanMessage, SystemMessage
from langchain_ollama import ChatOllama
from markdown_it import MarkdownIt
from ollama import AsyncClient as OllamaAsyncClient
from ollama import ResponseError
from pydantic import BaseModel, ConfigDict, Field, model_validator

from fastapi.middleware.cors import CORSMiddleware
from auth import (
    ALLOWED_ORIGINS,
    User,
    engine as auth_engine,
    initialize_database,
    require_user,
    router as auth_router,
)
from tools import (
    ASPECT_RATIOS,
    ImageGenerateRequest,
    ImageGenerateResponse,
    ImageGenerationError,
    ProviderTimeoutError,
    ProviderUnavailableError,
    detect_image_prompt,
    image_cache,
    image_provider,
    rate_limiter,
)


class OpenAICompatibleModel:
    """Universal adapter for hosted model APIs (Groq, OpenRouter, Together, OpenAI)."""

    def __init__(self, model: str, base_url: str, api_key: str):
        self.model = model
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key

    async def astream(self, messages: list[BaseMessage]) -> AsyncIterator[AIMessageChunk]:
        payload_messages = []
        for msg in messages:
            if isinstance(msg, SystemMessage):
                payload_messages.append({"role": "system", "content": msg.content})
            elif isinstance(msg, HumanMessage):
                payload_messages.append({"role": "user", "content": msg.content})
            else:
                payload_messages.append({"role": "assistant", "content": msg.content})

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        if "openrouter.ai" in self.base_url:
            headers["HTTP-Referer"] = "https://luma-ai.vercel.app"
            headers["X-Title"] = "Luma AI"

        async with httpx.AsyncClient(timeout=60.0) as client:
            async with client.stream(
                "POST",
                f"{self.base_url}/chat/completions",
                headers=headers,
                json={
                    "model": self.model,
                    "messages": payload_messages,
                    "stream": True,
                },
            ) as response:
                if response.status_code != 200:
                    error_bytes = await response.aread()
                    error_msg = error_bytes.decode("utf-8", errors="replace")
                    raise RuntimeError(
                        f"Model provider error ({response.status_code}): {error_msg}"
                    )
                async for line in response.aiter_lines():
                    if not line:
                        continue
                    if line.startswith("data: "):
                        data_str = line[6:].strip()
                        if data_str == "[DONE]":
                            break
                        try:
                            data = json.loads(data_str)
                            delta = data.get("choices", [{}])[0].get("delta", {})
                            text = delta.get("content")
                            if text:
                                yield AIMessageChunk(content=text)
                        except Exception:
                            continue


# Model provider configuration: "ollama" (default) or "openai" / "groq" / "openrouter"
AI_PROVIDER = os.getenv("AI_PROVIDER", "").strip().lower()
if not AI_PROVIDER:
    if os.getenv("GROQ_API_KEY"):
        AI_PROVIDER = "groq"
    else:
        AI_PROVIDER = "ollama"

OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
OLLAMA_API_KEY = os.getenv("OLLAMA_API_KEY")

if AI_PROVIDER == "groq":
    HOSTED_API_KEY = os.getenv("GROQ_API_KEY") or os.getenv("OPENAI_API_KEY")
    HOSTED_BASE_URL = os.getenv("OPENAI_BASE_URL") or "https://api.groq.com/openai/v1"
    HOSTED_MODEL = os.getenv("OPENAI_MODEL") or "openai/gpt-oss-120b"
elif AI_PROVIDER in {"openai", "openrouter", "together"}:
    HOSTED_API_KEY = os.getenv("OPENAI_API_KEY")
    HOSTED_BASE_URL = os.getenv("OPENAI_BASE_URL") or "https://api.openai.com/v1"
    HOSTED_MODEL = os.getenv("OPENAI_MODEL") or "gpt-4o-mini"
else:
    HOSTED_API_KEY = None
    HOSTED_BASE_URL = None
    HOSTED_MODEL = None

if HOSTED_API_KEY and HOSTED_BASE_URL:
    MODEL = HOSTED_MODEL
    llm = OpenAICompatibleModel(
        model=MODEL,
        base_url=HOSTED_BASE_URL,
        api_key=HOSTED_API_KEY,
    )
else:
    MODEL = OLLAMA_MODEL
    ollama_client_kwargs = {}
    if OLLAMA_API_KEY:
        ollama_client_kwargs["headers"] = {"Authorization": f"Bearer {OLLAMA_API_KEY}"}
    llm = ChatOllama(
        model=MODEL,
        base_url=OLLAMA_BASE_URL,
        client_kwargs=ollama_client_kwargs if ollama_client_kwargs else None,
    )

MAX_HISTORY_MESSAGES = 40
MAX_MESSAGE_LENGTH = 12_000
MAX_HISTORY_LENGTH = 40_000
MAX_MARKDOWN_LENGTH = 100_000
DOWNLOAD_REQUEST_PATTERN = re.compile(
    r"\b(?:download(?:able)?|ready[\s-]+to[\s-]+download|project\s+files?|"
    r"complete\s+files?|save\s+(?:it|this|the\s+code)|source\s+file|"
    r"(?:create|generate|make|write|provide|give).{0,60}\bfile\b)",
    re.IGNORECASE,
)
DOWNLOADABLE_CODE_INSTRUCTION = (
    "The user wants downloadable source file(s). Provide complete, usable source. "
    "For each file, write a short line exactly as `File: filename.ext` immediately "
    "before its own language-tagged fenced code block. Put only that file's source "
    "inside the block, use separate blocks for separate files, and choose a sensible "
    "filename and extension if none was specified. Keep any explanation outside "
    "the code blocks. Do not put shell commands, usage examples, or partial snippets "
    "in fenced blocks."
)
PROJECT_DIR = Path(__file__).resolve().parent
STATIC_DIR = PROJECT_DIR / "static"
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(_app: FastAPI):
    await initialize_database()
    try:
        yield
    finally:
        await auth_engine.dispose()


app = FastAPI(
    title="Luma AI",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=sorted(ALLOWED_ORIGINS),
    allow_origin_regex=r"https://.*\.vercel\.app",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(auth_router)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
markdown = MarkdownIt("commonmark", {"html": False, "linkify": False})


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    connect_sources = " ".join(["'self'"] + sorted(ALLOWED_ORIGINS) + ["https://*.vercel.app"])
    response.headers["Content-Security-Policy"] = (
        f"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
        f"img-src 'self' data:; connect-src {connect_sources}; object-src 'none'; "
        f"base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
    )
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Permissions-Policy"] = (
        "camera=(), microphone=(), geolocation=()"
    )
    return response


ALLOWED_MARKDOWN_TAGS = {
    "a", "blockquote", "br", "code", "del", "em", "h1", "h2", "h3", "h4",
    "h5", "h6", "hr", "li", "ol", "p", "pre", "strong", "table", "tbody",
    "td", "th", "thead", "tr", "ul",
}


class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=MAX_MESSAGE_LENGTH)

    @model_validator(mode="after")
    def content_is_not_blank(self) -> ChatMessage:
        if not self.content.strip():
            raise ValueError("Message content cannot be blank.")
        return self


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    messages: list[ChatMessage] = Field(
        min_length=1,
        max_length=MAX_HISTORY_MESSAGES,
    )

    @model_validator(mode="after")
    def history_is_bounded_and_ends_with_user(self) -> ChatRequest:
        if self.messages[-1].role != "user":
            raise ValueError("The latest message must be from the user.")
        if sum(len(message.content) for message in self.messages) > MAX_HISTORY_LENGTH:
            raise ValueError("Conversation history is too long.")
        return self


class MarkdownRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    content: str = Field(max_length=MAX_MARKDOWN_LENGTH)


def _to_langchain_messages(messages: list[ChatMessage]) -> list[BaseMessage]:
    return [
        HumanMessage(content=message.content)
        if message.role == "user"
        else AIMessage(content=message.content)
        for message in messages
    ]


def _requests_downloadable_code(prompt: str) -> bool:
    return (
        DOWNLOAD_REQUEST_PATTERN.search(prompt) is not None
        and re.search(
            r"\b(?:code|source|program|script|project|file|python|html|css|"
            r"javascript|typescript|json|markdown|sql)\b",
            prompt,
            re.IGNORECASE,
        )
        is not None
    )


def _sse(event: str, payload: dict[str, str]) -> str:
    return f"event: {event}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"


def _safe_error(_exc: Exception) -> str:
    return "Luma AI is temporarily unavailable. Please try again."


async def stream_response(
    messages: list[BaseMessage],
) -> AsyncIterator[str]:
    response_length = 0
    try:
        async for chunk in llm.astream(messages):
            content = chunk.content
            if isinstance(content, str) and content:
                text = content
                remaining = MAX_MESSAGE_LENGTH - response_length
                if len(text) > remaining:
                    text = text[:remaining]
                if text:
                    response_length += len(text)
                    yield _sse("token", {"text": text})
                if len(content) > remaining:
                    yield _sse(
                        "error",
                        {"message": "The response reached the maximum message length."},
                    )
                    return
            elif isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and isinstance(block.get("text"), str):
                        if block["text"]:
                            text = block["text"]
                            remaining = MAX_MESSAGE_LENGTH - response_length
                            if len(text) > remaining:
                                text = text[:remaining]
                            if text:
                                response_length += len(text)
                                yield _sse("token", {"text": text})
                            if len(block["text"]) > remaining:
                                yield _sse(
                                    "error",
                                    {"message": "The response reached the maximum message length."},
                                )
                                return
        yield _sse("done", {})
    except Exception as exc:
        logger.exception("AI response generation failed")
        yield _sse("error", {"message": _safe_error(exc)})


async def stream_image_response(
    user_id: str,
    prompt: str,
    aspect_ratio: str,
) -> AsyncIterator[str]:
    if not await rate_limiter.is_allowed(user_id):
        yield _sse(
            "error",
            {"message": "Rate limit exceeded. Please wait a moment before generating another image."},
        )
        return
    try:
        image_bytes, content_type = await image_provider.generate_image(
            prompt=prompt,
            aspect_ratio=aspect_ratio,
        )
        image_id = str(uuid4())
        actual_seed = secrets.randbelow(1_000_000)
        await image_cache.put(
            image_id=image_id,
            data=image_bytes,
            content_type=content_type,
            prompt=prompt,
            aspect_ratio=aspect_ratio,
            seed=actual_seed,
        )
        width, height = ASPECT_RATIOS.get(aspect_ratio, (1024, 1024))
        image_payload = {
            "id": image_id,
            "prompt": prompt,
            "aspect_ratio": aspect_ratio,
            "image_url": f"/api/image/view/{image_id}",
            "width": width,
            "height": height,
            "provider": image_provider.name,
            "model": image_provider.model_name,
            "created_at": int(time.time() * 1000),
        }
        yield f"event: image\ndata: {json.dumps(image_payload, ensure_ascii=False)}\n\n"
        yield _sse("token", {"text": "Here is your generated image."})
        yield _sse("done", {})
    except ProviderTimeoutError as exc:
        yield _sse("error", {"message": str(exc)})
    except ProviderUnavailableError as exc:
        yield _sse("error", {"message": str(exc)})
    except Exception:
        logger.exception("Image generation streaming failed")
        yield _sse("error", {"message": "Failed to generate image. Please try again."})


@app.get("/", include_in_schema=False)
async def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/health/ai")
async def ai_health(_user: User = Depends(require_user)) -> dict[str, str | bool]:
    if AI_PROVIDER in {"openai", "groq", "openrouter", "together"} and HOSTED_API_KEY and HOSTED_BASE_URL:
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                headers = {"Authorization": f"Bearer {HOSTED_API_KEY}"}
                resp = await client.get(f"{HOSTED_BASE_URL.rstrip('/')}/models", headers=headers)
                connected = resp.status_code == 200
                return {
                    "status": "ok" if connected else "unavailable",
                    "model": MODEL,
                    "ollama_connected": connected,
                    "model_available": connected,
                }
        except Exception as exc:
            logger.warning("AI backend health check failed: %s", type(exc).__name__)
            return {
                "status": "unavailable",
                "model": MODEL,
                "ollama_connected": False,
                "model_available": False,
            }

    try:
        client_kwargs = {"host": OLLAMA_BASE_URL, "timeout": 3.0}
        if OLLAMA_API_KEY:
            client_kwargs["headers"] = {"Authorization": f"Bearer {OLLAMA_API_KEY}"}
        async with OllamaAsyncClient(**client_kwargs) as client:
            response = await client.list()
    except (ConnectionError, httpx.HTTPError, ResponseError):
        logger.warning("AI backend health check failed", exc_info=True)
        return {
            "status": "unavailable",
            "model": MODEL,
            "ollama_connected": False,
            "model_available": False,
        }

    available_models = {model.model.split(":")[0] for model in response.models}
    model_available = MODEL in available_models
    return {
        "status": "ok" if model_available else "model_missing",
        "model": MODEL,
        "ollama_connected": True,
        "model_available": model_available,
    }


@app.post("/api/chat/stream")
async def chat_stream(
    request: ChatRequest,
    _user: User = Depends(require_user),
) -> StreamingResponse:
    latest_user_message = request.messages[-1]
    if latest_user_message.role == "user":
        is_img, clean_prompt, aspect_ratio = detect_image_prompt(latest_user_message.content)
        if is_img:
            return StreamingResponse(
                stream_image_response(_user.id, clean_prompt, aspect_ratio),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache, no-transform",
                    "X-Accel-Buffering": "no",
                },
            )

    messages = _to_langchain_messages(request.messages)
    if latest_user_message.role == "user" and _requests_downloadable_code(
        latest_user_message.content
    ):
        messages.insert(0, SystemMessage(content=DOWNLOADABLE_CODE_INSTRUCTION))
    return StreamingResponse(
        stream_response(messages),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "X-Accel-Buffering": "no",
        },
    )


@app.post("/api/image/generate", response_model=ImageGenerateResponse)
async def generate_image_endpoint(
    req: ImageGenerateRequest,
    user: User = Depends(require_user),
) -> ImageGenerateResponse:
    if not await rate_limiter.is_allowed(user.id):
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. Please wait a moment before generating another image.",
        )
    try:
        image_bytes, content_type = await image_provider.generate_image(
            prompt=req.prompt,
            aspect_ratio=req.aspect_ratio,
            seed=req.seed,
        )
    except ProviderTimeoutError as exc:
        raise HTTPException(status_code=504, detail=str(exc))
    except ProviderUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception:
        logger.exception("Image generation failed")
        raise HTTPException(status_code=500, detail="Failed to generate image. Please try again.")

    image_id = str(uuid4())
    actual_seed = req.seed if req.seed is not None else secrets.randbelow(1_000_000)
    await image_cache.put(
        image_id=image_id,
        data=image_bytes,
        content_type=content_type,
        prompt=req.prompt,
        aspect_ratio=req.aspect_ratio,
        seed=actual_seed,
    )
    width, height = ASPECT_RATIOS.get(req.aspect_ratio, (1024, 1024))
    return ImageGenerateResponse(
        id=image_id,
        prompt=req.prompt,
        aspect_ratio=req.aspect_ratio,
        image_url=f"/api/image/view/{image_id}",
        width=width,
        height=height,
        provider=image_provider.name,
        model=image_provider.model_name,
        created_at=int(time.time() * 1000),
    )


@app.get("/api/image/view/{image_id}", include_in_schema=False)
async def view_image(image_id: str) -> Response:
    cached = await image_cache.get(image_id)
    if not cached:
        raise HTTPException(status_code=404, detail="Image not found or expired.")
    ext = "png" if "png" in cached.content_type else "jpg"
    return Response(
        content=cached.data,
        media_type=cached.content_type,
        headers={
            "Cache-Control": "public, max-age=86400",
            "Content-Disposition": f'inline; filename="luma-{image_id}.{ext}"',
        },
    )


ALLOWED_IMAGE_HOSTS = {
    "image.pollinations.ai",
    "pollinations.ai",
    "127.0.0.1",
    "localhost",
}


@app.get("/api/image/proxy")
async def proxy_image(url: str, _user: User = Depends(require_user)) -> Response:
    parsed = urlparse(url)
    if parsed.hostname not in ALLOWED_IMAGE_HOSTS:
        raise HTTPException(status_code=400, detail="Disallowed image host.")
    try:
        async with httpx.AsyncClient(timeout=35.0) as client:
            resp = await client.get(url, follow_redirects=True)
            if resp.status_code != 200:
                raise HTTPException(status_code=resp.status_code, detail="Failed to fetch image.")
            content_type = resp.headers.get("content-type", "image/jpeg").split(";")[0]
            return Response(
                content=resp.content,
                media_type=content_type,
                headers={"Cache-Control": "public, max-age=86400"},
            )
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Image proxy timed out.")
    except Exception:
        raise HTTPException(status_code=502, detail="Failed to proxy image.")


MAX_VOICE_AUDIO_SIZE = 25 * 1024 * 1024  # 25 MB max


@app.post("/api/voice/transcribe")
async def transcribe_voice(
    request: Request,
    _user: User = Depends(require_user),
) -> dict[str, str]:
    content_type = request.headers.get("content-type", "audio/webm").split(";")[0]
    audio_bytes = await request.body()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Empty audio recording.")
    if len(audio_bytes) > MAX_VOICE_AUDIO_SIZE:
        raise HTTPException(status_code=413, detail="Audio recording is too large (max 25MB).")
    if len(audio_bytes) < 100:
        raise HTTPException(status_code=400, detail="Audio recording is too short or silent.")

    whisper_api_key = os.getenv("GROQ_API_KEY") or os.getenv("OPENAI_API_KEY") or HOSTED_API_KEY
    whisper_base_url = (
        "https://api.groq.com/openai/v1"
        if os.getenv("GROQ_API_KEY")
        else (HOSTED_BASE_URL or "https://api.openai.com/v1")
    )
    model_name = "whisper-large-v3-turbo" if "groq" in whisper_base_url else "whisper-1"

    if not whisper_api_key:
        raise HTTPException(
            status_code=503,
            detail="Voice transcription service is not configured.",
        )

    ext = "webm"
    if "wav" in content_type:
        ext = "wav"
    elif "ogg" in content_type:
        ext = "ogg"
    elif "mp4" in content_type or "m4a" in content_type:
        ext = "m4a"

    files = {"file": (f"recording.{ext}", audio_bytes, content_type)}
    data = {"model": model_name}
    headers = {"Authorization": f"Bearer {whisper_api_key}"}

    try:
        async with httpx.AsyncClient(timeout=25.0) as client:
            resp = await client.post(
                f"{whisper_base_url.rstrip('/')}/audio/transcriptions",
                headers=headers,
                files=files,
                data=data,
            )
            if resp.status_code == 200:
                result = resp.json()
                text = result.get("text", "").strip()
                return {"text": text}
            if resp.status_code == 429:
                raise HTTPException(
                    status_code=429,
                    detail="Transcription rate limit exceeded. Please wait a moment.",
                )
            logger.warning("Whisper transcription error: %s - %s", resp.status_code, resp.text)
            raise HTTPException(status_code=502, detail="Transcription provider error.")
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Transcription timed out.")
    except HTTPException:
        raise
    except Exception:
        logger.exception("Voice transcription failed")
        raise HTTPException(status_code=500, detail="Voice transcription failed.")


@app.post("/api/markdown")
async def render_markdown(
    request: MarkdownRequest,
    _user: User = Depends(require_user),
) -> dict[str, str]:
    rendered = markdown.render(request.content)

    def allowed_attributes(tag: str, name: str, value: str) -> bool:
        if tag == "a" and name in {"href", "title"}:
            return True
        return (
            tag == "code"
            and name == "class"
            and re.fullmatch(r"language-[A-Za-z0-9_+.-]{1,40}", value) is not None
        )

    sanitized = bleach.clean(
        rendered,
        tags=ALLOWED_MARKDOWN_TAGS,
        attributes=allowed_attributes,
        protocols={"http", "https", "mailto"},
        strip=True,
    )
    return {"html": sanitized}


@app.exception_handler(RequestValidationError)
async def invalid_request(
    request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "detail": "Invalid request. Check message count, size, and order.",
            "path": request.url.path,
            "validation_issues": len(exc.errors()),
        },
    )


def main() -> None:
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")


if __name__ == "__main__":
    main()
