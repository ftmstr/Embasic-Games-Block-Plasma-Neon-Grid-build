# Block Plasma: Neon Grid

**Embasic Games** — original offline neon-grid block puzzle for Android, written in **Flutter/Dart**.

> Stage: v0.1 bootstrap. Real CI PASS, debug APK, on-device performance and app signing must be confirmed from GitHub Actions logs; source presence alone is not proof.

## Canonical mechanics

- Portrait 8×8 board; three tray slots; 15 fixed unrotated shapes.
- Atomic legal placement, simultaneous completed-row/column union clearing, deterministic scores/combo/tray refill/game over.
- Place score = cells × 5; unique cleared cells × 10; extra lines × 25; consecutive clear combo × 20.
- Game logic is pure Dart (`lib/domain/game_engine.dart`); Flutter owns rendering and touch interaction.
- First-stage UI has Home, Classic, drag/drop, scoring, pause and restart. Local save, polished animation, localization, accessibility and Ads are later stages.

## Build on your Android / Flutter workstation

The initial Build repository deliberately contains no historical or private Git metadata. The Android platform scaffold is reproducibly generated with Flutter 3.47.7 (same version pinned by the private planning template):

```sh
flutter create --platforms=android --org com.embasicgames --project-name block_plasma_neon_grid .
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
sha256sum build/app/outputs/flutter-apk/app-debug.apk
```

The clean CI generates `android/` on the runner because the authoring environment initially has no Flutter/Android SDK. **Do not claim a completely checked-in native Android scaffold or a reproducible lockfile until they are generated and reviewed in a subsequent verified pass.** `pubspec.lock` is intentionally *not ignored* and must be committed in the next SDK-verified bootstrap pass.

Android application ID is provisional from `--org com.embasicgames`; final identifier and targetSdk compliance require an ADR and Play Console checks before release.

## CI and security

`.github/workflows/android-debug.yml` uses `ubuntu-latest`, read-only workflow permissions, no keystore, no prod AdMob and an unprivileged debug APK artifact. The production signing key, personal data, financial records, licensed brand assets, original Private repository history and private account configuration must NEVER be stored here.

The project currently uses Flutter's built-in rendering; independent animation/sound/asset/AdMob modules are not shipped in this baseline. See `docs/ADR/001-clean-build.md`.

## Reference

Canonical design and acceptance criteria are in the owner's 13-document Block Plasma: Neon Grid source package (2026-10-14). Branch changes are proposed via PR; no Play production deployment is authorized.
