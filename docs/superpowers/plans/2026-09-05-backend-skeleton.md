# Backend Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a running, tested FastAPI backend skeleton with a Postgres-backed health check — the first verifiable slice of WeatherGPT, with nothing else attached yet.

**Architecture:** A minimal FastAPI app (`backend/app/`) with a plain liveness endpoint and a second endpoint that proves real database connectivity via SQLAlchemy against a Postgres instance run through Docker Compose. No providers, no business logic — this sprint only proves the skeleton runs and is testable end to end.

**Tech Stack:** Python 3.13 (confirmed installed on this machine), FastAPI, Uvicorn, SQLAlchemy 2.x, psycopg 3, pydantic-settings, pytest, httpx, Docker Compose (Postgres only).

**Spec:** `docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md`

## Global Constraints

- Backend is FastAPI + PostgreSQL (spec §2) — no other backend framework or database engine.
- Every sprint ends in a state that actually runs and is verified before the next sprint starts (spec §6) — no task in this plan is "done" until its manual verification command has actually been run and its output checked.
- This sprint scaffolds only — no provider code, no ingestion jobs, no LLM code. Those are later sprints per spec §2–§4.
- This machine has `python` on PATH (3.13.9), not `python3`. Use `python` in all commands.
- Docker Desktop is installed and running, but `docker` is NOT on PATH in this shell environment. Use the full path in every docker command: `/c/Users/ACER/AppData/Local/Programs/DockerDesktop/resources/bin/docker.exe`. Confirmed working: `docker.exe --version`, `docker.exe ps` both succeed via this full path. `docker compose` subcommand works the same way (`.../docker.exe compose up -d db`).
- All commands below are given relative to the repo root of the current working tree (whatever that root is — a worktree or the main checkout). Do not hardcode an absolute path.

---

## File Structure

```
<repo-root>/
├── docker-compose.yml
├── .gitignore
└── backend/
    ├── requirements.txt
    ├── pytest.ini
    ├── .env.example
    ├── app/
    │   ├── __init__.py
    │   ├── main.py       # FastAPI app, /health and /health/db endpoints
    │   ├── config.py     # Settings (DATABASE_URL) via pydantic-settings
    │   └── db.py         # SQLAlchemy engine + check_db_connection()
    └── tests/
        ├── __init__.py
        ├── test_health.py
        └── test_db_health.py
```

---

### Task 1: FastAPI skeleton with a liveness health check

**Files:**
- Create: `backend/requirements.txt`
- Create: `backend/pytest.ini`
- Create: `backend/app/__init__.py`
- Create: `backend/app/main.py`
- Create: `backend/tests/__init__.py`
- Create: `backend/tests/test_health.py`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `app.main:app` — a FastAPI instance. `GET /health` → `200 {"status": "ok"}`. Task 2 imports `app` from `app.main` and adds a route to the same instance.

- [ ] **Step 1: Create the backend directory and requirements file**

Create `backend/requirements.txt`:

```
fastapi>=0.115
uvicorn[standard]>=0.32
pydantic-settings>=2.5
sqlalchemy>=2.0
psycopg[binary]>=3.2
pytest>=8.3
httpx>=0.27
```

- [ ] **Step 2: Create a virtual environment and install dependencies**

Run (from the repo root):
```bash
cd backend
python -m venv .venv
source .venv/Scripts/activate
pip install -r requirements.txt
```
Expected: install completes with no errors.

- [ ] **Step 3: Configure pytest's import path**

Create `backend/pytest.ini`:

```ini
[pytest]
pythonpath = .
```

This lets tests do `from app.main import app` without installing the package or fiddling with `PYTHONPATH` manually — `pythonpath` is a built-in pytest ini option (pytest ≥7.0).

- [ ] **Step 4: Create the empty package marker**

Create `backend/app/__init__.py` (empty file).

Create `backend/tests/__init__.py` (empty file).

- [ ] **Step 5: Write the failing test**

Create `backend/tests/test_health.py`:

```python
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_returns_ok():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

- [ ] **Step 6: Run the test and confirm it fails**

Run (from `backend/`, venv active):
```bash
pytest tests/test_health.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'app.main'` (or similar), because `app/main.py` doesn't exist yet.

- [ ] **Step 7: Write the minimal implementation**

Create `backend/app/main.py`:

```python
from fastapi import FastAPI

app = FastAPI(title="WeatherGPT Backend")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
```

- [ ] **Step 8: Run the test and confirm it passes**

Run:
```bash
pytest tests/test_health.py -v
```
Expected: PASS.

- [ ] **Step 9: Manually verify the server actually runs**

Run (from `backend/`, venv active):
```bash
uvicorn app.main:app --reload --port 8000
```
In a second terminal:
```bash
curl http://127.0.0.1:8000/health
```
Expected: `{"status":"ok"}`. Stop the server (Ctrl+C) once confirmed.

- [ ] **Step 10: Add a root .gitignore**

Create `.gitignore` at the repo root:

```
.venv/
__pycache__/
*.pyc
.env
.pytest_cache/
```

- [ ] **Step 11: Commit**

```bash
cd ..
git add backend/ .gitignore
git commit -m "feat: add FastAPI skeleton with liveness health check"
```

---

### Task 2: Postgres via Docker Compose + DB-backed health check

**Files:**
- Create: `docker-compose.yml`
- Create: `backend/.env.example`
- Create: `backend/app/config.py`
- Create: `backend/app/db.py`
- Modify: `backend/app/main.py` (add `/health/db` route)
- Create: `backend/tests/test_db_health.py`

**Interfaces:**
- Consumes: `app.main:app` (Task 1).
- Produces: `app.config:get_settings() -> Settings` where `Settings.database_url: str`. `app.db:check_db_connection() -> bool` (returns `True` on success, raises `sqlalchemy.exc.OperationalError` on failure — callers catch this, never assume it returns `False`). Later provider/ingestion sprints reuse `app.db` for their own DB sessions.

- [ ] **Step 1: Add the Postgres service**

Create `docker-compose.yml` at the repo root:

```yaml
services:
  db:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_USER: weathergpt
      POSTGRES_PASSWORD: weathergpt_dev
      POSTGRES_DB: weathergpt
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U weathergpt"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
```

- [ ] **Step 2: Start Postgres and confirm it's healthy**

Run (from the repo root — `docker` is not on PATH, use the full path per Global Constraints):
```bash
DOCKER=/c/Users/ACER/AppData/Local/Programs/DockerDesktop/resources/bin/docker.exe
"$DOCKER" compose up -d db
"$DOCKER" compose ps
```
Expected: `db` service shows `healthy` (may take a few seconds — re-run `"$DOCKER" compose ps` if it still says `starting`).

- [ ] **Step 3: Add settings and an example env file**

Create `backend/.env.example`:

```
DATABASE_URL=postgresql+psycopg://weathergpt:weathergpt_dev@localhost:5432/weathergpt
```

Create `backend/app/config.py`:

```python
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = (
        "postgresql+psycopg://weathergpt:weathergpt_dev@localhost:5432/weathergpt"
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

- [ ] **Step 4: Write the failing test**

Create `backend/tests/test_db_health.py`:

```python
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_db_returns_connected():
    response = client.get("/health/db")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "db": "connected"}
```

- [ ] **Step 5: Run the test and confirm it fails**

Run (from `backend/`, venv active, Postgres running from Step 2):
```bash
pytest tests/test_db_health.py -v
```
Expected: FAIL — `404` (route doesn't exist yet) or `AttributeError`, since `/health/db` isn't defined and `app/db.py` doesn't exist.

- [ ] **Step 6: Write the minimal implementation**

Create `backend/app/db.py`:

```python
from sqlalchemy import create_engine, text

from app.config import get_settings

engine = create_engine(get_settings().database_url, pool_pre_ping=True)


def check_db_connection() -> bool:
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return True
```

Modify `backend/app/main.py` to add the new route:

```python
from fastapi import FastAPI

from app.db import check_db_connection

app = FastAPI(title="WeatherGPT Backend")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health/db")
def health_db() -> dict[str, str]:
    check_db_connection()
    return {"status": "ok", "db": "connected"}
```

- [ ] **Step 7: Run the test and confirm it passes**

Run:
```bash
pytest tests/test_db_health.py -v
```
Expected: PASS. (If it fails with a connection error, confirm `docker compose ps` shows `db` as `healthy` and that port 5432 isn't already in use by another local Postgres install.)

- [ ] **Step 8: Manually verify against the running server**

Run (from `backend/`, venv active):
```bash
uvicorn app.main:app --reload --port 8000
```
In a second terminal:
```bash
curl http://127.0.0.1:8000/health/db
```
Expected: `{"status":"ok","db":"connected"}`. Stop the server (Ctrl+C) once confirmed.

- [ ] **Step 9: Run the full test suite**

Run (from `backend/`):
```bash
pytest -v
```
Expected: both `test_health.py` and `test_db_health.py` pass (2 passed).

- [ ] **Step 10: Commit**

```bash
cd ..
git add docker-compose.yml backend/
git commit -m "feat: add Postgres via docker compose and DB-backed health check"
```
