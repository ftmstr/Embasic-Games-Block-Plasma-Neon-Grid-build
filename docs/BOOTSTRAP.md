# Android bootstrap provenance — 18 October 2026

- Source project: Embasic Games / Block Plasma: Neon Grid.
- Public Build feature branch: `feat/p0-flutter-game-core-20261018`.
- Prior verified game SHA: `2a0cab117727683fd81b11e91ead3a0e121d01c9` (21 tests and debug APK).
- Source scaffold generator: `flutter create --platforms=android --org com.embasicgames --project-name block_plasma_neon_grid .` using Flutter 3.47.7 on an Ubuntu GitHub-hosted runner.
- Runner confirmation: https://github.com/ftmstr/Embasic-Games-Block-Plasma-Neon-Grid-build/actions/runs/39127595607
- Read-back inventory: 23 `android/` and `pubspec.lock` files captured as base64 byte-perfect Git blobs; `android/gradlew` executable mode preserved, `gradle-wrapper.jar` and placeholder launcher icons retained as generated.
- Machine-only `android/local.properties`, local keystores, secrets, caches, and Private Git author/history records were excluded.
- SDK dependency source: `pub.dev` package integrity hashes as resolved by the above Flutter run; no third-party proprietary gameplay assets.
- The native manifest application name was changed to the approved product name. Debug-only CI continues; release Gradle configuration has no signing credentials and no debug signing fallback.
- The launcher icon supplied by Flutter is temporary and must be replaced with approved Embasic Games assets before store distribution.
- Verification gate: `flutter pub get`, no diffs in committed `pubspec.lock` or Android platform, `flutter analyze`, `flutter test`, `flutter build apk --debug`, artifact SHA-256.
- Real-device touch, responsive UI, heat, FPS and release AAB have not been verified.
