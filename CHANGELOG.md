# Changelog

## Unreleased

## 0.4.0 - 2026-05-16

### Added

- Added `VlcMediaSource` and `VlcPlayerController.setMedia()` for loading media
  with HTTP headers, VLC media options, and an initial start position.

### Changed

- Kept `setSource()` as the simple URI API and route it through the richer
  media source flow.

## 0.3.0 - 2026-05-16

### Added

- Added `VlcPlayerError`, `VlcPlayerException`, and structured
  `VlcPlayerValue.error` playback errors.
- Normalized native platform error codes for Dart-facing command failures and
  playback error events.

## 0.2.0 - 2026-05-16

### Added

- Added readiness, seekability, live stream detection, decoded video size, and
  buffering progress fields to `VlcPlayerValue`.
- Surfaced the new playback status fields from Android, iOS, macOS, Windows,
  and Linux native players.

### Changed

- Updated the full player example to show loading state and disable seeking for
  non-seekable or live streams.

## 0.1.0 - 2026-05-16

### Changed

- Hardened controller and native player lifecycle handling when widgets are
  detached, replaced, or disposed during async attachment.
- Strengthened release and CI validation so Android, iOS, macOS, Windows, and
  Linux run real plugin integration tests.

### Fixed

- Rejected empty media URIs and non-finite playback speeds before they reach
  native VLC code.
- Returned `track_not_found` errors for missing iOS and macOS audio/subtitle
  track ids.

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
