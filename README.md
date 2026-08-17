# Lucid Ride

> A SwiftUI iOS app that turns a motorcycle ride into a queryable, body-state-aware record.

A standalone iOS app, distributed via [AltStore PAL](https://altstore.io/), that joins three streams on one timeline:

1. **Heart rate + HRV**: pulled from a linked health backend (Supabase REST + JOIN by ride window)
2. **GPS + IMU + lean angle + segments**: from a tracker I built and mounted on the bike, described below
3. **Body-state correlation**: *"on rides where my morning HRV was poor, am I leaning less?"* That kind of question.

## Why this exists

Most fitness platforms have nothing comparable to lean-angle data. Body-state ↔ ride-quality joins reveal patterns that no single consumer source can show. The pipeline is reusable for running, cycling, hiking once it exists.

## Stack

- **iOS:** SwiftUI native, iOS 26 deployment target (Liquid Glass)
- **Build:** [XcodeGen](https://github.com/yonaskolb/XcodeGen) → `xcodebuild` → ad-hoc signed IPA via GitHub Actions (macos-15 runner)
- **Distribution:** AltStore PAL, free Apple Developer account, 7-day re-sign cadence
- **Hosting:** Supabase Storage for IPA + AltStore source JSON, versioned URLs to bust the AltStore client cache
- **Backend:** Supabase Postgres 17 with [pg_partman](https://github.com/pgpartman/pg_partman) for monthly partitions, [PostGIS](https://postgis.net/) for GPS, no TimescaleDB
- **Realtime (later):** [Supabase Broadcast](https://supabase.com/docs/guides/realtime/broadcast), not Postgres Changes (WAL bottleneck at 25 Hz inserts)

## The tracker

The telemetry does not come from the phone. It comes from a box I built and mounted on the bike.

- **Hardware:** a NodeMCU ESP8266 and a BNO085 IMU, hand soldered, sitting in a 3D printed enclosure modelled around those specific components. NeoPixel status LED, battery sense on the ADC.
- **Logging:** 25 Hz to onboard flash in its own binary format, `LRD4`. A 16 byte header carries rate, flags, epoch and file id, and the reader still parses the older 8 byte header, so rides recorded before the format changed did not become unreadable.
- **Clock and upload:** the tracker joins my phone hotspot, the only network that comes along on a ride. That buys it a real clock over NTP plus live 5 Hz upload, and it drains anything still sitting on flash when it reconnects.
- **Cloud:** a hand written HTTP POST straight to Supabase PostgREST with `Prefer: resolution=ignore-duplicates`, so re-uploading a ride is harmless.
- **On device:** it serves its own dashboard and analyzer, and takes OTA firmware updates, off the chip itself.

Rides recorded by the app and telemetry uploaded by the tracker are joined by time window, so both halves land on one timeline without the phone ever talking to the box directly.

**The firmware is not in this repo.** It is written against one board, one wiring diagram and one enclosure, so it would not drop cleanly into anyone else's build. If you want to read it anyway, message me and I will send it over.

## Quick start

See [`ios/LucidRide/SETUP.md`](ios/LucidRide/SETUP.md) for first-time setup, including required GitHub secrets, AltStore source URL, the bundle-ID-headroom note for free Apple Dev accounts.

## Project layout

```
lucid-ride/
├── README.md                    # this file
├── ios/LucidRide/               # the app
│   ├── project.yml              # XcodeGen config (don't commit the .xcodeproj)
│   ├── SETUP.md                 # setup walkthrough
│   └── LucidRide/               # SwiftUI sources
│       ├── DesignSystem.swift   # tokens + 4 glass tiers + mesh background + components
│       ├── Services/            # Supabase REST client (auth + activities + realtime_health)
│       ├── Models/              # Ride, BodyState
│       └── Views/               # Today / Rides / RideDetail / Settings + components
└── .github/workflows/
    └── build-lucidride.yml      # CI: XcodeGen → xcodebuild → IPA → Supabase Storage → AltStore source merge
```

## Phase A status

✅ Today view: body-state band (real HRV from the health backend) + Start/End Ride morphing button + recent rides
✅ Rides list: every ride activity, newest first
✅ Ride detail: real HR profile chart (Swift Charts) + placeholder telemetry tiles
✅ Settings: auth, build info, sign out
✅ AltStore PAL pipeline (CI build, upload, source.json merge)

✅ Tracker telemetry landing in `tracker_telemetry` and bound to app-recorded rides by time window

🚧 Phase B:
- Rendering that telemetry in the app. The ride detail tiles are still placeholders.
- Health webhook handler for ride aggregates (Edge Function)
- GPMF (GoPro telemetry) ingest pipeline
- OBD adapter BLE service
- ride_telemetry table + ride_segments materialization
- Cardo Bluetooth voice debrief
- iOS Action Button binding
- Live Activity for in-progress ride

## Frozen architectural decisions

- **No new `rides` table.** The existing health backend's activities table tagged with the right activity type *is* the rides table. High-frequency tracker telemetry lives in a separate FK'd table and is bound to a ride by time window.
- **No PWA / Capacitor / Tauri.** Native SwiftUI for best CoreBluetooth access (BLE telemetry hardware), best AltStore sideload compatibility, best iOS 26 Liquid Glass adoption.
- **Don't try to mod the bike's stock TFT cluster.** Signed firmware, dealer-only updates, no realistic custom-UI path. Phone HUD on a Quad Lock / X-Grip mount is the only sane option.
- **AltStore PAL ships everything.** Versioned IPA URLs in the source JSON bust the client cache.

## License

Personal project. Feel free to take reference patterns. Ask before forking the actual app target.
