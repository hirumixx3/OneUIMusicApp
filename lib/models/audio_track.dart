import 'dart:convert';
import 'dart:typed_data';

class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.uri,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.path,
    required this.mimeType,
    required this.dateAdded,
    required this.dateModified,
    this.albumId,
    this.albumArtist,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.composer,
    this.author,
    this.writer,
    this.bitrate,
    this.lyrics,
    this.artworkBase64,
    this.artworkUrl,
    this.isRemote = false,
    this.remoteStreamUri,
    this.videoId,
    this.artistId,
    this.browseId,
  });

  final String id;
  final String uri;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String path;
  final String mimeType;
  final int dateAdded;
  final int dateModified;
  final String? albumId;
  final String? albumArtist;
  final String? genre;
  final String? year;
  final String? trackNumber;
  final String? discNumber;
  final String? composer;
  final String? author;
  final String? writer;
  final String? bitrate;
  final String? lyrics;
  final String? artworkBase64;
  final String? artworkUrl;
  final bool isRemote;
  final String? remoteStreamUri;
  final String? videoId;
  final String? artistId;
  final String? browseId;

  factory AudioTrack.fromJson(Map<String, dynamic> json) {
    return AudioTrack(
      id: '${json['id'] ?? ''}',
      uri: '${json['uri'] ?? ''}',
      title: _read(json, ['title', 'displayName']).trim().isEmpty
          ? 'Faixa sem nome'
          : _read(json, ['title', 'displayName']),
      artist: _cleanUnknown(_read(json, ['artist', 'albumArtist'])),
      album: _cleanUnknown(_read(json, ['album'])),
      durationMs: _toInt(json['duration']),
      path: '${json['path'] ?? ''}',
      mimeType: '${json['mimeType'] ?? ''}',
      dateAdded: _toInt(json['dateAdded']),
      dateModified: _toInt(json['dateModified']),
      albumId: _emptyToNull('${json['albumId'] ?? ''}'),
      albumArtist: _emptyToNull('${json['albumArtist'] ?? ''}'),
      genre: _emptyToNull('${json['genre'] ?? ''}'),
      year: _emptyToNull('${json['year'] ?? ''}'),
      trackNumber: _emptyToNull('${json['trackNumber'] ?? ''}'),
      discNumber: _emptyToNull('${json['discNumber'] ?? ''}'),
      composer: _emptyToNull('${json['composer'] ?? ''}'),
      author: _emptyToNull('${json['author'] ?? ''}'),
      writer: _emptyToNull('${json['writer'] ?? ''}'),
      bitrate: _emptyToNull('${json['bitrate'] ?? ''}'),
      lyrics: _emptyToNull('${json['lyrics'] ?? ''}'),
      artworkBase64: _emptyToNull('${json['artworkBase64'] ?? ''}'),
      artworkUrl: _emptyToNull('${json['artworkUrl'] ?? ''}'),
      isRemote: json['isRemote'] == true,
      remoteStreamUri: _emptyToNull('${json['remoteStreamUri'] ?? ''}'),
      videoId: _emptyToNull('${json['videoId'] ?? ''}'),
      artistId: _emptyToNull('${json['artistId'] ?? ''}'),
      browseId: _emptyToNull('${json['browseId'] ?? ''}'),
    );
  }

  factory AudioTrack.remote({
    required String id,
    required String title,
    required String artist,
    required String album,
    required int durationMs,
    required String videoId,
    String? artworkUrl,
    String? artistId,
    String? browseId,
    String? trackNumber,
  }) {
    return AudioTrack(
      id: id,
      uri: '',
      title: title.trim().isEmpty ? 'Faixa sem nome' : title.trim(),
      artist: artist.trim().isEmpty ? 'Desconhecido' : artist.trim(),
      album: album.trim().isEmpty ? 'YouTube Music' : album.trim(),
      durationMs: durationMs,
      path: '',
      mimeType: 'audio/webm',
      dateAdded: 0,
      dateModified: 0,
      artworkUrl: _emptyToNull(artworkUrl ?? ''),
      isRemote: true,
      videoId: _emptyToNull(videoId),
      artistId: _emptyToNull(artistId ?? ''),
      browseId: _emptyToNull(browseId ?? ''),
      trackNumber: _emptyToNull(trackNumber ?? ''),
    );
  }

  static String _read(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = '${json[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  static String _cleanUnknown(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '<unknown>' || trimmed.toLowerCase() == 'unknown') {
      return 'Desconhecido';
    }
    return trimmed;
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase();
  }

  Duration get duration => Duration(milliseconds: durationMs);

  int get trackNumberInt {
    final raw = trackNumber ?? '';
    final match = RegExp(r'\d+').firstMatch(raw);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }

  int get discNumberInt {
    final raw = discNumber ?? '';
    final match = RegExp(r'\d+').firstMatch(raw);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }

  int get yearInt => int.tryParse(year ?? '') ?? 0;

  bool get hasLyrics => (lyrics ?? '').trim().isNotEmpty;

  Uint8List? get artworkBytes {
    final data = artworkBase64;
    if (data == null || data.isEmpty) return null;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  String get primaryArtistForAlbum {
    final raw = (albumArtist ?? '').trim();
    if (raw.isNotEmpty && raw.toLowerCase() != '<unknown>' && raw.toLowerCase() != 'unknown') {
      return raw;
    }
    return artist;
  }

  String get albumGroupKey {
    if (isRemote) {
      return 'remote:${_normalize(album)}|${_normalize(primaryArtistForAlbum)}|${_normalize(browseId ?? videoId ?? id)}';
    }
    return '${_normalize(album)}|${_normalize(primaryArtistForAlbum)}';
  }

  String get dedupeKey {
    if (isRemote) {
      return 'remote:${_normalize(videoId ?? id)}';
    }
    final cleanedPath = path.trim();
    if (cleanedPath.isNotEmpty) {
      return 'path:${_normalize(cleanedPath)}';
    }

    final cleanedTitle = _normalize(title);
    final cleanedArtist = _normalize(artist);
    final cleanedAlbum = _normalize(album);
    final trackNo = trackNumberInt;
    final discNo = discNumberInt;

    return 'sig:$cleanedTitle|$cleanedArtist|$cleanedAlbum|$durationMs|$discNo|$trackNo';
  }

  String get libraryKey {
    if (isRemote) {
      return 'remote:${_normalize(videoId ?? id)}';
    }
    final cleanedPath = path.trim();
    if (cleanedPath.isNotEmpty) {
      return 'path:${_normalize(cleanedPath)}';
    }

    final cleanedUri = uri.trim();
    if (cleanedUri.isNotEmpty) {
      return 'uri:${_normalize(cleanedUri)}';
    }

    return dedupeKey;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'uri': uri,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': durationMs,
      'path': path,
      'mimeType': mimeType,
      'dateAdded': dateAdded,
      'dateModified': dateModified,
      'albumId': albumId,
      'albumArtist': albumArtist,
      'genre': genre,
      'year': year,
      'trackNumber': trackNumber,
      'discNumber': discNumber,
      'composer': composer,
      'author': author,
      'writer': writer,
      'bitrate': bitrate,
      'lyrics': lyrics,
      'artworkBase64': artworkBase64,
      'artworkUrl': artworkUrl,
      'isRemote': isRemote,
      'remoteStreamUri': remoteStreamUri,
      'videoId': videoId,
      'artistId': artistId,
      'browseId': browseId,
    };
  }

  AudioTrack copyWith({
    String? id,
    String? uri,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? path,
    String? mimeType,
    int? dateAdded,
    int? dateModified,
    String? albumId,
    String? albumArtist,
    String? genre,
    String? year,
    String? trackNumber,
    String? discNumber,
    String? composer,
    String? author,
    String? writer,
    String? bitrate,
    String? lyrics,
    String? artworkBase64,
    String? artworkUrl,
    bool? isRemote,
    String? remoteStreamUri,
    String? videoId,
    String? artistId,
    String? browseId,
  }) {
    return AudioTrack(
      id: id ?? this.id,
      uri: uri ?? this.uri,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      path: path ?? this.path,
      mimeType: mimeType ?? this.mimeType,
      dateAdded: dateAdded ?? this.dateAdded,
      dateModified: dateModified ?? this.dateModified,
      albumId: albumId ?? this.albumId,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      composer: composer ?? this.composer,
      author: author ?? this.author,
      writer: writer ?? this.writer,
      bitrate: bitrate ?? this.bitrate,
      lyrics: lyrics ?? this.lyrics,
      artworkBase64: artworkBase64 ?? this.artworkBase64,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      isRemote: isRemote ?? this.isRemote,
      remoteStreamUri: remoteStreamUri ?? this.remoteStreamUri,
      videoId: videoId ?? this.videoId,
      artistId: artistId ?? this.artistId,
      browseId: browseId ?? this.browseId,
    );
  }
}
