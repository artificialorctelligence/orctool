# Verification — slice 1, on a real Android phone

Nothing in `flutter test` proves a sensor. Walk this after every change to an instrument
or to permissions, on the phone, and tick what you saw.

1. Launch: plain skin; rail shows Motion, Compass, Location, Weather, Records, Settings.
   Any instrument missing = its `isAvailable()` said no — check `adb logcat | grep -i sensor`.
2. Motion: tilt the phone; the bubble moves to the HIGH side (right edge down → bubble
   left; nose up → bubble up); `g` reads ~1.000 at rest.
3. Compass: rotate; heading changes smoothly and is steady when the phone is still (it is
   the OS's fused rotation-vector sensor, not the raw magnetometer). N on the dial points to
   magnetic north — a maps app shows TRUE north, so expect them to differ by the local
   declination. Field reads 25–65 µT away from metal. "Accuracy" is the OS's own estimate;
   ±30° means "calibrate me" (figure-8 the phone).
4. Location: first open asks for location permission → allow "while using". Lat/lon appear
   within a minute outdoors. Deny instead → the band says "Location permission needed" with
   Retry and App settings; the record button is disabled.
5. Weather: temperature and a condition appear; "as of" shows the fetch time. Airplane mode,
   then wait 15 min: the reading stays, the time does not move.
6. Session: record on Compass for 30 s, stop. Records lists it with rows > 0; open it; Export
   CSV opens the share sheet; the file has `ts,field,heading,mx,my,mz`.
7. Title bar: tap it; the rail slides in and "Compass" appears on the right; tap again; kill
   and relaunch — the rail state was remembered.
8. Skin: Settings → Console. Everything uppercase, Antonio, amber on black; back to Plain.
9. Settings → Instruments: drag Weather to the top — the rail follows. Hide Motion — it leaves
   the rail; unhide it.
10. Logging, Weather: Log on, details: every 15 min. Close the app fully. After ~20–30 min
    (Android may delay it), reopen: Records shows a Log run for Weather with ≥1 row.
    A closed app cannot get a GPS fix without the "all the time" grant; Weather uses the
    last foreground fix instead — open Location once first. To re-run the worker
    immediately, toggle Weather's Log off and on (it re-registers and runs once).
11. Logging, Location: Log on → blocked with the "all the time" message. Details → Allow all
    the time → the system settings page; choose "Allow all the time"; back; Log on succeeds.
    Close the app; after the interval, Records shows a Location log row.
12. Retention: Settings → cap 10 MB; record Motion for 10 min; the storage line never exceeds
    10 MB.
13. Store rules: `flutter pub deps --style=compact` — the plugin list is what the Play Data
    safety form is answered from (location: collected, on-device; weather: approximate
    location sent to Open-Meteo).

Record the phone model and Android version with each run:

| Date | Phone | Android | Result |
|---|---|---|---|
| 2026-09-14 | Pixel 9 Pro XL | 17 | 1–11 pass. Found and fixed the same day: raw-magnetometer heading wandered ~9° at rest → switched to the fused rotation-vector sensor; sessions ran at ~100 Hz → throttled to the display rate; stored values unrounded; run table showed minutes only; CSV named `compass-compass-…`; app label `orctool`. Background logs (10, 11) proven with the app's process killed: Location fix at 22:22 under the "all the time" grant, Weather fetch at 22:24. Not walked: 4's deny branch, 5's airplane-mode wait, 12 (at ~9 Hz a 10-min Motion session is ~1 MB — the cap is exercised by unit tests and the emulator), 13. |
