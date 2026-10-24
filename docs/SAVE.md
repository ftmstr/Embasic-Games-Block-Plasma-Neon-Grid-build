# BP-NG P0 local-save contract — draft verification

Schema: `GameState.schemaVersion = 1`. Persist `board[64]`, `tray[3]` (piece IDs), `score`, `bestScore`, `combo`, `rngState`, `turnId` and `gameOver` atomically.

The Android application-owned files directory is returned by a Kotlin MethodChannel. No runtime storage permission or plugin is required.

Save contract: asynchronous `pending` file with `flush:true` → previous valid primary rotated to `backup` → pending renamed to primary. Call sequence is serialized. A killed process cannot commit a half-updated turn. Read contract: primary, then backup; invalid or future-version records surface explicit statuses. A recovered backup is never overwritten by a corrupt primary. Orphan pending files are ignored. No cloud synchronization.

Versioning: unknown `schemaVersion` is unsupported, not quietly parsed as v1. No migration is asserted to exist until a new schema is introduced and tested. A player-visible warning is required before resetting an unsupported snapshot.

Evidence gate: deterministic unit tests, CI analyze/test/debug APK, physical Android kill/relaunch on-device smoke, source SHA, APK checksum. Device validation has not been carried out.

Security note: only gameplay state is persisted; no identifiers, credentials, advertising or personally identifying information.

## R002 hardening notes (2026-10-18)

A schema from a future game version in **either** on-disk slot blocks automatic downgrade even if another slot contains older valid game state. Loading signals `unsupportedVersion` and preserves both files. A new save independently validates existing primary and backup, so callers that skip `load()` cannot clobber the only valid backup or newer-version data. The UI remains blocked if `clear()` fails; only an explicitly successful clear permits a new game.

A snapshot larger than 64 KiB is rejected before JSON decoding. Invalid board values, truncated payloads and schema failures are not considered valid backup candidates. The temporary `pending` file remains ignored on reads; operations within one repository instance are serialized. Empty first launches immediately persist the initial deterministic three-piece tray. Disk `flush:true` plus same-directory rename offer process-crash recovery, **not** a cross-filesystem or power-loss durability guarantee; emulator and device validation must be separately proven.

## R003 native drag QA specification

The Android API35 x86_64 emulator smoke uses the installed debug APK and performs a genuine Android touchscreen `input draganddrop` from the first Classic tray piece to board cell (8,8). Accessibility semantics supply coordinate locations without assuming fixed device density. The fixture state (score=73, turnId=9, rngState=314159265, slot0=single, board[0]=1) is restored first. The drag must yield score=78, turnId=10, unchanged RNG/best/combo, board cells 0+63 occupied, consumed tray0, and identical disk snapshot after a force-stop and fresh app launch. No JSON editing is permitted after the actual drag. Screens 04 and 05 are produced by adb screencap and checked in the five-capture proof bundle. Flutter widget regression separately long-press-drags onto the last grid cell. Emulator smoke PASS requires final new marker `SMOKE-REAL-DRAG-RELAUNCH-RNG-TURN-BOARD-PASS`, not just prior seeded-fixture markers. Device testing is a separate NOT RUN gate.
