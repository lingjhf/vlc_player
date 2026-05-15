class VlcTrackDescription {
  const VlcTrackDescription({
    required this.id,
    required this.name,
    this.language,
  });

  factory VlcTrackDescription.fromMap(Map<Object?, Object?> map) {
    return VlcTrackDescription(
      id: (map['id'] as num?)?.toInt() ?? -1,
      name: map['name'] as String? ?? '',
      language: map['language'] as String?,
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
      title: map['title'] as String?,
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      duration: Duration(milliseconds: (map['duration'] as num?)?.toInt() ?? 0),
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
    if (value is! List<Object?>) {
      return const <VlcMediaTrackInfo>[];
    }
    return value
        .whereType<Map<Object?, Object?>>()
        .map(VlcMediaTrackInfo.fromMap)
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
      type: map['type'] as String? ?? 'unknown',
      codec: map['codec'] as String?,
      language: map['language'] as String?,
      bitrate: (map['bitrate'] as num?)?.toInt(),
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      channels: (map['channels'] as num?)?.toInt(),
      sampleRate: (map['sampleRate'] as num?)?.toInt(),
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
