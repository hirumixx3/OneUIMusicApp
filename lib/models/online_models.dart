import 'audio_track.dart';

class OnlineAlbum {
  const OnlineAlbum({
    required this.browseId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    this.year,
    this.playlistId,
  });

  final String browseId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final String? year;
  final String? playlistId;
}

class OnlineArtist {
  const OnlineArtist({
    required this.browseId,
    required this.name,
    required this.thumbnailUrl,
  });

  final String browseId;
  final String name;
  final String thumbnailUrl;
}

class OnlinePlaylist {
  const OnlinePlaylist({
    required this.playlistId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    this.songCountText,
    this.browseId,
  });

  final String playlistId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final String? songCountText;
  final String? browseId;
}

class OnlineAlbumPage {
  const OnlineAlbumPage({
    required this.album,
    required this.tracks,
  });

  final OnlineAlbum album;
  final List<AudioTrack> tracks;
}

class OnlineArtistPage {
  const OnlineArtistPage({
    required this.artist,
    required this.topSongs,
    required this.albums,
    required this.playlists,
    this.songsMoreBrowseId,
    this.songsMoreParams,
    this.albumsMoreBrowseId,
    this.albumsMoreParams,
  });

  final OnlineArtist artist;
  final List<AudioTrack> topSongs;
  final List<OnlineAlbum> albums;
  final List<OnlinePlaylist> playlists;
  final String? songsMoreBrowseId;
  final String? songsMoreParams;
  final String? albumsMoreBrowseId;
  final String? albumsMoreParams;
}

class OnlinePlaylistPage {
  const OnlinePlaylistPage({
    required this.playlist,
    required this.tracks,
  });

  final OnlinePlaylist playlist;
  final List<AudioTrack> tracks;
}

class OnlineSearchResult {
  const OnlineSearchResult({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.playlists,
  });

  final List<AudioTrack> songs;
  final List<OnlineAlbum> albums;
  final List<OnlineArtist> artists;
  final List<OnlinePlaylist> playlists;

  bool get isEmpty => songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;
}
