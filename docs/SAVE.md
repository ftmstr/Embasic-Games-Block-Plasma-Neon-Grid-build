# BP-NG P0 local-save contract — draft verification

Schema: `GameState.schemaVersion = 1`. Persist `board[64]`, `tray[3]` (piece IDs), `score`, `bestScore`, `combo`, `rngState`, `turnId` and `gameOver` atomically.

The Android application-owned files directory is returned by a Kotlin MethodChannel. No runtime storage permission or plugin is required.

Save contract: asynchronous `pending` file with `flush:true` → previous valid primary rotated to `backup` → pending renamed to primary. Call sequence is serialized. A killed process cannot commit a half-updated turn. Read contract: primary, then backup; invalid or future-version records surface explicit statuses. A recovered backup is never overwritten by a corrupt primary. Orphan pending files are ignored. No cloud synchronization.

Versioning: unknown `schemaVersion` is unsupported, not quietly parsed as v1. No migration is asserted to exist until a new schema is introduced and tested. A player-visible warning is required before resetting an unsupported snapshot.

Evidence gate: deterministic unit tests, CI analyze/test/debug APK, physical Android kill/relaunch on-device smoke, source SHA, APK checksum. Device validation has not been carried out.

Security note: only gameplay state is persisted; no identifiers, credentials, advertising or personally identifying information.
