import asyncio
import json
import os
import secrets
import unittest
from unittest.mock import AsyncMock, patch

import httpx
from langchain_core.messages import AIMessageChunk, HumanMessage, SystemMessage
from ollama import ResponseError
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

import auth
import main
import tools


class StubModel:
    def __init__(self, chunks=None, error=None, delay=0):
        self.chunks = chunks or ["first ", "second"]
        self.error = error
        self.delay = delay
        self.received_messages = None

    async def astream(self, messages):
        self.received_messages = messages
        for chunk in self.chunks:
            await asyncio.sleep(self.delay)
            yield AIMessageChunk(content=chunk)
        if self.error:
            raise self.error


class StubOllamaClient:
    def __init__(self, models=None, error=None, **_kwargs):
        self.models = models or []
        self.error = error

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_args):
        return None

    async def list(self):
        if self.error:
            raise self.error
        return type(
            "ModelList",
            (),
            {"models": [type("Model", (), {"model": name}) for name in self.models]},
        )()


class AppTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.original_llm = main.llm
        self.original_ai_provider = main.AI_PROVIDER
        self.original_model = main.MODEL
        self.original_image_provider = main.image_provider
        tools.rate_limiter._requests.clear()
        main.AI_PROVIDER = "ollama"
        main.MODEL = "llama3.2"
        self.original_engine = auth.engine
        self.original_session_factory = auth.SessionFactory
        self.engine = create_async_engine("sqlite+aiosqlite://")
        auth.engine = self.engine
        auth.SessionFactory = async_sessionmaker(self.engine, expire_on_commit=False)
        await auth.initialize_database()
        self.session_token = secrets.token_urlsafe(32)
        async with auth.SessionFactory.begin() as db:
            user = auth.User(
                id="test-user-id",
                full_name="Test User",
                email="test@example.com",
                password_hash=auth.DUMMY_PASSWORD_HASH,
                created_at=auth._utcnow(),
            )
            db.add(user)
            db.add(
                auth.AuthSession(
                    token_hash=auth._token_hash(self.session_token),
                    user_id=user.id,
                    expires_at=auth._utcnow() + auth.SESSION_LIFETIME,
                )
            )
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=main.app),
            base_url="http://test",
        )
        self.client.cookies.set(
            auth.SESSION_COOKIE,
            self.session_token,
            domain="test.local",
            path="/",
        )

    async def asyncTearDown(self):
        main.llm = self.original_llm
        main.AI_PROVIDER = self.original_ai_provider
        main.MODEL = self.original_model
        main.image_provider = self.original_image_provider
        await self.client.aclose()
        auth.engine = self.original_engine
        auth.SessionFactory = self.original_session_factory
        await self.engine.dispose()

    async def test_registration_login_and_logout_use_server_sessions(self):
        registration = await self.client.post(
            "/api/auth/register",
            json={
                "full_name": "  Luma   User ",
                "email": "LUMA.USER@example.com",
                "password": "Correct Horse Battery 9",
            },
        )
        self.assertEqual(registration.status_code, 201)
        self.assertEqual(registration.json()["full_name"], "Luma User")
        self.assertEqual(registration.json()["email"], "luma.user@example.com")
        cookie = registration.headers["set-cookie"].casefold()
        self.assertIn("httponly", cookie)
        self.assertIn("samesite=lax", cookie)
        self.assertNotIn("secure", cookie)
        self.assertEqual(
            (await self.client.get("/api/auth/me")).json()["id"],
            registration.json()["id"],
        )

        duplicate = await self.client.post(
            "/api/auth/register",
            json={
                "full_name": "Another User",
                "email": "luma.user@example.com",
                "password": "Correct Horse Battery 9",
            },
        )
        self.assertEqual(duplicate.status_code, 409)

        logout = await self.client.post("/api/auth/logout")
        self.assertEqual(logout.status_code, 204)
        self.assertEqual((await self.client.get("/api/auth/me")).status_code, 401)

        login = await self.client.post(
            "/api/auth/login",
            json={
                "email": "luma.user@example.com",
                "password": "Correct Horse Battery 9",
            },
        )
        self.assertEqual(login.status_code, 200)
        self.assertEqual((await self.client.get("/api/auth/me")).status_code, 200)

    async def test_invalid_credentials_and_unauthed_chat_are_rejected(self):
        self.client.cookies.clear()
        self.assertEqual(
            (await self.client.get("/api/health")).json(),
            {"status": "ok"},
        )
        self.assertEqual(
            (await self.client.get("/api/health/ai")).status_code,
            401,
        )
        invalid_login = await self.client.post(
            "/api/auth/login",
            json={"email": "test@example.com", "password": "incorrect password"},
        )
        self.assertEqual(invalid_login.status_code, 401)
        self.assertNotIn(auth.SESSION_COOKIE, self.client.cookies)
        self.assertEqual(
            (await self.client.post("/api/chat/stream", json={"messages": [
                {"role": "user", "content": "hello"},
            ]})).status_code,
            401,
        )
        self.assertEqual(
            (await self.client.post("/api/markdown", json={"content": "hello"})).status_code,
            401,
        )

    async def test_public_health_is_minimal_and_does_not_check_model_provider(self):
        self.client.cookies.clear()
        with patch.object(main, "OllamaAsyncClient") as client_factory:
            response = await self.client.get("/api/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})
        client_factory.assert_not_called()

    async def test_registration_validates_email_and_password_length(self):
        response = await self.client.post(
            "/api/auth/register",
            json={
                "full_name": "Test User",
                "email": "not-an-email",
                "password": "short",
            },
        )
        self.assertEqual(response.status_code, 422)

    async def test_auth_rejects_cross_origin_posts(self):
        response = await self.client.post(
            "/api/auth/login",
            headers={"Origin": "https://attacker.example"},
            json={"email": "test@example.com", "password": "password"},
        )
        self.assertEqual(response.status_code, 403)

    async def test_health_reports_local_model(self):
        with patch.object(
            main,
            "OllamaAsyncClient",
            side_effect=lambda **kwargs: StubOllamaClient(
                models=["llama3.2:latest"],
                **kwargs,
            ),
        ):
            response = await self.client.get("/api/health/ai")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {
                "status": "ok",
                "model": "llama3.2",
                "ollama_connected": True,
                "model_available": True,
            },
        )

    async def test_health_uses_configured_ollama_url_and_model(self):
        with patch.multiple(
            main,
            OLLAMA_BASE_URL="https://ollama.example",
            MODEL="qwen2.5",
        ):
            with patch.object(
                main,
                "OllamaAsyncClient",
                side_effect=lambda **kwargs: StubOllamaClient(
                    models=["qwen2.5:latest"],
                    **kwargs,
                ),
            ) as client_factory:
                response = await self.client.get("/api/health/ai")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["model"], "qwen2.5")
        self.assertTrue(response.json()["model_available"])
        client_factory.assert_called_once_with(
            host="https://ollama.example",
            timeout=3.0,
        )

    async def test_health_reports_missing_local_model(self):
        with patch.object(
            main,
            "OllamaAsyncClient",
            side_effect=lambda **kwargs: StubOllamaClient(**kwargs),
        ):
            response = await self.client.get("/api/health/ai")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "model_missing")
        self.assertTrue(response.json()["ollama_connected"])
        self.assertFalse(response.json()["model_available"])

    async def test_health_reports_unavailable_service(self):
        with patch.object(
            main,
            "OllamaAsyncClient",
            side_effect=ConnectionError("private connection detail"),
        ):
            response = await self.client.get("/api/health/ai")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "unavailable")
        self.assertNotIn("private connection detail", response.text)

    async def test_stream_sends_each_token_before_generation_finishes(self):
        model = StubModel(chunks=["first", "second"], delay=0.08)
        main.llm = model
        response = await main.chat_stream(
            main.ChatRequest(
                messages=[main.ChatMessage(role="user", content="hello")],
            ),
        )
        sent = []
        first_token_sent = asyncio.Event()

        async def receive():
            await asyncio.Future()

        async def send(message):
            sent.append(message)
            if (
                message["type"] == "http.response.body"
                and b'"text": "first"' in message.get("body", b"")
            ):
                first_token_sent.set()

        scope = {
            "type": "http",
            "asgi": {"version": "3.0"},
            "http_version": "1.1",
            "method": "POST",
            "scheme": "http",
            "path": "/api/chat/stream",
            "raw_path": b"/api/chat/stream",
            "query_string": b"",
            "headers": [],
            "client": ("test", 1234),
            "server": ("test", 8000),
        }
        task = asyncio.create_task(response(scope, receive, send))
        await asyncio.wait_for(first_token_sent.wait(), timeout=1)
        self.assertFalse(task.done())
        await task
        body_chunks = [
            message["body"]
            for message in sent
            if message["type"] == "http.response.body" and message.get("body")
        ]
        self.assertGreaterEqual(len(body_chunks), 3)
        self.assertIn(b'"text": "first"', body_chunks[0])
        self.assertIn(b'"text": "second"', body_chunks[1])

    async def test_stream_passes_prior_conversation_messages(self):
        model = StubModel()
        main.llm = model
        response = await self.client.post(
            "/api/chat/stream",
            json={
                "messages": [
                    {"role": "user", "content": "Remember the word amber."},
                    {"role": "assistant", "content": "I will remember amber."},
                    {"role": "user", "content": "What word should you remember?"},
                ],
            },
        )
        self.assertEqual(response.status_code, 200)
        events = [
            (line.removeprefix("event: ").strip(), json.loads(data.removeprefix("data: ")))
            for line, data in zip(
                [line for line in response.text.splitlines() if line.startswith("event:")],
                [line for line in response.text.splitlines() if line.startswith("data:")],
            )
        ]
        self.assertEqual([event for event, _payload in events], ["token", "token", "done"])
        self.assertEqual([payload["text"] for event, payload in events if event == "token"], ["first ", "second"])
        self.assertEqual(len(model.received_messages), 3)
        self.assertIsInstance(model.received_messages[0], HumanMessage)
        self.assertEqual(model.received_messages[0].content, "Remember the word amber.")
        self.assertEqual(model.received_messages[2].content, "What word should you remember?")

    async def test_download_request_adds_file_format_instructions(self):
        model = StubModel()
        main.llm = model
        response = await self.client.post(
            "/api/chat/stream",
            json={
                "messages": [
                    {
                        "role": "user",
                        "content": "Make this code available as an HTML file.",
                    },
                ],
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertIsInstance(model.received_messages[0], SystemMessage)
        self.assertIn("File: filename.ext", model.received_messages[0].content)
        self.assertIsInstance(model.received_messages[-1], HumanMessage)
        self.assertEqual(
            model.received_messages[-1].content,
            "Make this code available as an HTML file.",
        )

    async def test_ordinary_code_request_does_not_add_file_instructions(self):
        model = StubModel()
        main.llm = model
        response = await self.client.post(
            "/api/chat/stream",
            json={
                "messages": [
                    {"role": "user", "content": "Explain how a Python loop works."},
                ],
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(model.received_messages), 1)
        self.assertIsInstance(model.received_messages[0], HumanMessage)

    async def test_download_intent_recognizes_common_file_requests(self):
        prompts = [
            "Give me the code in a ready-to-download format.",
            "Create a downloadable Python file.",
            "Make this code available as an HTML file.",
            "Give me the complete project files.",
            "Generate a JavaScript file I can download.",
        ]
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                self.assertTrue(main._requests_downloadable_code(prompt))
        self.assertFalse(
            main._requests_downloadable_code("Explain how a Python loop works.")
        )

    async def test_invalid_conversation_is_rejected_without_echoing_content(self):
        response = await self.client.post(
            "/api/chat/stream",
            json={
                "messages": [
                    {"role": "user", "content": "private message"},
                    {"role": "assistant", "content": "private assistant response"},
                ],
            },
        )
        self.assertEqual(response.status_code, 422)
        self.assertNotIn("private message", response.text)
        self.assertNotIn("private assistant response", response.text)

    async def test_oversized_message_is_rejected_without_echoing_content(self):
        private_content = "p" * (main.MAX_MESSAGE_LENGTH + 1)
        response = await self.client.post(
            "/api/chat/stream",
            json={"messages": [{"role": "user", "content": private_content}]},
        )
        self.assertEqual(response.status_code, 422)
        self.assertNotIn(private_content, response.text)

    async def test_oversized_history_is_rejected(self):
        response = await self.client.post(
            "/api/chat/stream",
            json={
                "messages": [
                    {"role": "user", "content": "x" * 10_001},
                    {"role": "user", "content": "y" * 10_001},
                    {"role": "user", "content": "z" * 10_001},
                    {"role": "user", "content": "w" * 10_001},
                    {"role": "user", "content": "latest"},
                ],
            },
        )
        self.assertEqual(response.status_code, 422)
        self.assertEqual(
            response.json()["detail"],
            "Invalid request. Check message count, size, and order.",
        )

    async def test_too_many_history_messages_are_rejected(self):
        response = await self.client.post(
            "/api/chat/stream",
            json={
                "messages": [
                    {"role": "user", "content": "hello"}
                    for _ in range(main.MAX_HISTORY_MESSAGES + 1)
                ],
            },
        )
        self.assertEqual(response.status_code, 422)

    async def test_model_errors_are_sanitized_in_stream(self):
        main.llm = StubModel(error=ResponseError("model llama3.2 not found", 404))
        response = await self.client.post(
            "/api/chat/stream",
            json={"messages": [{"role": "user", "content": "hello"}]},
        )
        self.assertIn(
            'event: error\ndata: {"message": "Luma AI is temporarily unavailable. Please try again."}',
            response.text,
        )
        self.assertNotIn("Ollama", response.text)
        self.assertNotIn("not found", response.text)
        self.assertNotIn("404", response.text)

    async def test_missing_model_error_is_provider_independent(self):
        main.llm = StubModel(error=ResponseError("model llama3.2 not found", 404))
        response = await self.client.post(
            "/api/chat/stream",
            json={"messages": [{"role": "user", "content": "hello"}]},
        )
        self.assertIn("Luma AI is temporarily unavailable", response.text)
        self.assertNotIn("Ollama", response.text)

    async def test_timeout_error_is_sanitized_in_stream(self):
        main.llm = StubModel(error=httpx.ReadTimeout("private timeout detail"))
        response = await self.client.post(
            "/api/chat/stream",
            json={"messages": [{"role": "user", "content": "hello"}]},
        )
        self.assertIn("Luma AI is temporarily unavailable", response.text)
        self.assertNotIn("Ollama", response.text)
        self.assertNotIn("private timeout detail", response.text)

    async def test_unexpected_error_is_sanitized_in_stream(self):
        main.llm = StubModel(error=RuntimeError("private internal detail"))
        response = await self.client.post(
            "/api/chat/stream",
            json={"messages": [{"role": "user", "content": "hello"}]},
        )
        self.assertIn("Luma AI is temporarily unavailable", response.text)
        self.assertNotIn("private internal detail", response.text)
        self.assertNotIn("Ollama", response.text)

    async def test_markdown_is_sanitized(self):
        response = await self.client.post(
            "/api/markdown",
            json={
                "content": (
                    "## Safe heading\n\n"
                    "<script>alert(1)</script>\n\n"
                    "[unsafe](javascript:alert(1))\n\n"
                    "```python\nprint('safe')\n```"
                ),
            },
        )
        self.assertEqual(response.status_code, 200)
        rendered = response.json()["html"]
        self.assertIn("<h2>Safe heading</h2>", rendered)
        self.assertNotIn("<script>", rendered)
        self.assertNotIn('href="javascript:', rendered)
        self.assertIn('class="language-python"', rendered)

    async def test_page_sets_browser_security_headers(self):
        response = await self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn("script-src 'self'", response.headers["content-security-policy"])
        self.assertEqual(response.headers["x-content-type-options"], "nosniff")
        self.assertEqual(response.headers["referrer-policy"], "no-referrer")
        self.assertIn("<title>Luma AI</title>", response.text)
        self.assertIn('aria-label="Luma AI home"', response.text)
        self.assertIn("<strong>Luma AI</strong>", response.text)
        self.assertNotIn("AI Agent", response.text)
        self.assertNotIn("Ollama", response.text)
        self.assertIn(">Connecting…</span>", response.text)

    async def test_cross_origin_options_preflight_allows_trusted_origin(self):
        response = await self.client.options(
            "/api/auth/login",
            headers={
                "Origin": "http://127.0.0.1:8765",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "Content-Type",
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.headers.get("access-control-allow-origin"),
            "http://127.0.0.1:8765",
        )
        self.assertEqual(
            response.headers.get("access-control-allow-credentials"),
            "true",
        )

    async def test_cross_origin_login_allows_trusted_origin(self):
        login = await self.client.post(
            "/api/auth/login",
            headers={"Origin": "http://127.0.0.1:8765"},
            json={
                "email": "test@example.com",
                "password": "incorrect-password",
            },
        )
        self.assertEqual(login.status_code, 401)
        self.assertEqual(
            login.headers.get("access-control-allow-origin"),
            "http://127.0.0.1:8765",
        )
        self.assertEqual(
            login.json()["detail"],
            "Email or password is incorrect.",
        )

    async def test_cross_origin_register_allows_trusted_origin(self):
        registration = await self.client.post(
            "/api/auth/register",
            headers={"Origin": "http://127.0.0.1:8765"},
            json={
                "full_name": "Trusted Cross Origin User",
                "email": "trusted.cross@example.com",
                "password": "Correct Horse Battery 9",
            },
        )
        self.assertEqual(registration.status_code, 201)
        self.assertEqual(
            registration.headers.get("access-control-allow-origin"),
            "http://127.0.0.1:8765",
        )
        self.assertIn(auth.SESSION_COOKIE, registration.headers.get("set-cookie", ""))

    async def test_cross_origin_markdown_requires_auth(self):
        self.client.cookies.clear()
        unauthed = await self.client.post(
            "/api/markdown",
            headers={"Origin": "http://127.0.0.1:8765"},
            json={"content": "# Test"},
        )
        self.assertEqual(unauthed.status_code, 401)

    async def test_openai_compatible_model_streaming(self):
        model = main.OpenAICompatibleModel(
            model="llama-3.2-3b-preview",
            base_url="https://api.groq.com/openai/v1",
            api_key="test-key",
        )
        messages = [HumanMessage(content="Explain the second law of thermodynamics.")]
        
        async def mock_aiter_lines(_self):
            yield 'data: {"choices": [{"delta": {"content": "The second law "}}]}'
            yield 'data: {"choices": [{"delta": {"content": "of thermodynamics states..."}}]}'
            yield 'data: [DONE]'

        class MockResponse:
            status_code = 200
            aiter_lines = mock_aiter_lines
            async def __aenter__(self):
                return self
            async def __aexit__(self, *args):
                pass

        class MockClient:
            def stream(self, method, url, **kwargs):
                return MockResponse()
            async def __aenter__(self):
                return self
            async def __aexit__(self, *args):
                pass

        with patch.object(httpx, "AsyncClient", return_value=MockClient()):
            chunks = []
            async for chunk in model.astream(messages):
                chunks.append(chunk.content)
            self.assertEqual(chunks, ["The second law ", "of thermodynamics states..."])

    async def test_detect_image_prompt_intent(self):
        # Must detect required prompts from objective
        p1 = "Generate a premium minimalist website landing page concept."
        p2 = "Create a realistic futuristic city at sunset."
        p3 = "Design a modern app icon using off-white, white, and black."
        p4 = "Generate a cinematic landscape in 16:9 format."
        p5 = "Draw a cute red panda drinking coffee in a cafe"

        self.assertTrue(tools.detect_image_prompt(p1)[0])
        self.assertTrue(tools.detect_image_prompt(p2)[0])
        self.assertTrue(tools.detect_image_prompt(p3)[0])
        is_p4, clean_p4, aspect_p4 = tools.detect_image_prompt(p4)
        self.assertTrue(is_p4)
        self.assertEqual(aspect_p4, "16:9")
        self.assertTrue(tools.detect_image_prompt(p5)[0])

        # Must not falsely detect normal questions or code requests
        self.assertFalse(tools.detect_image_prompt("What is image generation?")[0])
        self.assertFalse(tools.detect_image_prompt("Generate a python function to resize an image")[0])
        self.assertFalse(tools.detect_image_prompt("Create a modern login form in HTML and CSS")[0])
        self.assertFalse(tools.detect_image_prompt("Explain how diffusion models work")[0])

    async def test_image_generation_success_mocked(self):
        mock_provider = tools.MockImageProvider()
        main.image_provider = mock_provider

        response = await self.client.post(
            "/api/image/generate",
            json={
                "prompt": "a serene minimalist Japanese zen garden with stones",
                "aspect_ratio": "16:9",
            },
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("id", data)
        self.assertEqual(data["aspect_ratio"], "16:9")
        self.assertEqual(data["width"], 1280)
        self.assertEqual(data["height"], 720)
        self.assertEqual(data["provider"], "mock")
        self.assertTrue(data["image_url"].startswith("/api/image/view/"))

        # Verify image retrieval endpoint
        img_resp = await self.client.get(data["image_url"])
        self.assertEqual(img_resp.status_code, 200)
        self.assertEqual(img_resp.headers["content-type"], "image/png")
        self.assertEqual(img_resp.content, tools.MockImageProvider.TINY_PNG)

    async def test_image_generation_unauthenticated(self):
        unauth_client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=main.app),
            base_url="http://test",
        )
        try:
            response = await unauth_client.post(
                "/api/image/generate",
                json={"prompt": "futuristic city", "aspect_ratio": "1:1"},
            )
            self.assertEqual(response.status_code, 401)
        finally:
            await unauth_client.aclose()

    async def test_image_generation_invalid_prompt(self):
        # Empty prompt
        resp = await self.client.post(
            "/api/image/generate",
            json={"prompt": "   ", "aspect_ratio": "1:1"},
        )
        self.assertEqual(resp.status_code, 422)

        # Exceeds max length
        resp_long = await self.client.post(
            "/api/image/generate",
            json={"prompt": "x" * 1001, "aspect_ratio": "1:1"},
        )
        self.assertEqual(resp_long.status_code, 422)

    async def test_image_generation_invalid_aspect_ratio(self):
        resp = await self.client.post(
            "/api/image/generate",
            json={"prompt": "valid prompt", "aspect_ratio": "21:9"},
        )
        self.assertEqual(resp.status_code, 422)

    async def test_image_generation_provider_timeout(self):
        main.image_provider = tools.MockImageProvider(should_fail=True, fail_type="timeout")
        resp = await self.client.post(
            "/api/image/generate",
            json={"prompt": "a cinematic skyline", "aspect_ratio": "1:1"},
        )
        self.assertEqual(resp.status_code, 504)
        self.assertIn("timeout", resp.json()["detail"].lower())

    async def test_image_generation_provider_unavailable(self):
        main.image_provider = tools.MockImageProvider(should_fail=True, fail_type="error")
        resp = await self.client.post(
            "/api/image/generate",
            json={"prompt": "a cinematic skyline", "aspect_ratio": "1:1"},
        )
        self.assertEqual(resp.status_code, 503)
        self.assertIn("unavailable", resp.json()["detail"].lower())

    async def test_huggingface_missing_api_key(self):
        hf_provider = tools.HuggingFaceImageProvider(api_key="")
        with self.assertRaises(tools.ProviderUnavailableError):
            await hf_provider.generate_image("a testing prompt")

    async def test_image_generation_rate_limiting(self):
        main.image_provider = tools.MockImageProvider()
        # Reset limiter for this test
        tools.rate_limiter._requests["test-user-id"] = []
        for _ in range(10):
            allowed = await tools.rate_limiter.is_allowed("test-user-id")
            self.assertTrue(allowed)
        # 11th request must be blocked
        allowed_11th = await tools.rate_limiter.is_allowed("test-user-id")
        self.assertFalse(allowed_11th)

        # Generating an image when rate-limited returns HTTP 429
        resp = await self.client.post(
            "/api/image/generate",
            json={"prompt": "blocked prompt", "aspect_ratio": "1:1"},
        )
        self.assertEqual(resp.status_code, 429)

    async def test_chat_stream_with_image_intent(self):
        main.image_provider = tools.MockImageProvider()
        tools.rate_limiter._requests["test-user-id"] = []

        response = await self.client.post(
            "/api/chat/stream",
            json={
                "messages": [
                    {"role": "user", "content": "Generate a cinematic landscape in 16:9 format."}
                ]
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["content-type"], "text/event-stream; charset=utf-8")
        text = response.text
        self.assertIn("event: image", text)
        self.assertIn('"aspect_ratio": "16:9"', text)
        self.assertIn("Here is your generated image.", text)
        self.assertIn("event: done", text)

    async def test_chat_stream_normal_text_chat_unaffected(self):
        main.llm = StubModel(["Quantum ", "computing ", "uses qubits."])
        response = await self.client.post(
            "/api/chat/stream",
            json={
                "messages": [
                    {"role": "user", "content": "Explain how quantum computers work."}
                ]
            },
        )
        self.assertEqual(response.status_code, 200)
        text = response.text
        self.assertNotIn("event: image", text)
        self.assertIn("Quantum ", text)
        self.assertIn("computing ", text)
        self.assertIn("uses qubits.", text)
        self.assertIn("event: done", text)

    async def test_image_proxy_security(self):
        # Disallow arbitrary external hosts
        bad_resp = await self.client.get("/api/image/proxy?url=https://attacker-domain.com/evil.jpg")
        self.assertEqual(bad_resp.status_code, 400)
        self.assertIn("Disallowed image host", bad_resp.json()["detail"])

    async def test_voice_transcribe_unauthenticated_rejected(self):
        self.client.cookies.clear()
        resp = await self.client.post(
            "/api/voice/transcribe",
            content=b"dummy audio content that is long enough to pass length checks",
            headers={"Content-Type": "audio/webm"},
        )
        self.assertEqual(resp.status_code, 401)

    async def test_voice_transcribe_empty_or_short_body_rejected(self):
        resp_empty = await self.client.post(
            "/api/voice/transcribe",
            content=b"",
            headers={"Content-Type": "audio/webm"},
        )
        self.assertEqual(resp_empty.status_code, 400)
        self.assertIn("Empty audio", resp_empty.json()["detail"])

        resp_short = await self.client.post(
            "/api/voice/transcribe",
            content=b"too short",
            headers={"Content-Type": "audio/webm"},
        )
        self.assertEqual(resp_short.status_code, 400)
        self.assertIn("too short", resp_short.json()["detail"])

    async def test_voice_transcribe_success(self):
        audio_payload = b"RIFF" + b"\x00" * 200  # valid length > 100 bytes
        mock_response = httpx.Response(
            200,
            json={"text": "Hello Luma AI, this is a real-time voice test."},
            request=httpx.Request("POST", "https://api.groq.com/openai/v1/audio/transcriptions"),
        )
        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch.dict(os.environ, {"GROQ_API_KEY": "mock-test-key"}):
            with patch("main.httpx.AsyncClient", return_value=mock_client):
                resp = await self.client.post(
                    "/api/voice/transcribe",
                    content=audio_payload,
                    headers={"Content-Type": "audio/webm"},
                )
                self.assertEqual(resp.status_code, 200)
                self.assertEqual(resp.json(), {"text": "Hello Luma AI, this is a real-time voice test."})

    async def test_voice_transcribe_rate_limit(self):
        audio_payload = b"RIFF" + b"\x00" * 200
        mock_response = httpx.Response(
            429,
            json={"error": {"message": "Rate limit reached"}},
            request=httpx.Request("POST", "https://api.groq.com/openai/v1/audio/transcriptions"),
        )
        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch.dict(os.environ, {"GROQ_API_KEY": "mock-test-key"}):
            with patch("main.httpx.AsyncClient", return_value=mock_client):
                resp = await self.client.post(
                    "/api/voice/transcribe",
                    content=audio_payload,
                    headers={"Content-Type": "audio/webm"},
                )
                self.assertEqual(resp.status_code, 429)
                self.assertIn("rate limit exceeded", resp.json()["detail"].lower())


if __name__ == "__main__":
    unittest.main()

