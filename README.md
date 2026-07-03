# RoadSense AI

RoadSense AI is a production-quality, AI-powered navigation platform designed to provide optimal routing with real-time, background-enabled road quality monitoring. 

Rather than being a simple pothole detection application, the core focus is **safe, anomaly-aware navigation**. The road monitoring feature operates as an intelligent background process, utilizing localized on-device AI to detect anomalies (potholes, cracks) and report verified evidence back to a backend server.

---

## 1. Project Architecture

The codebase is organized as a **Monorepo** consisting of two main sub-systems:
- `/frontend` - Cross-platform Flutter mobile application.
- `/backend` - FastAPI high-performance Python backend server.

### System Overview & Flow
```mermaid
graph TD
    subgraph Mobile App (Frontend)
        UI["Material 3 UI Dashboard"] -->|Search & Nav| Router["GoRouter / Riverpod"]
        GPS["Geolocator GPS Tracking"] -.->|Metadata Injection| FrameCap["Frame Capture"]
        Cam["Camera Stream"] -->|Background Service| FrameCap
        FrameCap -->|Local Inference| AI["YOLOv8 Nano TFLite"]
        AI -->|Pothole/Crack Detected| ReportQueue["Offline-First Evidence Queue"]
        ReportQueue -->|Upload (WiFi/Cellular)| APIClient["Dio API Client"]
    end

    subgraph Backend Server (FastAPI)
        APIClient -->|Secure Upload| FastAPI["FastAPI Routers"]
        FastAPI -->|Verification Engine| AIVal["AI Confidence Validator"]
        FastAPI -->|Write Report| DB[("PostgreSQL + SQLAlchemy")]
        FastAPI -->|Expose Verified Hazards| GeoAPI["GeoJSON Anomaly Endpoint"]
    end

    GeoAPI -->|Load Anomalies Overlay| UI
```

---

## 2. Directory Layout & Folder Structure

### Frontend Folder Structure (Flutter)
We utilize a **feature-first** organization inside Clean Architecture, where each feature contains its own presentation, domain, and data layers to isolate dependencies and facilitate code reuse.

```
frontend/
├── assets/
│   ├── images/               # App logos, markers, default icons
│   └── models/               # YOLOv8 Nano .tflite weights
├── lib/
│   ├── core/
│   │   ├── constants/        # AppConstants (routes, pref keys)
│   │   ├── error/            # Failures and Exception definitions
│   │   ├── network/          # Network clients, configurations
│   │   ├── router/           # GoRouter setup & route trees
│   │   ├── services/         # Device services (Geolocator, voice alert players)
│   │   └── theme/            # AppTheme (Light & Dark M3 schemes)
│   ├── features/
│   │   ├── home/             # Home Dashboard Feature
│   │   │   └── presentation/ # Home Screen & stats cards
│   │   ├── navigation/       # GPS Route calculation & routing features
│   │   │   ├── data/         # Navigation repository implementations, api datasources
│   │   │   ├── domain/       # Use cases, models, repository interfaces
│   │   │   └── presentation/ # Route selection and turn-by-turn guidance screens
│   │   ├── road_monitoring/  # Camera & local YOLO inference module
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   └── presentation/ # PiP overlay and monitoring controls
│   │   ├── settings/         # Theme toggles & system choices
│   │   │   └── presentation/ # Settings Screen
│   │   └── splash/           # Launch transitions
│   │       └── presentation/ # Animated Splash Screen
│   ├── widgets/              # Reusable global design UI components
│   └── main.dart             # Application initialization entry point
└── pubspec.yaml              # Dependency manager configuration
```

### Backend Folder Structure (FastAPI)
```
backend/
├── app/
│   ├── api/
│   │   └── v1/
│   │       ├── endpoints/    # Routers (auth.py, navigation.py, reports.py)
│   │       └── api.py        # Master router collection
│   ├── core/
│   │   ├── config.py         # Settings & env variables loading
│   │   ├── database.py       # SQLAlchemy engine and session makers
│   │   └── security.py       # Password hashes & JWT authentication
│   ├── crud/                 # Base database transactions (CREATE, READ, UPDATE, DELETE)
│   ├── models/               # SQLAlchemy ORM declarations (user.py, report.py)
│   ├── schemas/              # Pydantic schemas for data validation
│   ├── services/             # Logic (image upload verification, geo filtering)
│   └── main.py               # Uvicorn FastAPI startup file
├── migrations/               # Alembic database migration scripts
├── alembic.ini               # Alembic database config file
└── requirements.txt          # Python dependencies
```

---

## 3. Tech Stack & Dependencies

### Frontend Dependencies (`pubspec.yaml`)
- **State Management**: `flutter_riverpod` (v2.5.1) - Declarative, compiler-safe dependency injection.
- **Routing**: `go_router` (v14.2.0) - Declarative router supporting deep linking.
- **HTTP Client**: `dio` (v5.5.0+1) - Supporting interceptors, request cancellation, and robust file uploading.
- **Hardware Integration**:
  - `camera` - Real-time lens output.
  - `geolocator` - High-accuracy GPS tracking.
- **Map Services**: `google_maps_flutter` - Renders interactive route lines and safety hazard markers.
- **On-Device AI**: `tflite_flutter` (or local compiled bindings) - Runs the YOLOv8 Nano model on device frames.

### Backend Dependencies (`requirements.txt`)
- **Web Framework**: `fastapi`, `uvicorn` - High-performance asynchronous API service.
- **Database Access**: `sqlalchemy` (v2.x ORM), `alembic` (database migration control), `psycopg2-binary` (PostgreSQL adapter).
- **Security**: `python-jose`, `passlib` (bcrypt) - Safe user management and JWT.
- **Data Validation**: `pydantic` - Strict API payload assertions.

---

## 4. Naming & Style Conventions

### Dart / Flutter
- **Files & Folders**: `snake_case` (e.g., `navigation_repository.dart`).
- **Classes**: `UpperCamelCase` (e.g., `NavigationScreen`).
- **Variables & Methods**: `lowerCamelCase` (e.g., `calculateRoutes()`).
- **Constants**: `lowerCamelCase` or prefixed inside classes as static fields (e.g., `AppConstants.routeHome`).
- **Widget Customization**: Const constructors should be preferred wherever possible.

### Python / FastAPI
- **Files & Modules**: `snake_case` (e.g., `db_session.py`).
- **Classes (Models, Schemas)**: `UpperCamelCase` (e.g., `ReportCreate`).
- **Functions & Variables**: `snake_case` (e.g., `create_new_report()`).
- **Environment Settings**: `UPPERCASE_SNAKE` (e.g., `DATABASE_URL`).

---

## 5. Development Roadmap

### Phase 1: Foundation & Layout (Completed)
- Establish monorepo workspace.
- Configure dependencies and lint systems.
- Code main Flutter compilation skeletons: Router, Theme configuration, Splash Screen, Home Screen, Navigation Screen, and Settings Screen.

### Phase 2: Core Map Integration & Local Tracking
- Implement Google Maps SDK for route display on the Navigation Screen.
- Integrate Geolocator to query and stream user locations.
- Connect local mock location streams to simulate navigation progress.

### Phase 3: Background Camera & On-device Inference
- Integrate Camera plugin to run camera capture pipeline.
- Implement Picture-in-Picture preview overlay widget.
- Build local TFLite service to run YOLOv8 Nano inference on camera frame buffers (running pothole/crack detection classifiers).
- Establish frame-to-GPS coordinate synchronization.

### Phase 4: Backend Implementation
- Set up FastAPI app with PostgreSQL, SQLAlchemy, and Alembic migrations.
- Build secure upload endpoints to receive anomaly reports (image binary + GPS + timestamp meta).
- Establish database storage for reports with a verification status field.

### Phase 5: Verification & Safety Hazard Map
- Build hazard querying API to return verified anomalies in GeoJSON format.
- Connect mobile client to query safety overlays and render hazard icons (warning indicators) on navigation paths.
- Setup audio alert triggers (Text-To-Speech / Voice Alerts) during navigation near upcoming hazards.
