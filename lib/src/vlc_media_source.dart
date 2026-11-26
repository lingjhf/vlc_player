import 'package:flutter/foundation.dart';

/// Describes one media item before it is loaded into VLC.
///
/// Use this instead of a bare [Uri] when the item needs request headers, VLC
/// media options, or an initial seek position. Supported URI schemes and
/// container/codec combinations are ultimately determined by the native VLC
/// build used on the target platform.
@immutable
class VlcMediaSource {
  /// Creates a media source for [uri].
  ///
  /// [uri] must be non-empty. [httpHeaders] are sent when VLC opens HTTP(S)
  /// media. [mediaOptions] are passed to VLC for this source only; use VLC
  /// option syntax such as `:network-caching=1200`. [startPosition] must be
  /// non-negative and is applied after the source is loaded when the platform
  /// backend supports seeking.
  VlcMediaSource({
    required Uri uri,
    Map<String, String> httpHeaders = const <String, String>{},
    List<String> mediaOptions = const <String>[],
    Duration startPosition = Duration.zero,
  }) : this._(
         uri: uri,
         location: uri.toString(),
         httpHeaders: httpHeaders,
         mediaOptions: mediaOptions,
         startPosition: startPosition,
       );

  /// Creates a source from an exact VLC media location.
  ///
  /// Use this for VLC locations whose syntax Dart's [Uri] normalizes, such as
  /// `udp://@127.0.0.1:12345`. [location] is passed to the platform backend
  /// unchanged; [uri] is its parsed representation and may serialize
  /// differently. Platform backends may apply their own URL parsing. The
  /// other arguments have the same meaning as the default constructor.
  VlcMediaSource.location({
    required String location,
    Map<String, String> httpHeaders = const <String, String>{},
    List<String> mediaOptions = const <String>[],
    Duration startPosition = Duration.zero,
  }) : this._(
         uri: Uri.parse(location),
         location: location,
         httpHeaders: httpHeaders,
         mediaOptions: mediaOptions,
         startPosition: startPosition,
       );

  VlcMediaSource._({
    required this.uri,
    required this.location,
    required Map<String, String> httpHeaders,
    required List<String> mediaOptions,
    required this.startPosition,
  }) : httpHeaders = Map<String, String>.unmodifiable(httpHeaders),
       mediaOptions = List<String>.unmodifiable(mediaOptions) {
    if (location.isEmpty) {
      throw ArgumentError.value(location, 'location', 'Must be non-empty.');
    }
    if (startPosition.isNegative) {
      throw ArgumentError.value(
        startPosition,
        'startPosition',
        'Must be non-negative.',
      );
    }
  }

  /// Parsed representation of the media location.
  final Uri uri;

  /// Exact media location sent to the platform backend.
  final String location;

  /// HTTP headers used when opening [uri].
  final Map<String, String> httpHeaders;

  /// VLC media options applied only to this source.
  final List<String> mediaOptions;

  /// Initial playback position requested after loading this source.
  final Duration startPosition;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VlcMediaSource &&
            other.location == location &&
            mapEquals(other.httpHeaders, httpHeaders) &&
            listEquals(other.mediaOptions, mediaOptions) &&
            other.startPosition == startPosition;
  }

  @override
  int get hashCode => Object.hash(
    location,
    Object.hashAll(_sortedHeaderHashes),
    Object.hashAll(mediaOptions),
    startPosition,
  );

  Iterable<int> get _sortedHeaderHashes {
    final keys = httpHeaders.keys.toList()..sort();
    return keys.map((key) => Object.hash(key, httpHeaders[key]));
  }

  @override
  String toString() {
    return 'VlcMediaSource(uri: $location, httpHeaders: $httpHeaders, '
        'mediaOptions: $mediaOptions, startPosition: $startPosition)';
  }
}
