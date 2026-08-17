# Lucid Ride

> A SwiftUI iOS app that turns a motorcycle ride into a queryable, body-state-aware record.

A standalone iOS app, distributed via [AltStore PAL](https://altstore.io/), that joins three streams on one timeline:

1. **Heart rate + HRV**: pulled from a linked health backend (Supabase REST + JOIN by ride window)
2. **GPS + IMU + lean angle + segments**: telemetry placeholders today, wired up as hardware lands
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

🚧 Phase B (deferred, hardware-pending):
- Health webhook handler for ride aggregates (Edge Function)
- GPMF (GoPro telemetry) ingest pipeline
- 25 Hz IMU CSV ingest (RaceBox Mini S)
- OBD adapter BLE service
- ride_telemetry table + ride_segments materialization
- Cardo Bluetooth voice debrief
- iOS Action Button binding
- Live Activity for in-progress ride

## Frozen architectural decisions

- **No new `rides` table.** The existing health backend's activities table tagged with the right activity type *is* the rides table. New high-frequency telemetry goes in a separate FK'd table once hardware lands.
- **No PWA / Capacitor / Tauri.** Native SwiftUI for best CoreBluetooth access (BLE telemetry hardware), best AltStore sideload compatibility, best iOS 26 Liquid Glass adoption.
- **Don't try to mod the bike's stock TFT cluster.** Signed firmware, dealer-only updates, no realistic custom-UI path. Phone HUD on a Quad Lock / X-Grip mount is the only sane option.
- **AltStore PAL ships everything.** Versioned IPA URLs in the source JSON bust the client cache.

## License

Personal project. Feel free to take reference patterns. Ask before forking the actual app target.
