# Changelog

## Unreleased

## 0.7.4 - 2026-05-16

### Fixed

- Hardened Dart-side platform event parsing so malformed native payload fields
  are ignored instead of throwing during event handling.

## 0.7.3 - 2026-05-16

### Changed

- Updated GitHub Actions checkout steps to the Node 24 runtime generation to
  remove CI deprecation warnings.
- Updated Java setup and integration-test drive commands for more reliable
  GitHub Actions runs.
- Switched iOS integration CI to direct `flutter test` execution on a clean
  simulator to avoid Flutter Driver launch hangs.

## 0.7.2 - 2026-05-16

### Fixed

- Preserve playlist state when a pending playlist item is replayed during
  platform view or texture attachment.

## 0.7.1 - 2026-05-16

### Fixed

- Report playlist auto-advance loading failures through `VlcPlayerValue.error`
  instead of leaving them as unhandled asynchronous errors.

## 0.7.0 - 2026-05-16

### Added

- Added package topics and third-party notices for VLC, VLCKit, MobileVLCKit,
  and the vendored libvlcpp headers.
- Added release metadata tests that verify pubspec, podspec, README, and
  changelog version alignment.

### Changed

- Updated iOS and macOS podspec metadata to point at the project repository and
  package author.
- Replaced the example README template with plugin-specific run instructions.
- Hardened example integration tests to create native players without loading
  invalid media fixtures and to use VLC's dummy audio output on headless Linux
  CI, with Linux core coverage handled by native ctest.

### Fixed

- Avoided querying native VLC playback state before a media source is attached
  on desktop texture players.

## 0.6.0 - 2026-05-16

### Added

- Added `VlcPlaylistLoopMode` for playlist repeat behavior, including
  `loopOne` and `loopAll` handling for auto advance and manual navigation.

## 0.5.0 - 2026-05-16

### Added

- Added Dart-side playlist support with `setPlaylist()`, `next()`,
  `previous()`, current playlist state, and optional auto advance on ended
  playback.

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
