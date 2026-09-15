# Verification — slice 1, on a real Android phone

Nothing in `flutter test` proves a sensor. Walk this after every change to an instrument
or to permissions, on the phone, and tick what you saw.

1. Launch: plain skin; rail shows Motion, Compass, Location, Weather, Records, Settings.
   Any instrument missing = its `isAvailable()` said no — check `adb logcat | grep -i sensor`.
2. Motion: tilt the phone; the bubble moves opposite to the tilt; `g` reads ~1.000 at rest.
3. Compass: rotate; heading changes smoothly; N on the dial points to magnetic north
   (compare with another compass app). Field reads 25–65 µT away from metal.
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
