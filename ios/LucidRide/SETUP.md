# Lucid Ride — iOS Setup

Single-screen SwiftUI app: the bike is the menu. Tap any part for that part's telemetry. Built on a GitHub Actions macOS runner, distributed exclusively via AltStore PAL.

## How distribution works

**One install path: AltStore PAL.**

GitHub Releases are intentionally NOT used. This is a public repo and the CI bakes Supabase auth credentials into the IPA — a Release would make those credentials discoverable to anyone. The IPA lives in Supabase Storage at an obscured URL referenced only by the AltStore source JSON.

| Path | Cost | Friction | Notes |
|------|------|----------|-------|
| **AltStore PAL** | Free | Medium — 7-day manual refresh in-app | Only supported path. iOS 17.4+ EU only OR sideloaded AltServer (Mac/PC). |
| ~~Sideloadly~~ | — | — | Disabled. Would require a public IPA URL. |
| ~~Appetize~~ | — | — | Disabled (no .app upload while creds are baked in). |
| ~~GitHub Releases~~ | — | — | **Permanently disabled** — public repo + baked credentials. |

The CI workflow produces a device IPA and an AltStore source JSON on every push to `ios/LucidRide/**`. Both are uploaded to Supabase Storage. **AltStore subscribes to the Supabase URL directly** — no Vercel / CDN layer. This is the only stable URL; any other (like `app.lucid-ai.app/altstore-source.json`) is a static copy that drifts and breaks.

## First-time install via AltStore PAL

**One-time iPhone setup:**

1. Install **AltStore PAL** from the App Store (requires iOS 17.4+ and being in the EU).
   - Outside EU: install AltServer on a Mac/PC and pair AltStore via Wi-Fi — both Apple devs have walkthroughs.
2. Open AltStore PAL → Browse tab → Sources → tap **+** in the top-right.
3. Add source URL: `https://db.speed-running-life.com/storage/v1/object/public/ipa-builds/altstore-source.json`
4. Tap **Add Source**. Lucid Ride appears in the source's app list.
5. Tap **Free** / **Get** next to Lucid Ride. Sign in with your free Apple ID when prompted (used only for the on-device re-sign; never shared).
6. App installs to home screen.

**Every install / update (~10 seconds):**

1. Open AltStore PAL → My Apps tab.
2. Tap the refresh icon next to Lucid Ride to pull the latest build.
3. Re-signs and installs in place.

**7-day cert refresh:** Free-Apple-ID-signed apps expire after 7 days. Open AltStore PAL → My Apps → tap the refresh icon (or hit **Refresh All**). That's it — no PC required after the initial AltStore install.

## Distribution security note

The CI pipeline injects `EE_TASKS_EMAIL` and `EE_TASKS_PASSWORD` into `SupabaseClient.swift` before xcodebuild. Anyone who obtains the IPA can extract those credentials from the compiled binary. Mitigations:

- ✅ No public GitHub Releases (this rule)
- ✅ IPA URL is in Supabase Storage with an obscure path (only AltStore source references it)
- ✅ Source JSON URL (Supabase Storage path) is only known to people Fabi shares it with
- ⚠️ Anyone Fabi shares the source URL with can decompile the IPA. Acceptable trust boundary — same set of people who would have his password anyway.

**The proper fix** (deferred): a Keychain-backed sign-in screen so the IPA contains no credentials at all. Tracked in `.private/CLAUDE.md`.

## AltStore PAL landmines (documented, do not repeat)

Known issues recurring on this pipeline — all fixed, kept here as warnings:

1. **`appPermissions` must use the object-wrapped shape**, NOT the legacy strings/dict shape that faq.altstore.io's docs show. Real Codable wants `entitlements: [{name}]` and `privacy: [{name, usageDescription}]`. This was the actual recurring root cause of "data isn't in correct format."
2. **`entitlements` must match the IPA's real entitlements file** — declare `com.apple.security.application-groups` because `LucidRide.entitlements` ships App Groups.
3. **`marketplaceID` field must NOT be present on any app entry.** That field flags apps as Apple-notarized marketplace distribution; AltStore Classic refuses any source carrying it.
4. **Subscribe AltStore to the Supabase URL directly**, never to the Vercel static copy. The Vercel file (`app.lucid-ai.app/altstore-source.json`) is legacy / not maintained.
5. **`iconURL` must be on `app.lucid-ai.app`**, NOT Supabase. AltStore rejects Supabase Storage URLs for iconURL specifically (works fine for downloadURL).

Full diagnostic + recovery commands in `.private/CLAUDE.md`.

## CI prerequisites (one-time, already done)

Repo secrets that must be set in https://github.com/Fabi-SPL/lucid-ride/settings/secrets/actions:

- `EE_TASKS_EMAIL` — Supabase auth email (sed-injected into IPA — see security note above)
- `EE_TASKS_PASSWORD` — Supabase auth password (sed-injected into IPA — see security note above)
- `SUPABASE_SERVICE_KEY` — Supabase service-role key (uploads IPA + source.json to Storage; CI-only, never in IPA)

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
- ✅ GLTFKit2 SPM dep loads `bike.glb` with position-clustered hit testing

## Phase B (deferred — hardware-pending)

- Keychain-backed sign-in screen (eliminates credential injection — see security note)
- Health-backend webhook handler (Edge Function — workout-updated event upserts ride aggregates)
- GoPro GPMF ingest (Edge Function watches a synced folder for new MP4s)
- RaceBox Mini S CSV pipeline + IMU lean-angle calculation
- OBD adapter BLE service + Swift OBD-II integration
- ride_telemetry table DDL (FK to activities.id, partitioned monthly via pg_partman)
- ride_segments materialized table (corner detection at upload time)
- Cardo Bluetooth voice debrief (TTS through helmet intercom)
- iOS Action Button binding (Start/End Ride from lock screen)
- Live Activity for in-progress ride (lock-screen HR + duration)
