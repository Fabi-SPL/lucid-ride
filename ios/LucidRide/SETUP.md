# Lucid Ride — iOS Setup

Single-screen SwiftUI app: the bike is the menu. Tap any part for that part's telemetry. Built on a GitHub Actions macOS runner, distributed via Sideloadly (recommended) or AltStore PAL (fallback). Live desktop preview via Appetize.io free tier.

## How distribution works now (after 2026-05-11 rewrite)

Three install paths exist, ranked by friction:

| Path | Cost | Friction | Best for |
|------|------|----------|----------|
| **Sideloadly** | Free | Lowest — drag IPA into Sideloadly, daemon auto-re-signs every few days | **Daily use** |
| **Appetize.io (free tier)** | Free | None on phone — opens in browser as iPhone 15 Pro | **Visual preview, no phone** |
| **AltStore PAL** | Free | Highest — 7-day manual refresh, schema-validation landmines | Fallback only |

The CI workflow produces all three artifacts on every push: a device IPA on GitHub Releases (for Sideloadly + AltStore), a simulator .app uploaded to Appetize (for browser preview), and the AltStore source JSON (for the legacy AltStore PAL flow).

## First-time install via Sideloadly (recommended)

**One-time PC setup, ~10 minutes:**

1. Download Sideloadly for Windows: https://sideloadly.io/
2. Install it. Open it.
3. Plug your iPhone into the PC via Lightning/USB-C cable.
4. Sign in to Sideloadly with your **free Apple ID** (not the project owner's — your personal one). Sideloadly only uses this for re-signing; it never shares credentials.
5. (Optional but recommended) Enable "Anisette" daemon in Sideloadly settings for stable cert refresh.

**Every install / update, ~30 seconds:**

1. Open https://github.com/Fabi-SPL/lucid-ride/releases/latest in a browser
2. Download `LucidRide.ipa` from the latest release
3. Drag the IPA file onto the Sideloadly window
4. Hit **Start** — it pushes to your iPhone wirelessly (USB only required for first device pair)
5. App appears on the iPhone home screen ~30 seconds later

**Auto re-sign:** Sideloadly's background daemon refreshes the cert every few days while your PC is awake. The 7-day expiration of free-Apple-ID-signed apps becomes invisible as long as you boot the PC at least once a week with Sideloadly running in the tray.

## Desktop preview via Appetize.io (free tier)

**One-time account setup:**

1. Create a free Appetize account: https://appetize.io/signup
2. From the Appetize dashboard, generate an API token (Account → API)
3. In the lucid-ride GitHub repo: Settings → Secrets → Actions → New repository secret
   - Name: `APPETIZE_API_TOKEN`
   - Value: (paste the token from step 2)
4. Push any commit to `ios/LucidRide/**` (or manually re-run the workflow)
5. The workflow uploads the simulator build. Open the workflow's run summary — at the bottom there's a "Preview URL" notice plus a `publicKey` to save.
6. Save that publicKey as another GitHub secret: `APPETIZE_PUBLIC_KEY`. From now on every build updates the same Appetize app, keeping the preview URL stable.

**Daily use:** bookmark the preview URL from step 5. Open it in any browser on your Windows desktop. The app runs as a virtual iPhone 15 Pro. Free tier = 100 min/month, 3 min per session, plenty for solo preview.

**What works in the simulator:** the bike scene, the HUD layout, the tap-to-sheet flow, the visual animations, the placeholder telemetry. What doesn't: real heart rate from LucidBridge, real Bluetooth, real motion sensors. Use Sideloadly install for those.

## AltStore PAL fallback

Only use this if both Sideloadly and Appetize are unavailable. The AltStore source URL is `https://app.lucid-ai.app/altstore-source.json` and requires the AltStore PAL app on iPhone. Known landmines (entitlements mismatch, iconURL host, Vercel cache drift) are documented in `.private/CLAUDE.md`.

## CI prerequisites (one-time, already done)

Repo secrets that must be set in https://github.com/Fabi-SPL/lucid-ride/settings/secrets/actions:

- `EE_TASKS_EMAIL` — Supabase auth email
- `EE_TASKS_PASSWORD` — Supabase auth password
- `SUPABASE_SERVICE_KEY` — Supabase service-role key (used to upload IPA to Storage for the AltStore fallback path)
- `APPETIZE_API_TOKEN` — Appetize API token (optional — Appetize upload is skipped cleanly if absent)
- `APPETIZE_PUBLIC_KEY` — Appetize app publicKey (optional — set after first Appetize upload so subsequent builds update the same app)

## Local Xcode dev (optional — for iterating on a Mac)

XcodeGen reads `project.yml` and generates `LucidRide.xcodeproj`. Don't commit the .xcodeproj — let XcodeGen regenerate it.

```bash
cd ios/LucidRide
brew install xcodegen   # one time
xcodegen generate       # produces LucidRide.xcodeproj
open LucidRide.xcodeproj
```

Re-run `xcodegen generate` after adding or removing files.

## Bundle ID + Apple Dev account headroom

- Bundle ID: `com.fabi.lucidride`
- App Group: `group.com.fabi.lucidride.shared`
- Free Apple Dev accounts allow 10 unique bundle IDs total per 7 days. Each app + each widget extension counts.

## Phase A scope (what's built today)

- ✅ Bike-as-app — single full-screen 3D bike, tap any part for telemetry
- ✅ Headlight tap → real HR / HRV / Body State from `realtime_health` table
- ✅ Other parts (tank, fairings, wheels) → "Hardware pending" placeholders with the right slots
- ✅ START / END RIDE pill (floating bottom-right)
- ✅ Settings sheet (auth status, build version pulled live from Info.plist, sign out)
- ✅ Landscape-only, status bar hidden, idle timer disabled while app is open
- ✅ GLTFKit2 SPM dep loads `bike.glb` (Suzuki SV650, CC-BY 3.0 / Paul Spooner) with position-clustered hit testing

## Phase B (deferred — hardware-pending)

- Health-backend webhook handler (Edge Function — workout-updated event upserts ride aggregates)
- GoPro GPMF ingest (Edge Function watches a synced folder for new MP4s)
- RaceBox Mini S CSV pipeline + IMU lean-angle calculation
- OBD adapter BLE service + Swift OBD-II integration
- ride_telemetry table DDL (FK to activities.id, partitioned monthly via pg_partman)
- ride_segments materialized table (corner detection at upload time)
- Cardo Bluetooth voice debrief (TTS through helmet intercom)
- iOS Action Button binding (Start/End Ride from lock screen)
- Live Activity for in-progress ride (lock-screen HR + duration)
