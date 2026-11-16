# Changelog — cv_kasippu_system

All notable changes to the Kasippu script.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) · Versioning: [SemVer](https://semver.org/).

## How to release a version

1. Move everything under **[Unreleased]** into a new `## [x.y.z] - YYYY-MM-DD` section.
2. Bump `version` in `fxmanifest.lua` to the same number.
3. Write 3–6 short lines for server owners in `version.json` (same number).
4. Upload the build to keymaster.
5. **Last:** copy `version.json` over `gsc_kasippu_system.json` in
   [0nexo0/CronicalVerse-Versions](https://github.com/0nexo0/CronicalVerse-Versions), commit, push.
   Pushing tells every server to update, so only do it once the build is on keymaster.

The server console shows the result on start (`cv_core/server/version.lua`):
up to date (green), outdated with the changelog lines from that JSON (red), or a dev build (yellow, local version newer than the release).

## [Unreleased]

## [1.6.0] - not released yet

### Added
- **Kasippu radial menu (F6)** — every action available where you stand, in one wheel.
- **Version check, CronicalVerse edition** — `cv_core/server/version.lua` is now the shared
  `versioncheck.lua` from CronicalVerse-Versions.
  - Says so in the console when `version` or `cv_version_id` is missing from `fxmanifest.lua`.
  - This file (`CHANGELOG.md`) and `version.json` (the release notes to publish).

### Changed
- **Resource folder is now `cv_kasippu_system`** (was `gsc_kasippu_system`). Event names are unchanged.
  - `fxmanifest.lua`: `gsc_version_id` → `cv_version_id`.
  - The version file stays `gsc_kasippu_system.json`, so 1.5.x and 1.6.0 servers read the same file.
- **Turning the version check off:** `set cv_versioncheck false` in `server.cfg` (was `gsc_versioncheck`).
  A server that only has `set gsc_versioncheck false` will see the check again; add the `cv_` line too.
  `Config.VersionCheck = false` in `config/main.lua` still works.
- **Placement notes use VORP `NotifyObjective`.** Setting down a still, an aging crate, a Water Barrel or a Log Rack.
  A new placement note always replaces the old one. `Config.Notify.PlacementObjective` (true; false = show them like any other note).

### Fixed
- **Fill Water Barrel could be spammed, and X cancelled the pour but kept the water.**
  The barrel now fills only when the pour animation plays out. Breaking it off (X, moving, ragdoll, death) fills nothing.
- **A new VORP note waited behind the previous action's note.** The old note is now cleared from the game feed first.

## [1.5.1] - 2026-11-10
### Added
- New notify system.
- New minigames.
### Changed
- Improved performance.
### Fixed
- Bug fixes.

## [1.5.0] - 2026-10-26
### Added
- First release as `gsc_kasippu_system`.
