# Changelog

## Unreleased

## 0.0.4 - 2026-05-16

### Added

- Added Windows and Linux desktop playback support.
- Added desktop APIs for source, playback controls, seeking, volume, speed, tracks, subtitles, and media info.
- Added CI integration tests across Android, iOS, macOS, Windows, and Linux.

### Fixed

- Improved native player lifecycle handling for desktop texture players.

## 0.0.3 - 2026-05-15

### Fixed

- Fixed the release workflow so pub.dev validation runs before platform builds mutate example lockfiles.

## 0.0.2 - 2026-05-15

### Added

- Added Windows support with bundled VLC runtime download.
- Added example pages for video, HLS, and full-player controls.
- Added GitHub Actions validation and pub.dev publishing workflow.

### Fixed

- Improved player lifecycle handling and event delivery across platforms.

## 0.0.1 - 2026-05-15

### Added

- Initial Android, iOS, and macOS implementation backed by VLC.
