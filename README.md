# Prairie Apple

Native Apple clients for the [Prairie](https://github.com/Prairie-Server/prairie-server) self-hosted media server.

This repo builds iOS, tvOS, and the early macOS target. Prairie is a fork of Silo, re-identified with Prairie bundle IDs, app groups, keychain groups, URL schemes, signing defaults, app names, and brand assets.

## TestFlight

Try the latest beta builds of the iOS and tvOS apps:

**[Join the Prairie TestFlight beta](https://testflight.apple.com/join/XZy8cu5q)**

## Screenshots

### iOS

<p>
  <img src="project-images/prairie-apple-native/04-home.png" width="260" alt="iOS home screen" />
  <img src="project-images/prairie-apple-native/09-movie-detail.png" width="260" alt="iOS movie detail" />
  <img src="project-images/prairie-apple-native/05-libraries.png" width="260" alt="iOS movies library" />
</p>

### tvOS

<p>
  <img src="project-images/prairie-tvos/05-tv-home.png" width="800" alt="tvOS home screen" />
</p>

## Layout

- `iosApp/iosApp/` - shared SwiftUI app code for iOS, tvOS, and macOS
- `iosApp/TopShelf/` - tvOS Top Shelf extension
- `iosApp/Tests/` - XCTest targets
- `iosApp/Resources/` - shared Apple resources
- `iosApp/Signing/` - checked-in signing defaults plus local override sample
- `iosApp/project.yml` - XcodeGen project source of truth
- `fastlane/` - iOS/tvOS release automation
- `docs/tvos-player/` - Apple TV playback notes

## Prerequisites

- Xcode 16+
- `xcodegen`
- Ruby 3.2 with Bundler for release automation
- A running Prairie server for local auth, browsing, and playback validation

## Build

Generate the Xcode project from the checked-in XcodeGen spec:

```sh
cd iosApp
xcodegen generate
open Prairie.xcodeproj
```

Build without local signing:

```sh
cd iosApp
xcodebuild build \
  -project Prairie.xcodeproj \
  -scheme Prairie \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project Prairie.xcodeproj \
  -scheme PrairieTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project Prairie.xcodeproj \
  -scheme PrairieMac \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_ALLOWED=NO
```

## VS Code

The checked-in `.vscode` configuration provides recommended extensions,
unsigned build and test tasks, and SweetPad integration for building, running,
debugging, simulator management, and Swift code intelligence without using the
Xcode UI.

1. Install Xcode and select its command-line toolchain:

   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```

2. Install XcodeGen:

   ```sh
   brew install xcodegen
   ```

3. Open the repository root in VS Code and accept its extension
   recommendations.
4. Run `Tasks: Run Task` → `Prairie: Generate Xcode project`.
5. In the SweetPad sidebar, select a scheme and an installed destination.
6. Run `SweetPad: Set up Swift code intelligence (BSP)` once from the command
   palette, then open a Swift file. The generated `buildServer.json` is
   machine-specific and intentionally ignored.

Use `Cmd+Shift+B` for the default unsigned iOS build. Use the Testing sidebar
or `Tasks: Run Test Task` for XCTest. The test task prompts for a simulator
destination so each developer can use an installed device without committing
machine-specific configuration.

SweetPad uses Xcode's compiler, SDKs, signing tools, and simulators under the
hood, so the full Xcode application remains required even when its UI is not
part of the daily workflow.

## Signing

Local signing overrides are intentionally ignored.

1. Copy `iosApp/Signing/Local.xcconfig.sample` to `iosApp/Signing/Local.xcconfig`.
2. Override bundle identifiers, entitlements, or development team values as needed.
3. Run `xcodegen generate` from `iosApp/`.

Personal Apple Developer teams cannot join the production App Group, so Top Shelf rows stay empty under that setup.

## Release Flow

Fastlane lanes are defined in `fastlane/Fastfile`. All Apple IDs, team IDs, signing repo URLs, and App Store Connect credentials must come from CI environment variables.

## License & Trademarks

Prairie Apple is licensed under `AGPL-3.0-or-later`. See [LICENSE](LICENSE).

The **Prairie name, logo, wordmark, app icons, and other brand assets** are **not**
covered by the AGPL. You're free to fork and redistribute the code, including with
truthful notices such as "fork of Silo," but forks and redistributions must not
use the Prairie brand as their identity and must remove or replace the Prairie
brand assets. See [TRADEMARK.md](TRADEMARK.md).

FFmpeg, Nuke, fastlane, and other third-party dependencies retain their own licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
