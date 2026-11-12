# Packaging and HCG Executable Maker

This note is about **building and packaging**. The publication connection is a bundled resource, `HCGNews/Resources/HCGNewsConfiguration.json` (`hcgPlatform`), so Debug, Release and archive builds are all connected. It contains only public values: the shared HCG project URL, its **anon** key (the same one the HCG website ships), the website URL and the publication URL. A configuration imported in Settings › Advanced takes precedence.

## Compatibility with HCG Executable Maker (Mobile Build Studio)

HCG Executable Maker parses `project.pbxproj` statically and builds with `xcodebuild`, using structured arguments rather than a shell (see its `docs/IOS-BUILDING.md`). This project is set up for that:

| What the Maker reads | This project |
|---|---|
| Project | `iOS app/HCGNews/HCGNews.xcodeproj`. Import the whole **`iOS app/HCGNews`** folder so that the local package `HCGNewsKit` (referenced by relative path) is included. |
| Shared scheme | `HCGNews` in `xcshareddata/xcschemes` |
| App target | `HCGNews` (`com.apple.product-type.application`), bundle id `com.hakmicapitalgroup.hcgnews` (PROPOSED), iOS 17.0 |
| Signing | `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM` empty. Simulator builds and unsigned archives work; signed archives and IPAs need the founder's team and certificates. The Maker never creates them. |
| Swift packages | One local package (`XCLocalSwiftPackageReference` → `HCGNewsKit`). No remote dependencies, no CocoaPods. |
| Project format | `objectVersion = 77` (Xcode 16 file-system-synchronised groups). If a tool can't read it, generate an equivalent project with `xcodegen` from `iOS app/HCGNews/project.yml`. |
| Paths | The repository folder is named `iOS app` (with a space). The Maker passes arguments without a shell, so this is safe. In your own scripts, quote the path. |

Outputs that make sense for this app: a **Simulator build** (for testing) and an **unsigned `.xcarchive`** (for inspection). No upload of any kind: not to TestFlight, and not to the App Store.

## Versioning

Version numbers are changed only on purpose and are recorded in [`../CHANGELOG.md`](../CHANGELOG.md):

| Setting | Value |
|---|---|
| `MARKETING_VERSION` | `0.2.0` |
| `CURRENT_PROJECT_VERSION` | `2` |

Both are set in the app target's Debug and Release configurations, and in the UI-test target to match. `project.yml` mirrors them.

## Things that would change packaging (none are needed today)

- **Push notifications:** the Push Notifications capability and an `aps-environment` entitlement. Not added: there is no notification service.
- **Universal links:** an Associated Domains entitlement. Not needed for the custom-scheme sign-in redirect.
- **Background audio:** the `audio` background mode. Not added: published audio plays in the foreground only.
- **Bundled configuration:** `HCGNews/Resources/HCGNewsConfiguration.json` is in the synchronised `HCGNews` folder, so it's copied into every build. Never put a secret, service-role key or private value in it: the loader refuses them, and the file is public once the app ships.
- **Keychain:** the HCG account session uses the item `com.hakmicapitalgroup.hcgnews.account` (this device only, never synchronised). No Keychain Sharing entitlement is needed.
