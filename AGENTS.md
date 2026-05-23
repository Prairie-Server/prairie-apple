# Repository Guidelines

## Project Structure & Module Organization

This repository contains only the Silo Apple clients. SwiftUI app code lives under `iosApp/iosApp/`, tests live in `iosApp/Tests/`, Top Shelf code lives in `iosApp/TopShelf/`, resources live in `iosApp/Resources/`, and generated Xcode structure is controlled by `iosApp/project.yml`. Apple TV playback notes live in `docs/tvos-player/`; release automation lives in `fastlane/`.

## Build, Test, and Development Commands

- `cd iosApp && xcodegen generate` regenerates `Silo.xcodeproj` from `project.yml`; do this after target or source layout changes.
- `cd iosApp && xcodebuild build -project Silo.xcodeproj -scheme Silo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO` builds iOS without local signing.
- Use scheme `SiloTV` with a tvOS simulator destination for tvOS builds.
- Use scheme `SiloMac` with `platform=macOS` for macOS builds.

## Coding Style & Naming Conventions

Use Swift 5 and SwiftUI naming conventions. Types use `PascalCase`; functions and properties use `camelCase`. Keep platform-specific code under the existing `iOS`, `tvOS`, or `macOS` folders and update `project.yml` instead of hand-editing generated `.xcodeproj` files. Preserve existing Apple bundle IDs and keychain groups during this migration for TestFlight continuity.

## Testing Guidelines

Apple tests use XCTest under `iosApp/Tests/`. Do not add tests for small changes or UI changes unless requested. For shared logic changes, add focused tests only for critical or high-risk behavior.

## Security & Configuration Tips

Do not commit local signing overrides. Start from `iosApp/Signing/Local.xcconfig.sample`, create `iosApp/Signing/Local.xcconfig`, and regenerate with XcodeGen after signing changes. Keep App Store Connect keys, Match repo URLs, and team identifiers in environment variables only.
