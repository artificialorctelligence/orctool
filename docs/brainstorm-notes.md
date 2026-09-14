# Orctool — brainstorm notes (2026-09-13, carried over from the orcshot session)

Cross-platform mobile app in the spirit of Moonblink's Android *Tricorder* (pulled from the
Market in 2011 after a CBS takedown over the name and the LCARS look): real onboard sensors and
free online services, no fiction. Skinnable UI; one skin LCARS-*adjacent*, not a copy.

## Orclab routing

App, Android + iOS → **Flutter** (`orclab:stack-flutter`; alternatives React Native, Kotlin
Multiplatform). Not the game flow: realtime waveform/spectrum is a `CustomPainter` redrawn per
frame off a mic stream; a game engine would make the skinnable chrome (panels, pills, type) the
hard part. iOS builds via Codemagic's free Mac minutes; everything else builds on this machine.

## Legal guardrails

- No "Tricorder" / "LCARS" in the app or skin names; no Trek names anywhere.
- No Swiss 911 Ultra Compressed (licensed); the open lookalike is *Antonio*.
- Skin = curved frames, warm palette, condensed type — adjacent, not a reproduction.

## Feature availability, Android vs iOS — FROM MEMORY, verify every row against live Apple/Android docs before it enters a spec (`orclab:currency-discipline`)

| Feature | Android | iOS |
|---|---|---|
| Accelerometer, gyro, magnetometer, compass, level | yes | yes |
| Barometer (pressure/altitude) | many phones, not all | iPhone 6+ |
| GPS + altitude | yes | yes |
| GNSS satellite view (constellation, SNR) | yes | no API |
| Weather / online services | yes | yes |
| Mic waveform / spectrum / dB | yes | yes |
| Wi-Fi SSID | yes (location perm) | yes (entitlement + location perm) |
| Wi-Fi RSSI, channel, link speed, scan | yes | no |
| Cell: carrier, network type | yes | network type only; carrier name "--" since iOS 16 |
| Cell: signal strength, cell ID | yes | no |
| NFC/RFID tag read | full (NDEF + raw tag tech) | NDEF + ISO tags, iPhone 7+; Apple's system scan sheet is mandatory |
| Ambient light (lux) | yes | no (camera-exposure workaround only) |
| BLE scan (nearby + RSSI) | yes | yes |
| LiDAR distance | no | Pro models |

Rule: each instrument declares `isAvailable()`, probed once at launch; the menu is built from
what answers yes. No other per-platform UI code.

## Candidate features beyond the original list

Space weather (NOAA SWPC Kp / solar wind, free, no key); air quality + UV (Open-Meteo, free, no
key); World Magnetic Model computed offline → measured-vs-expected magnetic field; sun/moon/ISS
ephemeris (offline math); USGS earthquake feed; BLE nearby radar; camera instruments (light meter,
color sampler, heart rate via finger-on-flash); ruler (screen-ruler needs physical DPI — Android
reports it, iOS needs a model lookup; AR ruler is a later, heavy slice); level from accelerometer.

## Stores

Play: $25 one-time; new personal accounts must run a closed test (12 testers, 14 days) before
production. Apple: $99/year. Orclab's `play` and `app-store` ingredients and the Flutter skill are
researched but unproven — this project proves them. No account needed until slice 1 runs on a
real phone.

## Scope — at least five slices, each its own spec → plan cycle

1. Skeleton + skin system + capability gating + motion/compass/level (offline, no permissions)
2. Location + online services (weather, air, space weather, ephemeris)
3. Audio (waveform, spectrum, dB)
4. Radios: Wi-Fi, cell, BLE, NFC
5. Store onboarding (Play internal track first, then App Store via Codemagic)

## Open questions

- iOS day-one, or Android-first with iOS a later slice?
- Which phones are available to test on?
- Project name confirmed: **orctool**.
