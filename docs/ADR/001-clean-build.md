# ADR-001: Clean Public Build bootstrap (2026-10-18)

**Decision:** Keep `ftmstr/block-plasma-neon-grid` Private, untouched. Maintain an independent Public Build source history. Do not cherry-pick, clone/push or carry metadata from Private. Implement 8×8 game rules as pure Dart; Flutter Material widgets are a temporary visual adapter until CustomPainter and final neon motion system have dedicated acceptance tests.

**Scope:** v0.1 15-piece classic; 3 slots; row/column union; scoring 5/10/25/20; immutable snapshots; deterministic 32-bit LCG RNG for replay, NOT cryptographic purposes. No timer, rotation, Challenge levels, sound pack, ads or production release.

**Bootstrap update (2026-10-18):** Flutter 3.47.7 GitHub Actions generated 23 native Android/lock files; these are staged from a verified CI log into clean Build source. CI will now consume a committed native scaffold and `pubspec.lock` without `flutter create`. Each post-commit analyze/test/build result must still be verified by its exact SHA. Device, performance, release-signing and Play gates remain open.

**Risk gates:** Branch protection is not presumed. UI drag anchor and performance are not physically validated. Save serialization is implemented as a domain codec but durable disk save/resume is not. Product identity `com.embasicgames...` remains provisional. All remaining gates are tracked in future PRs; never publish to Google Play automatically.
