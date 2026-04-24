# Django Files iOS — Agent Context

## Purpose
SwiftUI iOS client for [django-files](../django-files), a self-hosted file manager. Core flows: multi-server session management, file upload (incl. share sheet extension), file/album/short-URL browsing, file preview.

## Tech Stack
- Swift + SwiftUI, iOS 18.6+ deployment target
- SwiftData (persistence), async/await (networking), Combine-light
- Apple HTTPTypes / HTTPTypesFoundation (HTTP client)
- FirebaseAnalytics + FirebaseCrashlytics, FLAnimatedImage, HighlightSwift
- Fastlane (CI, TestFlight, App Store)

## Project Layout
```
Django Files/
  Django_FilesApp.swift   # @main entry, AppDelegate, Firebase init, deep-link routing
  Models/
    DjangoFilesSession.swift  # SwiftData @Model — server URL, auth token, user prefs
  API/
    DFAPI.swift           # Core HTTP client; token auth, streaming multipart upload
    Files.swift / Albums.swift / Short.swift / Users.swift / Stats.swift / Websocket.swift
  Utils/
    SessionManager.swift  # Load/save active session
    WebSocketObs.swift    # /ws/ real-time observer
    DeepLinks.swift       # djangofiles:// scheme routing
  Views/
    TabView.swift         # Root tab nav (Files, Albums, Shorts, Settings, Web)
    Login/                # Local + OAuth auth flows
    Lists/                # File/album/short listings
    Uploads/              # File picker, album/short creation
    Preview/              # Image, PDF, video, audio, text renderers
    Settings/             # Server config, session management
  ContextMenus/           # File action sheets / dialogs
UploadAndCopy/            # Share sheet extension (separate target)
Django FilesTests/        # Unit tests
Django FilesUITests/      # UI tests (fastlane scan)
fastlane/                 # Fastfile: lanes = tests | beta | push_appstore | ci
```

## Auth & API
- **Auth**: Bearer token (`Authorization` header). `401` → session marked unauthenticated.
- **Base URL**: configurable per `DjangoFilesSession`; API root at `/api/`.
- **User-Agent**: `DjangoFiles iOS <version>(<build>)`
- **Login endpoints**:
  - `POST /api/auth/methods/` — available auth methods
  - `POST /api/auth/token/` — local (username/password) → `{token}`
  - `POST /api/auth/application/` — signature-based deep-link auth → `{token}`
- **Core endpoints used**:
  - `POST /api/upload/` — multipart; headers: Albums, Private, format, expires-at
  - `GET /api/files/{page}/`, `/api/albums/`, `/api/shorts/`, `/api/recent/`, `/api/stats/`
  - `POST /api/shorten/` — create short URL
  - `WS /ws/` — real-time updates

## Build & Test
```bash
# Run tests (fastlane)
bundle exec fastlane tests

# Deploy to TestFlight
bundle exec fastlane beta

# App Store release
bundle exec fastlane push_appstore
```
No Makefile; all automation is Fastlane. Standard `xcodebuild` also works.

## Key Patterns
- Each server is a `DjangoFilesSession` (SwiftData); `SessionManager` picks the active one.
- All `DFAPI` methods are `async throws`; errors surfaced via SwiftUI `.alert`.
- Share sheet (`UploadAndCopy` target) shares `DjangoFilesSession` via App Group container.
- Deep links use `djangofiles://` scheme; `DeepLinks.swift` dispatches routes.
- WebSocket (`/ws/`) pumped through `WebSocketObs` for live file-list updates.

## django-files Backend (sibling repo)
See `../django-files/AGENTS.md` for full backend context.
Short version: Django + Channels + Celery + Redis; RESTful JSON API; token auth via `CustomUser.authorization`; optional S3 storage; Docker compose for local dev.
