# Repository Guidelines

## Project Structure & Module Organization

This repository contains only the Prairie Apple clients. SwiftUI app code lives under `iosApp/iosApp/`, tests live in `iosApp/Tests/`, Top Shelf code lives in `iosApp/TopShelf/`, resources live in `iosApp/Resources/`, and generated Xcode structure is controlled by `iosApp/project.yml`. Apple TV playback notes live in `docs/tvos-player/`; release automation lives in `fastlane/`.

## Prairie Workspace Context

This repository is part of a broader multi-repo Prairie workspace. The sibling
repositories are usually checked out alongside this repository.

- `prairie-apple` owns iOS, tvOS, and macOS client code only.
- `prairie-server` owns the Go backend, web admin UI, API contracts, auth/session
  behavior, catalog/scanner/playback services, database migrations, Jellyfin
  compatibility, and host-side plugin runtime.
- `prairie-android` owns the Android phone and TV clients. When changing shared
  client behavior, compare Android so Apple and Android stay aligned.

When a task touches auth, API models, playback/session state, library browsing,
metadata display, or server-driven behavior, check whether the server and
Android client need coordinated changes. Do not force server concerns into this
repo.

## Build, Test, and Development Commands

- `cd iosApp && xcodegen generate` regenerates `Prairie.xcodeproj` from `project.yml`; do this after target or source layout changes.
- `cd iosApp && xcodebuild build -project Prairie.xcodeproj -scheme Prairie -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO` builds iOS without local signing.
- Use scheme `PrairieTV` with a tvOS simulator destination for tvOS builds.
- Use scheme `PrairieMac` with `platform=macOS` for macOS builds.

## Coding Style & Naming Conventions

Use Swift 5 and SwiftUI naming conventions. Types use `PascalCase`; functions and properties use `camelCase`. Keep platform-specific code under the existing `iOS`, `tvOS`, or `macOS` folders and update `project.yml` instead of hand-editing generated `.xcodeproj` files. Use the Prairie bundle IDs, App Group, keychain group, and signing variables defined under `iosApp/Signing/`.

For tvOS focus work, read `docs/tvos-focus.md` before editing navigation,
menus, grids, or custom controls. Prefer a stable native focus graph or a
single composite focus owner; do not mix row-level focusable controls with
manual directional focus mutation.

## Testing Guidelines

Apple tests use XCTest under `iosApp/Tests/`. Do not add tests for small changes or UI changes unless requested. For shared logic changes, add focused tests only for critical or high-risk behavior.

ViewInspector (`https://github.com/nalexn/ViewInspector`) is linked to the `PrairieTests` target only (see `iosApp/project.yml`). Use it sparingly for high-risk SwiftUI screens where empty/loading/error affordances must not regress — for example Live TV channel list states — not as a default for every view. Prefer decoder and pure-logic unit tests for Networking and ViewModel code.

CI enforces a 75% line-coverage gate over `/Networking/`, `/Screens/LiveTV/`, and `BrowseViewModel.swift` via `scripts/check-xccov-coverage.sh` (not overall app UI coverage).

## Security & Configuration Tips

Do not commit local signing overrides. Start from `iosApp/Signing/Local.xcconfig.sample`, create `iosApp/Signing/Local.xcconfig`, and regenerate with XcodeGen after signing changes. Keep App Store Connect keys, Match repo URLs, and team identifiers in environment variables only.
