import Cocoa
import FlutterMacOS
import VLCKit

public class VlcPlayerPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  private let methodChannel: FlutterMethodChannel
  private var players: [Int64: VlcPlayerPlatformView] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VlcPlayerPlugin(binaryMessenger: registrar.messenger)
    let factory = VlcPlayerViewFactory(messenger: registrar.messenger) { [weak instance] viewId, player in
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

    DispatchQueue.main.async {
      self.handle(call.method, arguments: arguments, player: player, result: result)
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
      player.setSource(uri, httpHeaders: httpHeaders, autoPlay: autoPlay, result: result)
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

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let options = (args as? [String: Any])?["options"] as? [String] ?? []
    let platformView = VlcPlayerPlatformView(
      viewId: viewId,
      messenger: messenger,
      options: options
    )
    onCreate(viewId, platformView)
    return platformView.view
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

final class VlcPlayerPlatformView: NSObject, VLCMediaPlayerDelegate {
  let view: VlcPlayerContainerView

  private let mediaPlayer: VLCMediaPlayer
  private let eventChannel: FlutterEventChannel
  private let eventHandler = VlcPlayerEventStreamHandler()
  private(set) var isDisposed = false

  init(
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    options: [String]
  ) {
    view = VlcPlayerContainerView()
    mediaPlayer = VLCMediaPlayer(options: options)
    eventChannel = FlutterEventChannel(name: "vlc_player/events/\(viewId)", binaryMessenger: messenger)
    super.init()

    view.fillScreen = false
    mediaPlayer.drawable = view
    mediaPlayer.delegate = self
    eventChannel.setStreamHandler(eventHandler)
    sendSnapshot()
  }

  func setSource(_ uri: String, httpHeaders: [String: String], autoPlay: Bool, result: @escaping FlutterResult) {
    guard let url = URL(string: uri) else {
      result(FlutterError(code: "invalid_uri", message: "The provided uri is invalid.", details: uri))
      return
    }

    let media = VLCMedia(url: url)
    for (name, value) in httpHeaders where Self.isValidHeader(name: name, value: value) {
      media.addOption(":http-header=\(name): \(value)")
    }
    mediaPlayer.media = media
    sendSnapshot(stateOverride: "opening")
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

  func dispose() {
    guard !isDisposed else {
      return
    }
    isDisposed = true
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
    stateOverride: String? = nil,
    errorCode: String? = nil,
    errorDescription: String? = nil
  ) {
    guard !isDisposed else {
      return
    }

    let stateName = stateOverride ?? Self.stateName(mediaPlayer.state)
    let duration = Self.milliseconds(from: mediaPlayer.media?.length)
    let isSeekable = mediaPlayer.isSeekable
    var event: [String: Any] = [
      "state": stateName,
      "position": Self.milliseconds(from: mediaPlayer.time),
      "duration": duration,
      "volume": Int(mediaPlayer.audio?.volume ?? 0),
      "playbackSpeed": Double(mediaPlayer.rate),
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

final class VlcPlayerContainerView: VLCVideoView {}

final class VlcPlayerEventStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
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
