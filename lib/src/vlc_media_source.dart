import 'package:flutter/foundation.dart';

@immutable
class VlcMediaSource {
  VlcMediaSource({
    required this.uri,
    Map<String, String> httpHeaders = const <String, String>{},
    List<String> mediaOptions = const <String>[],
    this.startPosition = Duration.zero,
  }) : httpHeaders = Map<String, String>.unmodifiable(httpHeaders),
       mediaOptions = List<String>.unmodifiable(mediaOptions) {
    if (uri.toString().isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Must be non-empty.');
    }
    if (startPosition.isNegative) {
      throw ArgumentError.value(
        startPosition,
        'startPosition',
        'Must be non-negative.',
      );
    }
  }

  final Uri uri;
  final Map<String, String> httpHeaders;
  final List<String> mediaOptions;
  final Duration startPosition;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VlcMediaSource &&
            other.uri == uri &&
            mapEquals(other.httpHeaders, httpHeaders) &&
            listEquals(other.mediaOptions, mediaOptions) &&
            other.startPosition == startPosition;
  }

  @override
  int get hashCode => Object.hash(
    uri,
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
    return 'VlcMediaSource(uri: $uri, httpHeaders: $httpHeaders, '
        'mediaOptions: $mediaOptions, startPosition: $startPosition)';
  }
}
