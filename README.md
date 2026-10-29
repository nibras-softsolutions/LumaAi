# Luma AI

A thoughtful, privacy-first local AI workspace powered by **FastAPI**, **LangChain**, **Ollama**, and a modern Vanilla JavaScript SPA.

---

## Features

- **Native iOS App (SwiftUI & iOS 17+)**:
  - **Live Camera-to-Text (OCR)**: Real-time on-device text recognition using Apple's Vision framework (`VNRecognizeTextRequest`) and `AVFoundation`, with live highlight bounding boxes, single-block tap-to-copy, and direct insertion into "Ask Luma".
  - **Google Sign-In**: Native Google Sign-In powered by `GoogleSignIn-iOS` SDK with cryptographic server-side ID token verification.
  - **Dynamic Multiline Composer**: Smart keyboard avoidance, auto-scrolling conversation feed, and interactive drag-to-dismiss.
  - **Voice Conversations**: Real-time voice interaction with animated audio visualizer and speech recognition.
  - **AI Image Generation**: Multi-aspect image synthesis with full-screen viewer and history.
- **Local LLM Intelligence**: Powered by Ollama (default: `llama3.2`) or cloud providers, streaming responses token-by-token using Server-Sent Events (SSE).
- **Modern Responsive Web Interface**: Distraction-free design with onboarding flow, chat history, search, and collapsible sidebar.
- **Downloadable Code Generation**: Automatic intent detection format (`File: filename.ext`) with one-click code file download buttons.
- **Enterprise-Grade Security**:
  - Google OAuth ID token verification (issuer, signature, audience, expiration).
  - Password hashing with **Argon2** via `pwdlib`.
  - Secure session management with hashed tokens and HTTP-only cookies.
  - SameSite cookies and origin verification to defend against CSRF.
  - Brute-force rate limiting on authentication attempts.
  - Strict Content Security Policy (CSP) and Bleach-sanitized Markdown rendering.
- **Database Flexibility**: Default local SQLite support (`sqlite+aiosqlite`) or managed cloud PostgreSQL (e.g., **Neon** via `asyncpg`).
- **Decoupled Architecture**: Supports running as an integrated single-port app, a Vercel-hosted frontend, or a native iOS SwiftUI client.

---

## Project Structure

```
├── auth.py             # Authentication router, SQLAlchemy models, session management, Google OAuth
├── main.py             # FastAPI app, SSE chat streaming, Markdown rendering, CSP
├── requirements.txt    # Python dependencies
├── pytest.ini          # Pytest configuration
├── .env.example        # Environment variable template
├── static/
│   ├── index.html      # Single Page Application HTML
│   ├── styles.css      # Design system styles
│   └── app.js          # Client logic (SSE streaming, state, downloads)
├── tests/
│   └── test_app.py     # Backend test suite (28 integration tests)
└── LumaAI/             # Native iOS SwiftUI Application (iOS 17+)
    ├── project.yml     # XcodeGen specification
    ├── LumaAI/
    │   ├── Core/       # Networking, Authentication (GoogleSignIn), Models
    │   ├── DesignSystem/ # Typography, ColorPalette, HapticFeedback
    │   └── Features/
    │       ├── Authentication/ # Google Sign-In & Email/Password flows
    │       ├── Chat/          # ChatView, multiline ComposerView, MarkdownView
    │       ├── Scanner/       # LiveCameraService, LiveTextScannerView (Vision OCR)
    │       ├── Voice/         # VoiceConversationView, SpeechRecognitionService
    │       ├── ImageGeneration/ # ImageGenerationView, ImageViewerView
    │       └── Settings/      # SettingsView, UserPreferences
    └── LumaAITests/    # iOS unit test suite (23 unit tests)
```

---

## Getting Started

### Prerequisites

- Python 3.10+
- [Ollama](https://ollama.ai) installed and running locally:
  ```bash
  ollama serve
  ollama pull llama3.2
  ```

### 1. Clone & Set Up Virtual Environment

```bash
git clone https://github.com/nibras-softsolutions/LumaAi.git
cd LumaAi

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure Environment

Copy the example environment file:
```bash
cp .env.example .env
```

To connect a Neon or external PostgreSQL database, update `DATABASE_URL` in `.env`:
```bash
DATABASE_URL="postgresql://user:password@host/dbname?sslmode=require"
```
*(If unset, Luma AI will automatically default to local SQLite `luma_auth.db`)*

### 3. Run the Backend

```bash
python main.py
```
The server will start at `http://127.0.0.1:8000`.

### 4. Open Luma AI

- **Integrated Mode**: Visit `http://127.0.0.1:8000` in your browser.
- **Decoupled Frontend Mode**: You can also serve `static/` independently (e.g. on port `8765`):
  ```bash
  python3 -m http.server 8765 --directory static
  ```
  and visit `http://127.0.0.1:8765`. The frontend will automatically route requests to the backend.

---

## Running Tests

Run the full automated test suite:
```bash
pytest
```

---

## Deploying Frontend on Vercel

You can deploy the static frontend to **Vercel** and connect it to your live FastAPI backend.

### Architecture
- **Frontend**: Hosted on Vercel CDN (`index.html`, `static/app.js`, `static/styles.css`).
- **Database**: Neon Serverless PostgreSQL (`DATABASE_URL`).
- **Backend**: FastAPI (`main.py`) hosted on Render, Railway, Fly.io, or your own server.

### Option A: Using Vercel Rewrites Proxy (Recommended)
This approach proxies all `/api/*` requests through Vercel directly to your backend. It completely avoids CORS issues and allows secure `HttpOnly; SameSite=Lax` session cookies to work natively without cross-origin cookie restrictions.

1. In [`vercel.json`](vercel.json), replace `https://YOUR_BACKEND_URL` with your live FastAPI backend URL:
   ```json
   {
     "rewrites": [
       {
         "source": "/api/:path*",
         "destination": "https://your-backend.onrender.com/api/:path*"
       }
     ]
   }
   ```
2. Deploy to Vercel:
   - Import your GitHub repo on [vercel.com](https://vercel.com/new).
   - Framework Preset: **Other**.
   - Root Directory: `./`.
   - Click **Deploy**.

### Option B: Direct Cross-Origin API Connection
If you prefer direct client-side requests:
1. In `index.html`, uncomment the `api-base-url` meta tag:
   ```html
   <meta name="api-base-url" content="https://your-backend.onrender.com">
   ```
2. On your backend environment variables:
   - `ALLOWED_ORIGINS`: `https://your-project.vercel.app`
   - `COOKIE_SECURE`: `true`
   - `COOKIE_SAMESITE`: `none`

---

## Vercel Speed Insights

This project is configured with **Vercel Speed Insights** to monitor real-time performance metrics and Core Web Vitals.

### Setup Requirements

1. **Dashboard Configuration**: Enable Speed Insights in your Vercel project dashboard:
   - Navigate to your project on [vercel.com](https://vercel.com)
   - Go to **Settings** → **Speed Insights**
   - Click **Enable Speed Insights**

2. **Code Integration**: The Speed Insights tracking script is already integrated in `static/speed-insights.js` and loaded in the HTML files.

3. **Viewing Metrics**: After deployment, access performance data:
   - Go to your project dashboard
   - Click the **Speed Insights** tab in the sidebar
   - View Real Experience Score (RES) and Core Web Vitals

### How It Works

- The `speed-insights.js` script automatically injects the Vercel Speed Insights tracking code
- Performance metrics are collected from real user visits
- Data appears in your Vercel dashboard after deployment
- In local development, the debug version provides console feedback

---

## Google Sign-In (Cross-Platform)

Luma AI supports seamless **Continue with Google** authentication across both the web and native iOS apps, sharing a unified user database and session security architecture.

### Unified Account Linking
- **Single Account Identity**: Signing in with `user@gmail.com` on either web or iOS connects to the exact same account, preserving conversation history and profile data.
- **Email/Password Coexistence**: If an account was previously created with email/password, signing in via Google with that same email safely links to the existing user record without creating duplicates.
- **Server-Side Cryptographic Verification**: The backend validates Google ID tokens against Google's public keys, verifying audience, issuer (`accounts.google.com`), and expiration.

### OAuth Client IDs
- **Google Web Client ID**: `172474086048-02bpfth3nc9md882lhc22bkfl2raojpd.apps.googleusercontent.com`
- **Google iOS Client ID**: `172474086048-ke3r4ekgdm0vcak48j1bvqqb6msrmubh.apps.googleusercontent.com`

### Google Cloud Console Configuration
Ensure the following Authorized JavaScript Origins are added to the Web Client ID in the Google Cloud Console:
- `https://luma-ai-bay.vercel.app`
- `https://lumaai-j0u3.onrender.com`
- `http://localhost:8000`
- `http://127.0.0.1:8000`
- `http://localhost:8765`
- `http://127.0.0.1:8765`

---

## License

MIT License.
