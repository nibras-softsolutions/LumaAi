from __future__ import annotations

import asyncio
import base64
import logging
import os
import re
import secrets
import time
from abc import ABC, abstractmethod
from typing import Literal
from urllib.parse import quote_plus

import httpx
from pydantic import BaseModel, ConfigDict, Field, model_validator

logger = logging.getLogger(__name__)

ASPECT_RATIOS: dict[str, tuple[int, int]] = {
    "1:1": (1024, 1024),
    "16:9": (1280, 720),
    "9:16": (720, 1280),
    "4:3": (1024, 768),
}

MAX_PROMPT_LENGTH = 1000
MIN_PROMPT_LENGTH = 2
MAX_CACHE_ITEMS = 60
CACHE_TTL_SECONDS = 7200  # 2 hours

VISUAL_NOUNS = (
    r"image|picture|photo|photograph|illustration|icon|wallpaper|graphic|artwork|"
    r"landscape|portrait|scene|concept|logo|poster|render(?:ing)?|visual|drawing|painting|"
    r"avatar|banner|thumbnail|mockup"
)

ASPECT_RATIO_PATTERN = re.compile(
    r"\b(?:in\s+)?(?:aspect\s+ratio\s+|format\s+)?(1:1|16:9|9:16|4:3)(?:\s+(?:format|aspect\s+ratio|ratio))?\b",
    re.IGNORECASE,
)

IMAGE_INTENT_PATTERN = re.compile(
    rf"^\s*(?:please\s+)?(?:generate|create|render|draw|make|design|paint)\s+(?:an?\s+|the\s+)?(?:[\w-]+\s+){{0,6}}(?:{VISUAL_NOUNS})\b",
    re.IGNORECASE,
)

SCENE_INTENT_PATTERN = re.compile(
    r"^\s*(?:please\s+)?(?:generate|create|draw|paint|render)\s+(?:an?\s+|the\s+)?(?:[\w-]+\s+){0,4}(?:city|view|skyline|sunset|sunrise|forest|planet|galaxy|room|ocean|castle|temple)\b",
    re.IGNORECASE,
)

NOT_CODE_PATTERN = re.compile(
    r"\b(?:function|class|method|component|script|algorithm|api|endpoint|sql|database|python|html|css|javascript|typescript|c\+\+|java|rust|go)\b",
    re.IGNORECASE,
)

PROMPT_CLEAN_PREFIXES = re.compile(
    rf"^\s*(?:please\s+)?(?:generate|create|render|draw|make|design|paint)\s+(?:an?\s+|the\s+)?(?:image|picture|photo|illustration|icon|wallpaper|graphic|visual|artwork|poster)?\s*(?:of|for|showing|depicting)?\s*",
    re.IGNORECASE,
)


class ImageGenerationError(Exception):
    """Base error for image generation failures."""


class ProviderUnavailableError(ImageGenerationError):
    """Raised when the image provider is unreachable or returns a server error."""


class ProviderTimeoutError(ImageGenerationError):
    """Raised when the image provider takes too long to respond."""


class InvalidPromptError(ImageGenerationError):
    """Raised when the prompt violates validation constraints."""


def detect_image_prompt(prompt: str) -> tuple[bool, str, str]:
    """Inspects a user prompt and determines if image generation is requested.

    Returns (is_image_request, clean_prompt, aspect_ratio).
    """
    clean_text = prompt.strip()
    if len(clean_text) < MIN_PROMPT_LENGTH:
        return False, clean_text, "1:1"

    if NOT_CODE_PATTERN.search(clean_text) and not any(
        k in clean_text.lower() for k in ["app icon", "logo", "wallpaper", "landing page concept"]
    ):
        return False, clean_text, "1:1"

    aspect = "1:1"
    ar_match = ASPECT_RATIO_PATTERN.search(clean_text)
    if ar_match:
        aspect = ar_match.group(1)
        clean_text = ASPECT_RATIO_PATTERN.sub("", clean_text).strip()

    is_intent = bool(
        IMAGE_INTENT_PATTERN.search(clean_text)
        or SCENE_INTENT_PATTERN.search(clean_text)
        or clean_text.lower().startswith("draw ")
        or clean_text.lower().startswith("/image ")
    )

    if not is_intent:
        return False, clean_text, aspect

    # Strip command prefixes if present
    if clean_text.lower().startswith("/image "):
        extracted = clean_text[7:].strip()
    else:
        extracted = clean_text

    return True, extracted, aspect


class ImageGenerateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    prompt: str = Field(min_length=MIN_PROMPT_LENGTH, max_length=MAX_PROMPT_LENGTH)
    aspect_ratio: Literal["1:1", "16:9", "9:16", "4:3"] = "1:1"
    seed: int | None = Field(default=None, ge=0, le=2147483647)

    @model_validator(mode="after")
    def validate_content(self) -> ImageGenerateRequest:
        if not self.prompt.strip():
            raise ValueError("Prompt cannot be empty or blank.")
        return self


class ImageGenerateResponse(BaseModel):
    id: str
    prompt: str
    aspect_ratio: str
    image_url: str
    width: int
    height: int
    provider: str
    model: str
    created_at: int


class CachedImage:
    def __init__(
        self,
        image_id: str,
        data: bytes,
        content_type: str,
        prompt: str,
        aspect_ratio: str,
        seed: int,
    ):
        self.image_id = image_id
        self.data = data
        self.content_type = content_type
        self.prompt = prompt
        self.aspect_ratio = aspect_ratio
        self.seed = seed
        self.created_at = time.time()


class InMemoryImageCache:
    """Thread-safe bounded in-memory image cache with TTL eviction."""

    def __init__(self, max_items: int = MAX_CACHE_ITEMS, ttl_seconds: float = CACHE_TTL_SECONDS):
        self._max_items = max_items
        self._ttl_seconds = ttl_seconds
        self._cache: dict[str, CachedImage] = {}
        self._lock = asyncio.Lock()

    async def put(
        self,
        image_id: str,
        data: bytes,
        content_type: str,
        prompt: str,
        aspect_ratio: str,
        seed: int,
    ) -> CachedImage:
        async with self._lock:
            now = time.time()
            # Evict expired
            expired = [k for k, v in self._cache.items() if now - v.created_at > self._ttl_seconds]
            for k in expired:
                del self._cache[k]

            # Evict oldest if still over capacity
            while len(self._cache) >= self._max_items:
                oldest_key = min(self._cache.keys(), key=lambda k: self._cache[k].created_at)
                del self._cache[oldest_key]

            entry = CachedImage(image_id, data, content_type, prompt, aspect_ratio, seed)
            self._cache[image_id] = entry
            return entry

    async def get(self, image_id: str) -> CachedImage | None:
        async with self._lock:
            entry = self._cache.get(image_id)
            if not entry:
                return None
            if time.time() - entry.created_at > self._ttl_seconds:
                del self._cache[image_id]
                return None
            return entry


class UserRateLimiter:
    """Simple sliding window rate limiter per user ID."""

    def __init__(self, max_requests: int = 10, window_seconds: float = 60.0):
        self._max_requests = max_requests
        self._window_seconds = window_seconds
        self._requests: dict[str, list[float]] = {}
        self._lock = asyncio.Lock()

    async def is_allowed(self, user_id: str) -> bool:
        async with self._lock:
            now = time.time()
            cutoff = now - self._window_seconds
            user_history = [ts for ts in self._requests.get(user_id, []) if ts > cutoff]
            if len(user_history) >= self._max_requests:
                self._requests[user_id] = user_history
                return False
            user_history.append(now)
            self._requests[user_id] = user_history
            return True


class ImageProvider(ABC):
    """Abstract interface for image generation providers."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Provider name."""

    @property
    @abstractmethod
    def model_name(self) -> str:
        """Active model name."""

    @abstractmethod
    async def generate_image(
        self,
        prompt: str,
        aspect_ratio: str = "1:1",
        seed: int | None = None,
    ) -> tuple[bytes, str]:
        """Generates image bytes and returns (image_bytes, content_type)."""


class PollinationsImageProvider(ImageProvider):
    """Free, open text-to-image provider powered by Pollinations.ai with FLUX/SDXL models."""

    def __init__(self, model: str = "flux"):
        self._model = model or "flux"

    @property
    def name(self) -> str:
        return "pollinations"

    @property
    def model_name(self) -> str:
        return self._model

    async def generate_image(
        self,
        prompt: str,
        aspect_ratio: str = "1:1",
        seed: int | None = None,
    ) -> tuple[bytes, str]:
        width, height = ASPECT_RATIOS.get(aspect_ratio, (1024, 1024))
        actual_seed = seed if seed is not None else secrets.randbelow(1_000_000)

        encoded_prompt = quote_plus(prompt.strip())
        url = (
            f"https://image.pollinations.ai/prompt/{encoded_prompt}"
            f"?width={width}&height={height}&model={self._model}&nologo=true&seed={actual_seed}"
        )

        try:
            async with httpx.AsyncClient(timeout=50.0) as client:
                response = await client.get(url, follow_redirects=True)
                if response.status_code == 200:
                    content_type = response.headers.get("content-type", "image/jpeg").split(";")[0]
                    return response.content, content_type
                if response.status_code == 429:
                    raise ProviderUnavailableError("Image provider rate limit reached. Please wait a moment.")
                raise ProviderUnavailableError(
                    f"Image generation failed with provider status {response.status_code}."
                )
        except httpx.TimeoutException as exc:
            raise ProviderTimeoutError(
                "Image generation timed out. The model server took too long to respond."
            ) from exc
        except httpx.RequestError as exc:
            raise ProviderUnavailableError(
                "Unable to connect to the image generation provider."
            ) from exc


class HuggingFaceImageProvider(ImageProvider):
    """Serverless Hugging Face text-to-image inference provider."""

    def __init__(self, api_key: str, model: str = "black-forest-labs/FLUX.1-schnell"):
        self._api_key = api_key
        self._model = model or "black-forest-labs/FLUX.1-schnell"

    @property
    def name(self) -> str:
        return "huggingface"

    @property
    def model_name(self) -> str:
        return self._model

    async def generate_image(
        self,
        prompt: str,
        aspect_ratio: str = "1:1",
        seed: int | None = None,
    ) -> tuple[bytes, str]:
        if not self._api_key:
            raise ProviderUnavailableError(
                "Hugging Face API key is not configured (IMAGE_API_KEY)."
            )

        width, height = ASPECT_RATIOS.get(aspect_ratio, (1024, 1024))
        url = f"https://router.huggingface.co/hf-inference/models/{self._model}"
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
            "x-use-cache": "false",
        }
        payload = {
            "inputs": prompt.strip(),
            "parameters": {
                "width": width,
                "height": height,
            },
        }

        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(url, headers=headers, json=payload)
                if response.status_code == 200:
                    content_type = response.headers.get("content-type", "image/jpeg").split(";")[0]
                    return response.content, content_type
                if response.status_code == 503:
                    raise ProviderUnavailableError(
                        "The Hugging Face model is currently loading. Please retry in a few moments."
                    )
                if response.status_code == 401:
                    raise ProviderUnavailableError(
                        "Hugging Face authentication failed. Check your IMAGE_API_KEY."
                    )
                raise ProviderUnavailableError(
                    f"Hugging Face generation returned error ({response.status_code})."
                )
        except httpx.TimeoutException as exc:
            raise ProviderTimeoutError(
                "Hugging Face request timed out."
            ) from exc
        except httpx.RequestError as exc:
            raise ProviderUnavailableError(
                "Unable to connect to Hugging Face inference endpoint."
            ) from exc


class LocalSDImageProvider(ImageProvider):
    """Local Stable Diffusion provider compatible with AUTOMATIC1111 / ComfyUI OpenAPI."""

    def __init__(self, base_url: str = "http://127.0.0.1:7860", model: str = "sdxl"):
        self._base_url = (base_url or "http://127.0.0.1:7860").rstrip("/")
        self._model = model or "sdxl"

    @property
    def name(self) -> str:
        return "local_sd"

    @property
    def model_name(self) -> str:
        return self._model

    async def generate_image(
        self,
        prompt: str,
        aspect_ratio: str = "1:1",
        seed: int | None = None,
    ) -> tuple[bytes, str]:
        width, height = ASPECT_RATIOS.get(aspect_ratio, (1024, 1024))
        url = f"{self._base_url}/sdapi/v1/txt2img"
        payload = {
            "prompt": prompt.strip(),
            "width": width,
            "height": height,
            "steps": 20,
            "seed": seed if seed is not None else -1,
        }

        try:
            async with httpx.AsyncClient(timeout=90.0) as client:
                response = await client.post(url, json=payload)
                if response.status_code == 200:
                    data = response.json()
                    images = data.get("images")
                    if not images or not isinstance(images, list):
                        raise ProviderUnavailableError("Local SD returned no images.")
                    image_b64 = images[0]
                    image_bytes = base64.b64decode(image_b64)
                    return image_bytes, "image/png"
                raise ProviderUnavailableError(
                    f"Local SD endpoint returned status {response.status_code}."
                )
        except httpx.TimeoutException as exc:
            raise ProviderTimeoutError(
                "Local Stable Diffusion inference timed out."
            ) from exc
        except httpx.RequestError as exc:
            raise ProviderUnavailableError(
                f"Cannot connect to Local Stable Diffusion at {self._base_url}. Ensure the server is running."
            ) from exc


class MockImageProvider(ImageProvider):
    """Mock provider for unit and integration testing without external HTTP calls."""

    # 1x1 transparent PNG bytes
    TINY_PNG = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
        b"\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc\x00\x01\x00\x00\x05"
        b"\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
    )

    def __init__(self, should_fail: bool = False, fail_type: str = "error"):
        self.should_fail = should_fail
        self.fail_type = fail_type

    @property
    def name(self) -> str:
        return "mock"

    @property
    def model_name(self) -> str:
        return "mock-flux"

    async def generate_image(
        self,
        prompt: str,
        aspect_ratio: str = "1:1",
        seed: int | None = None,
    ) -> tuple[bytes, str]:
        if self.should_fail:
            if self.fail_type == "timeout":
                raise ProviderTimeoutError("Mock provider timeout.")
            raise ProviderUnavailableError("Mock provider unavailable.")
        return self.TINY_PNG, "image/png"


def create_image_provider() -> ImageProvider:
    """Factory to initialize the configured image provider based on environment variables."""
    provider_name = os.getenv("IMAGE_PROVIDER", "pollinations").strip().lower()
    model = os.getenv("IMAGE_MODEL", "")

    if provider_name == "huggingface":
        api_key = os.getenv("IMAGE_API_KEY") or os.getenv("HF_TOKEN") or ""
        return HuggingFaceImageProvider(
            api_key=api_key,
            model=model or "black-forest-labs/FLUX.1-schnell",
        )
    if provider_name in {"local_sd", "sd", "automatic1111"}:
        base_url = os.getenv("IMAGE_API_BASE_URL", "http://127.0.0.1:7860")
        return LocalSDImageProvider(base_url=base_url, model=model or "sdxl")

    # Default: pollinations (free, zero API key required, FLUX)
    return PollinationsImageProvider(model=model or "flux")


# Global instances
image_cache = InMemoryImageCache()
rate_limiter = UserRateLimiter(max_requests=10, window_seconds=60.0)
image_provider: ImageProvider = create_image_provider()
