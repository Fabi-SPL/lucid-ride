# LucidRide — iOS Setup

This is the SwiftUI iOS app that ships through AltStore PAL. The pipeline mirrors LucidHealth's exactly — XcodeGen → xcodebuild → ad-hoc signed IPA → Supabase Storage → AltStore source JSON.

## First-time setup (one-shot)

1. **Create the GitHub repo** for `lucid-ride/` if it doesn't exist yet.
   ```powershell
   cd C:/Programs/Claude/lucid-ride
   git init
   git add .
   git commit -m "Initial LucidRide scaffold (Phase A)"
   gh repo create lucid-ride --private --source=. --push
   ```

2. **Add these GitHub secrets** to the new repo (Settings → Secrets → Actions):
   - `EE_TASKS_EMAIL` — your Supabase auth email
   - `EE_TASKS_PASSWORD` — your Supabase auth password
   - `SUPABASE_SERVICE_KEY` — Supabase service-role key (used at build time to upload IPA + source JSON to Storage; never shipped in the IPA)

3. **Trigger the first build:**
   - Push any commit, or
   - Manually dispatch via Actions → "Build LucidRide iOS" → Run workflow.

4. **Add the source to AltStore on the iPhone:**
   - Open AltStore PAL app on iPhone
   - Add Source → `[private — see project owner]`
   - "Lucid Ride" appears alongside Lucid Health / Bridge / Foods. Tap install.

That's it. From now on every push to `ios/LucidRide/**` rebuilds, uploads, and bumps the version in the AltStore source.

## Local Xcode dev (optional — for iterating on Mac)

XcodeGen reads `project.yml` and produces `LucidRide.xcodeproj`. Don't commit the .xcodeproj — let XcodeGen regenerate it.

```bash
cd ios/LucidRide
brew install xcodegen          # one time
xcodegen generate              # produces LucidRide.xcodeproj
open LucidRide.xcodeproj
```

When you change file structure (add/remove files), re-run `xcodegen generate`.

## Bundle ID + Apple Dev account headroom

- Bundle ID: `com.fabi.lucidride`
- App Group: `group.com.fabi.lucidride.shared`
- Free Apple Dev accounts allow 10 unique bundle IDs total. Each app + each widget extension counts. Plan accordingly if you also have other sideloaded apps.

## Phase A scope (what's built today)

✅ Today view — body-state band (real HRV from the health backend) + Start/End Ride morphing button
✅ Rides list — every ride-tagged activity, newest first
✅ Ride detail — real HR profile chart + placeholder telemetry tiles
✅ Settings — auth status, build info, sign out
✅ Auth (signin / refresh / signout) against the shared Supabase backend
✅ AltStore PAL pipeline (CI build, upload, source.json merge)

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
