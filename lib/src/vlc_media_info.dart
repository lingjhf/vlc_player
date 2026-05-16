class VlcTrackDescription {
  const VlcTrackDescription({
    required this.id,
    required this.name,
    this.language,
  });

  factory VlcTrackDescription.fromMap(Map<Object?, Object?> map) {
    return VlcTrackDescription(
      id: _intValue(map['id']) ?? -1,
      name: _stringValue(map['name']) ?? '',
      language: _stringValue(map['language']),
    );
  }

  final int id;
  final String name;
  final String? language;

  @override
  bool operator ==(Object other) {
    return other is VlcTrackDescription &&
        other.id == id &&
        other.name == name &&
        other.language == language;
  }

  @override
  int get hashCode => Object.hash(id, name, language);
}

class VlcMediaInfo {
  const VlcMediaInfo({
    this.title,
    this.artist,
    this.album,
    this.duration = Duration.zero,
    this.videoTracks = const <VlcMediaTrackInfo>[],
    this.audioTracks = const <VlcMediaTrackInfo>[],
    this.subtitleTracks = const <VlcMediaTrackInfo>[],
  });

  factory VlcMediaInfo.fromMap(Map<Object?, Object?> map) {
    return VlcMediaInfo(
      title: _stringValue(map['title']),
      artist: _stringValue(map['artist']),
      album: _stringValue(map['album']),
      duration: _durationFromMilliseconds(map['duration']),
      videoTracks: _tracksFrom(map['videoTracks']),
      audioTracks: _tracksFrom(map['audioTracks']),
      subtitleTracks: _tracksFrom(map['subtitleTracks']),
    );
  }

  final String? title;
  final String? artist;
  final String? album;
  final Duration duration;
  final List<VlcMediaTrackInfo> videoTracks;
  final List<VlcMediaTrackInfo> audioTracks;
  final List<VlcMediaTrackInfo> subtitleTracks;

  static List<VlcMediaTrackInfo> _tracksFrom(Object? value) {
    if (value is! Iterable) {
      return const <VlcMediaTrackInfo>[];
    }
    return value
        .whereType<Map>()
        .map(
          (track) => VlcMediaTrackInfo.fromMap(track.cast<Object?, Object?>()),
        )
        .toList(growable: false);
  }
}

class VlcMediaTrackInfo {
  const VlcMediaTrackInfo({
    required this.type,
    this.codec,
    this.language,
    this.bitrate,
    this.width,
    this.height,
    this.channels,
    this.sampleRate,
  });

  factory VlcMediaTrackInfo.fromMap(Map<Object?, Object?> map) {
    return VlcMediaTrackInfo(
      type: _stringValue(map['type']) ?? 'unknown',
      codec: _stringValue(map['codec']),
      language: _stringValue(map['language']),
      bitrate: _intValue(map['bitrate']),
      width: _intValue(map['width']),
      height: _intValue(map['height']),
      channels: _intValue(map['channels']),
      sampleRate: _intValue(map['sampleRate']),
    );
  }

  final String type;
  final String? codec;
  final String? language;
  final int? bitrate;
  final int? width;
  final int? height;
  final int? channels;
  final int? sampleRate;
}

Duration _durationFromMilliseconds(Object? value) {
  final milliseconds = _intValue(value);
  if (milliseconds == null || milliseconds < 0) {
    return Duration.zero;
  }
  return Duration(milliseconds: milliseconds);
}

String? _stringValue(Object? value) => value is String ? value : null;

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    return value.toInt();
  }
  return null;
}
