import asyncio
import base64
import hashlib
import hmac
import io
import json
import os
import secrets
import time
from datetime import datetime, timedelta, timezone
from unittest import IsolatedAsyncioTestCase
from unittest.mock import patch

import httpx
from PIL import Image
from pwdlib.hashers.argon2 import Argon2Hasher

# Configure test environment
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///:memory:"
os.environ["COOKIE_SECURE"] = "false"

from auth import (
    CSRF_COOKIE,
    SESSION_COOKIE,
    AuthSession,
    Base,
    SigningKeyModel,
    User,
    _email_digest,
    _token_hash,
    _utcnow,
    _validate_image_magic_bytes,
    compute_request_signature,
    engine as auth_engine,
    initialize_database,
    password_hasher,
)
from main import app


class SecurityHardeningTests(IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.original_engine = auth_engine
        import auth
        self.original_session_factory = auth.SessionFactory
        from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
        self.engine = create_async_engine("sqlite+aiosqlite://")
        auth.engine = self.engine
        auth.SessionFactory = async_sessionmaker(self.engine, expire_on_commit=False)
        await auth.initialize_database()
        self.transport = httpx.ASGITransport(app=app)
        self.client = httpx.AsyncClient(transport=self.transport, base_url="http://test")

    async def asyncTearDown(self):
        await self.client.aclose()
        import auth
        auth.engine = self.original_engine
        auth.SessionFactory = self.original_session_factory
        await self.engine.dispose()

    async def _create_test_user(self, email="secuser@example.com", password="Password123!@#"):
        hashed = await asyncio.to_thread(password_hasher.hash, password)
        from auth import SessionFactory
        async with SessionFactory.begin() as db:
            user = User(
                id="sec-user-id-1",
                full_name="Security Test User",
                email=email,
                password_hash=hashed,
                created_at=_utcnow(),
            )
            db.add(user)
            await db.flush()
            user_id = user.id

        login_res = await self.client.post("/api/auth/login", json={"email": email, "password": password})
        self.assertEqual(login_res.status_code, 200)
        return user_id, login_res.cookies.get(SESSION_COOKIE), login_res.cookies.get(CSRF_COOKIE)

    # ---------------------------------------------------------
    # 1. Bcrypt Password Security & Transparent Argon2 Migration
    # ---------------------------------------------------------
    async def test_passwords_hashed_with_bcrypt_12_rounds(self):
        reg_res = await self.client.post("/api/auth/register", json={
            "full_name": "Bcrypt User",
            "email": "bcrypt_user@example.com",
            "password": "SuperSecurePassword123!"
        })
        self.assertEqual(reg_res.status_code, 201)
        user_data = reg_res.json()
        self.assertNotIn("password", user_data)
        self.assertNotIn("password_hash", user_data)

        from auth import SessionFactory
        from sqlalchemy import select
        async with SessionFactory() as db:
            user = await db.scalar(select(User).where(User.email == "bcrypt_user@example.com"))
            self.assertIsNotNone(user)
            # Bcrypt hash format begins with $2b$12$
            self.assertTrue(user.password_hash.startswith("$2b$12$"), f"Expected bcrypt 12-round hash, got: {user.password_hash}")

    async def test_legacy_argon2_password_migration_to_bcrypt_on_login(self):
        legacy_argon2_hash = Argon2Hasher().hash("LegacySecret999!")
        self.assertTrue(legacy_argon2_hash.startswith("$argon2id$"))

        from auth import SessionFactory
        from sqlalchemy import select
        async with SessionFactory.begin() as db:
            user = User(
                full_name="Legacy Argon2 User",
                email="argon_legacy@example.com",
                password_hash=legacy_argon2_hash,
                created_at=_utcnow(),
            )
            db.add(user)

        # Login with legacy argon2 password
        login_res = await self.client.post("/api/auth/login", json={
            "email": "argon_legacy@example.com",
            "password": "LegacySecret999!"
        })
        self.assertEqual(login_res.status_code, 200)

        # Verify password hash in database was automatically upgraded to Bcrypt
        async with SessionFactory() as db:
            updated_user = await db.scalar(select(User).where(User.email == "argon_legacy@example.com"))
            self.assertTrue(
                updated_user.password_hash.startswith("$2b$12$"),
                f"Password should have migrated to bcrypt on login, got: {updated_user.password_hash}"
            )

    # ---------------------------------------------------------
    # 2. HTTPS Enforcement & Security Headers
    # ---------------------------------------------------------
    async def test_hsts_and_security_headers_present(self):
        res = await self.client.get("/")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.headers.get("x-content-type-options"), "nosniff")
        self.assertEqual(res.headers.get("x-frame-options"), "DENY")
        self.assertIn("microphone=(self)", res.headers.get("permissions-policy", ""))
        self.assertIn("camera=(self)", res.headers.get("permissions-policy", ""))

    async def test_insecure_http_rejected_or_redirected_in_production(self):
        with patch.dict(os.environ, {"FORCE_HTTPS": "true"}):
            # Plaintext HTTP GET redirected with 308
            get_res = await self.client.get("/", headers={"x-forwarded-proto": "http"}, follow_redirects=False)
            self.assertEqual(get_res.status_code, 308)
            self.assertTrue(get_res.headers.get("location", "").startswith("https://"))

            # Plaintext HTTP POST with credentials rejected with 403 Forbidden
            post_res = await self.client.post("/api/auth/login", json={"email": "a@b.com", "password": "123"}, headers={"x-forwarded-proto": "http"})
            self.assertEqual(post_res.status_code, 403)
            self.assertIn("Insecure HTTP requests are rejected", post_res.json()["detail"])

            # HTTPS request receives Strict-Transport-Security
            secure_res = await self.client.get("/", headers={"x-forwarded-proto": "https"})
            self.assertIn("max-age=31536000", secure_res.headers.get("strict-transport-security", ""))

    # ---------------------------------------------------------
    # 3. HMAC-SHA-256 Request Integrity & Replay Protection
    # ---------------------------------------------------------
    async def test_ephemeral_signing_key_provisioning(self):
        _, session_token, _ = await self._create_test_user()
        res = await self.client.post("/api/auth/signing-key", cookies={SESSION_COOKIE: session_token})
        self.assertEqual(res.status_code, 200)
        key_data = res.json()
        self.assertTrue(key_data["key_id"].startswith("key_"))
        self.assertEqual(len(key_data["signing_secret"]), 64)
        self.assertEqual(key_data["algorithm"], "HMAC-SHA256")
        self.assertIn("expires_at", key_data)

    async def test_hmac_request_signing_valid_request_accepted(self):
        _, session_token, csrf_token = await self._create_test_user()
        key_res = await self.client.post("/api/auth/signing-key", cookies={SESSION_COOKIE: session_token})
        key_data = key_res.json()
        secret = key_data["signing_secret"]
        key_id = key_data["key_id"]

        method = "PUT"
        path = "/api/user/profile"
        payload = {"bio": "Cryptographically verified bio"}
        body_bytes = json.dumps(payload).encode("utf-8")
        timestamp = str(int(time.time()))
        nonce = f"nonce_{time.time()}_{os.urandom(4).hex()}"

        body_hash = hashlib.sha256(body_bytes).hexdigest()
        canonical = f"{method}\n{path}\n{timestamp}\n{nonce}\n{body_hash}"
        sig = hmac.new(secret.encode("utf-8"), canonical.encode("utf-8"), hashlib.sha256).hexdigest()

        headers = {
            "Content-Type": "application/json",
            "X-Signature": sig,
            "X-Timestamp": timestamp,
            "X-Nonce": nonce,
            "X-Key-Id": key_id,
            "X-CSRF-Token": csrf_token or "",
        }

        res = await self.client.put(path, content=body_bytes, headers=headers, cookies={SESSION_COOKIE: session_token})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["bio"], "Cryptographically verified bio")
        # Response integrity verification
        self.assertIn("x-response-signature", res.headers)
        self.assertEqual(res.headers.get("x-response-nonce"), nonce)

    async def test_tampered_request_body_rejected(self):
        _, session_token, _ = await self._create_test_user()
        key_res = await self.client.post("/api/auth/signing-key", cookies={SESSION_COOKIE: session_token})
        key_data = key_res.json()
        secret = key_data["signing_secret"]
        key_id = key_data["key_id"]

        method = "PUT"
        path = "/api/user/profile"
        original_body = json.dumps({"bio": "Original bio"}).encode("utf-8")
        timestamp = str(int(time.time()))
        nonce = f"nonce_{time.time()}_{os.urandom(4).hex()}"

        body_hash = hashlib.sha256(original_body).hexdigest()
        canonical = f"{method}\n{path}\n{timestamp}\n{nonce}\n{body_hash}"
        sig = hmac.new(secret.encode("utf-8"), canonical.encode("utf-8"), hashlib.sha256).hexdigest()

        # Attacker modifies the body payload in transit
        tampered_body = json.dumps({"bio": "TAMPERED BIO BY ATTACKER"}).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "X-Signature": sig,
            "X-Timestamp": timestamp,
            "X-Nonce": nonce,
            "X-Key-Id": key_id,
        }

        res = await self.client.put(path, content=tampered_body, headers=headers, cookies={SESSION_COOKIE: session_token})
        self.assertEqual(res.status_code, 403)
        self.assertIn("Invalid request signature", res.json()["detail"])

    async def test_expired_timestamp_rejected(self):
        _, session_token, _ = await self._create_test_user()
        key_res = await self.client.post("/api/auth/signing-key", cookies={SESSION_COOKIE: session_token})
        key_data = key_res.json()
        secret = key_data["signing_secret"]
        key_id = key_data["key_id"]

        method = "PUT"
        path = "/api/user/profile"
        body_bytes = json.dumps({"bio": "Expired"}).encode("utf-8")
        # Timestamp 10 minutes in the past (> 300s tolerance)
        expired_ts = str(int(time.time()) - 600)
        nonce = f"nonce_{time.time()}_{os.urandom(4).hex()}"

        body_hash = hashlib.sha256(body_bytes).hexdigest()
        canonical = f"{method}\n{path}\n{expired_ts}\n{nonce}\n{body_hash}"
        sig = hmac.new(secret.encode("utf-8"), canonical.encode("utf-8"), hashlib.sha256).hexdigest()

        headers = {
            "Content-Type": "application/json",
            "X-Signature": sig,
            "X-Timestamp": expired_ts,
            "X-Nonce": nonce,
            "X-Key-Id": key_id,
        }

        res = await self.client.put(path, content=body_bytes, headers=headers, cookies={SESSION_COOKIE: session_token})
        self.assertEqual(res.status_code, 403)
        self.assertIn("timestamp expired", res.json()["detail"])

    async def test_replayed_nonce_rejected(self):
        _, session_token, _ = await self._create_test_user()
        key_res = await self.client.post("/api/auth/signing-key", cookies={SESSION_COOKIE: session_token})
        key_data = key_res.json()
        secret = key_data["signing_secret"]
        key_id = key_data["key_id"]

        method = "PUT"
        path = "/api/user/profile"
        body_bytes = json.dumps({"bio": "Replay test"}).encode("utf-8")
        timestamp = str(int(time.time()))
        nonce = f"fixed_reused_nonce_{os.urandom(4).hex()}"

        body_hash = hashlib.sha256(body_bytes).hexdigest()
        canonical = f"{method}\n{path}\n{timestamp}\n{nonce}\n{body_hash}"
        sig = hmac.new(secret.encode("utf-8"), canonical.encode("utf-8"), hashlib.sha256).hexdigest()

        headers = {
            "Content-Type": "application/json",
            "X-Signature": sig,
            "X-Timestamp": timestamp,
            "X-Nonce": nonce,
            "X-Key-Id": key_id,
        }

        # First request succeeds
        res1 = await self.client.put(path, content=body_bytes, headers=headers, cookies={SESSION_COOKIE: session_token})
        self.assertEqual(res1.status_code, 200)

        # Second request with identical nonce is rejected as a replay attack
        res2 = await self.client.put(path, content=body_bytes, headers=headers, cookies={SESSION_COOKIE: session_token})
        self.assertEqual(res2.status_code, 403)
        self.assertIn("Replay attack detected", res2.json()["detail"])

    # ---------------------------------------------------------
    # 4. Upload & File Protection (Magic Bytes & Size Validation)
    # ---------------------------------------------------------
    async def test_upload_magic_bytes_validation(self):
        # Valid JPEG magic bytes
        self.assertEqual(_validate_image_magic_bytes(b"\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01"), "image/jpeg")
        # Valid PNG magic bytes
        self.assertEqual(_validate_image_magic_bytes(b"\x89PNG\r\n\x1a\n\x00\x00\x00\r"), "image/png")
        # Fake malicious file (e.g. bash script disguised as image)
        with self.assertRaises(Exception):
            _validate_image_magic_bytes(b"#!/bin/bash\nrm -rf /")

    async def test_upload_profile_photo_disguised_file_rejected(self):
        _, session_token, _ = await self._create_test_user()
        fake_payload = base64.b64encode(b"malicious script content").decode("ascii")

        res = await self.client.post(
            "/api/user/profile/photo",
            json={"image": f"data:image/jpeg;base64,{fake_payload}"},
            cookies={SESSION_COOKIE: session_token},
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("Invalid file type", res.json()["detail"])

    async def test_upload_valid_jpeg_accepted(self):
        _, session_token, _ = await self._create_test_user()
        buf = io.BytesIO()
        img = Image.new("RGB", (64, 64), color="blue")
        img.save(buf, format="JPEG")
        valid_b64 = base64.b64encode(buf.getvalue()).decode("ascii")

        res = await self.client.post(
            "/api/user/profile/photo",
            json={"image": f"data:image/jpeg;base64,{valid_b64}"},
            cookies={SESSION_COOKIE: session_token},
        )
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.json()["profile_image_url"].startswith("/api/user/profile/avatar/"))

    # ---------------------------------------------------------
    # 5. Session Revocation on Logout
    # ---------------------------------------------------------
    async def test_session_and_signing_keys_revoked_on_logout(self):
        _, session_token, _ = await self._create_test_user()
        key_res = await self.client.post("/api/auth/signing-key", cookies={SESSION_COOKIE: session_token})
        key_id = key_res.json()["key_id"]

        logout_res = await self.client.post("/api/auth/logout", cookies={SESSION_COOKIE: session_token})
        self.assertEqual(logout_res.status_code, 204)

        # Subsequent authenticated calls fail
        me_res = await self.client.get("/api/auth/me", cookies={SESSION_COOKIE: session_token})
        self.assertEqual(me_res.status_code, 401)

        # Signing keys purged from DB
        from auth import SessionFactory
        async with SessionFactory() as db:
            db_key = await db.get(SigningKeyModel, key_id)
            self.assertIsNone(db_key, "Signing keys must be deleted on user logout")

    # ---------------------------------------------------------
    # 6. Application-Layer Credential Encryption & Anti-Replay
    # ---------------------------------------------------------
    def _create_encrypted_envelope(
        self,
        public_key_pem: str,
        payload_dict: dict,
        timestamp: int | None = None,
        nonce: str | None = None,
    ) -> tuple[dict, bytes]:
        from cryptography.hazmat.primitives.asymmetric import padding
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        import secrets

        pub_key = serialization.load_pem_public_key(public_key_pem.encode("utf-8"))
        aes_key = AESGCM.generate_key(bit_length=256)
        enc_key = pub_key.encrypt(
            aes_key,
            padding.OAEP(
                mgf=padding.MGF1(algorithm=hashes.SHA256()),
                algorithm=hashes.SHA256(),
                label=None,
            ),
        )
        iv = secrets.token_bytes(12)
        inner = {
            "payload": payload_dict,
            "timestamp": int(time.time()) if timestamp is None else timestamp,
            "nonce": secrets.token_hex(16) if nonce is None else nonce,
        }
        inner_bytes = json.dumps(inner).encode("utf-8")
        aesgcm = AESGCM(aes_key)
        ciphertext = aesgcm.encrypt(iv, inner_bytes, None)
        envelope = {
            "encrypted": True,
            "enc_key": base64.b64encode(enc_key).decode("ascii"),
            "iv": base64.b64encode(iv).decode("ascii"),
            "ciphertext": base64.b64encode(ciphertext).decode("ascii"),
        }
        return envelope, aes_key

    def _decrypt_encrypted_response(self, response_json: dict, aes_key: bytes) -> dict:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        iv = base64.b64decode(response_json["iv"])
        ciphertext = base64.b64decode(response_json["ciphertext"])
        aesgcm = AESGCM(aes_key)
        plaintext = aesgcm.decrypt(iv, ciphertext, None)
        return json.loads(plaintext.decode("utf-8"))

    async def test_server_encryption_key_endpoint(self):
        res = await self.client.get("/api/auth/encryption-key")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("public_key", data)
        self.assertTrue(data["public_key"].startswith("-----BEGIN PUBLIC KEY-----"))
        self.assertEqual(data["algorithm"], "RSA-OAEP-256")
        self.assertEqual(data["format"], "SPKI")

    async def test_encrypted_login_hides_credentials_and_returns_encrypted_reply(self):
        email = f"enc_user_{secrets.token_hex(4)}@example.com"
        password = "SecurePassword123!"
        
        # Register user normally first
        reg_res = await self.client.post(
            "/api/auth/register",
            json={"full_name": "Encrypted Test User", "email": email, "password": password},
        )
        self.assertEqual(reg_res.status_code, 201)

        # Get server RSA public key
        key_res = await self.client.get("/api/auth/encryption-key")
        self.assertEqual(key_res.status_code, 200)
        pub_key_pem = key_res.json()["public_key"]

        # Encrypt login payload
        envelope, aes_key = self._create_encrypted_envelope(
            pub_key_pem,
            {"email": email, "password": password},
        )

        # Verify plaintext credentials are NOT in the envelope
        envelope_str = json.dumps(envelope)
        self.assertNotIn(email, envelope_str)
        self.assertNotIn(password, envelope_str)

        # Perform login with encrypted envelope
        login_res = await self.client.post("/api/auth/login", json=envelope)
        self.assertEqual(login_res.status_code, 200)
        self.assertEqual(login_res.headers.get("x-encrypted-response"), "1")

        # Plaintext response body is opaque ciphertext
        res_data = login_res.json()
        self.assertTrue(res_data.get("encrypted"))
        self.assertIn("ciphertext", res_data)
        self.assertNotIn(email, login_res.text)

        # Decrypt response with client's ephemeral AES key
        decrypted = self._decrypt_encrypted_response(res_data, aes_key)
        self.assertEqual(decrypted["email"], email)
        self.assertEqual(decrypted["full_name"], "Encrypted Test User")

    async def test_replaying_encrypted_login_rejected(self):
        email = f"enc_replay_{secrets.token_hex(4)}@example.com"
        password = "SecurePassword123!"
        
        await self.client.post(
            "/api/auth/register",
            json={"full_name": "Replay User", "email": email, "password": password},
        )
        key_res = await self.client.get("/api/auth/encryption-key")
        pub_key_pem = key_res.json()["public_key"]

        envelope, _ = self._create_encrypted_envelope(
            pub_key_pem,
            {"email": email, "password": password},
        )

        # First request succeeds
        first_res = await self.client.post("/api/auth/login", json=envelope)
        self.assertEqual(first_res.status_code, 200)

        # Second request with identical envelope / nonce is rejected as replay attack
        second_res = await self.client.post("/api/auth/login", json=envelope)
        self.assertEqual(second_res.status_code, 403)
        self.assertIn("Replay attack detected", second_res.json()["detail"])

    async def test_expired_timestamp_in_envelope_rejected(self):
        key_res = await self.client.get("/api/auth/encryption-key")
        pub_key_pem = key_res.json()["public_key"]

        # Timestamp 400 seconds in the past
        envelope, _ = self._create_encrypted_envelope(
            pub_key_pem,
            {"email": "dummy@example.com", "password": "password123"},
            timestamp=int(time.time()) - 400,
        )

        res = await self.client.post("/api/auth/login", json=envelope)
        self.assertEqual(res.status_code, 403)
        self.assertIn("expired", res.json()["detail"])

    async def test_tampered_ciphertext_in_envelope_rejected(self):
        key_res = await self.client.get("/api/auth/encryption-key")
        pub_key_pem = key_res.json()["public_key"]

        envelope, _ = self._create_encrypted_envelope(
            pub_key_pem,
            {"email": "dummy@example.com", "password": "password123"},
        )
        # Corrupt the ciphertext bytes
        tampered_bytes = bytearray(base64.b64decode(envelope["ciphertext"]))
        tampered_bytes[0] ^= 0xFF
        envelope["ciphertext"] = base64.b64encode(tampered_bytes).decode("ascii")

        res = await self.client.post("/api/auth/login", json=envelope)
        self.assertEqual(res.status_code, 400)
        self.assertIn("failed to decrypt", res.json()["detail"].lower())
