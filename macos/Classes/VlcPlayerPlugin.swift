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
      guard let speed = Self.doubleValue(arguments["speed"]), speed > 0 else {
        result(FlutterError(code: "invalid_args", message: "A positive playback speed is required.", details: nil))
        return
      }
      player.setPlaybackSpeed(speed)
      result(nil)
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
      sendSnapshot(errorDescription: "VLC encountered an error while playing the media.")
      return
    }
    sendSnapshot()
  }

  func mediaPlayerTimeChanged(_ aNotification: Notification) {
    sendSnapshot()
  }

  private func sendSnapshot(stateOverride: String? = nil, errorDescription: String? = nil) {
    guard !isDisposed else {
      return
    }

    var event: [String: Any] = [
      "state": stateOverride ?? Self.stateName(mediaPlayer.state),
      "position": Self.milliseconds(from: mediaPlayer.time),
      "duration": Self.milliseconds(from: mediaPlayer.media?.length),
      "volume": Int(mediaPlayer.audio?.volume ?? 0),
      "playbackSpeed": Double(mediaPlayer.rate),
    ]
    if let errorDescription {
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
