#if os(iOS)
import Flutter
import MobileVLCKit
import UIKit
#elseif os(macOS)
import Cocoa
import FlutterMacOS
import VLCKit
#endif

public class VlcPlayerPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  private let methodChannel: FlutterMethodChannel
  private var players: [Int64: VlcPlayerPlatformView] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #elseif os(macOS)
    let messenger = registrar.messenger
    #endif
    let instance = VlcPlayerPlugin(binaryMessenger: messenger)
    let factory = VlcPlayerViewFactory(messenger: messenger) { [weak instance] viewId, player in
      instance?.players.removeValue(forKey: viewId)?.dispose()
      instance?.players[viewId] = player
    }

    registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)
    registrar.register(factory, withId: "plugins.lingjhf.com/vlc_player/view")
  }

  init(binaryMessenger: FlutterBinaryMessenger) {
    messenger = binaryMessenger
    methodChannel = FlutterMethodChannel(name: "vlc_player", binaryMessenger: binaryMessenger)
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let viewId = Self.int64Value(arguments["viewId"]) else {
      result(FlutterError(code: "invalid_args", message: "A valid viewId is required.", details: nil))
      return
    }

    if call.method == "dispose" {
      disposePlayer(viewId: viewId, result: result)
      return
    }

    guard let player = players[viewId] else {
      result(FlutterError(code: "player_not_found", message: "No vlc_player player exists for viewId \(viewId).", details: nil))
      return
    }

    DispatchQueue.main.async { [player] in
      player.whenSourceReady { [weak player] in
        guard let player else {
          result(Self.disposedError())
          return
        }
        self.handle(call.method, arguments: arguments, player: player, result: result)
      }
    }
  }

  private func handle(
    _ method: String,
    arguments: [String: Any],
    player: VlcPlayerPlatformView,
    result: @escaping FlutterResult
  ) {
    guard !player.isDisposed else {
      result(Self.disposedError())
      return
    }

    switch method {
    case "setSource":
      guard let uri = arguments["uri"] as? String, !uri.isEmpty else {
        result(FlutterError(code: "invalid_args", message: "A non-empty uri is required.", details: nil))
        return
      }
      let autoPlay = arguments["autoPlay"] as? Bool ?? false
      let httpHeaders = arguments["httpHeaders"] as? [String: String] ?? [:]
      let mediaOptions = arguments["mediaOptions"] as? [String] ?? []
      let startPosition = Self.intValue(arguments["startPosition"]) ?? 0
      guard startPosition >= 0 else {
        result(FlutterError(code: "invalid_args", message: "A non-negative startPosition is required.", details: nil))
        return
      }
      player.setSource(
        uri,
        httpHeaders: httpHeaders,
        mediaOptions: mediaOptions,
        startPosition: startPosition,
        autoPlay: autoPlay,
        result: result
      )
    case "play":
      player.play()
      result(nil)
    case "pause":
      player.pause()
      result(nil)
    case "stop":
      player.stop()
      result(nil)
    case "seekTo":
      guard let position = Self.intValue(arguments["position"]), position >= 0 else {
        result(FlutterError(code: "invalid_args", message: "A non-negative position is required.", details: nil))
        return
      }
      player.seekTo(milliseconds: position)
      result(nil)
    case "setVolume":
      guard let volume = Self.intValue(arguments["volume"]) else {
        result(FlutterError(code: "invalid_args", message: "A volume value is required.", details: nil))
        return
      }
      player.setVolume(volume)
      result(nil)
    case "setPlaybackSpeed":
      guard let speed = Self.doubleValue(arguments["speed"]), speed.isFinite && speed > 0 else {
        result(FlutterError(code: "invalid_args", message: "A finite positive playback speed is required.", details: nil))
        return
      }
      player.setPlaybackSpeed(speed)
      result(nil)
    case "setAudioDelay":
      guard let delay = Self.intValue(arguments["delay"]) else {
        result(FlutterError(code: "invalid_args", message: "An audio delay value is required.", details: nil))
        return
      }
      player.setAudioDelay(delay)
      result(nil)
    case "setSubtitleDelay":
      guard let delay = Self.intValue(arguments["delay"]) else {
        result(FlutterError(code: "invalid_args", message: "A subtitle delay value is required.", details: nil))
        return
      }
      player.setSubtitleDelay(delay)
      result(nil)
    case "takeSnapshot":
      let rawWidth = Self.intValue(arguments["width"])
      let rawHeight = Self.intValue(arguments["height"])
      if let rawWidth = rawWidth, rawWidth <= 0 {
        result(FlutterError(code: "invalid_args", message: "Snapshot dimensions must be positive.", details: nil))
        return
      }
      if let rawHeight = rawHeight, rawHeight <= 0 {
        result(FlutterError(code: "invalid_args", message: "Snapshot dimensions must be positive.", details: nil))
        return
      }
      let width = rawWidth ?? 0
      let height = rawHeight ?? 0
      player.takeSnapshot(width: width, height: height, result: result)
    case "getAudioTracks":
      result(player.getAudioTracks())
    case "setAudioTrack":
      guard let id = Self.intValue(arguments["id"]), id >= 0 else {
        result(FlutterError(code: "invalid_args", message: "A non-negative audio track id is required.", details: nil))
        return
      }
      guard player.setAudioTrack(id) else {
        result(FlutterError(code: "track_not_found", message: "Audio track \(id) was not found.", details: nil))
        return
      }
      result(nil)
    case "getSubtitleTracks":
      result(player.getSubtitleTracks())
    case "setSubtitleTrack":
      guard let id = Self.intValue(arguments["id"]), id >= 0 else {
        result(FlutterError(code: "invalid_args", message: "A non-negative subtitle track id is required.", details: nil))
        return
      }
      guard player.setSubtitleTrack(id) else {
        result(FlutterError(code: "track_not_found", message: "Subtitle track \(id) was not found.", details: nil))
        return
      }
      result(nil)
    case "disableSubtitle":
      player.disableSubtitle()
      result(nil)
    case "addSubtitle":
      guard let uri = arguments["uri"] as? String, !uri.isEmpty else {
        result(FlutterError(code: "invalid_args", message: "A non-empty subtitle uri is required.", details: nil))
        return
      }
      player.addSubtitle(uri, result: result)
    case "getMediaInfo":
      result(player.getMediaInfo())
    case "getMediaStats":
      result(player.getMediaStats())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func disposePlayer(viewId: Int64, result: FlutterResult? = nil) {
    let dispose = {
      self.players.removeValue(forKey: viewId)?.dispose()
      result?(nil)
    }
    if Thread.isMainThread {
      dispose()
    } else {
      DispatchQueue.main.async(execute: dispose)
    }
  }

  private static func disposedError() -> FlutterError {
    return FlutterError(code: "disposed", message: "The vlc_player has been disposed.", details: nil)
  }

  private static func int64Value(_ value: Any?) -> Int64? {
    if let number = value as? NSNumber {
      return number.int64Value
    }
    return value as? Int64
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let number = value as? NSNumber {
      return number.intValue
    }
    return value as? Int
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    return value as? Double
  }
}

final class VlcPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private let onCreate: (Int64, VlcPlayerPlatformView) -> Void

  init(
    messenger: FlutterBinaryMessenger,
    onCreate: @escaping (Int64, VlcPlayerPlatformView) -> Void
  ) {
    self.messenger = messenger
    self.onCreate = onCreate
    super.init()
  }

  #if os(iOS)
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return createPlayer(frame: frame, viewId: viewId, arguments: args)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
  #elseif os(macOS)
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    return createPlayer(frame: .zero, viewId: viewId, arguments: args).nativeView
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    return FlutterStandardMessageCodec.sharedInstance()
  }
  #endif

  private func createPlayer(frame: CGRect, viewId: Int64, arguments args: Any?) -> VlcPlayerPlatformView {
    let arguments = args as? [String: Any]
    let player = VlcPlayerPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      options: arguments?["options"] as? [String] ?? [],
      fit: arguments?["fit"] as? String ?? "contain"
    )
    onCreate(viewId, player)
    return player
  }
}

final class VlcPlayerPlatformView: NSObject, VLCMediaPlayerDelegate, VLCMediaDelegate {
  private struct SourcePreparation {
    let media: VLCMedia
    let complete: (Bool) -> Void
    var deferredCalls: [() -> Void] = []
  }

  private static let shortVideoContainers: Set<String> = ["mov", "mp4", "m4v", "mkv", "webm"]
  private static let decoderThreadOptions: Set<String> = ["avcodec-threads"]
  private static let hardwareDecoderOptions: Set<String> = ["avcodec-hw", "videotoolbox", "no-videotoolbox", "codec"]
  private static let avformatCodecs: [String: UInt32] = [
    "avi": 0x41524c55, // Ut Video ('ULRA')
    "mov": 0x3176326d, // MPEG-2 with the 'm2v1' sample entry
  ]

  let nativeView: VlcPlayerContainerView

  private let mediaPlayer: VLCMediaPlayer
  private let pausesAtEnd: Bool
  private let playerOptions: [String]
  private let eventChannel: FlutterEventChannel
  private var sourcePreparation: SourcePreparation?
  private let eventHandler = VlcPlayerEventStreamHandler()
  private var lastSentEvent: NSDictionary?
  private(set) var isDisposed = false

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    options: [String],
    fit: String
  ) {
    #if os(iOS)
    nativeView = VlcPlayerContainerView(frame: frame)
    #elseif os(macOS)
    nativeView = VlcPlayerContainerView()
    #endif
    mediaPlayer = VLCMediaPlayer(options: options)
    pausesAtEnd = options.contains("--play-and-pause")
    playerOptions = options
    eventChannel = FlutterEventChannel(name: "vlc_player/events/\(viewId)", binaryMessenger: messenger)
    super.init()

    nativeView.applyFit(fit)
    mediaPlayer.drawable = nativeView
    mediaPlayer.delegate = self
    eventHandler.onListen = { [weak self] in
      self?.sendSnapshot(force: true)
    }
    eventChannel.setStreamHandler(eventHandler)
    sendSnapshot()
  }

  func setSource(
    _ uri: String,
    httpHeaders: [String: String],
    mediaOptions: [String],
    startPosition: Int,
    autoPlay: Bool,
    result: @escaping FlutterResult
  ) {
    guard let url = URL(string: uri) else {
      result(FlutterError(code: "invalid_uri", message: "The provided uri is invalid.", details: uri))
      return
    }

    let media = VLCMedia(url: url)
    // VLCKit defaults to pausing at EOF on macOS. Playlists need an ended event.
    if !pausesAtEnd {
      media.addOption(":no-play-and-pause")
    }
    for (name, value) in httpHeaders where Self.isValidHeader(name: name, value: value) {
      media.addOption(":http-header=\(name): \(value)")
    }
    for option in mediaOptions {
      media.addOption(option)
    }
    if startPosition > 0 {
      media.addOption(":start-time=\(Double(startPosition) / 1000.0)")
    }

    let options = playerOptions + mediaOptions
    #if os(macOS)
    // VLCKit 3.7.3 can retain all frames of a short clip with frame threading.
    let tuneThreads = !Self.hasOption(Self.decoderThreadOptions, in: options)
    #else
    let tuneThreads = false
    #endif
    #if os(iOS) && !targetEnvironment(simulator)
    let tuneHardware = !Self.hasOption(Self.hardwareDecoderOptions, in: options)
    #else
    let tuneHardware = false
    #endif
    let fileExtension = url.pathExtension.lowercased()
    let tuneDemux = !Self.hasOption(["demux"], in: options)
    let avformatCodec = tuneDemux ? Self.avformatCodecs[fileExtension] : nil
    if tuneDemux, fileExtension == "vc1", url.isFileURL,
       (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
       Self.hasVC1SequenceHeader(in: url) {
      // Autodetection can select the MPEG video demuxer for raw VC-1.
      media.addOption(":demux=vc1")
    }
    let tuneShortVideo = (tuneThreads || tuneHardware) && Self.shortVideoContainers.contains(fileExtension)
    let canParseContainer = avformatCodec != nil || tuneShortVideo
    let isElementaryHEVC = tuneHardware && (fileExtension == "hevc" || fileExtension == "h265")
    if url.isFileURL, canParseContainer || isElementaryHEVC,
       let properties = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
       properties.isRegularFile == true, let size = properties.fileSize {
      if isElementaryHEVC, size <= 32 * 1024 {
        // Tiny elementary HEVC streams have no container duration to parse.
        Self.useSoftwareVideo(on: media)
      } else if canParseContainer, size <= 4 * 1024 * 1024 {
        prepareSource(media) { [weak self] parsed in
          guard let self, !self.isDisposed else {
            result(FlutterError(code: "disposed", message: "The vlc_player has been disposed.", details: nil))
            return
          }
          if parsed {
            if let avformatCodec,
               (Self.firstVideoTrack(in: media)?[VLCMediaTracksInformationCodec] as? NSNumber)?.uint32Value == avformatCodec {
              media.addOption(":demux=avformat")
            }
            if tuneShortVideo {
              Self.configureShortVideo(media, tuneThreads: tuneThreads, tuneHardware: tuneHardware)
            }
          }
          self.startSource(media, autoPlay: autoPlay, result: result)
        }
        return
      }
    }
    startSource(media, autoPlay: autoPlay, result: result)
  }

  func whenSourceReady(_ call: @escaping () -> Void) {
    if sourcePreparation != nil {
      sourcePreparation?.deferredCalls.append(call)
    } else {
      call()
    }
  }

  private func prepareSource(_ media: VLCMedia, complete: @escaping (Bool) -> Void) {
    sourcePreparation = SourcePreparation(media: media, complete: complete)
    media.delegate = self
    // Parse local metadata only and bound the delay before handing the source to VLC.
    if media.parse(options: [], timeout: 200) != 0 {
      finishSourcePreparation(media, parsed: false)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self, weak media] in
      if let media {
        self?.finishSourcePreparation(media, parsed: false)
      }
    }
  }

  func mediaDidFinishParsing(_ media: VLCMedia) {
    DispatchQueue.main.async { [weak self] in
      self?.finishSourcePreparation(media, parsed: media.parsedStatus == .done)
    }
  }

  private func finishSourcePreparation(_ media: VLCMedia, parsed: Bool) {
    guard let preparation = sourcePreparation, preparation.media === media else { return }
    sourcePreparation = nil
    media.delegate = nil
    if !parsed {
      media.parseStop()
    }
    preparation.complete(parsed)
    for call in preparation.deferredCalls {
      whenSourceReady(call)
    }
  }

  private static func configureShortVideo(_ media: VLCMedia, tuneThreads: Bool, tuneHardware: Bool) {
    let duration = Self.milliseconds(from: media.length)
    guard duration > 0, duration <= 500,
          let videoTrack = Self.firstVideoTrack(in: media) else { return }

    // Frame-threaded decoding can retain every displayable frame of a short clip until EOF.
    if tuneThreads {
      media.addOption(":avcodec-threads=1")
    }
    if tuneHardware, (videoTrack[VLCMediaTracksInformationCodec] as? NSNumber)?.uint32Value == 0x63766568 {
      // HEVC ('hevc') can finish before VideoToolbox presents its first picture.
      useSoftwareVideo(on: media)
    }
  }

  private static func firstVideoTrack(in media: VLCMedia) -> [String: Any]? {
    let tracks = media.tracksInformation as? [[String: Any]]
    return tracks?.first { Self.trackType($0[VLCMediaTracksInformationType]) == "video" }
  }

  private static func hasVC1SequenceHeader(in url: URL) -> Bool {
    guard let file = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? file.close() }
    return (try? file.read(upToCount: 4)) == Data([0x00, 0x00, 0x01, 0x0f])
  }

  private static func useSoftwareVideo(on media: VLCMedia) {
    media.addOption(":no-videotoolbox")
    media.addOption(":avcodec-hw=none")
  }

  private static func hasOption(_ names: Set<String>, in options: [String]) -> Bool {
    let prefixes = CharacterSet(charactersIn: ":-")
    return options.contains { option in
      let name = option.prefix(while: { $0 != "=" }).trimmingCharacters(in: prefixes)
      return names.contains(name)
    }
  }

  private func startSource(_ media: VLCMedia, autoPlay: Bool, result: FlutterResult) {
    mediaPlayer.media = media
    sendSnapshot(force: true, stateOverride: "opening")
    if autoPlay {
      mediaPlayer.play()
    }
    result(nil)
  }

  func play() {
    mediaPlayer.play()
    sendSnapshot()
  }

  func pause() {
    mediaPlayer.pause()
    sendSnapshot()
  }

  func stop() {
    mediaPlayer.stop()
    sendSnapshot(stateOverride: "stopped")
  }

  func seekTo(milliseconds: Int) {
    mediaPlayer.time = VLCTime(number: NSNumber(value: milliseconds))
    sendSnapshot()
  }

  func setVolume(_ volume: Int) {
    mediaPlayer.audio?.volume = Int32(max(0, min(200, volume)))
    sendSnapshot()
  }

  func setPlaybackSpeed(_ speed: Double) {
    mediaPlayer.rate = Float(speed)
    sendSnapshot()
  }

  func setAudioDelay(_ microseconds: Int) {
    mediaPlayer.currentAudioPlaybackDelay = microseconds
    sendSnapshot()
  }

  func setSubtitleDelay(_ microseconds: Int) {
    mediaPlayer.currentVideoSubTitleDelay = microseconds
    sendSnapshot()
  }

  func takeSnapshot(width: Int, height: Int, result: @escaping FlutterResult) {
    guard mediaPlayer.media != nil else {
      result(FlutterError(code: "snapshot_failed", message: "No media is loaded.", details: nil))
      return
    }
    guard mediaPlayer.hasVideoOut else {
      result(FlutterError(code: "snapshot_failed", message: "No video output is available.", details: nil))
      return
    }

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "vlc_player_snapshot_\(UUID().uuidString).png"
    )
    try? FileManager.default.removeItem(at: url)
    mediaPlayer.saveVideoSnapshot(at: url.path, withWidth: Int32(width), andHeight: Int32(height))

    DispatchQueue.global(qos: .userInitiated).async {
      for _ in 0..<40 {
        if let data = try? Data(contentsOf: url), !data.isEmpty {
          try? FileManager.default.removeItem(at: url)
          DispatchQueue.main.async {
            result(FlutterStandardTypedData(bytes: data))
          }
          return
        }
        Thread.sleep(forTimeInterval: 0.05)
      }

      try? FileManager.default.removeItem(at: url)
      DispatchQueue.main.async {
        result(FlutterError(code: "snapshot_failed", message: "VLC did not produce snapshot image data.", details: nil))
      }
    }
  }

  func getAudioTracks() -> [[String: Any?]] {
    return trackDescriptions(indexes: mediaPlayer.audioTrackIndexes, names: mediaPlayer.audioTrackNames)
  }

  func setAudioTrack(_ id: Int) -> Bool {
    guard trackIndexes(mediaPlayer.audioTrackIndexes).contains(id) else {
      return false
    }
    mediaPlayer.currentAudioTrackIndex = Int32(id)
    return true
  }

  func getSubtitleTracks() -> [[String: Any?]] {
    return trackDescriptions(indexes: mediaPlayer.videoSubTitlesIndexes, names: mediaPlayer.videoSubTitlesNames)
  }

  func setSubtitleTrack(_ id: Int) -> Bool {
    guard trackIndexes(mediaPlayer.videoSubTitlesIndexes).contains(id) else {
      return false
    }
    mediaPlayer.currentVideoSubTitleIndex = Int32(id)
    return true
  }

  func disableSubtitle() {
    mediaPlayer.currentVideoSubTitleIndex = -1
  }

  func addSubtitle(_ uri: String, result: @escaping FlutterResult) {
    guard let url = URL(string: uri) else {
      result(FlutterError(code: "invalid_uri", message: "The provided subtitle uri is invalid.", details: uri))
      return
    }
    let status = mediaPlayer.addPlaybackSlave(url, type: .subtitle, enforce: true)
    if status != 0 {
      result(FlutterError(code: "add_subtitle_failed", message: "Failed to add subtitle: \(uri)", details: status))
      return
    }
    result(nil)
  }

  func getMediaInfo() -> [String: Any?] {
    let media = mediaPlayer.media
    return [
      "title": media?.metaData.title,
      "artist": media?.metaData.artist,
      "album": media?.metaData.album,
      "duration": Self.milliseconds(from: media?.length),
      "videoTracks": mediaTracks(media, matching: "video"),
      "audioTracks": mediaTracks(media, matching: "audio"),
      "subtitleTracks": mediaTracks(media, matching: "subtitle"),
    ]
  }

  func getMediaStats() -> [String: Any] {
    guard let media = mediaPlayer.media else {
      return Self.emptyMediaStats()
    }

    let stats = media.statistics
    return [
      "available": true,
      "readBytes": Int(stats.readBytes),
      "inputBitrate": Double(stats.inputBitrate),
      "demuxReadBytes": Int(stats.demuxReadBytes),
      "demuxBitrate": Double(stats.demuxBitrate),
      "demuxCorrupted": Int(stats.demuxCorrupted),
      "demuxDiscontinuity": Int(stats.demuxDiscontinuity),
      "decodedVideo": Int(stats.decodedVideo),
      "decodedAudio": Int(stats.decodedAudio),
      "displayedPictures": Int(stats.displayedPictures),
      "lostPictures": Int(stats.lostPictures),
      "playedAudioBuffers": Int(stats.playedAudioBuffers),
      "lostAudioBuffers": Int(stats.lostAudioBuffers),
      "sentPackets": Int(stats.sentPackets),
      "sentBytes": Int(stats.sentBytes),
      "sendBitrate": Double(stats.sendBitrate),
    ]
  }

  func dispose() {
    guard !isDisposed else {
      return
    }
    isDisposed = true
    if let sourcePreparation {
      finishSourcePreparation(sourcePreparation.media, parsed: false)
    }
    eventChannel.setStreamHandler(nil)
    mediaPlayer.delegate = nil
    mediaPlayer.stop()
    mediaPlayer.drawable = nil
  }

  func mediaPlayerStateChanged(_ aNotification: Notification) {
    if mediaPlayer.state == .error {
      sendSnapshot(
        errorCode: "playback_error",
        errorDescription: "VLC encountered an error while playing the media."
      )
      return
    }
    sendSnapshot()
  }

  func mediaPlayerTimeChanged(_ aNotification: Notification) {
    sendSnapshot()
  }

  private func sendSnapshot(
    force: Bool = false,
    stateOverride: String? = nil,
    errorCode: String? = nil,
    errorDescription: String? = nil
  ) {
    guard !isDisposed, sourcePreparation == nil else {
      return
    }
    guard eventHandler.isListening else {
      return
    }

    let state = mediaPlayer.state
    // VLCKit caches buffering and track events even after libVLC starts playback.
    let isPlaying = (state == .buffering || state == .esAdded) && mediaPlayer.isPlaying
    let stateName = stateOverride ?? (isPlaying ? "playing" : Self.stateName(state))
    let duration = Self.milliseconds(from: mediaPlayer.media?.length)
    let isSeekable = mediaPlayer.isSeekable
    var event: [String: Any] = [
      "state": stateName,
      "position": Self.milliseconds(from: mediaPlayer.time),
      "duration": duration,
      "volume": Int(mediaPlayer.audio?.volume ?? 0),
      "playbackSpeed": Double(mediaPlayer.rate),
      "audioDelay": Int(mediaPlayer.currentAudioPlaybackDelay),
      "subtitleDelay": Int(mediaPlayer.currentVideoSubTitleDelay),
      "isReady": Self.isReadyState(stateName),
      "isSeekable": isSeekable,
      "isLive": Self.isLiveState(stateName) && duration == 0 && !isSeekable,
    ]
    if let videoSize = Self.videoSizeMap(mediaPlayer.videoSize) {
      event["videoSize"] = videoSize
    }
    if let errorDescription {
      event["errorCode"] = errorCode ?? "playback_error"
      event["errorDescription"] = errorDescription
    }
    let snapshot = NSDictionary(dictionary: event)
    if !force, let lastSentEvent = lastSentEvent, lastSentEvent.isEqual(snapshot) {
      return
    }
    lastSentEvent = snapshot
    eventHandler.send(event)
  }

  private static func milliseconds(from time: VLCTime?) -> Int {
    guard let time else {
      return 0
    }
    return max(0, Int(time.intValue))
  }

  private static func videoSizeMap(_ size: CGSize) -> [String: Int]? {
    let width = Int(size.width)
    let height = Int(size.height)
    guard width > 0 && height > 0 else {
      return nil
    }
    return ["width": width, "height": height]
  }

  private static func emptyMediaStats() -> [String: Any] {
    return [
      "available": false,
      "readBytes": 0,
      "inputBitrate": 0.0,
      "demuxReadBytes": 0,
      "demuxBitrate": 0.0,
      "demuxCorrupted": 0,
      "demuxDiscontinuity": 0,
      "decodedVideo": 0,
      "decodedAudio": 0,
      "displayedPictures": 0,
      "lostPictures": 0,
      "playedAudioBuffers": 0,
      "lostAudioBuffers": 0,
      "sentPackets": 0,
      "sentBytes": 0,
      "sendBitrate": 0.0,
    ]
  }

  private func trackDescriptions(indexes: [Any]?, names: [Any]?) -> [[String: Any?]] {
    let trackIndexes = indexes as? [NSNumber] ?? []
    let trackNames = names as? [String] ?? []
    return trackIndexes.enumerated().map { offset, index in
      [
        "id": index.intValue,
        "name": offset < trackNames.count ? trackNames[offset] : "",
        "language": nil,
      ]
    }
  }

  private func trackIndexes(_ indexes: [Any]?) -> Set<Int> {
    return Set((indexes as? [NSNumber] ?? []).map(\.intValue))
  }

  private func mediaTracks(_ media: VLCMedia?, matching type: String) -> [[String: Any?]] {
    guard let tracks = media?.tracksInformation as? [[String: Any]] else {
      return []
    }

    return tracks.compactMap { track in
      guard Self.trackType(track[VLCMediaTracksInformationType]) == type else {
        return nil
      }
      var info: [String: Any?] = [
        "type": type,
        "codec": track[VLCMediaTracksInformationCodec],
        "language": track[VLCMediaTracksInformationLanguage],
        "bitrate": track[VLCMediaTracksInformationBitrate],
      ]
      if type == "video" {
        info["width"] = track[VLCMediaTracksInformationVideoWidth]
        info["height"] = track[VLCMediaTracksInformationVideoHeight]
      }
      if type == "audio" {
        info["channels"] = track[VLCMediaTracksInformationAudioChannelsNumber]
        info["sampleRate"] = track[VLCMediaTracksInformationAudioRate]
      }
      return info
    }
  }

  private static func trackType(_ value: Any?) -> String {
    let raw = String(describing: value ?? "").lowercased()
    if raw.contains("video") {
      return "video"
    }
    if raw.contains("audio") {
      return "audio"
    }
    if raw.contains("text") || raw.contains("subtitle") {
      return "subtitle"
    }
    return "unknown"
  }

  private static func stateName(_ state: VLCMediaPlayerState) -> String {
    switch state {
    case .opening:
      return "opening"
    case .buffering:
      return "buffering"
    case .playing:
      return "playing"
    case .paused:
      return "paused"
    case .stopped:
      return "stopped"
    case .ended:
      return "ended"
    case .error:
      return "error"
    default:
      return "idle"
    }
  }

  private static func isReadyState(_ state: String) -> Bool {
    return state == "playing" ||
      state == "paused" ||
      state == "stopped" ||
      state == "ended"
  }

  private static func isLiveState(_ state: String) -> Bool {
    return state == "buffering" ||
      state == "playing" ||
      state == "paused"
  }

  private static func isValidHeader(name: String, value: String) -> Bool {
    return !name.isEmpty &&
      !name.contains("\r") &&
      !name.contains("\n") &&
      !value.contains("\r") &&
      !value.contains("\n")
  }
}

#if os(iOS)
extension VlcPlayerPlatformView: FlutterPlatformView {
  func view() -> UIView {
    return nativeView
  }
}

final class VlcPlayerContainerView: UIView {
  func applyFit(_ fit: String) {
    backgroundColor = .black
    clipsToBounds = true
    switch fit {
    case "cover":
      contentMode = .scaleAspectFill
    case "fill":
      contentMode = .scaleToFill
    case "none":
      contentMode = .center
    default:
      contentMode = .scaleAspectFit
    }
  }
}
#elseif os(macOS)
final class VlcPlayerContainerView: VLCVideoView {
  func applyFit(_ fit: String) {
    fillScreen = fit == "cover" || fit == "fill"
  }
}
#endif

final class VlcPlayerEventStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  var onListen: (() -> Void)?
  var isListening: Bool {
    return eventSink != nil
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    onListen?()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func send(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }
}
