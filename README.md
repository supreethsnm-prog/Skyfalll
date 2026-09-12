# 🌦️ WeatherGPT (Skyfall)

> **Hyper-Local Indian Meteorological Intelligence & Multilingual Voice AI Weather Assistant**

[![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Python](https://img.shields.io/badge/Python-3.13+-3776AB?logo=python&logoColor=white)](https://python.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.24+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)](https://postgresql.org)
[![Gemini 2.5](https://img.shields.io/badge/Gemini-2.5_Flash-8E75B2?logo=googlegemini&logoColor=white)](https://ai.google.dev)
[![Bhashini AI](https://img.shields.io/badge/Bhashini-23_Languages-FF9933)](https://bhashini.gov.in)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

WeatherGPT is a production-grade, Bharat-first weather and disaster intelligence platform built with **FastAPI**, **PostgreSQL**, and **Flutter**. It combines live meteorological data from premier Indian and global institutions (IMD, NDMA SACHET, INCOIS, NOAA GFS, ECMWF ERA5) with **Google Gemini 2.5** and the Government of India's **Bhashini AI** voice and translation stack — localized end-to-end across **all 23 official Indian languages**, with first-class voice input/output in regional tongues such as Kannada, Hindi, Tamil, Telugu, and more.

---

## 🏛️ System Architecture

```mermaid
flowchart TD
    subgraph Client["📱 Flutter Mobile App (Android / Web / Desktop)"]
        UI["Flutter UI (Dark Minimalist)"]
        Riverpod["Riverpod 3 State Management"]
        Audio["Record & JustAudio Device Engine"]
        L10n["AppStrings (23 Bhashini Locales)"]
        UI --> Riverpod
        Riverpod --> L10n
        Riverpod --> Audio
    end

    subgraph Backend["⚡ FastAPI Backend Engine (Python 3.13)"]
        API["REST Endpoints & WebSockets (/ws/alerts)"]
        Ingest["Scheduled Ingestion (Alerts, Marine, GFS)"]
        ChatEngine["Agentic Multi-Turn Chat Engine"]
        VoiceService["Voice & Script Detection Engine"]
        API --> Ingest
        API --> ChatEngine
        API --> VoiceService
    end

    subgraph Storage["🗄️ Database & Cache (PostgreSQL 16)"]
        DB[(PostgreSQL)]
        AlertsTable[("alerts (SACHET & IMD Nowcasts)")]
        MarineTable[("pfz_zones (INCOIS 105 Zones)")]
        GfsTable[("gfs_forecast_points (93k India Grid)")]
        WeatherCache[("weather_readings (Point TTL Cache)")]
        DB --> AlertsTable
        DB --> MarineTable
        DB --> GfsTable
        DB --> WeatherCache
    end

    subgraph Upstream["🌐 Upstream Providers & AI Services"]
        SACHET["SACHET / NDMA (Disaster Alerts)"]
        INCOIS["INCOIS (Marine PFZ Line Geometry)"]
        NOAA["NOAA GFS 0.25° (Atmospheric Grid)"]
        OM["Open-Meteo (Realtime & 16-Day Forecast)"]
        ERA5["ECMWF ERA5 (Historical 1940-Present)"]
        Aviation["METAR / ICAO Global Aviation"]
        Bhashini["Bhashini ULCA (STT, TTS, NMT Translate)"]
        Gemini["Google Gemini 2.5 Flash (Tool Calling)"]
    end

    Riverpod <==>|HTTP / WebSocket| API
    Backend <==> DB
    Ingest --> SACHET
    Ingest --> INCOIS
    Ingest --> NOAA
    API --> OM
    API --> ERA5
    API --> Aviation
    VoiceService <==> Bhashini
    ChatEngine <==> Gemini
```

---

## 📸 Feature & Tab Gallery (English vs. Kannada)

Every screen in WeatherGPT is engineered for clarity and fully localized across **all 23 official Indian languages**. Below is a side-by-side walkthrough of every tab in **English** and **Kannada (ಕನ್ನಡ)**.

### 1. Home Dashboard (`/home`)
Real-time microclimate observations, perceived temperature (Feels like), 8-hour horizontal forecast scrub, 5-day daily outlook, air quality index (AQI) with PM2.5 details, and NOAA NWP atmospheric stability (CAPE, CIN, MSLP).

| English (EN) | Kannada (KN - ಮುಖಪುಟ) |
| :---: | :---: |
| <img src="docs/screenshots/home_en.png" width="380" alt="Home English" /> | <img src="docs/screenshots/home_kn.png" width="380" alt="Home Kannada" /> |

---

### 2. Navigation Sidebar (`AppDrawer`)
Slide-out drawer inspired by modern AI interfaces: destination switcher with active screen indicator, fast location switching, and persistent conversation history.

| English (EN) | Kannada (KN - ಮೆನು) |
| :---: | :---: |
| <img src="docs/screenshots/sidebar_en.png" width="380" alt="Sidebar English" /> | <img src="docs/screenshots/sidebar_kn.png" width="380" alt="Sidebar Kannada" /> |

---

### 3. Conversational Weather AI & Voice Assistant (`/chat`)
Multi-turn conversational weather reasoning powered by **Gemini 2.5 Flash** with multi-tool calling. Equipped with **Bhashini Speech-to-Text (STT)**, dynamic language reply detection, and **Text-to-Speech (TTS)** read-aloud.

| English (EN) | Kannada (KN - ಸಂಭಾಷಣೆ) |
| :---: | :---: |
| <img src="docs/screenshots/chat_en.png" width="380" alt="Chat English" /> | <img src="docs/screenshots/chat_kn.png" width="380" alt="Chat Kannada" /> |

---

### 4. Sector-Specific Advisories (`/advisories`)
Actionable meteorological guidance tailored for agriculture and urban infrastructure:
- **Agriculture**: Sowing windows, spray timings, pest infestation risks, crop-specific guidance (Paddy, Wheat, Cotton, Sugarcane).
- **Urban**: Micro-risk categorizations for waterlogging, heat stress, and wind damage.

| English (EN) | Kannada (KN - ಸಲಹೆಗಳು) |
| :---: | :---: |
| <img src="docs/screenshots/advisories_en.png" width="380" alt="Advisories English" /> | <img src="docs/screenshots/advisories_kn.png" width="380" alt="Advisories Kannada" /> |

---

### 5. Aviation Weather (`/aviation`)
Dedicated terminal aerodrome forecasts and real-time METAR reports across Indian and global airports (ICAO lookup). Features flight condition classifications (**VFR**, **MVFR**, **IFR**, **LIFR**), cloud ceiling, visibility, barometric altimeter setting, and raw METAR text.

| English (EN) | Kannada (KN - ವಾಯುಯಾನ) |
| :---: | :---: |
| <img src="docs/screenshots/aviation_en.png" width="380" alt="Aviation English" /> | <img src="docs/screenshots/aviation_kn.png" width="380" alt="Aviation Kannada" /> |

---

### 6. Marine Potential Fishing Zones (`/marine`)
Interactive OpenStreetMap vector visualization of INCOIS (Indian National Centre for Ocean Information Services) **Potential Fishing Zones (PFZ)**. Plotted from satellite sea-surface temperature (SST) and ocean-colour chlorophyll fronts to guide artisanal fisherfolk.

| English (EN) | Kannada (KN - ಮೀನುಗಾರಿಕೆ ವಲಯಗಳು) |
| :---: | :---: |
| <img src="docs/screenshots/marine_en.png" width="380" alt="Marine English" /> | <img src="docs/screenshots/marine_kn.png" width="380" alt="Marine Kannada" /> |

---

### 7. Historical Climate Archive (`/historical`)
Access ECMWF ERA5 reanalysis and historical archive records for any latitude/longitude coordinate on Earth from **1940 to present day**. Features year-over-year temperature comparison cards, precipitation totals, and dominant wind vectors.

| English (EN) | Kannada (KN - ಐತಿಹಾಸಿಕ) |
| :---: | :---: |
| <img src="docs/screenshots/historical_en.png" width="380" alt="Historical English" /> | <img src="docs/screenshots/historical_kn.png" width="380" alt="Historical Kannada" /> |

---

### 8. Saved Places & Fast Switching (`/saved`)
Bookmark favorite cities, agricultural holdings, or offshore sectors. Fast location switching powered by Nominatim OpenStreetMap geocoding with instant offline fallback.

| English (EN) | Kannada (KN - ಉಳಿಸಿದ ಸ್ಥಳಗಳು) |
| :---: | :---: |
| <img src="docs/screenshots/saved_places_en.png" width="380" alt="Saved Places English" /> | <img src="docs/screenshots/saved_places_kn.png" width="380" alt="Saved Places Kannada" /> |

---

### 9. Disaster Early Warnings & Severe Alerts (`/alerts`)
Real-time integration with **NDMA SACHET** (Common Alerting Protocol - CAP) and **IMD Nowcast feeds**. Features color-coded severity tiers (Severe, Orange Watch, Yellow Alert), location-specific push alerts via WebSockets, and historical weekly disaster archives.

| Real-Time Alert Banner (Home) | Severe Alert Bottom Sheet |
| :---: | :---: |
| <img src="docs/screenshots/home_alert_banner_en.png" width="380" alt="Home Alert Banner" /> | <img src="docs/screenshots/alerts_severe_en.png" width="380" alt="Severe Disaster Alert" /> |

---

## 🇮🇳 Complete Multilingual Support (23 Languages)

WeatherGPT features native offline string bundles and live NMT translation for all **23 Constitutionally recognized Indian languages**:

| Code | Language | Script / Native Name | Code | Language | Script / Native Name |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `en` | English | English | `kn` | Kannada | ಕನ್ನಡ |
| `hi` | Hindi | हिन्दी | `ta` | Tamil | தமிழ் |
| `te` | Telugu | తెలుగు | `mr` | Marathi | मराठी |
| `bn` | Bengali | বাংলা | `ml` | Malayalam | മലയാളം |
| `gu` | Gujarati | ગુજરાતી | `pa` | Punjabi | ਪੰਜਾਬੀ |
| `or` | Odia | ଓଡ଼ିଆ | `as` | Assamese | অসমীয়া |
| `ur` | Urdu | اردو | `sa` | Sanskrit | संस्कृतम् |
| `ne` | Nepali | नेपाली | `gom`| Konkani | कोंकणी |
| `sd` | Sindhi | سنڌي / सिन्धी | `mai`| Maithili | मैथिली |
| `doi`| Dogri | डोगरी | `ks` | Kashmiri | कॉशुर / كٲشُر |
| `brx`| Bodo | बड़ो | `sat`| Santali | ᱥᱟᱱᱛᱟᱲᱤ |
| `mni`| Manipuri | মৈতৈলোন্ / Meiteilon | | | |

- **Smart Script Fallback**: Automatically renders with bundled `NotoSansKannada` and `NotoSansDevanagari` variable typefaces to eliminate missing glyphs or tofu boxes.
- **Dynamic Reply Voice Synthesis**: When conversing with the AI assistant, the backend detects the language of the generated response and automatically invokes Bhashini TTS with the matching dialect.

---

## 🚀 Getting Started

### Prerequisites
- **Python 3.11 - 3.13**
- **Docker Desktop** (for PostgreSQL)
- **Flutter SDK 3.24+**
- **Android SDK & Platform-Tools** (if deploying to Android)

---

### 1. Clone & Setup Environment
```bash
git clone https://github.com/supreethsnm-prog/Skyfalll.git
cd Skyfalll
```

Create and configure your `backend/.env` file:
```env
DATABASE_URL=postgresql+psycopg://weathergpt:weathergpt_dev@127.0.0.1:5432/weathergpt
GEMINI_API_KEY=your_gemini_api_key
BHASHINI_USER_ID=your_bhashini_user_id
BHASHINI_API_KEY=your_bhashini_api_key
BHASHINI_PIPELINE_ID=your_bhashini_pipeline_id
INTERNAL_API_KEY=your_secure_internal_key
```

---

### 2. Start PostgreSQL Database
```bash
docker compose -f docker-compose.yml up -d
```

---

### 3. Setup Python Backend Virtual Environment
```bash
cd backend
python -m venv .venv
.venv\Scriptsctivate   # On Windows (or source .venv/bin/activate on Linux/macOS)
pip install -r requirements.txt
```

---

### 4. Prime the Demo Data (One-Command Seeder)
Pre-populate the database with live INCOIS marine fishing zones, SACHET disaster alerts, NOAA GFS atmospheric grid points, and key location caches:
```bash
python -m scripts.prime_demo
```
*Output:*
```text
Priming WeatherGPT demo data
  Alerts (SACHET/IMD) ... OK — 209 alerts (2.8s)
  Marine PFZ (INCOIS) ... OK — 105 PFZ zones (1.2s)
  NWP (NOAA GFS) ... OK — 93654 NWP grid points (37.2s)
  Point caches ... OK — 15 point caches warmed (0.1s)
  ERA5 historical ... OK — 27 historical rows restored (0.1s)
  Advisories ... OK — advisory rules OK (3 advisories across 2 cities) (0.1s)
All sources primed.
```

---

### 5. Launch the FastAPI Backend
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```
Test the health check in your browser or terminal:
```bash
curl http://127.0.0.1:8000/health/db
# {"status":"ok","db":"connected"}
```

---

### 6. Run the Flutter Mobile App

#### A. Running on a Physical Android Phone over USB
1. Connect your phone with USB Debugging enabled.
2. Reverse port 8000 so the device communicates with your PC's backend:
   ```bash
   adb reverse tcp:8000 tcp:8000
   ```
3. Run the Flutter app targeting port 8000:
   ```bash
   cd frontend/weathergpt_app
   flutter run -d <your-device-id> --dart-define=API_BASE_URL=http://127.0.0.1:8000
   ```

#### B. Running on Android Emulator
```bash
cd frontend/weathergpt_app
flutter run
# Default connects to http://10.0.2.2:8000 automatically
```

#### C. Running on Windows Desktop or Chrome Web
```bash
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

---

## 🧪 Testing Suite

### Backend Unit & Integration Tests
```bash
cd backend
pytest -v
```

### Frontend Widget & Golden Image Tests
```bash
cd frontend/weathergpt_app
# Run standard unit & widget tests
flutter test

# Run and update pixel-perfect golden renders
flutter test test/golden/tabs_kannada_golden_test.dart
```

---

## 📂 Repository Structure

```text
├── backend/
│   ├── app/
│   │   ├── air_quality/      # CPCB / Open-Meteo AQI calculation & caching
│   │   ├── aviation/         # ICAO METAR parsing & flight categories
│   │   ├── chat/             # Gemini 2.5 LLM agent with thought signatures
│   │   ├── forecast/         # Multi-day and hourly weather forecasting
│   │   ├── geocoding/        # Nominatim place search & reverse geocoding
│   │   ├── history/          # ERA5 ECMWF historical climate archive
│   │   ├── ingestion/        # Background cron sync (Alerts, Marine, GFS)
│   │   ├── marine/           # INCOIS Potential Fishing Zone (PFZ) querying
│   │   ├── models.py         # SQLAlchemy ORM models (PostgreSQL)
│   │   ├── nwp/              # NOAA GFS NWP convective metrics (CAPE, CIN)
│   │   ├── providers/        # Upstream client wrappers (IMD, SACHET, INCOIS, Bhashini)
│   │   ├── realtime/         # Realtime WebSockets alert broadcaster (/ws/alerts)
│   │   ├── skills/           # Agricultural & urban advisory heuristics
│   │   └── voice/            # Speech-to-text, text-to-speech, language detection
│   ├── scripts/              # prime_demo.py, snapshot seeders, db migration
│   └── tests/                # Comprehensive pytest suite
│
├── frontend/weathergpt_app/
│   ├── lib/
│   │   ├── core/             # Themes (Dark mode), Dio HTTP client, Audio recorder
│   │   ├── data/             # API repositories & GeoJSON / METAR model parsers
│   │   ├── features/         # Screen implementations (Home, Chat, Marine, Advisories, etc.)
│   │   ├── l10n/             # 23-language string translation bundles (strings.g.dart)
│   │   └── shared/           # Reusable widgets (round icon buttons, bottom sheets)
│   ├── assets/               # Localized fonts (Roboto, NotoSansKannada, NotoSansDevanagari)
│   └── test/
│       ├── golden/           # Golden image regression test suites & PNG outputs
│       └── support/          # Mock APIs and offline providers
│
├── docs/
│   ├── screenshots/          # High-resolution UI captures for English & Kannada
│   └── superpowers/          # Architecture design specs and task plans
└── docker-compose.yml        # PostgreSQL 16 local database container
```

---

## 📜 License
This project is released under the **MIT License**.
