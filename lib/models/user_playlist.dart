import 'dart:convert';

import 'audio_track.dart';

class UserPlaylist {
  const UserPlaylist({
    required this.id,
    required this.name,
    required this.tracks,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<AudioTrack> tracks;
  final int createdAt;
  final int updatedAt;

  factory UserPlaylist.fromJson(Map<String, dynamic> json) {
    final rawTracks = (json['tracks'] as List?) ?? const <dynamic>[];
    final tracks = <AudioTrack>[];
    for (final item in rawTracks) {
      try {
        if (item is Map<String, dynamic>) {
          tracks.add(AudioTrack.fromJson(item));
        } else if (item is Map) {
          tracks.add(AudioTrack.fromJson(item.cast<String, dynamic>()));
        } else if (item is String) {
          final decoded = jsonDecode(item);
          if (decoded is Map<String, dynamic>) {
            tracks.add(AudioTrack.fromJson(decoded));
          } else if (decoded is Map) {
            tracks.add(AudioTrack.fromJson(decoded.cast<String, dynamic>()));
          }
        }
      } catch (_) {}
    }

    return UserPlaylist(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? 'Minha playlist'}'.trim().isEmpty
          ? 'Minha playlist'
          : '${json['name'] ?? 'Minha playlist'}'.trim(),
      tracks: tracks,
      createdAt: _toInt(json['createdAt']),
      updatedAt: _toInt(json['updatedAt']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  UserPlaylist copyWith({
    String? id,
    String? name,
    List<AudioTrack>? tracks,
    int? createdAt,
    int? updatedAt,
  }) {
    return UserPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
