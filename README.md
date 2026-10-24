# Luma AI

A thoughtful, privacy-first local AI workspace powered by **FastAPI**, **LangChain**, **Ollama**, and a modern Vanilla JavaScript SPA.

---

## Features

- **Local LLM Intelligence**: Powered by Ollama (default: `llama3.2`), streaming responses token-by-token using Server-Sent Events (SSE).
- **Modern Responsive Interface**: Distraction-free design with onboarding flow, chat history, search, and collapsible sidebar.
- **Downloadable Code Generation**: Automatic intent detection format (`File: filename.ext`) with one-click code file download buttons.
- **Enterprise-Grade Security**:
  - Password hashing with **Argon2** via `pwdlib`.
  - Secure session management with hashed tokens and HTTP-only cookies.
  - SameSite cookies and origin verification to defend against CSRF.
  - Brute-force rate limiting on authentication attempts.
  - Strict Content Security Policy (CSP) and Bleach-sanitized Markdown rendering.
- **Database Flexibility**: Default local SQLite support (`sqlite+aiosqlite`) or managed cloud PostgreSQL (e.g., **Neon** via `asyncpg`).
- **Decoupled Architecture**: Supports running as an integrated single-port app or with frontend and backend served on separate ports with CORS.

---

## Project Structure

```
├── auth.py             # Authentication router, SQLAlchemy models, session management
├── main.py             # FastAPI app, SSE chat streaming, Markdown rendering, CSP
├── requirements.txt    # Python dependencies
├── pytest.ini          # Pytest configuration
├── .env.example        # Environment variable template
├── static/
│   ├── index.html      # Single Page Application HTML
│   ├── styles.css      # Design system styles
│   └── app.js          # Client logic (SSE streaming, state, downloads)
└── tests/
    └── test_app.py     # Automated test suite (28 integration tests)
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

## License

MIT License.
