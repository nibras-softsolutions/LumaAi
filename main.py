
from __future__ import annotations

import json
import logging
import os
import re
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Literal

import bleach
import httpx
from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from langchain_core.messages import AIMessage, BaseMessage, HumanMessage, SystemMessage
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

MODEL = os.getenv("OLLAMA_MODEL", "llama3.2")
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
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
llm = ChatOllama(model=MODEL, base_url=OLLAMA_BASE_URL)
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


@app.get("/", include_in_schema=False)
async def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/health/ai")
async def ai_health(_user: User = Depends(require_user)) -> dict[str, str | bool]:
    try:
        async with OllamaAsyncClient(
            host=OLLAMA_BASE_URL,
            timeout=3.0,
        ) as client:
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
    messages = _to_langchain_messages(request.messages)
    latest_user_message = request.messages[-1]
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
