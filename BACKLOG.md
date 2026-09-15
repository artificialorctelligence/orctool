# Backlog

Open items not yet scheduled into a task. Each entry keeps the context that
led to it - not just "what," but "why this matters" - so picking it up later
doesn't require re-deriving the reasoning from scratch.

## #1: Recorder: the stale-session guard in _fail has no test that drives it, and onDone/_runId share the same race shape

Found by the final whole-branch review of slice 1 (2026-09-14). `Recorder` is shared by every
instrument screen. A session whose store writes fail slowly (the realistic trigger is a
background WorkManager sample holding SQLite's 2.5 s busy timeout per queued row) fires
`_fail` → `stop()` once per failed row, unawaited; if the user has meanwhile started a new
session, a stale `stop()` used to null the new subscription — an unstoppable recording. The fix
landed in 0bd8397: `stop()` nulls `_sub`/`_session` before any await and `_fail` ignores a
session token that is no longer current. The re-review found the fix correct but the test
`"_fail's fire-and-forget stop() cannot orphan a session started while it is still cancelling"`
only exercises the null-before-await half; removing the `if (session != _session) return;` line
still passes the suite. So the guard is unprotected against a future refactor. Two siblings of
the same shape are also untested and ungated: `onDone: stop` is passed bare (a straggling
`onDone` from an old subscription would stop a new session), and `_runId!` is read as a live
field inside `onData`, so a straggling old reading during the cancel window would be tagged
with the new session's run id. What to do: one test that delivers an old session's failure
*after* a new session has started (a controller whose error is added after `start(B)`), then
gate `onDone` and capture `_runId` per session the same way `_fail` is gated. Does not affect
scheduled logging (`runScheduledSample` has no session state).

## #2: Console skin: bold weight is invisible because Antonio is a variable font

Seen on the emulator during Task 15 of slice 1 (screenshots in docs/screenshots/slice-1, e.g.
07-console-motion.png): "MOTION" (fontWeight bold) and "PITCH" (regular) render identically in
the console skin. `assets/fonts/Antonio[wght].ttf` is a variable font registered as a single
asset in `pubspec.yaml`; Flutter maps `FontWeight` to a static face, not to the `wght` axis, so
bold does nothing. Consequence: the rail's active segment and the title bar lose the weight
contrast the mockup had; readability is fine, it is just flatter than designed. Fix: in
`lib/skins/console.dart` set `fontVariations: [FontVariation.weight(700)]` on the text styles
that ask for bold (keeps the literal inside `lib/skins/`, so the literal-scan test stays
clean), or ship a second static instance of Antonio. Plain skin unaffected (Roboto is static).

## #3: Play packaging prerequisites the code does not yet meet: upload signing, app label, coarse-location declaration

Collected by the final review of slice 1 (2026-09-14); none blocks merging the branch, all
block or embarrass the first Play internal-track upload, which is `/orc-package play`'s job:
(1) `android/app/build.gradle.kts` still signs release builds with the debug key — Play rejects
the bundle; `android/key.properties` is already git-ignored, the standard
`signingConfigs.release` block from the Flutter deployment doc is what is missing. (2)
`AndroidManifest.xml` has `android:label="orctool"` from `flutter create` — the launcher shows a
lowercase name; it should be "Orctool". (3) `ACCESS_COARSE_LOCATION` is not declared; Android
12+ adds it implicitly (confirmed in the emulator's requested permissions) and geolocator reads
the merged list, so it works today, but the Data safety answer is "approximate location" and the
explicit declaration is the documented requirement. (4) The Data safety form must be answered
from the *merged* manifest (workmanager and geolocator merge `POST_NOTIFICATIONS` and
`FOREGROUND_SERVICE*`), not from `AndroidManifest.xml`, and the privacy policy must name
Open-Meteo as a recipient of approximate (2-decimal) location. Also worth knowing for
VERIFICATION.md item 4: the emulator run granted location with `pm grant`, so the real runtime
permission prompt has never been exercised — the phone walk is the first time it will be.
