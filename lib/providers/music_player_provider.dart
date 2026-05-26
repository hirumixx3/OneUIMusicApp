import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../audio/audio_runtime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_track.dart';
import '../models/user_playlist.dart';
import '../models/online_models.dart';

enum LibraryTab { tracks, albums, artists, favorites, online }
enum SortMode { launch, alphabetical, artist }
enum RepeatMode { off, track, album }
enum AppLanguage { portuguese, english, japanese }
enum EqualizerPreset { balanced, bassBoost, soft, dynamic, crisp, trebleBoost, custom }

class EqualizerBandSetting {
  const EqualizerBandSetting({
    required this.index,
    required this.centerMilliHz,
    required this.minLevel,
    required this.maxLevel,
    required this.level,
  });

  final int index;
  final int centerMilliHz;
  final int minLevel;
  final int maxLevel;
  final int level;

  factory EqualizerBandSetting.fromJson(Map<String, dynamic> json) => EqualizerBandSetting(
        index: (json['index'] as num?)?.toInt() ?? 0,
        centerMilliHz: (json['centerMilliHz'] as num?)?.toInt() ?? 0,
        minLevel: (json['minLevel'] as num?)?.toInt() ?? -1500,
        maxLevel: (json['maxLevel'] as num?)?.toInt() ?? 1500,
        level: (json['level'] as num?)?.toInt() ?? 0,
      );

  EqualizerBandSetting copyWith({int? level}) => EqualizerBandSetting(
        index: index,
        centerMilliHz: centerMilliHz,
        minLevel: minLevel,
        maxLevel: maxLevel,
        level: level ?? this.level,
      );

  String get label {
    final hz = centerMilliHz / 1000.0;
    if (hz >= 1000) {
      final khz = hz / 1000.0;
      return khz >= 10 ? '${khz.toStringAsFixed(0)} kHz' : '${khz.toStringAsFixed(1)} kHz';
    }
    return '${hz.toStringAsFixed(0)} Hz';
  }
}

class MusicPlayerProvider extends ChangeNotifier {
  static const MethodChannel _scannerChannel = MethodChannel('fast_audio_scanner');
  static const MethodChannel _equalizerChannel = MethodChannel('com.hirumisu.musicapp/equalizer');
  static const MethodChannel _systemChannel = MethodChannel('com.hirumisu.musicapp/system');
  static const MethodChannel _metrolistChannel = MethodChannel('com.hirumisu.musicapp/metrolist_stream');
  static const _favoritesKey = 'favorites_ids';
  static const _onlineFavoriteIdsKey = 'online_favorites_ids';
  static const _onlineFavoritesDataKey = 'online_favorites_data';
  static const _lastTrackIdKey = 'last_track_id';
  static const _lastPositionKey = 'last_position_ms';
  static const _shuffleKey = 'shuffle_enabled';
  static const _repeatModeKey = 'repeat_mode';
  static const _sortModeKey = 'sort_mode';
  static const _tabKey = 'library_tab';
  static const _scrollKeyPrefix = 'scroll_offset_';
  static const _onlineSearchHistoryKey = 'online_search_history';
  static const _onlineRecentTracksKey = 'online_recent_tracks';
  static const _playHistoryKey = 'play_history_tracks';
  static const _downloadedTracksKey = 'downloaded_tracks';
  static const _userPlaylistsKey = 'user_playlists';
  static const _onlineSectionKey = 'online_section_index';
  static const _languageKey = 'app_language';
  static const _equalizerEnabledKey = 'equalizer_enabled';
  static const _equalizerBandLevelsKey = 'equalizer_band_levels';
  static const _equalizerPresetKey = 'equalizer_preset';
  static const _libraryCacheFileName = 'library_cache_v1.json';

  final AudioPlayer player = AudioRuntime.sharedPlayer;
  final TextEditingController searchController = TextEditingController();

  final Set<String> _favoriteIds = <String>{};
  final Set<String> _onlineFavoriteIds = <String>{};
  final Map<String, AudioTrack> _onlineFavoriteTracks = <String, AudioTrack>{};
  final List<String> _onlineSearchHistory = <String>[];
  final List<AudioTrack> _onlineRecentTracks = <AudioTrack>[];
  final List<AudioTrack> _playHistory = <AudioTrack>[];
  final List<UserPlaylist> _userPlaylists = <UserPlaylist>[];
  final List<AudioTrack> _downloadedTracks = <AudioTrack>[];
  final Map<LibraryTab, double> _scrollOffsets = {
    LibraryTab.tracks: 0,
    LibraryTab.albums: 0,
    LibraryTab.artists: 0,
    LibraryTab.favorites: 0,
    LibraryTab.online: 0,
  };
  final Map<String, Uint8List?> _artworkBytesCache = <String, Uint8List?>{};
  final Map<String, Future<Uint8List?>> _artworkFutureCache = <String, Future<Uint8List?>>{};
  final Map<String, Uri> _notificationArtworkUriCache = <String, Uri>{};
  final Map<String, String> _resolvedPlayablePathCache = <String, String>{};
  final Map<String, String> _lyricsCache = <String, String>{};
  final Map<String, Future<String>> _lyricsFutureCache = <String, Future<String>>{};

  List<AudioTrack> _tracks = <AudioTrack>[];

  List<AudioTrack> _onlineSongs = <AudioTrack>[];
  List<OnlineAlbum> _onlineAlbums = <OnlineAlbum>[];
  List<OnlineArtist> _onlineArtists = <OnlineArtist>[];
  List<OnlinePlaylist> _onlinePlaylists = <OnlinePlaylist>[];
  final Map<String, Future<OnlineAlbumPage>> _onlineAlbumPageFutures = <String, Future<OnlineAlbumPage>>{};
  final Map<String, Future<OnlineArtistPage>> _onlineArtistPageFutures = <String, Future<OnlineArtistPage>>{};
  final Map<String, Future<OnlinePlaylistPage>> _onlinePlaylistPageFutures = <String, Future<OnlinePlaylistPage>>{};
  final Map<String, Future<List<AudioTrack>>> _onlineArtistAllSongsFutures = <String, Future<List<AudioTrack>>>{};
  final Map<String, Future<List<OnlineAlbum>>> _onlineArtistAllAlbumsFutures = <String, Future<List<OnlineAlbum>>>{};
  List<AudioTrack> _onlineRecommendedSongs = <AudioTrack>[];
  List<OnlineArtist> _onlineRecommendedArtists = <OnlineArtist>[];
  List<OnlinePlaylist> _onlineRecommendedPlaylists = <OnlinePlaylist>[];
  bool _isOnlineLoading = false;
  String? _onlineError;
  String _lastOnlineQuery = '';

  // ── Google account ────────────────────────────────────────────────────────
  bool _isLoggedIn = false;
  String _accountName  = '';
  String _accountEmail = '';
  String _accountPhoto = '';

  bool   get isLoggedIn    => _isLoggedIn;
  String get accountName   => _accountName;
  String get accountEmail  => _accountEmail;
  String get accountPhoto  => _accountPhoto;
  int _onlineSectionIndex = 0;
  List<AudioTrack> _queue = <AudioTrack>[];
  AudioTrack? _currentTrack;
  AudioTrack? _pendingTrack;
  int _currentIndex = -1;
  bool _isLoading = true;
  bool _hasPermission = false;
  bool _shuffleEnabled = false;
  String? _error;
  LibraryTab _tab = LibraryTab.tracks;
  SortMode _sortMode = SortMode.alphabetical;
  RepeatMode _repeatMode = RepeatMode.off;
  AppLanguage _appLanguage = AppLanguage.portuguese;
  SharedPreferences? _prefs;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<int?>? _audioSessionIdSub;
  bool _bootstrapped = false;
  bool _bootstrapStarted = false;
  bool _isPreparingTrack = false;
  bool _manualRemoteQueueMode = false;
  bool _isRecoveringRemoteSource = false;
  String? _lastRecoveredRemoteTrackKey;
  bool _isRecoveringLocalSource = false;
  String? _lastRecoveredLocalTrackKey;
  final Set<String> _remoteProxyFallbackKeys = <String>{};
  final Set<String> _downloadInProgress = <String>{};
  final Map<String, double> _downloadProgress = <String, double>{};
  int _trackLoadGeneration = 0;
  int _notificationSyncGeneration = 0;
  DateTime _lastPersistAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _onlineSearchRequestSerial = 0;
  Future<void> _audioSourceLoadBarrier = Future<void>.value();
  bool _equalizerSupported = false;
  bool _equalizerEnabled = true;
  bool _equalizerAttached = false;
  int? _audioSessionId;
  EqualizerPreset _equalizerPreset = EqualizerPreset.balanced;
  List<EqualizerBandSetting> _equalizerBands = const <EqualizerBandSetting>[];

  MusicPlayerProvider() {
    _playerStateSub = player.playerStateStream.listen(_handlePlayerState);
    _positionSub = player.positionStream.listen((_) {
      final now = DateTime.now();
      if (now.difference(_lastPersistAt) >= const Duration(seconds: 1)) {
        _lastPersistAt = now;
        unawaited(_persistCurrentTrack());
      }
    });
    _currentIndexSub = player.currentIndexStream.listen(_handleCurrentIndexChanged);
    _playbackEventSub = player.playbackEventStream.listen((_) {}, onError: (Object error, StackTrace stackTrace) {
      unawaited(_handlePlaybackException(error));
    });
    _audioSessionIdSub = player.androidAudioSessionIdStream.listen((sessionId) {
      if (sessionId == null || sessionId <= 0) return;
      _audioSessionId = sessionId;
      unawaited(_attachEqualizerToCurrentSession());
    });
    searchController.addListener(() {
      notifyListeners();
    });
    AudioRuntime.setNavigationCallbacks(
      onSkipNext: () => nextTrack(wrap: true),
      onSkipPrevious: () => previousTrack(wrap: true),
    );
  }



  Map<String, dynamic> _nativeMap(dynamic value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry('$key', val));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _nativeMapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map>().map(_nativeMap).toList(growable: false);
  }

  Future<Map<String, dynamic>> _invokeMetrolistMap(String method, [Map<String, dynamic>? args]) async {
    final result = await _metrolistChannel.invokeMethod<dynamic>(method, args ?? const <String, dynamic>{});
    return _nativeMap(result);
  }

  Future<List<Map<String, dynamic>>> _invokeMetrolistList(String method, [Map<String, dynamic>? args]) async {
    final result = await _metrolistChannel.invokeMethod<dynamic>(method, args ?? const <String, dynamic>{});
    return _nativeMapList(result);
  }

  AudioTrack _trackFromNative(dynamic value) {
    final map = _nativeMap(value);
    return AudioTrack.fromJson(map);
  }

  List<AudioTrack> _tracksFromNative(dynamic value) => _nativeMapList(value).map(_trackFromNative).toList(growable: false);

  OnlineAlbum _albumFromNative(dynamic value) {
    final map = _nativeMap(value);
    return OnlineAlbum(
      browseId: '${map['browseId'] ?? map['id'] ?? ''}',
      title: '${map['title'] ?? 'Álbum'}',
      artist: '${map['artist'] ?? ''}',
      thumbnailUrl: _highQualityArtworkUrl('${map['thumbnailUrl'] ?? map['thumbnail'] ?? ''}'),
      year: _emptyToNull('${map['year'] ?? ''}'),
      playlistId: _emptyToNull('${map['playlistId'] ?? ''}'),
    );
  }

  List<OnlineAlbum> _albumsFromNative(dynamic value) => _nativeMapList(value).map(_albumFromNative).toList(growable: false);

  OnlineArtist _artistFromNative(dynamic value) {
    final map = _nativeMap(value);
    return OnlineArtist(
      browseId: '${map['browseId'] ?? map['id'] ?? ''}',
      name: '${map['name'] ?? map['title'] ?? 'Artista'}',
      thumbnailUrl: _highQualityArtworkUrl('${map['thumbnailUrl'] ?? map['thumbnail'] ?? ''}'),
    );
  }

  List<OnlineArtist> _artistsFromNative(dynamic value) => _nativeMapList(value).map(_artistFromNative).toList(growable: false);

  OnlinePlaylist _playlistFromNative(dynamic value) {
    final map = _nativeMap(value);
    return OnlinePlaylist(
      playlistId: '${map['playlistId'] ?? map['id'] ?? ''}'.replaceFirst(RegExp(r'^VL'), ''),
      title: '${map['title'] ?? 'Playlist'}',
      author: '${map['author'] ?? ''}',
      thumbnailUrl: _highQualityArtworkUrl('${map['thumbnailUrl'] ?? map['thumbnail'] ?? ''}'),
      songCountText: _emptyToNull('${map['songCountText'] ?? ''}'),
      browseId: _emptyToNull('${map['browseId'] ?? ''}'),
    );
  }

  List<OnlinePlaylist> _playlistsFromNative(dynamic value) => _nativeMapList(value).map(_playlistFromNative).toList(growable: false);

  OnlineSearchResult _searchResultFromNative(dynamic value) {
    final map = _nativeMap(value);
    return OnlineSearchResult(
      songs: _tracksFromNative(map['songs']),
      albums: _albumsFromNative(map['albums']),
      artists: _artistsFromNative(map['artists']),
      playlists: _playlistsFromNative(map['playlists']),
    );
  }

  OnlineAlbumPage _albumPageFromNative(dynamic value) {
    final map = _nativeMap(value);
    return OnlineAlbumPage(
      album: _albumFromNative(map['album']),
      tracks: _tracksFromNative(map['tracks']),
    );
  }

  OnlineArtistPage _artistPageFromNative(dynamic value) {
    final map = _nativeMap(value);
    return OnlineArtistPage(
      artist: _artistFromNative(map['artist']),
      topSongs: _tracksFromNative(map['topSongs']),
      albums: _albumsFromNative(map['albums']),
      playlists: _playlistsFromNative(map['playlists']),
      songsMoreBrowseId: _emptyToNull('${map['songsMoreBrowseId'] ?? ''}'),
      songsMoreParams: _emptyToNull('${map['songsMoreParams'] ?? ''}'),
      albumsMoreBrowseId: _emptyToNull('${map['albumsMoreBrowseId'] ?? ''}'),
      albumsMoreParams: _emptyToNull('${map['albumsMoreParams'] ?? ''}'),
    );
  }

  OnlinePlaylistPage _playlistPageFromNative(dynamic value) {
    final map = _nativeMap(value);
    return OnlinePlaylistPage(
      playlist: _playlistFromNative(map['playlist']),
      tracks: _tracksFromNative(map['tracks']),
    );
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == 'null' ? null : trimmed;
  }

  String _highQualityArtworkUrl(String value) {
    var url = value.trim();
    if (url.isEmpty) return url;
    url = url.replaceAll(RegExp(r'=w\d+-h\d+(?:-[^?&]*)?'), '=w1200-h1200-l90-rj');
    url = url.replaceAll(RegExp(r'=s\d+(?:-[^?&]*)?'), '=s1200');
    url = url
        .replaceAll('=s60', '=s1200')
        .replaceAll('=s120', '=s1200')
        .replaceAll('=s226', '=s1200')
        .replaceAll('/default.jpg', '/maxresdefault.jpg')
        .replaceAll('/mqdefault.jpg', '/maxresdefault.jpg')
        .replaceAll('/hqdefault.jpg', '/maxresdefault.jpg')
        .replaceAll('/sddefault.jpg', '/maxresdefault.jpg');
    return url;
  }

  Future<OnlineSearchResult> _homeNative() async => _searchResultFromNative(await _invokeMetrolistMap('home'));

  Future<OnlineSearchResult> _searchNative(String query) async => _searchResultFromNative(
        await _invokeMetrolistMap('search', <String, dynamic>{'query': query}),
      );

  Future<List<AudioTrack>> _searchSongsNative(String query) async => _tracksFromNative(
        await _invokeMetrolistList('searchSongs', <String, dynamic>{'query': query}),
      );

  Future<List<OnlineAlbum>> _searchAlbumsNative(String query) async => _albumsFromNative(
        await _invokeMetrolistList('searchAlbums', <String, dynamic>{'query': query}),
      );

  Future<List<OnlineArtist>> _searchArtistsNative(String query) async => _artistsFromNative(
        await _invokeMetrolistList('searchArtists', <String, dynamic>{'query': query}),
      );

  Future<List<OnlinePlaylist>> _searchPlaylistsNative(String query) async => _playlistsFromNative(
        await _invokeMetrolistList('searchPlaylists', <String, dynamic>{'query': query}),
      );

  Future<List<OnlinePlaylist>> _fetchPersonalizedPlaylistsNative(List<String> queries) async => _playlistsFromNative(
        await _invokeMetrolistList('fetchPersonalizedPlaylists', <String, dynamic>{'queries': queries}),
      );

  Future<OnlineAlbumPage> _albumNative(String browseId) async => _albumPageFromNative(
        await _invokeMetrolistMap('album', <String, dynamic>{'browseId': browseId}),
      );

  Future<OnlineArtistPage> _artistNative(String browseId) async => _artistPageFromNative(
        await _invokeMetrolistMap('artist', <String, dynamic>{'browseId': browseId}),
      );

  Future<OnlinePlaylistPage> _playlistNative(String playlistId) async => _playlistPageFromNative(
        await _invokeMetrolistMap('playlist', <String, dynamic>{'playlistId': playlistId}),
      );

  Future<List<AudioTrack>> _artistSongsNative({
    required String artistName,
    required String artistBrowseId,
    String? moreBrowseId,
    String? moreParams,
    List<AudioTrack> seed = const <AudioTrack>[],
  }) async {
    final tracks = _tracksFromNative(
      await _invokeMetrolistList('artistSongs', <String, dynamic>{
        'artistName': artistName,
        'artistBrowseId': artistBrowseId,
        'moreBrowseId': moreBrowseId ?? '',
        'moreParams': moreParams ?? '',
      }),
    );
    return tracks.isNotEmpty ? _dedupeTracks(<AudioTrack>[...seed, ...tracks]) : seed;
  }

  Future<List<OnlineAlbum>> _artistAlbumsNative({
    required String artistName,
    required String artistBrowseId,
    String? moreBrowseId,
    String? moreParams,
    List<OnlineAlbum> seed = const <OnlineAlbum>[],
  }) async {
    final albums = _albumsFromNative(
      await _invokeMetrolistList('artistAlbums', <String, dynamic>{
        'artistName': artistName,
        'artistBrowseId': artistBrowseId,
        'moreBrowseId': moreBrowseId ?? '',
        'moreParams': moreParams ?? '',
      }),
    );
    return albums.isNotEmpty ? _dedupeAlbums(<OnlineAlbum>[...seed, ...albums]) : seed;
  }

  Future<AudioTrack> _resolveMetrolistStream(AudioTrack track, {bool forceRefresh = false}) async {
    final videoId = (track.videoId ?? track.id).trim();
    if (videoId.isEmpty) {
      throw Exception('Faixa online sem videoId para o Innertube do Metrolist');
    }
    final result = await _invokeMetrolistMap('resolveStream', <String, dynamic>{
      'videoId': videoId,
      'quality': 'AUTO',
      'forceRefresh': forceRefresh,
    }).timeout(const Duration(seconds: 18));
    final url = '${result['url'] ?? ''}'.trim();
    final parsed = Uri.tryParse(url);
    if (url.isEmpty || parsed == null || !(parsed.scheme == 'http' || parsed.scheme == 'https')) {
      throw Exception('Innertube do Metrolist não devolveu stream válido');
    }
    final durationValue = result['durationMs'];
    final durationMs = durationValue is num ? durationValue.toInt() : int.tryParse('$durationValue') ?? track.durationMs;
    final title = '${result['title'] ?? ''}'.trim();
    return track.copyWith(
      uri: url,
      remoteStreamUri: url,
      videoId: videoId,
      mimeType: '${result['mimeType'] ?? track.mimeType}',
      bitrate: _emptyToNull('${result['bitrate'] ?? track.bitrate ?? ''}'),
      durationMs: durationMs > 0 ? durationMs : track.durationMs,
      title: title.isNotEmpty && track.title.trim().isEmpty ? title : track.title,
    );
  }

  Future<void> _prewarmMetrolistStream(AudioTrack track) async {
    final videoId = (track.videoId ?? track.id).trim();
    if (!track.isRemote || videoId.isEmpty) return;
    try {
      await _invokeMetrolistMap('prewarmStream', <String, dynamic>{
        'videoId': videoId,
        'quality': 'AUTO',
      }).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Playback still works without prewarm; this only warms the native
      // Metrolist cache so the first 512 KiB chunk is ready faster.
    }
  }


  // ── Google login ──────────────────────────────────────────────────────────

  /// Launches the Google WebView login flow.
  Future<Map<String, dynamic>?> loginWithGoogle() async {
    try {
      final result = await _metrolistChannel.invokeMapMethod<String, dynamic>('loginWithGoogle');
      if (result != null && (result['cookie'] as String?)?.isNotEmpty == true) {
        _isLoggedIn    = true;
        _accountName   = (result['name']  as String?) ?? '';
        _accountEmail  = (result['email'] as String?) ?? '';
        _accountPhoto  = (result['photo'] as String?) ?? '';
        notifyListeners();
        unawaited(searchOnline(forceQuery: '', refresh: true));
        return result;
      }
    } catch (_) {}
    return null;
  }

  /// Clears the Google session.
  Future<void> logoutGoogle() async {
    try { await _metrolistChannel.invokeMethod<bool>('logoutGoogle'); } catch (_) {}
    _isLoggedIn = false; _accountName = '';
    _accountEmail = '';
    _accountPhoto = '';
    notifyListeners();
    unawaited(searchOnline(forceQuery: '', refresh: true));
  }

  /// Restores persisted Google session on app start.
  Future<void> loadAccountState() async {
    try {
      final result = await _metrolistChannel.invokeMapMethod<String, dynamic>('getGoogleAccount');
      if (result != null) {
        _isLoggedIn   = true;
        _accountName  = (result['name']  as String?) ?? '';
        _accountEmail = (result['email'] as String?) ?? '';
        _accountPhoto = (result['photo'] as String?) ?? '';
        notifyListeners();
      }
    } catch (_) {}
  }

  void _markRemoteStreamFailure(AudioTrack track, {String? failedUrl}) {
    _remoteProxyFallbackKeys.add(track.libraryKey);
  }

  static Map<String, String>? _playbackHeadersForUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.contains('googlevideo.com') || host.contains('youtube.com') || host.contains('ytimg.com')) {
      return const <String, String>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        'Referer': 'https://music.youtube.com/',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Connection': 'keep-alive',
      };
    }
    return null;
  }

  List<AudioTrack> get tracks => List.unmodifiable(_tracks);
  AudioTrack? get currentTrack => _currentTrack;
  AudioTrack? get pendingTrack => _pendingTrack;
  AudioTrack? get activeDisplayTrack => _pendingTrack ?? _currentTrack;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  String? get error => _error;
  LibraryTab get tab => _tab;
  SortMode get sortMode => _sortMode;
  bool get shuffleEnabled => _shuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  AppLanguage get appLanguage => _appLanguage;
  Locale get locale {
    switch (_appLanguage) {
      case AppLanguage.english:
        return const Locale('en');
      case AppLanguage.japanese:
        return const Locale('ja');
      case AppLanguage.portuguese:
        return const Locale('pt', 'BR');
    }
  }
  bool get isPreparingTrack => _isPreparingTrack;
  bool get manualRemoteQueueMode => _manualRemoteQueueMode;

  List<AudioTrack> get onlineSongs => List.unmodifiable(_onlineSongs);
  List<OnlineAlbum> get onlineAlbums => List.unmodifiable(_onlineAlbums);
  List<OnlineArtist> get onlineArtists => List.unmodifiable(_onlineArtists);
  List<OnlinePlaylist> get onlinePlaylists => List.unmodifiable(_onlinePlaylists);
  List<AudioTrack> get onlineRecommendedSongs => List.unmodifiable(_onlineRecommendedSongs);
  List<OnlineArtist> get onlineRecommendedArtists => List.unmodifiable(
        _dedupeRecommendedArtists(<OnlineArtist>[..._onlineRecommendedArtists, ..._onlineArtists]),
      );
  List<OnlinePlaylist> get onlineRecommendedPlaylists => List.unmodifiable(
        _dedupePlaylists(<OnlinePlaylist>[..._onlineRecommendedPlaylists, ..._onlinePlaylists]),
      );
  String get onlineActiveQuery => _lastOnlineQuery.trim().toLowerCase();
  List<AudioTrack> get onlineDisplaySongs => List.unmodifiable(
        onlineActiveQuery.isEmpty && _onlineRecommendedSongs.isNotEmpty
            ? _dedupeTracks(<AudioTrack>[..._onlineRecommendedSongs, ..._onlineSongs])
            : _onlineSongs,
      );
  List<OnlineArtist> get onlineDisplayArtists => List.unmodifiable(
        onlineActiveQuery.isEmpty
            ? _dedupeRecommendedArtists(<OnlineArtist>[..._onlineRecommendedArtists, ..._onlineArtists])
            : _onlineArtists,
      );
  List<OnlinePlaylist> get onlineDisplayPlaylists => List.unmodifiable(
        onlineActiveQuery.isEmpty
            ? _dedupePlaylists(<OnlinePlaylist>[..._onlineRecommendedPlaylists, ..._onlinePlaylists])
            : _onlinePlaylists,
      );
  bool get isOnlineLoading => _isOnlineLoading;
  String? get onlineError => _onlineError;
  List<String> get onlineSearchHistory => List.unmodifiable(_onlineSearchHistory);
  List<AudioTrack> get onlineRecentTracks => List.unmodifiable(_onlineRecentTracks);


  bool _hasOnlineHomeContent() {
    final hasSongs = _onlineSongs.isNotEmpty || _onlineRecommendedSongs.isNotEmpty;
    final hasArtists = _onlineArtists.isNotEmpty || _onlineRecommendedArtists.isNotEmpty;
    final hasPlaylists = _onlinePlaylists.isNotEmpty || _onlineRecommendedPlaylists.isNotEmpty;
    return hasSongs && hasArtists && hasPlaylists;
  }
  List<AudioTrack> get playHistory => List.unmodifiable(_playHistory);
  List<UserPlaylist> get userPlaylists => List.unmodifiable(_userPlaylists);
  List<AudioTrack> get playbackQueue => List.unmodifiable(_queue.isNotEmpty ? _queue : _tracks);
  List<AudioTrack> get queuePreviousTracks {
    final queue = _queueForDisplay();
    if (queue.isEmpty) return const <AudioTrack>[];
    final currentIndex = _currentQueueIndexForDisplay(queue);
    if (currentIndex <= 0) return const <AudioTrack>[];
    final start = max(0, currentIndex - 3);
    return List<AudioTrack>.from(queue.sublist(start, currentIndex).reversed);
  }

  List<AudioTrack> get queueNextTracks {
    final queue = _queueForDisplay();
    if (queue.isEmpty) return const <AudioTrack>[];
    final currentIndex = _currentQueueIndexForDisplay(queue);
    if (currentIndex == -1 || currentIndex >= queue.length - 1) return const <AudioTrack>[];
    final end = min(queue.length, currentIndex + 4);
    return List<AudioTrack>.from(queue.sublist(currentIndex + 1, end));
  }
  List<AudioTrack> get downloadedTracks => List.unmodifiable(_downloadedTracks);
  double? downloadProgressFor(AudioTrack track) => _downloadProgress[track.libraryKey];
  int get onlineSectionIndex => _onlineSectionIndex;
  bool get equalizerSupported => _equalizerSupported;
  bool get equalizerEnabled => _equalizerEnabled;
  bool get equalizerAttached => _equalizerAttached;
  int? get equalizerAudioSessionId => _audioSessionId;
  EqualizerPreset get equalizerPreset => _equalizerPreset;
  List<EqualizerBandSetting> get equalizerBands => List.unmodifiable(
        _equalizerBands.where((band) => band.centerMilliHz > 0).toList(growable: false),
      );

  String get query => searchController.text.trim().toLowerCase();

  String get repeatLabel {
    switch (_repeatMode) {
      case RepeatMode.off:
        switch (_appLanguage) {
          case AppLanguage.english:
            return 'No repeat';
          case AppLanguage.japanese:
            return 'リピートなし';
          case AppLanguage.portuguese:
            return 'Sem repetição';
        }
      case RepeatMode.track:
        switch (_appLanguage) {
          case AppLanguage.english:
            return 'Repeat track';
          case AppLanguage.japanese:
            return '1曲リピート';
          case AppLanguage.portuguese:
            return 'Repetir faixa';
        }
      case RepeatMode.album:
        switch (_appLanguage) {
          case AppLanguage.english:
            return 'Repeat album';
          case AppLanguage.japanese:
            return 'アルバムをリピート';
          case AppLanguage.portuguese:
            return 'Repetir álbum';
        }
    }
  }

  AppLanguage _defaultLanguageFromSystem() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();
    if (code.startsWith('ja')) return AppLanguage.japanese;
    if (code.startsWith('en')) return AppLanguage.english;
    return AppLanguage.portuguese;
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_appLanguage == language) return;
    _appLanguage = language;
    await _prefs?.setString(_languageKey, language.name);
    notifyListeners();
  }

  Future<void> bootstrap() async {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;

    _prefs = await SharedPreferences.getInstance();
    final savedLanguage = _prefs?.getString(_languageKey);
    final matchedLanguage = AppLanguage.values.where((item) => item.name == savedLanguage);
    _appLanguage = matchedLanguage.isEmpty ? _defaultLanguageFromSystem() : matchedLanguage.first;
    _favoriteIds
      ..clear()
      ..addAll(_prefs?.getStringList(_favoritesKey) ?? const <String>[]);
    _onlineFavoriteIds
      ..clear()
      ..addAll(_prefs?.getStringList(_onlineFavoriteIdsKey) ?? const <String>[]);
    _onlineFavoriteTracks
      ..clear()
      ..addAll(_loadSavedOnlineFavorites());
    _onlineSearchHistory
      ..clear()
      ..addAll(_prefs?.getStringList(_onlineSearchHistoryKey) ?? const <String>[]);
    _onlineRecentTracks
      ..clear()
      ..addAll(_loadSavedOnlineRecentTracks());
    _playHistory
      ..clear()
      ..addAll(_loadSavedPlayHistory());
    _userPlaylists
      ..clear()
      ..addAll(_loadSavedUserPlaylists());
    _downloadedTracks
      ..clear()
      ..addAll(_loadSavedDownloadedTracks());
    _shuffleEnabled = _prefs?.getBool(_shuffleKey) ?? false;
    _repeatMode = RepeatMode.values[_prefs?.getInt(_repeatModeKey) ?? 0];
    _sortMode = SortMode.values[_prefs?.getInt(_sortModeKey) ?? 1];
    _tab = LibraryTab.values[_prefs?.getInt(_tabKey) ?? 0];
    _onlineSectionIndex = _normalizeOnlineSectionIndex((_prefs?.getInt(_onlineSectionKey) ?? 0));
    _equalizerEnabled = _prefs?.getBool(_equalizerEnabledKey) ?? true;
    _equalizerPreset = EqualizerPreset.values[_prefs?.getInt(_equalizerPresetKey) ?? 0];
    final savedEqualizerLevelsRaw = _prefs?.getString(_equalizerBandLevelsKey) ?? '[]';
    try {
      final decoded = jsonDecode(savedEqualizerLevelsRaw);
      if (decoded is List) {
        _equalizerBands = List<EqualizerBandSetting>.generate(
          decoded.length,
          (index) => EqualizerBandSetting(
            index: index,
            centerMilliHz: 0,
            minLevel: -1500,
            maxLevel: 1500,
            level: (decoded[index] as num?)?.toInt() ?? 0,
          ),
        );
      }
    } catch (_) {}
    _onlineRecommendedSongs = _rankOnlineRecommendedSongs(<AudioTrack>[
      ..._onlineFavoriteTracks.values,
      ..._onlineRecentTracks,
      ..._playHistory,
    ]).take(80).toList(growable: false);
    for (final tab in LibraryTab.values) {
      _scrollOffsets[tab] = _prefs?.getDouble('$_scrollKeyPrefix${tab.name}') ?? 0;
    }

    final cachedLocalTracks = await _loadCachedLibraryTracks();
    if (cachedLocalTracks.isNotEmpty) {
      _tracks = _dedupeTracks(<AudioTrack>[...cachedLocalTracks, ..._downloadedTracks]);
      _queue = List<AudioTrack>.from(_tracks);
      _error = _tracks.isEmpty ? 'Nenhuma música encontrada no aparelho.' : null;
      _isLoading = false;
    } else if (_downloadedTracks.isNotEmpty) {
      _tracks = List<AudioTrack>.from(_downloadedTracks);
      _queue = List<AudioTrack>.from(_tracks);
      _error = null;
      _isLoading = false;
    } else if (_tab == LibraryTab.online || _onlineRecommendedSongs.isNotEmpty || _onlineFavoriteTracks.isNotEmpty || _playHistory.isNotEmpty || _onlineRecentTracks.isNotEmpty) {
      _error = null;
      _isLoading = false;
    }

    _bootstrapped = true;
    unawaited(_applyRepeatModeToPlayer());
    unawaited(_initializeEqualizer());
    unawaited(loadAccountState());
    notifyListeners();
    unawaited(_finishBootstrap());
  }

  Map<String, AudioTrack> _loadSavedOnlineFavorites() {
    final rawList = _prefs?.getStringList(_onlineFavoritesDataKey) ?? const <String>[];
    final map = <String, AudioTrack>{};
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final track = AudioTrack.fromJson(decoded);
          if (track.isRemote) {
            map[track.id] = _sanitizeRemoteTrack(track);
          }
        } else if (decoded is Map) {
          final track = AudioTrack.fromJson(decoded.cast<String, dynamic>());
          if (track.isRemote) {
            map[track.id] = _sanitizeRemoteTrack(track);
          }
        }
      } catch (_) {}
    }
    return map;
  }


  List<AudioTrack> _loadSavedOnlineRecentTracks() {
    final rawList = _prefs?.getStringList(_onlineRecentTracksKey) ?? const <String>[];
    final list = <AudioTrack>[];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final track = AudioTrack.fromJson(decoded);
          if (track.isRemote) list.add(_sanitizeRemoteTrack(track));
        } else if (decoded is Map) {
          final track = AudioTrack.fromJson(decoded.cast<String, dynamic>());
          if (track.isRemote) list.add(_sanitizeRemoteTrack(track));
        }
      } catch (_) {}
    }
    return _dedupeTracks(list).take(24).toList(growable: false);
  }

  List<AudioTrack> _loadSavedPlayHistory() {
    final rawList = _prefs?.getStringList(_playHistoryKey) ?? const <String>[];
    final list = <AudioTrack>[];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final loaded = AudioTrack.fromJson(decoded);
          list.add(loaded.isRemote ? _sanitizeRemoteTrack(loaded) : loaded);
        } else if (decoded is Map) {
          final loaded = AudioTrack.fromJson(decoded.cast<String, dynamic>());
          list.add(loaded.isRemote ? _sanitizeRemoteTrack(loaded) : loaded);
        }
      } catch (_) {}
    }
    return _dedupeTracks(list).take(60).toList(growable: false);
  }

  List<AudioTrack> _loadSavedDownloadedTracks() {
    final rawList = _prefs?.getStringList(_downloadedTracksKey) ?? const <String>[];
    final list = <AudioTrack>[];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        final track = decoded is Map<String, dynamic>
            ? AudioTrack.fromJson(decoded)
            : decoded is Map
                ? AudioTrack.fromJson(decoded.cast<String, dynamic>())
                : null;
        if (track == null) continue;
        final path = track.path.trim();
        if (path.isEmpty) continue;
        if (File(path).existsSync()) {
          list.add(track.copyWith(isRemote: false, uri: Uri.file(path).toString()));
        }
      } catch (_) {}
    }
    return _dedupeTracks(list);
  }

  List<UserPlaylist> _loadSavedUserPlaylists() {
    final rawList = _prefs?.getStringList(_userPlaylistsKey) ?? const <String>[];
    final list = <UserPlaylist>[];
    for (final raw in rawList) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final playlist = UserPlaylist.fromJson(decoded);
          list.add(playlist.copyWith(
            tracks: playlist.tracks
                .map((track) => track.isRemote ? _sanitizeRemoteTrack(track) : track)
                .toList(growable: false),
          ));
        } else if (decoded is Map) {
          final playlist = UserPlaylist.fromJson(decoded.cast<String, dynamic>());
          list.add(playlist.copyWith(
            tracks: playlist.tracks
                .map((track) => track.isRemote ? _sanitizeRemoteTrack(track) : track)
                .toList(growable: false),
          ));
        }
      } catch (_) {}
    }
    return list;
  }

  AudioTrack _sanitizeRemoteTrack(AudioTrack track) {
    if (!track.isRemote) return track;
    return track.copyWith(
      uri: '',
      remoteStreamUri: null,
      bitrate: null,
      mimeType: track.mimeType.trim().isEmpty ? 'audio/webm' : track.mimeType,
    );
  }

  Future<File> _libraryCacheFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_libraryCacheFileName');
  }

  Future<List<AudioTrack>> _loadCachedLibraryTracks() async {
    try {
      final file = await _libraryCacheFile();
      if (!await file.exists()) return <AudioTrack>[];
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <AudioTrack>[];
      final tracks = <AudioTrack>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final track = AudioTrack.fromJson(item);
          if (!track.isRemote && (track.uri.trim().isNotEmpty || track.path.trim().isNotEmpty)) {
            tracks.add(track.isRemote ? _sanitizeRemoteTrack(track) : track);
          }
        } else if (item is Map) {
          final track = AudioTrack.fromJson(item.cast<String, dynamic>());
          if (!track.isRemote && (track.uri.trim().isNotEmpty || track.path.trim().isNotEmpty)) {
            tracks.add(track.isRemote ? _sanitizeRemoteTrack(track) : track);
          }
        }
      }
      return _dedupeTracks(tracks);
    } catch (_) {
      return <AudioTrack>[];
    }
  }

  Future<void> _persistLibraryCache() async {
    try {
      final file = await _libraryCacheFile();
      final payload = _tracks
          .where((track) => !track.isRemote)
          .map((track) => track.toJson())
          .toList(growable: false);
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  Future<void> _persistOnlineSearchHistory() async {
    await _prefs?.setStringList(_onlineSearchHistoryKey, _onlineSearchHistory.take(12).toList(growable: false));
  }

  Future<void> _persistOnlineRecentTracks() async {
    final payload = _onlineRecentTracks.take(24).map((track) => jsonEncode(track.toJson())).toList(growable: false);
    await _prefs?.setStringList(_onlineRecentTracksKey, payload);
  }

  Future<void> _persistPlayHistory() async {
    final payload = _playHistory.take(60).map((track) => jsonEncode(track.toJson())).toList(growable: false);
    await _prefs?.setStringList(_playHistoryKey, payload);
  }

  Future<void> _persistDownloadedTracks() async {
    final payload = _downloadedTracks.map((track) => jsonEncode(track.toJson())).toList(growable: false);
    await _prefs?.setStringList(_downloadedTracksKey, payload);
  }

  AudioTrack? downloadedVersionOf(AudioTrack track) {
    final targetVideoId = (track.videoId ?? track.id).trim().toLowerCase();
    for (final item in _downloadedTracks) {
      final itemVideoId = (item.videoId ?? item.id).trim().toLowerCase();
      if (targetVideoId.isNotEmpty && itemVideoId == targetVideoId) return item;
      if (item.title.trim().toLowerCase() == track.title.trim().toLowerCase() &&
          item.artist.trim().toLowerCase() == track.artist.trim().toLowerCase()) {
        return item;
      }
    }
    return null;
  }

  bool isDownloaded(AudioTrack track) => downloadedVersionOf(track) != null;

  bool isDownloadInProgress(AudioTrack track) => _downloadInProgress.contains(track.libraryKey);

  Future<void> _persistUserPlaylists() async {
    final payload = _userPlaylists.map((playlist) => jsonEncode(playlist.toJson())).toList(growable: false);
    await _prefs?.setStringList(_userPlaylistsKey, payload);
  }

  Future<void> rememberOnlineSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    _onlineSearchHistory.removeWhere((item) => item.toLowerCase() == normalized.toLowerCase());
    _onlineSearchHistory.insert(0, normalized);
    if (_onlineSearchHistory.length > 12) {
      _onlineSearchHistory.removeRange(12, _onlineSearchHistory.length);
    }
    await _persistOnlineSearchHistory();
    notifyListeners();
    unawaited(_refreshOnlineRecommendations(seedSongs: _onlineSongs));
  }

  Future<void> clearOnlineSearchHistory() async {
    _onlineSearchHistory.clear();
    await _persistOnlineSearchHistory();
    await _refreshOnlineRecommendations(seedSongs: _onlineSongs);
    notifyListeners();
  }

  int _normalizeOnlineSectionIndex(int value) {
    switch (value) {
      case 0:
        return 0;
      case 1:
        return 0;
      case 2:
        return 1;
      case 3:
        return 2;
      case 4:
        return 3;
      case 5:
        return 4;
      case 6:
        return 5;
      default:
        return value.clamp(0, 5);
    }
  }

  void setOnlineSectionIndex(int value) {
    final safe = _normalizeOnlineSectionIndex(value);
    if (_onlineSectionIndex == safe) return;
    _onlineSectionIndex = safe;
    _prefs?.setInt(_onlineSectionKey, safe);
    notifyListeners();
  }

  Future<void> _persistOnlineFavorites() async {
    final ids = _onlineFavoriteIds.toList(growable: false);
    final payload = _onlineFavoriteTracks.values
        .where((track) => _onlineFavoriteIds.contains(track.id))
        .map((track) => jsonEncode(track.toJson()))
        .toList(growable: false);
    await _prefs?.setStringList(_onlineFavoriteIdsKey, ids);
    await _prefs?.setStringList(_onlineFavoritesDataKey, payload);
  }

  Future<void> _rememberOnlineTrack(AudioTrack track) async {
    if (!track.isRemote) return;
    final safeTrack = _sanitizeRemoteTrack(track);
    _onlineRecentTracks.removeWhere((item) => item.libraryKey == safeTrack.libraryKey);
    _onlineRecentTracks.insert(0, safeTrack);
    if (_onlineRecentTracks.length > 24) {
      _onlineRecentTracks.removeRange(24, _onlineRecentTracks.length);
    }
    if (_onlineFavoriteIds.contains(track.id)) {
      _onlineFavoriteTracks[track.id] = safeTrack;
      await _persistOnlineFavorites();
    }
    await _persistOnlineRecentTracks();
  }

  Future<void> _rememberPlaybackHistory(AudioTrack track) async {
    final safeTrack = track.isRemote ? _sanitizeRemoteTrack(track) : track;
    _playHistory.removeWhere((item) => item.libraryKey == safeTrack.libraryKey);
    _playHistory.insert(0, safeTrack);
    if (_playHistory.length > 60) {
      _playHistory.removeRange(60, _playHistory.length);
    }
    await _persistPlayHistory();
    if (_tab == LibraryTab.online && _lastOnlineQuery.isEmpty) {
      unawaited(_refreshOnlineRecommendations(seedSongs: _onlineSongs.isNotEmpty ? _onlineSongs : _onlineRecommendedSongs));
    }
  }

  Future<void> clearPlaybackHistory() async {
    _playHistory.clear();
    await _persistPlayHistory();
    notifyListeners();
  }

  Future<void> _forgetOnlineTrack(String trackId) async {
    _onlineFavoriteTracks.remove(trackId);
    await _persistOnlineFavorites();
  }

  Future<UserPlaylist> createUserPlaylist(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Informe um nome para a playlist');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final playlist = UserPlaylist(
      id: 'pl_${now}',
      name: trimmed,
      tracks: const <AudioTrack>[],
      createdAt: now,
      updatedAt: now,
    );
    _userPlaylists.insert(0, playlist.copyWith(id: 'pl_${now}'));
    await _persistUserPlaylists();
    notifyListeners();
    return _userPlaylists.first;
  }

  Future<void> renameUserPlaylist(String playlistId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final index = _userPlaylists.indexWhere((item) => item.id == playlistId);
    if (index == -1) return;
    _userPlaylists[index] = _userPlaylists[index].copyWith(
      name: trimmed,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persistUserPlaylists();
    notifyListeners();
  }

  Future<void> deleteUserPlaylist(String playlistId) async {
    _userPlaylists.removeWhere((item) => item.id == playlistId);
    await _persistUserPlaylists();
    notifyListeners();
  }

  Future<void> addTrackToUserPlaylist(String playlistId, AudioTrack track) async {
    final index = _userPlaylists.indexWhere((item) => item.id == playlistId);
    if (index == -1) return;
    final playlist = _userPlaylists[index];
    final tracks = List<AudioTrack>.from(playlist.tracks);
    if (!tracks.any((item) => item.libraryKey == track.libraryKey)) {
      tracks.add(track.isRemote ? _sanitizeRemoteTrack(track) : track);
    }
    _userPlaylists[index] = playlist.copyWith(
      tracks: tracks,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persistUserPlaylists();
    notifyListeners();
  }

  Future<void> removeTrackFromUserPlaylist(String playlistId, AudioTrack track) async {
    final index = _userPlaylists.indexWhere((item) => item.id == playlistId);
    if (index == -1) return;
    final playlist = _userPlaylists[index];
    final tracks = playlist.tracks.where((item) => item.libraryKey != track.libraryKey).toList(growable: false);
    _userPlaylists[index] = playlist.copyWith(
      tracks: tracks,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persistUserPlaylists();
    notifyListeners();
  }


  Future<void> _setPlaybackWakeLock(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _systemChannel.invokeMethod<void>('setPlaybackWakeLock', <String, dynamic>{'enabled': enabled});
    } catch (_) {}
  }


  Future<void> _refreshWakeLockForPlaybackAndDownloads() async {
    final processingState = player.processingState;
    final shouldHoldWakeLock = player.playing ||
        _downloadInProgress.isNotEmpty ||
        processingState == ProcessingState.loading ||
        processingState == ProcessingState.buffering;
    await _setPlaybackWakeLock(shouldHoldWakeLock);
  }

  Future<void> _showDownloadNotification(
    AudioTrack track, {
    required bool indeterminate,
    int progress = 0,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _systemChannel.invokeMethod<void>('showDownloadProgress', <String, dynamic>{
        'id': track.libraryKey,
        'title': track.title,
        'subtitle': track.artist,
        'progress': progress.clamp(0, 100),
        'indeterminate': indeterminate,
      });
    } catch (_) {}
  }

  Future<void> _completeDownloadNotification(AudioTrack track, String savedPath) async {
    if (!Platform.isAndroid) return;
    try {
      await _systemChannel.invokeMethod<void>('completeDownload', <String, dynamic>{
        'id': track.libraryKey,
        'title': track.title,
        'subtitle': track.artist,
        'path': savedPath,
      });
    } catch (_) {}
  }

  Future<void> _failDownloadNotification(AudioTrack track, Object error) async {
    if (!Platform.isAndroid) return;
    try {
      await _systemChannel.invokeMethod<void>('failDownload', <String, dynamic>{
        'id': track.libraryKey,
        'title': track.title,
        'subtitle': track.artist,
        'error': '$error',
      });
    } catch (_) {}
  }

  Future<void> _cancelDownloadNotification(AudioTrack track) async {
    if (!Platform.isAndroid) return;
    try {
      await _systemChannel.invokeMethod<void>('cancelDownload', <String, dynamic>{'id': track.libraryKey});
    } catch (_) {}
  }

  Uri? _normalizeRemoteDownloadUri(AudioTrack track) {
    final raw = (track.remoteStreamUri ?? track.uri).trim();
    if (raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    final host = parsed.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost') {
      return null;
    }
    if (parsed.scheme == 'http' || parsed.scheme == 'https') {
      return parsed;
    }
    return null;
  }

  Future<Directory> _preferredDownloadDirectory() async {
    if (Platform.isAndroid) {
      final exactDir = Directory('/storage/emulated/0/Android/data/com.hirumisu.musicapp');
      try {
        if (!await exactDir.exists()) {
          await exactDir.create(recursive: true);
        }
        return exactDir;
      } catch (_) {}

      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final dir = Directory(externalDir.path);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      } catch (_) {}
    }

    final documentsDir = await getApplicationDocumentsDirectory();
    final fallback = Directory('${documentsDir.path}/downloads');
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    return fallback;
  }


  Future<AudioTrack> downloadTrack(AudioTrack track) async {
    final existing = downloadedVersionOf(track);
    if (existing != null) return existing;

    final key = track.libraryKey;
    if (_downloadInProgress.contains(key)) {
      throw Exception('Download já está em andamento');
    }

    _downloadInProgress.add(key);
    _downloadProgress[key] = 0;
    notifyListeners();
    unawaited(_refreshWakeLockForPlaybackAndDownloads());
    unawaited(_showDownloadNotification(track, indeterminate: true, progress: 0));
    try {
      AudioTrack resolved = track;
      if (track.isRemote) {
        final normalizedExisting = _normalizeRemoteDownloadUri(track);
        resolved = normalizedExisting != null
            ? track.copyWith(remoteStreamUri: normalizedExisting.toString(), uri: normalizedExisting.toString())
            : await _resolveMetrolistStream(track, forceRefresh: true);
      }

      Uri? candidate = track.isRemote
          ? _normalizeRemoteDownloadUri(resolved)
          : Uri.tryParse((resolved.uri).trim());
      if (candidate == null || !(candidate.scheme == 'http' || candidate.scheme == 'https')) {
        candidate = await _quickPlayableUriForTrack(resolved, preferResolvedPath: true);
      }
      if (candidate == null || !(candidate.scheme == 'http' || candidate.scheme == 'https')) {
        throw Exception('Não consegui obter um link baixável para essa faixa');
      }

      final dir = await _preferredDownloadDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final safeTitle = resolved.title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_').trim();
      final safeArtist = resolved.artist.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_').trim();
      final lowerPath = candidate.path.toLowerCase();
      final mimeType = resolved.mimeType.toLowerCase();
      final ext = lowerPath.endsWith('.m4a') || mimeType.contains('audio/mp4') || mimeType.contains('mp4')
          ? 'm4a'
          : lowerPath.endsWith('.mp3') || mimeType.contains('mpeg')
              ? 'mp3'
              : 'webm';
      final fileName = '${safeArtist.isEmpty ? 'artist' : safeArtist}_${safeTitle.isEmpty ? 'track' : safeTitle}_${(resolved.videoId ?? resolved.id).replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '')}.$ext';
      final target = File('${dir.path}/$fileName');
      final temp = File('${target.path}.part');

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8)
        ..idleTimeout = const Duration(seconds: 20)
        ..userAgent = 'Mozilla/5.0';
      try {
        final request = await client.getUrl(candidate);
        request.followRedirects = true;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if (resolved.isRemote) {
          final playbackHeaders = _playbackHeadersForUri(candidate);
          playbackHeaders?.forEach(request.headers.set);
        }
        final response = await request.close().timeout(const Duration(seconds: 20));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('HTTP ${response.statusCode}');
        }
        if (await temp.exists()) {
          await temp.delete();
        }
        final sink = temp.openWrite();
        try {
          final totalBytes = response.contentLength;
          var receivedBytes = 0;
          var lastNotifiedProgress = -1;
          var lastNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
          if (totalBytes > 0) {
            _downloadProgress[key] = 0;
            notifyListeners();
            unawaited(_showDownloadNotification(track, indeterminate: false, progress: 0));
          }
          await for (final chunk in response) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              final progress = ((receivedBytes * 100) / totalBytes).floor().clamp(0, 100);
              final now = DateTime.now();
              if (progress != lastNotifiedProgress &&
                  (progress == 100 || progress - lastNotifiedProgress >= 1 || now.difference(lastNotifyAt) >= const Duration(milliseconds: 250))) {
                lastNotifiedProgress = progress;
                lastNotifyAt = now;
                _downloadProgress[key] = progress / 100.0;
                notifyListeners();
                unawaited(_showDownloadNotification(track, indeterminate: false, progress: progress));
              }
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
      } finally {
        client.close(force: true);
      }

      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);

      final downloaded = resolved.copyWith(
        id: 'dl_${resolved.videoId ?? resolved.id}',
        uri: target.uri.toString(),
        path: target.path,
        isRemote: false,
        remoteStreamUri: null,
        mimeType: ext == 'm4a' ? 'audio/mp4' : ext == 'mp3' ? 'audio/mpeg' : 'audio/webm',
        dateAdded: DateTime.now().millisecondsSinceEpoch,
        dateModified: DateTime.now().millisecondsSinceEpoch,
      );

      _downloadedTracks.removeWhere((item) => ((item.videoId ?? item.id).toLowerCase() == (resolved.videoId ?? resolved.id).toLowerCase()) || item.libraryKey == downloaded.libraryKey);
      _downloadedTracks.insert(0, downloaded);
      _tracks = _dedupeTracks(<AudioTrack>[..._tracks, downloaded]);
      await _persistDownloadedTracks();
      _downloadProgress[key] = 1;
      notifyListeners();
      unawaited(_completeDownloadNotification(track, target.path));
      return downloaded;
    } catch (error) {
      unawaited(_failDownloadNotification(track, error));
      rethrow;
    } finally {
      _downloadInProgress.remove(key);
      _downloadProgress.remove(key);
      notifyListeners();
      unawaited(_refreshWakeLockForPlaybackAndDownloads());
    }
  }

  Future<void> _finishBootstrap() async {
    try {
      final hasCachedLibrary = _tracks.isNotEmpty;
      final prefersOnlineRestore = _tab == LibraryTab.online || (_currentTrack?.isRemote ?? false);
      await requestPermissionAndScan(
        showLoading: !hasCachedLibrary && !prefersOnlineRestore,
        preserveExistingOnError: hasCachedLibrary || prefersOnlineRestore,
      );
      final lastId = _prefs?.getString(_lastTrackIdKey);
      if (lastId == null) return;

      final index = _tracks.indexWhere((track) => track.id == lastId || track.libraryKey == lastId);
      if (index != -1) {
        _currentTrack = _tracks[index];
        _currentIndex = index;
        unawaited(ensureArtwork(_currentTrack!));
        notifyListeners();
      }
    } catch (e) {
      _error = 'Erro ao iniciar biblioteca: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> requestPermissionAndScan({bool showLoading = true, bool preserveExistingOnError = false}) async {
    if (showLoading) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    final permissionOk = await _requestAudioPermission();
    _hasPermission = permissionOk;
    if (!permissionOk) {
      _isLoading = false;
      _error = 'Permissão de áudio negada.';
      notifyListeners();
      return;
    }

    await scanLibrary(showLoading: showLoading, preserveExistingOnError: preserveExistingOnError);
  }

  Future<bool> _requestAudioPermission() async {
    try {
      await Permission.notification.request();
    } catch (_) {}

    final audioStatus = await Permission.audio.request();
    if (audioStatus.isGranted || audioStatus.isLimited) {
      return true;
    }

    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted || storageStatus.isLimited;
  }

  Future<void> scanLibrary({bool showLoading = true, bool preserveExistingOnError = false}) async {
    final previousTracks = List<AudioTrack>.from(_tracks);
    final previousQueue = List<AudioTrack>.from(_queue);
    if (showLoading) {
      _isLoading = true;
      _error = null;
    }
    _artworkBytesCache.clear();
    _artworkFutureCache.clear();
    _resolvedPlayablePathCache.clear();
    _lyricsCache.clear();
    _lyricsFutureCache.clear();
    notifyListeners();

    try {
      final cachePath = await _scannerChannel
          .invokeMethod<String>('getAllAudioFilesJsonFile')
          .timeout(const Duration(seconds: 45));

      var rawJson = '[]';
      if (cachePath != null && cachePath.isNotEmpty) {
        final file = File(cachePath);
        if (await file.exists()) {
          rawJson = await file.readAsString();
        }
      } else {
        rawJson = await _scannerChannel
                .invokeMethod<String>('getAllAudioFilesJson')
                .timeout(const Duration(seconds: 45)) ??
            '[]';
      }

      final parsed = jsonDecode(rawJson) as List<dynamic>;
      final loadedTracks = <AudioTrack>[];
      for (final raw in parsed) {
        if (raw is! Map) continue;
        final track = AudioTrack.fromJson(raw.cast<String, dynamic>());
        if (track.uri.isEmpty && track.path.isEmpty) continue;
        loadedTracks.add(track);
      }

      _tracks = _dedupeTracks(<AudioTrack>[...loadedTracks, ..._downloadedTracks]);
      _queue = List<AudioTrack>.from(_tracks);
      unawaited(_persistLibraryCache());

      if (_currentTrack != null) {
        final restoredIndex = _tracks.indexWhere((track) => track.libraryKey == _currentTrack!.libraryKey);
        if (restoredIndex != -1) {
          _currentTrack = _tracks[restoredIndex];
          _currentIndex = restoredIndex;
        } else {
          _currentTrack = null;
          _currentIndex = -1;
        }
      }

      _error = _tracks.isEmpty ? 'Nenhuma música encontrada no aparelho.' : null;
    } on TimeoutException {
      if (preserveExistingOnError && previousTracks.isNotEmpty) {
        _tracks = previousTracks;
        _queue = previousQueue.isNotEmpty ? previousQueue : List<AudioTrack>.from(previousTracks);
      } else {
        _tracks = <AudioTrack>[];
        _queue = <AudioTrack>[];
      }
      _error = 'A leitura da biblioteca demorou demais. Toque em atualizar para tentar novamente.';
    } catch (e) {
      if (preserveExistingOnError && previousTracks.isNotEmpty) {
        _tracks = previousTracks;
        _queue = previousQueue.isNotEmpty ? previousQueue : List<AudioTrack>.from(previousTracks);
      } else {
        _tracks = <AudioTrack>[];
        _queue = <AudioTrack>[];
      }
      _error = 'Falha ao ler músicas: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Uint8List? cachedArtworkFor(AudioTrack track) {
    return track.artworkBytes ?? _artworkBytesCache[track.albumGroupKey] ?? _artworkBytesCache[track.libraryKey];
  }

  Future<Uint8List?> ensureArtwork(AudioTrack track) {
    final embedded = track.artworkBytes;
    if (embedded != null) {
      _artworkBytesCache[track.albumGroupKey] = embedded;
      _artworkBytesCache[track.libraryKey] = embedded;
      return Future<Uint8List?>.value(embedded);
    }

    final albumCached = _artworkBytesCache[track.albumGroupKey];
    if (albumCached != null) {
      return Future<Uint8List?>.value(albumCached);
    }

    final existing = _artworkFutureCache[track.albumGroupKey] ?? _artworkFutureCache[track.libraryKey];
    if (existing != null) return existing;

    final future = _loadArtwork(track);
    _artworkFutureCache[track.albumGroupKey] = future;
    _artworkFutureCache[track.libraryKey] = future;
    return future;
  }

  Future<Uint8List?> _loadArtwork(AudioTrack track) async {
    if (track.isRemote && (track.artworkUrl ?? '').trim().isNotEmpty) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
        try {
          final request = await client.getUrl(Uri.parse(_highQualityArtworkUrl(track.artworkUrl ?? '')));
          final response = await request.close();
          if (response.statusCode >= 200 && response.statusCode < 300) {
            final builder = BytesBuilder(copy: false);
            await for (final chunk in response) {
              builder.add(chunk);
            }
            final bytes = builder.takeBytes();
            _artworkBytesCache[track.albumGroupKey] = bytes;
            _artworkBytesCache[track.libraryKey] = bytes;
            notifyListeners();
            return bytes;
          }
        } finally {
          client.close(force: true);
        }
      } catch (_) {}
      _artworkBytesCache[track.albumGroupKey] = null;
      _artworkBytesCache[track.libraryKey] = null;
      return null;
    }
    try {
      final base64 = await _scannerChannel.invokeMethod<String>('getArtworkBase64', {
        'uri': track.uri,
        'path': track.path,
        'albumId': track.albumId ?? '',
      }).timeout(const Duration(seconds: 12));

      if (base64 == null || base64.isEmpty) {
        _artworkBytesCache[track.albumGroupKey] = null;
        _artworkBytesCache[track.libraryKey] = null;
        return null;
      }

      final bytes = base64Decode(base64);
      _artworkBytesCache[track.albumGroupKey] = bytes;
      _artworkBytesCache[track.libraryKey] = bytes;
      notifyListeners();
      return bytes;
    } catch (_) {
      _artworkBytesCache[track.albumGroupKey] = null;
      _artworkBytesCache[track.libraryKey] = null;
      return null;
    } finally {
      _artworkFutureCache.remove(track.albumGroupKey);
      _artworkFutureCache.remove(track.libraryKey);
    }
  }

  String lyricsFor(AudioTrack track) {
    final cached = _lyricsCache[track.libraryKey];
    if (cached != null && cached.trim().isNotEmpty) return cached.trim();
    return (track.lyrics ?? '').trim();
  }

  bool hasLyricsFor(AudioTrack track) => lyricsFor(track).isNotEmpty;

  bool isLoadingLyricsFor(AudioTrack track) => _lyricsFutureCache.containsKey(track.libraryKey);

  Future<String> ensureLyrics(AudioTrack track) {
    final existingText = lyricsFor(track);
    if (existingText.isNotEmpty) {
      _lyricsCache[track.libraryKey] = existingText;
      return Future<String>.value(existingText);
    }

    final existingFuture = _lyricsFutureCache[track.libraryKey];
    if (existingFuture != null) return existingFuture;

    final future = _loadLyrics(track);
    _lyricsFutureCache[track.libraryKey] = future;
    return future;
  }

  Future<String> _loadLyrics(AudioTrack track) async {
    try {
      String? lyrics;
      if (track.isRemote) {
        lyrics = await _metrolistChannel.invokeMethod<String>('lyrics', {
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'durationMs': track.durationMs,
        }).timeout(const Duration(seconds: 10));
      } else {
        lyrics = await _scannerChannel.invokeMethod<String>('getLyrics', {
          'uri': track.uri,
          'path': track.path,
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
        }).timeout(const Duration(seconds: 6));

        // Se a música local/baixada não tiver letra embutida nas tags,
        // usa o mesmo buscador nativo de letras do Metrolist/LrcLib.
        if ((lyrics ?? '').trim().isEmpty) {
          lyrics = await _metrolistChannel.invokeMethod<String>('lyrics', {
            'title': track.title,
            'artist': track.artist,
            'album': track.album,
            'durationMs': track.durationMs,
          }).timeout(const Duration(seconds: 10));
        }
      }

      final cleaned = (lyrics ?? '').trim();
      _lyricsCache[track.libraryKey] = cleaned;
      if (cleaned.isNotEmpty) {
        notifyListeners();
      }
      return cleaned;
    } catch (_) {
      _lyricsCache.putIfAbsent(track.libraryKey, () => '');
      return '';
    } finally {
      _lyricsFutureCache.remove(track.libraryKey);
    }
  }



  void handleAppResumeFromBackground() {
    var changed = false;

    if (_isOnlineLoading) {
      _isOnlineLoading = false;
      changed = true;
    }

    if (_isLoading && (_tracks.isNotEmpty || _downloadedTracks.isNotEmpty || _tab == LibraryTab.online)) {
      _isLoading = false;
      changed = true;
    }

    if (_isPreparingTrack && (_currentTrack == null || player.processingState == ProcessingState.ready || player.processingState == ProcessingState.completed || player.playing)) {
      _isPreparingTrack = false;
      _pendingTrack = null;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }

    if (_tab == LibraryTab.online && !_hasOnlineHomeContent() && !_isOnlineLoading) {
      unawaited(searchOnline(forceQuery: _lastOnlineQuery, refresh: true));
    }
  }

  void setTab(LibraryTab tabValue) {
    if (_tab == tabValue) return;
    _tab = tabValue;
    _prefs?.setInt(_tabKey, tabValue.index);
    notifyListeners();
    if (tabValue == LibraryTab.online && !_isOnlineLoading) {
      final hasOnlineContent = _hasOnlineHomeContent();
      if (!hasOnlineContent || _lastOnlineQuery.isEmpty) {
        unawaited(searchOnline(forceQuery: searchController.text, refresh: !hasOnlineContent || _lastOnlineQuery.isEmpty));
      }
    }
  }



  List<AudioTrack> _localFavoriteTracks() {
    if (_favoriteIds.isEmpty || _tracks.isEmpty) return const <AudioTrack>[];
    return _tracks.where((track) => _favoriteIds.contains(track.id)).take(24).toList(growable: false);
  }

  Map<String, int> _preferredArtistWeights() {
    final weights = <String, int>{};

    void addArtist(String raw, int value) {
      final normalized = raw.trim().toLowerCase();
      if (normalized.isEmpty || normalized == 'desconhecido') return;
      weights.update(normalized, (current) => current + value, ifAbsent: () => value);
    }

    for (final track in _localFavoriteTracks()) {
      addArtist(track.artist, 14);
    }
    for (final track in _onlineFavoriteTracks.values) {
      addArtist(track.artist, 18);
    }
    for (final track in _playHistory.take(36)) {
      addArtist(track.artist, 8);
    }
    return weights;
  }

  Map<String, int> _preferredGenreWeights() {
    final weights = <String, int>{};

    void addGenre(String raw, int value) {
      final normalized = raw.trim().toLowerCase();
      if (normalized.isEmpty) return;
      weights.update(normalized, (current) => current + value, ifAbsent: () => value);
    }

    for (final track in <AudioTrack>[..._localFavoriteTracks(), ..._onlineFavoriteTracks.values, ..._playHistory.take(30)]) {
      if ((track.genre ?? '').trim().isNotEmpty) {
        addGenre(track.genre!, track.isRemote ? 8 : 6);
      }
    }
    return weights;
  }

  List<String> _topPreferredArtists({int limit = 8}) {
    final entries = _preferredArtistWeights().entries.toList()
      ..sort((a, b) {
        final scoreCmp = b.value.compareTo(a.value);
        if (scoreCmp != 0) return scoreCmp;
        return a.key.compareTo(b.key);
      });
    return entries.take(limit).map((entry) => entry.key).toList(growable: false);
  }

  List<String> _topPreferredGenres({int limit = 4}) {
    final entries = _preferredGenreWeights().entries.toList()
      ..sort((a, b) {
        final scoreCmp = b.value.compareTo(a.value);
        if (scoreCmp != 0) return scoreCmp;
        return a.key.compareTo(b.key);
      });
    return entries.take(limit).map((entry) => entry.key).toList(growable: false);
  }

  List<AudioTrack> _queueForDisplay() {
    return _queue.isNotEmpty ? List<AudioTrack>.from(_queue) : List<AudioTrack>.from(_tracks);
  }

  int _currentQueueIndexForDisplay(List<AudioTrack> queue) {
    if (queue.isEmpty || _currentTrack == null) return -1;
    if (_currentIndex >= 0 && _currentIndex < queue.length && queue[_currentIndex].libraryKey == _currentTrack!.libraryKey) {
      return _currentIndex;
    }
    return queue.indexWhere((track) => track.libraryKey == _currentTrack!.libraryKey);
  }

  String _normalizeRecommendationText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9À-ɏ぀-ヿ㐀-䶿一-鿿\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int _recommendedArtistScore(OnlineArtist artist) {
    final weights = _preferredArtistWeights();
    final normalizedName = _normalizeRecommendationText(artist.name);
    var score = weights[normalizedName] ?? 0;

    for (final entry in weights.entries) {
      if (entry.key == normalizedName) continue;
      if (normalizedName.contains(entry.key) || entry.key.contains(normalizedName)) {
        score += (entry.value / 2).round();
      }
    }

    if (artist.thumbnailUrl.trim().isNotEmpty) score += 3;
    return score;
  }

  List<OnlineArtist> _dedupeRecommendedArtists(Iterable<OnlineArtist> source) {
    final map = <String, OnlineArtist>{};
    for (final artist in source) {
      final key = artist.browseId.trim().isNotEmpty
          ? artist.browseId.trim().toLowerCase()
          : _normalizeRecommendationText(artist.name);
      if (key.isEmpty) continue;
      map.putIfAbsent(key, () => artist);
    }
    return map.values.toList(growable: false);
  }

  List<OnlineArtist> _rankRecommendedArtists(Iterable<OnlineArtist> source) {
    final ranked = _dedupeRecommendedArtists(source).toList(growable: false);
    ranked.sort((a, b) {
      final scoreCmp = _recommendedArtistScore(b).compareTo(_recommendedArtistScore(a));
      if (scoreCmp != 0) return scoreCmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return ranked;
  }

  Future<void> _refreshOnlineRecommendedArtists() async {
    final preferredArtists = _topPreferredArtists(limit: 6);
    if (preferredArtists.isEmpty) {
      _onlineRecommendedArtists = _rankRecommendedArtists(_onlineArtists).take(24).toList(growable: false);
      return;
    }

    final collected = <OnlineArtist>[..._onlineArtists];
    for (final name in preferredArtists) {
      try {
        final results = await _searchArtistsNative(name).timeout(const Duration(seconds: 5));
        collected.addAll(
          results.where((artist) {
            final candidate = _normalizeRecommendationText(artist.name);
            return candidate == name || candidate.contains(name) || name.contains(candidate);
          }).take(4),
        );
      } catch (_) {}
    }

    _onlineRecommendedArtists = _rankRecommendedArtists(collected).take(24).toList(growable: false);
  }

  Future<T> _serializeAudioSourceLoad<T>(Future<T> Function() action) async {
    final previous = _audioSourceLoadBarrier;
    final completer = Completer<void>();
    _audioSourceLoadBarrier = completer.future;
    try {
      await previous.catchError((_) {});
      return await action();
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  List<String> _collectOnlineRecommendationQueries() {
    final ordered = <String>[];
    final seen = <String>{};

    void addTerm(String raw) {
      final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      final key = normalized.toLowerCase();
      if (normalized.isEmpty || key.length < 2 || !seen.add(key)) return;
      ordered.add(normalized);
    }

    for (final artist in _topPreferredArtists(limit: 6)) {
      addTerm(artist);
    }

    for (final genre in _topPreferredGenres(limit: 4)) {
      addTerm(genre);
    }

    for (final search in _onlineSearchHistory.take(6)) {
      addTerm(search);
    }

    for (final track in <AudioTrack>[..._localFavoriteTracks(), ..._onlineFavoriteTracks.values, ..._playHistory.take(20)]) {
      addTerm('${track.artist} ${track.title}');
      if (track.album.trim().isNotEmpty && track.album.trim().toLowerCase() != 'desconhecido') {
        addTerm('${track.artist} ${track.album}');
      }
    }

    return ordered.take(12).toList(growable: false);
  }

  int _onlineRecommendationScore(AudioTrack track) {
    final haystack = '${track.title} ${track.artist} ${track.album} ${(track.genre ?? '')}'.toLowerCase();
    var score = 0;

    final artistWeights = _preferredArtistWeights();
    final genreWeights = _preferredGenreWeights();
    score += artistWeights[track.artist.toLowerCase().trim()] ?? 0;
    final genreKey = (track.genre ?? '').toLowerCase().trim();
    if (genreKey.isNotEmpty) {
      score += genreWeights[genreKey] ?? 0;
    }

    for (final search in _onlineSearchHistory.take(6)) {
      final normalized = search.toLowerCase().trim();
      if (normalized.isEmpty) continue;
      if (haystack.contains(normalized)) {
        score += 120;
      }
      for (final token in normalized.split(RegExp(r'\s+'))) {
        if (token.length < 2) continue;
        if (haystack.contains(token)) score += 18;
      }
    }

    for (final fav in <AudioTrack>[..._localFavoriteTracks(), ..._onlineFavoriteTracks.values]) {
      if (fav.artist.isNotEmpty && fav.artist.toLowerCase() == track.artist.toLowerCase()) score += 110;
      if (fav.album.isNotEmpty && fav.album.toLowerCase() == track.album.toLowerCase()) score += 56;
      if (fav.title.isNotEmpty && fav.title.toLowerCase() == track.title.toLowerCase()) score += 36;
    }

    for (final played in _playHistory.take(30)) {
      if (played.artist.isNotEmpty && played.artist.toLowerCase() == track.artist.toLowerCase()) score += 42;
      if (played.album.isNotEmpty && played.album.toLowerCase() == track.album.toLowerCase()) score += 20;
      if (played.title.isNotEmpty && played.title.toLowerCase() == track.title.toLowerCase()) score += 10;
    }

    if ((track.artworkUrl ?? '').trim().isNotEmpty) score += 8;
    if (track.durationMs > 0) score += 8;
    if ((track.remoteStreamUri ?? '').trim().isNotEmpty) score += 6;
    if ((track.artistId ?? '').trim().isNotEmpty) score += 12;
    if ((track.browseId ?? '').trim().isNotEmpty) score += 10;
    return score;
  }

  List<AudioTrack> _rankOnlineRecommendedSongs(Iterable<AudioTrack> source) {
    final ranked = _dedupeTracks(source).where((track) => track.isRemote).toList();
    ranked.sort((a, b) {
      final scoreCmp = _onlineRecommendationScore(b).compareTo(_onlineRecommendationScore(a));
      if (scoreCmp != 0) return scoreCmp;
      final artistCmp = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      if (artistCmp != 0) return artistCmp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return ranked;
  }

  Future<void> _refreshOnlineRecommendations({List<AudioTrack>? seedSongs}) async {
    final previousRecommendedSongs = List<AudioTrack>.from(_onlineRecommendedSongs);
    final previousRecommendedArtists = List<OnlineArtist>.from(_onlineRecommendedArtists);
    final previousRecommendedPlaylists = List<OnlinePlaylist>.from(_onlineRecommendedPlaylists);

    final base = <AudioTrack>[...?seedSongs];
    final terms = _collectOnlineRecommendationQueries();

    // Fetch songs in parallel instead of sequentially for speed
    final songFutures = terms.take(6).map((term) async {
      try {
        return await _searchSongsNative(term).timeout(const Duration(seconds: 6));
      } catch (_) {
        return const <AudioTrack>[];
      }
    });
    final songResults = await Future.wait(songFutures);
    for (final results in songResults) {
      base.addAll(results.take(28));
    }

    final ranked = _rankOnlineRecommendedSongs(base);
    _onlineRecommendedSongs = ranked.take(80).toList(growable: false);
    if (_onlineRecommendedSongs.isEmpty && seedSongs != null && seedSongs.isNotEmpty) {
      _onlineRecommendedSongs = _dedupeTracks(seedSongs).take(24).toList(growable: false);
    }

    // Fetch artists and personalized playlists in parallel
    final artistFuture = _refreshOnlineRecommendedArtists();
    final playlistFuture = _refreshOnlineRecommendedPlaylists();
    await Future.wait([artistFuture, playlistFuture]);

    final songsChanged = _onlineRecommendedSongs.length != previousRecommendedSongs.length ||
        !_onlineRecommendedSongs.asMap().entries.every((entry) =>
            entry.key < previousRecommendedSongs.length &&
            previousRecommendedSongs[entry.key].libraryKey == entry.value.libraryKey);
    final artistsChanged = _onlineRecommendedArtists.length != previousRecommendedArtists.length ||
        !_onlineRecommendedArtists.asMap().entries.every((entry) =>
            entry.key < previousRecommendedArtists.length &&
            previousRecommendedArtists[entry.key].browseId == entry.value.browseId);
    final playlistsChanged = _onlineRecommendedPlaylists.length != previousRecommendedPlaylists.length ||
        !_onlineRecommendedPlaylists.asMap().entries.every((entry) =>
            entry.key < previousRecommendedPlaylists.length &&
            previousRecommendedPlaylists[entry.key].playlistId == entry.value.playlistId);

    if (songsChanged || artistsChanged || playlistsChanged) {
      notifyListeners();
    }
  }

  Future<void> _refreshOnlineRecommendedPlaylists() async {
    final preferredArtists = _topPreferredArtists(limit: 4);
    final searchTerms = <String>[
      ...preferredArtists,
      ..._onlineSearchHistory.take(4),
    ];
    try {
      final fetched = await _fetchPersonalizedPlaylistsNative(searchTerms)
          .timeout(const Duration(seconds: 12));
      final merged = <OnlinePlaylist>[...fetched, ..._onlinePlaylists, ..._onlineRecommendedPlaylists];
      if (merged.isNotEmpty) {
        _onlineRecommendedPlaylists = _dedupePlaylists(merged).take(40).toList(growable: false);
      }
    } catch (_) {
      final merged = <OnlinePlaylist>[..._onlineRecommendedPlaylists, ..._onlinePlaylists];
      if (merged.isNotEmpty) {
        _onlineRecommendedPlaylists = _dedupePlaylists(merged).take(40).toList(growable: false);
      }
    }
  }

  Future<void> searchOnline({String? forceQuery, bool refresh = false}) async {
    final rawQuery = (forceQuery ?? searchController.text).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_tab != LibraryTab.online && forceQuery == null) return;
    if (!refresh && _lastOnlineQuery == rawQuery) {
      final hasSearchPayload = rawQuery.isEmpty
          ? _hasOnlineHomeContent()
          : (_onlineSongs.isNotEmpty || _onlineAlbums.isNotEmpty || _onlineArtists.isNotEmpty || _onlinePlaylists.isNotEmpty);
      if (hasSearchPayload) {
        return;
      }
    }

    final requestId = ++_onlineSearchRequestSerial;
    final previousSongs = List<AudioTrack>.from(_onlineSongs);
    final previousRecommended = List<AudioTrack>.from(_onlineRecommendedSongs);
    final previousRecommendedPlaylists = List<OnlinePlaylist>.from(_onlineRecommendedPlaylists);
    final previousAlbums = List<OnlineAlbum>.from(_onlineAlbums);
    final previousArtists = List<OnlineArtist>.from(_onlineArtists);
    final previousPlaylists = List<OnlinePlaylist>.from(_onlinePlaylists);
    _isOnlineLoading = true;
    _onlineError = null;
    notifyListeners();
    try {
      final result = await (rawQuery.isEmpty ? _homeNative() : _searchNative(rawQuery))
          .timeout(const Duration(seconds: 14));
      if (requestId != _onlineSearchRequestSerial) {
        return;
      }
      _lastOnlineQuery = rawQuery;
      if (rawQuery.isNotEmpty) {
        unawaited(rememberOnlineSearch(rawQuery));
      }
      var mergedSongs = result.songs;
      var mergedAlbums = result.albums;
      var mergedArtists = result.artists;
      var mergedPlaylists = result.playlists;

      if (rawQuery.isNotEmpty) {
        // O searchSummary do Innertube às vezes devolve poucos cards. Reforça
        // com as buscas filtradas do Metrolist para músicas, álbuns, artistas
        // e playlists, sem depender só do primeiro payload.
        try {
          final extraSongs = await _searchSongsNative(rawQuery).timeout(const Duration(seconds: 7));
          mergedSongs = _dedupeTracks(<AudioTrack>[...mergedSongs, ...extraSongs]);
        } catch (_) {}
        try {
          final extraAlbums = await _searchAlbumsNative(rawQuery).timeout(const Duration(seconds: 6));
          mergedAlbums = _dedupeAlbums(<OnlineAlbum>[...mergedAlbums, ...extraAlbums]);
        } catch (_) {}
        try {
          final extraArtists = await _searchArtistsNative(rawQuery).timeout(const Duration(seconds: 6));
          mergedArtists = _dedupeRecommendedArtists(<OnlineArtist>[...mergedArtists, ...extraArtists]);
        } catch (_) {}
        try {
          final extraPlaylists = await _searchPlaylistsNative(rawQuery).timeout(const Duration(seconds: 6));
          mergedPlaylists = _dedupePlaylists(<OnlinePlaylist>[...mergedPlaylists, ...extraPlaylists]);
        } catch (_) {}
      }

      if (requestId != _onlineSearchRequestSerial) {
        return;
      }

      _onlineSongs = mergedSongs;
      _onlineAlbums = mergedAlbums;
      _onlineArtists = mergedArtists;
      _onlinePlaylists = mergedPlaylists;
      if (rawQuery.isEmpty) {
        _onlineRecommendedSongs = _rankOnlineRecommendedSongs(mergedSongs).take(80).toList(growable: false);
        _onlineRecommendedArtists = _rankRecommendedArtists(mergedArtists).take(24).toList(growable: false);
        // Seed recommended playlists from home content immediately, then refine
        if (mergedPlaylists.isNotEmpty) {
          _onlineRecommendedPlaylists = List<OnlinePlaylist>.from(mergedPlaylists);
        }
        unawaited(_refreshOnlineRecommendations(seedSongs: mergedSongs));
      } else {
        _onlineRecommendedArtists = _rankRecommendedArtists(mergedArtists).take(24).toList(growable: false);
        _onlineRecommendedPlaylists = _dedupePlaylists(mergedPlaylists).take(40).toList(growable: false);
        unawaited(_refreshOnlineRecommendations(seedSongs: _onlineSongs));
      }
      final prewarmTargets = (rawQuery.isEmpty ? _onlineRecommendedSongs : _onlineSongs)
          .where((item) => item.isRemote)
          .take(24)
          .toList(growable: false);
      for (final item in prewarmTargets) {
        unawaited(_prewarmMetrolistStream(item));
      }
      final hasMergedPayload = mergedSongs.isNotEmpty || mergedAlbums.isNotEmpty || mergedArtists.isNotEmpty || mergedPlaylists.isNotEmpty;
      _onlineError = !hasMergedPayload
          ? (rawQuery.isEmpty ? 'Não foi possível carregar sugestões online.' : 'Nenhum resultado online encontrado.')
          : null;
    } catch (e) {
      if (requestId != _onlineSearchRequestSerial) {
        return;
      }

      if (rawQuery.isNotEmpty) {
        try {
          final fallbackSongs = await _searchSongsNative(rawQuery).timeout(const Duration(seconds: 6));
          if (requestId == _onlineSearchRequestSerial && fallbackSongs.isNotEmpty) {
            _lastOnlineQuery = rawQuery;
            unawaited(rememberOnlineSearch(rawQuery));
            var fallbackArtists = const <OnlineArtist>[];
            var fallbackPlaylists = const <OnlinePlaylist>[];
            try {
              fallbackArtists = await _searchArtistsNative(rawQuery).timeout(const Duration(seconds: 5));
            } catch (_) {}
            try {
              fallbackPlaylists = await _searchPlaylistsNative(rawQuery).timeout(const Duration(seconds: 5));
            } catch (_) {}
            _onlineSongs = fallbackSongs;
            _onlineAlbums = const <OnlineAlbum>[];
            _onlineArtists = fallbackArtists;
            _onlinePlaylists = fallbackPlaylists;
            _onlineError = null;
            return;
          }
        } catch (_) {}
      }

      _onlineError = rawQuery.isEmpty ? 'Falha ao carregar sugestões online: $e' : 'Falha na busca online: $e';
      _onlineSongs = previousSongs;
      _onlineRecommendedSongs = previousRecommended;
      _onlineRecommendedPlaylists = previousRecommendedPlaylists;
      _onlineAlbums = previousAlbums;
      _onlineArtists = previousArtists;
      _onlinePlaylists = previousPlaylists;
    } finally {
      if (requestId == _onlineSearchRequestSerial) {
        _isOnlineLoading = false;
        notifyListeners();
      }
    }
  }

  Future<OnlineAlbumPage> loadOnlineAlbum(String browseId) {
    final key = browseId.trim();
    final cached = _onlineAlbumPageFutures[key];
    if (cached != null) return cached;
    final future = _albumNative(key).catchError((Object error, StackTrace stackTrace) {
      _onlineAlbumPageFutures.remove(key);
      Error.throwWithStackTrace(error, stackTrace);
    });
    _onlineAlbumPageFutures[key] = future;
    return future;
  }

  Future<OnlineArtistPage> loadOnlineArtist(String browseId) {
    final key = browseId.trim();
    final cached = _onlineArtistPageFutures[key];
    if (cached != null) return cached;
    final future = _artistNative(key).catchError((Object error, StackTrace stackTrace) {
      _onlineArtistPageFutures.remove(key);
      Error.throwWithStackTrace(error, stackTrace);
    });
    _onlineArtistPageFutures[key] = future;
    return future;
  }

  Future<List<AudioTrack>> loadOnlineArtistAllSongs(OnlineArtistPage page) {
    final key = 'songs:${page.artist.browseId}:${page.songsMoreBrowseId ?? ''}:${page.artist.name.toLowerCase()}';
    final cached = _onlineArtistAllSongsFutures[key];
    if (cached != null) return cached;
    final future = _artistSongsNative(
      artistName: page.artist.name,
      artistBrowseId: page.artist.browseId,
      moreBrowseId: page.songsMoreBrowseId,
      moreParams: page.songsMoreParams,
      seed: page.topSongs,
    ).catchError((Object error, StackTrace stackTrace) {
      _onlineArtistAllSongsFutures.remove(key);
      Error.throwWithStackTrace(error, stackTrace);
    });
    _onlineArtistAllSongsFutures[key] = future;
    return future;
  }

  Future<List<OnlineAlbum>> loadOnlineArtistAllAlbums(OnlineArtistPage page) {
    final key = 'albums:${page.artist.browseId}:${page.albumsMoreBrowseId ?? ''}:${page.artist.name.toLowerCase()}';
    final cached = _onlineArtistAllAlbumsFutures[key];
    if (cached != null) return cached;
    final future = _artistAlbumsNative(
      artistName: page.artist.name,
      artistBrowseId: page.artist.browseId,
      moreBrowseId: page.albumsMoreBrowseId,
      moreParams: page.albumsMoreParams,
      seed: page.albums,
    ).catchError((Object error, StackTrace stackTrace) {
      _onlineArtistAllAlbumsFutures.remove(key);
      Error.throwWithStackTrace(error, stackTrace);
    });
    _onlineArtistAllAlbumsFutures[key] = future;
    return future;
  }

  Future<OnlinePlaylistPage> loadOnlinePlaylist(String playlistId) {
    final key = playlistId.trim();
    final cached = _onlinePlaylistPageFutures[key];
    if (cached != null) return cached;
    final future = _playlistNative(key).catchError((Object error, StackTrace stackTrace) {
      _onlinePlaylistPageFutures.remove(key);
      Error.throwWithStackTrace(error, stackTrace);
    });
    _onlinePlaylistPageFutures[key] = future;
    return future;
  }

  Future<void> playOnlineTrack(AudioTrack track, {List<AudioTrack>? queue}) async {
    final sourceQueue = _dedupeTracks(queue ?? <AudioTrack>[track]);
    final targetQueueIndex = sourceQueue.indexWhere((item) => item.libraryKey == track.libraryKey);
    final pendingQueue = sourceQueue.isEmpty ? <AudioTrack>[track] : sourceQueue;
    final safeTargetIndex = targetQueueIndex >= 0 ? targetQueueIndex : 0;
    final selectedLibraryKey = track.libraryKey;
    final selectionGeneration = ++_trackLoadGeneration;

    _isRecoveringRemoteSource = false;
    _lastRecoveredRemoteTrackKey = null;
    _remoteProxyFallbackKeys.clear();
    try {
      await player.stop().timeout(const Duration(milliseconds: 350));
    } catch (_) {}

    _remoteProxyFallbackKeys.remove(track.libraryKey);
    _pendingTrack = track;
    _currentTrack = track;
    _queue = List<AudioTrack>.from(pendingQueue);
    _currentIndex = safeTargetIndex;
    _error = null;
    _isPreparingTrack = true;
    notifyListeners();
    // Warm the exact Metrolist native stream as soon as the user taps.
    // Wait only a tiny moment: when the stream is already cached this makes
    // playback start instantly; when it is cold we do not block the tap.
    final tapWarmup = _prewarmMetrolistStream(track);
    await tapWarmup.timeout(const Duration(milliseconds: 450), onTimeout: () {});
    if (selectionGeneration != _trackLoadGeneration || _currentTrack?.libraryKey != selectedLibraryKey) {
      return;
    }

    try {
      await _prepareTrackInternal(
        track,
        queue: pendingQueue,
        queueIndex: safeTargetIndex,
      );
      if (_currentTrack?.libraryKey != selectedLibraryKey) {
        return;
      }
      final resolvedTarget = _currentTrack ?? track;
      _pendingTrack = null;
      await _startPlayback();
      unawaited(_rememberOnlineTrack(resolvedTarget));
      unawaited(_rememberPlaybackHistory(resolvedTarget));
      if (pendingQueue.length > 1) {
        for (var offset = 1; offset <= 2 && offset < pendingQueue.length; offset++) {
          final next = pendingQueue[(safeTargetIndex + offset) % pendingQueue.length];
          unawaited(_prewarmMetrolistStream(next));
        }
      }
      notifyListeners();
    } catch (e) {
      if (_currentTrack?.libraryKey == selectedLibraryKey || _pendingTrack?.libraryKey == selectedLibraryKey) {
        _error = null;
        await _handlePlaybackException(e);
        _isPreparingTrack = false;
        _pendingTrack = null;
        _error = null;
        notifyListeners();
      }
    }
  }

  void setSortMode(SortMode mode) {
    _sortMode = mode;
    _prefs?.setInt(_sortModeKey, mode.index);
    notifyListeners();
  }

  int _launchSortValue(AudioTrack track) {
    if (track.yearInt > 0) return track.yearInt;
    if (track.dateModified > 0) return track.dateModified;
    return track.dateAdded;
  }

  int _launchSortValueForTracks(Iterable<AudioTrack> tracks) {
    var best = 0;
    for (final track in tracks) {
      final value = _launchSortValue(track);
      if (value > best) best = value;
    }
    return best;
  }

  void updateScrollOffset(LibraryTab tab, double offset) {
    _scrollOffsets[tab] = offset;
    _prefs?.setDouble('$_scrollKeyPrefix${tab.name}', offset);
  }

  double scrollOffsetFor(LibraryTab tab) => _scrollOffsets[tab] ?? 0;

  List<AudioTrack> _dedupeTracks(Iterable<AudioTrack> source) {
    final deduped = LinkedHashMap<String, AudioTrack>();
    for (final track in source) {
      deduped.putIfAbsent(track.dedupeKey, () => track);
    }
    return deduped.values.toList(growable: false);
  }

  List<OnlineAlbum> _dedupeAlbums(Iterable<OnlineAlbum> source) {
    final seen = <String, OnlineAlbum>{};
    for (final item in source) {
      final key = item.browseId.isNotEmpty
          ? item.browseId
          : (item.playlistId ?? '${item.title}|${item.artist}');
      seen.putIfAbsent(key, () => item);
    }
    return seen.values.toList(growable: false);
  }

  List<OnlinePlaylist> _dedupePlaylists(Iterable<OnlinePlaylist> source) {
    final seen = <String, OnlinePlaylist>{};
    for (final item in source) {
      final key = item.playlistId.isNotEmpty
          ? item.playlistId
          : (item.browseId ?? '${item.title}|${item.author}');
      seen.putIfAbsent(key, () => item);
    }
    return seen.values.toList(growable: false);
  }

  List<AudioTrack> _applySort(List<AudioTrack> source) {
    final sorted = List<AudioTrack>.from(source);
    switch (_sortMode) {
      case SortMode.launch:
        sorted.sort((a, b) {
          final cmp = _launchSortValue(b).compareTo(_launchSortValue(a));
          if (cmp != 0) return cmp;
          final trackCmp = a.trackNumberInt.compareTo(b.trackNumberInt);
          if (trackCmp != 0) return trackCmp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
      case SortMode.alphabetical:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case SortMode.artist:
        sorted.sort((a, b) {
          final artistCmp = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          if (artistCmp != 0) return artistCmp;
          final albumCmp = a.album.toLowerCase().compareTo(b.album.toLowerCase());
          if (albumCmp != 0) return albumCmp;
          final discCmp = a.discNumberInt.compareTo(b.discNumberInt);
          if (discCmp != 0) return discCmp;
          return a.trackNumberInt.compareTo(b.trackNumberInt);
        });
        break;
    }
    return sorted;
  }

  List<AudioTrack> get filteredTracks {
    final filtered = _tracks.where((track) {
      if (track.isRemote) return false;
      if (query.isEmpty) return true;
      return track.title.toLowerCase().contains(query) ||
          track.artist.toLowerCase().contains(query) ||
          track.album.toLowerCase().contains(query);
    });
    return _applySort(_dedupeTracks(filtered));
  }

  Map<String, List<AudioTrack>> get albums {
    final map = LinkedHashMap<String, List<AudioTrack>>();
    for (final track in filteredTracks) {
      map.putIfAbsent(track.albumGroupKey, () => <AudioTrack>[]).add(track);
    }

    final entries = map.entries.toList();
    switch (_sortMode) {
      case SortMode.launch:
        entries.sort((a, b) {
          final cmp = _launchSortValueForTracks(b.value).compareTo(_launchSortValueForTracks(a.value));
          if (cmp != 0) return cmp;
          return a.value.first.album.toLowerCase().compareTo(b.value.first.album.toLowerCase());
        });
        break;
      case SortMode.alphabetical:
        entries.sort((a, b) => a.value.first.album.toLowerCase().compareTo(b.value.first.album.toLowerCase()));
        break;
      case SortMode.artist:
        entries.sort((a, b) {
          final aa = a.value.first.primaryArtistForAlbum.toLowerCase();
          final ba = b.value.first.primaryArtistForAlbum.toLowerCase();
          final cmp = aa.compareTo(ba);
          if (cmp != 0) return cmp;
          return a.value.first.album.toLowerCase().compareTo(b.value.first.album.toLowerCase());
        });
        break;
    }

    return LinkedHashMap<String, List<AudioTrack>>.fromEntries(entries);
  }

  Map<String, List<AudioTrack>> get artists {
    final map = LinkedHashMap<String, List<AudioTrack>>();
    for (final track in filteredTracks) {
      map.putIfAbsent(track.artist, () => <AudioTrack>[]).add(track);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return LinkedHashMap<String, List<AudioTrack>>.fromEntries(entries);
  }

  Map<String, List<AudioTrack>> albumsForArtist(String artistName) {
    final normalizedArtist = artistName.trim().toLowerCase();
    final artistTracks = _tracks.where((track) => !track.isRemote && track.artist.trim().toLowerCase() == normalizedArtist).toList();
    final grouped = LinkedHashMap<String, List<AudioTrack>>();
    for (final track in _applySort(_dedupeTracks(artistTracks))) {
      grouped.putIfAbsent(track.albumGroupKey, () => <AudioTrack>[]).add(track);
    }
    final entries = grouped.entries.toList()
      ..sort((a, b) {
        switch (_sortMode) {
          case SortMode.launch:
            final cmp = _launchSortValueForTracks(b.value).compareTo(_launchSortValueForTracks(a.value));
            if (cmp != 0) return cmp;
            return a.value.first.album.toLowerCase().compareTo(b.value.first.album.toLowerCase());
          case SortMode.alphabetical:
            return a.value.first.album.toLowerCase().compareTo(b.value.first.album.toLowerCase());
          case SortMode.artist:
            return a.value.first.album.toLowerCase().compareTo(b.value.first.album.toLowerCase());
        }
      });
    return LinkedHashMap<String, List<AudioTrack>>.fromEntries(entries);
  }

  List<AudioTrack> get favoriteTracks {
    final favorites = filteredTracks.where((track) => _favoriteIds.contains(track.id));
    return _applySort(_dedupeTracks(favorites));
  }

  List<AudioTrack> get onlineHistoryTracks {
    return _applySort(_dedupeTracks(_onlineRecentTracks));
  }

  List<AudioTrack> get onlineFavoriteTracks {
    return _applySort(_dedupeTracks(_onlineFavoriteTracks.values));
  }

  bool isFavorite(AudioTrack track) {
    if (track.isRemote) {
      return _onlineFavoriteIds.contains(track.id);
    }
    return _favoriteIds.contains(track.id);
  }

  Future<void> toggleFavorite(AudioTrack track) async {
    if (track.isRemote) {
      if (_onlineFavoriteIds.contains(track.id)) {
        _onlineFavoriteIds.remove(track.id);
        await _forgetOnlineTrack(track.id);
      } else {
        _onlineFavoriteIds.add(track.id);
        _onlineFavoriteTracks[track.id] = _sanitizeRemoteTrack(track);
        await _persistOnlineFavorites();
      }
      notifyListeners();
      if (_tab == LibraryTab.online && _lastOnlineQuery.isEmpty) {
        unawaited(_refreshOnlineRecommendations(seedSongs: _onlineSongs.isNotEmpty ? _onlineSongs : _onlineRecommendedSongs));
      }
      return;
    }

    if (_favoriteIds.contains(track.id)) {
      _favoriteIds.remove(track.id);
    } else {
      _favoriteIds.add(track.id);
    }
    await _prefs?.setStringList(_favoritesKey, _favoriteIds.toList());
    notifyListeners();
    if (_tab == LibraryTab.online && _lastOnlineQuery.isEmpty) {
      unawaited(_refreshOnlineRecommendations(seedSongs: _onlineSongs.isNotEmpty ? _onlineSongs : _onlineRecommendedSongs));
    }
  }

  Future<void> toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;
    await _prefs?.setBool(_shuffleKey, _shuffleEnabled);
    notifyListeners();
  }

  Future<void> cycleRepeatMode() async {
    _repeatMode = RepeatMode.values[(_repeatMode.index + 1) % RepeatMode.values.length];
    await _prefs?.setInt(_repeatModeKey, _repeatMode.index);
    await _applyRepeatModeToPlayer();
    notifyListeners();
  }

  Future<void> _applyRepeatModeToPlayer() async {
    final manualQueue = _manualRemoteQueueMode;
    switch (_repeatMode) {
      case RepeatMode.off:
        await player.setLoopMode(LoopMode.off);
        break;
      case RepeatMode.track:
        await player.setLoopMode(LoopMode.one);
        break;
      case RepeatMode.album:
        await player.setLoopMode(manualQueue ? LoopMode.off : (_queue.length > 1 ? LoopMode.all : LoopMode.off));
        break;
    }
  }

  Future<AudioSource> _audioSourceForUri(Uri uri, AudioTrack track, {bool forceProxy = false}) async {
    Uri effectiveUri = uri;
    Map<String, String>? headers;

    if (track.isRemote && (uri.scheme == 'http' || uri.scheme == 'https')) {
      // Online playback now goes through the native Metrolist chunked source
      // at 127.0.0.1. Do not add YouTube headers to the local URL; the native
      // side applies the correct headers/ranges to googlevideo.
      headers = uri.host == '127.0.0.1' || uri.host == 'localhost' ? null : _playbackHeadersForUri(uri);
    } else if (track.isRemote) {
      headers = _playbackHeadersForUri(uri);
    }

    return AudioSource.uri(
      effectiveUri,
      headers: headers,
      tag: await _mediaItemForTrack(track, artUri: await _bestMediaArtUriForTrack(track)),
    );
  }

  Future<MediaItem> _mediaItemForTrack(AudioTrack track, {Uri? artUri}) async {
    final fallbackArtUri = artUri ?? await _bestMediaArtUriForTrack(track);
    return MediaItem(
      id: track.libraryKey,
      title: track.title.trim().isEmpty ? 'Faixa sem nome' : track.title,
      album: track.album,
      artist: track.artist,
      duration: track.durationMs > 0 ? Duration(milliseconds: track.durationMs) : null,
      artUri: fallbackArtUri,
      extras: <String, dynamic>{
        'path': track.path,
        'uri': track.uri,
        'albumId': track.albumId ?? '',
        'trackNumber': track.trackNumber ?? '',
      },
    );
  }

  Future<Uri?> _bestMediaArtUriForTrack(AudioTrack track) async {
    final artworkUrl = _highQualityArtworkUrl(track.artworkUrl ?? '');
    if (artworkUrl.isNotEmpty) {
      final remoteUri = Uri.tryParse(artworkUrl);
      if (remoteUri != null && (remoteUri.scheme == 'http' || remoteUri.scheme == 'https')) {
        return remoteUri;
      }
    }
    return _notificationArtUriForTrack(track);
  }

  Future<Uri?> _notificationArtUriForTrack(AudioTrack track) async {
    final cached = _notificationArtworkUriCache[track.albumGroupKey] ?? _notificationArtworkUriCache[track.libraryKey];
    if (cached != null) {
      return cached;
    }

    final bytes = cachedArtworkFor(track) ?? await ensureArtwork(track).timeout(
      const Duration(seconds: 2),
      onTimeout: () => cachedArtworkFor(track),
    );
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    try {
      final safeKey = track.albumGroupKey
          .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .trim();
      final fileName = '${safeKey.isEmpty ? 'artwork' : safeKey}_${track.albumId ?? track.id}.jpg';
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory('${supportDir.path}/music_app_artwork');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/$fileName');
      if (!await file.exists() || await file.length() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }
      final uri = file.uri;
      _notificationArtworkUriCache[track.albumGroupKey] = uri;
      _notificationArtworkUriCache[track.libraryKey] = uri;
      return uri;
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncNotificationQueue(
    List<AudioTrack> queue,
    int currentIndex, {
    required AudioTrack currentTrack,
  }) async {
    final requestGeneration = ++_notificationSyncGeneration;
    try {
      if (!AudioRuntime.handlerReady || queue.isEmpty) return;

      final safeIndex = currentIndex.clamp(0, queue.length - 1).toInt();
      await AudioRuntime.updateCurrentItem(
        await _mediaItemForTrack(currentTrack, artUri: await _bestMediaArtUriForTrack(currentTrack)),
      );
      if (requestGeneration != _notificationSyncGeneration) return;

      final items = <MediaItem>[];
      for (var i = 0; i < queue.length; i++) {
        final queuedTrack = queue[i];
        items.add(
          await _mediaItemForTrack(
            queuedTrack,
            artUri: await _bestMediaArtUriForTrack(queuedTrack),
          ),
        );
        if (requestGeneration != _notificationSyncGeneration) return;
      }
      await AudioRuntime.updateQueue(items, initialIndex: safeIndex);
      if (requestGeneration != _notificationSyncGeneration) return;
      await AudioRuntime.updateCurrentItem(items[safeIndex]);
    } catch (_) {}
  }

  Future<void> _syncNotificationCurrent(AudioTrack track) async {
    final requestGeneration = ++_notificationSyncGeneration;
    try {
      if (!AudioRuntime.handlerReady) return;
      await AudioRuntime.updateCurrentItem(await _mediaItemForTrack(track));
      if (requestGeneration != _notificationSyncGeneration) return;
      final artUri = await _bestMediaArtUriForTrack(track);
      if (requestGeneration != _notificationSyncGeneration) return;
      await AudioRuntime.updateCurrentItem(
        await _mediaItemForTrack(track, artUri: artUri),
      );
    } catch (_) {}
  }

  Future<void> _prepareTrackInternal(
    AudioTrack track, {
    List<AudioTrack>? queue,
    int queueIndex = -1,
    int autoSeekMs = 0,
  }) async {
    final generation = ++_trackLoadGeneration;

    if (queue != null) {
      _queue = _dedupeTracks(queue);
    }


    _currentTrack = track;
    _currentIndex = queueIndex >= 0 ? queueIndex : _queue.indexWhere((item) => item.libraryKey == track.libraryKey);
    _lastRecoveredRemoteTrackKey = null;
    _lastRecoveredLocalTrackKey = null;
    _error = null;
    _isPreparingTrack = true;

    unawaited(ensureArtwork(track));
    unawaited(ensureLyrics(track));
    notifyListeners();

    try {
      final prepareTimeout = track.isRemote ? const Duration(seconds: 10) : const Duration(seconds: 5);
      Future<void> loadSource() => _setBestAudioSource(track).timeout(
            prepareTimeout,
            onTimeout: () => throw Exception(track.isRemote
                ? 'Timeout no Innertube do Metrolist'
                : 'Timeout ao abrir arquivo local'),
          );

      if (track.isRemote) {
        // Online não pode ficar preso esperando uma seleção antiga terminar.
        // Cada toque novo incrementa _trackLoadGeneration e torna obsoleto o
        // carregamento anterior, então carregamos a fonte atual sem a barreira.
        await loadSource();
      } else {
        await _serializeAudioSourceLoad(loadSource);
      }
      if (generation != _trackLoadGeneration) return;

      if (autoSeekMs > 0) {
        await player.seek(Duration(milliseconds: autoSeekMs));
      }

      _isPreparingTrack = false;
      await _persistCurrentTrack();
      notifyListeners();
    } catch (e) {
      if (generation != _trackLoadGeneration) return;
      _isPreparingTrack = false;
      _error = track.isRemote ? null : 'Falha ao abrir a música: $e';
      notifyListeners();
      rethrow;
    }
  }

  bool _isLikelyRemovableStoragePath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('/storage/emulated/')) return false;
    if (normalized.startsWith('/storage/self/primary/')) return false;
    return RegExp(r'^/storage/[^/]+/').hasMatch(normalized);
  }

  bool _shouldPreferUriPlaybackForLocalTrack(AudioTrack track) {
    if (track.isRemote) return false;
    final rawUri = track.uri.trim();
    final parsed = rawUri.isNotEmpty ? Uri.tryParse(rawUri) : null;
    if (parsed?.scheme == 'content') return true;
    return _isLikelyRemovableStoragePath(track.path);
  }

  Future<Uri?> _quickPlayableUriForTrack(AudioTrack track, {bool preferResolvedPath = false}) async {
    if (track.isRemote) {
      final raw = (track.remoteStreamUri ?? track.uri).trim();
      if (raw.isNotEmpty) {
        final parsed = Uri.tryParse(raw);
        if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
          return parsed;
        }
      }
      return null;
    }

    final rawUri = track.uri.trim();
    final parsedRawUri = rawUri.isNotEmpty ? Uri.tryParse(rawUri) : null;
    final hasContentUri = parsedRawUri?.scheme == 'content';
    final preferUri = _shouldPreferUriPlaybackForLocalTrack(track);

    if (hasContentUri && (preferUri || !preferResolvedPath)) {
      return parsedRawUri;
    }

    final resolvedPath = await _resolvePlayablePath(track);
    if (resolvedPath != null && resolvedPath.trim().isNotEmpty) {
      return Uri.file(resolvedPath.trim());
    }

    if (hasContentUri) {
      return parsedRawUri;
    }

    final directPath = track.path.trim();
    if (directPath.isNotEmpty) {
      return Uri.file(directPath);
    }

    if (parsedRawUri != null) {
      return parsedRawUri;
    }

    return null;
  }

  Future<void> _setBestAudioSource(AudioTrack track) async {
    try {
      await player.stop().timeout(const Duration(milliseconds: 350));
    } catch (_) {}

    var queue = _dedupeTracks(_queue.isNotEmpty ? _queue : <AudioTrack>[track]);
    var requestedQueueIndex = queue.indexWhere((item) => item.libraryKey == track.libraryKey);
    if (requestedQueueIndex < 0) {
      queue = <AudioTrack>[track];
      requestedQueueIndex = 0;
    }

    if (track.isRemote) {
      // Online agora é 100% Metrolist nativo: sem proxy Dart,
      // O Flutter só entrega o videoId para o Innertube/YTPlayerUtils copiado do Metrolist antigo.
      final resolvedTrack = await _resolveMetrolistStream(
        track,
        forceRefresh: _remoteProxyFallbackKeys.contains(track.libraryKey),
      );
      final rawUrl = (resolvedTrack.remoteStreamUri ?? resolvedTrack.uri).trim();
      final remoteUri = Uri.tryParse(rawUrl);
      if (remoteUri == null || !(remoteUri.scheme == 'http' || remoteUri.scheme == 'https')) {
        throw Exception('Innertube do Metrolist não devolveu uma URL googlevideo válida');
      }

      await player.setAudioSource(
        await _audioSourceForUri(remoteUri, resolvedTrack),
        preload: false,
      );

      _manualRemoteQueueMode = true;
      _queue = List<AudioTrack>.from(queue);
      if (requestedQueueIndex >= 0 && requestedQueueIndex < _queue.length) {
        _queue[requestedQueueIndex] = resolvedTrack;
      }
      _currentIndex = requestedQueueIndex;
      _currentTrack = resolvedTrack;
      _pendingTrack = null;
      _isPreparingTrack = false;
      await _applyRepeatModeToPlayer();
      unawaited(_syncNotificationQueue(_queue, _currentIndex, currentTrack: resolvedTrack));
      return;
    }

    // Local: não montar ConcatenatingAudioSource com a biblioteca inteira.
    // Isso era o que travava música local antes de tocar. Carrega só a faixa
    // clicada e mantém a fila só na memória para próximo/anterior.
    final candidate = await _quickPlayableUriForTrack(track, preferResolvedPath: true);
    if (candidate == null) {
      throw Exception('arquivo local sem caminho válido');
    }

    await player.setAudioSource(
      await _audioSourceForUri(candidate, track),
      preload: false,
    );
    // O player carrega uma única fonte local por vez. Se deixarmos o
    // currentIndexStream do just_audio atualizar a UI, ele sempre emite 0 e
    // sobrescreve o player com a primeira faixa do álbum. A fila continua em
    // memória para próximo/anterior; a UI fica no índice manual correto.
    _manualRemoteQueueMode = true;
    _queue = List<AudioTrack>.from(queue);
    _currentIndex = requestedQueueIndex;
    _currentTrack = track;
    _pendingTrack = null;
    _isPreparingTrack = false;
    await _applyRepeatModeToPlayer();
    unawaited(_syncNotificationQueue(_queue, _currentIndex, currentTrack: track));
  }

  Future<String?> _resolvePlayablePath(AudioTrack track) async {
    final cached = _resolvedPlayablePathCache[track.libraryKey];
    if (cached != null && cached.isNotEmpty) {
      try {
        if (await File(cached).exists()) return cached;
      } catch (_) {}
    }

    final originalPath = track.path.trim();
    final shouldAvoidDirectPath = _shouldPreferUriPlaybackForLocalTrack(track);
    if (!shouldAvoidDirectPath && originalPath.isNotEmpty) {
      try {
        if (await File(originalPath).exists()) {
          _resolvedPlayablePathCache[track.libraryKey] = originalPath;
          return originalPath;
        }
      } catch (_) {}
    }

    try {
      final resolved = await _scannerChannel.invokeMethod<String>('ensurePlayableFilePath', {
        'id': track.id,
        'uri': track.uri,
        'path': track.path,
        'mimeType': track.mimeType,
        'title': track.title,
      }).timeout(const Duration(seconds: 4));
      if (resolved != null && resolved.trim().isNotEmpty) {
        _resolvedPlayablePathCache[track.libraryKey] = resolved.trim();
        return resolved.trim();
      }
    } catch (_) {}

    if (!shouldAvoidDirectPath && originalPath.isNotEmpty) {
      return originalPath;
    }

    return null;
  }

  Future<void> _initializeEqualizer() async {
    if (!Platform.isAndroid) {
      _equalizerSupported = false;
      _equalizerAttached = false;
      notifyListeners();
      return;
    }
    try {
      _equalizerSupported = await _equalizerChannel.invokeMethod<bool>('isSupported') ?? false;
      if (!_equalizerSupported) {
        _equalizerAttached = false;
        notifyListeners();
        return;
      }
      await _refreshEqualizerState(notify: false);
      await _attachEqualizerToCurrentSession();
    } catch (_) {
      _equalizerSupported = false;
      _equalizerAttached = false;
      notifyListeners();
    }
  }

  Future<void> _attachEqualizerToCurrentSession() async {
    if (!_equalizerSupported || !Platform.isAndroid) return;
    final sessionId = _audioSessionId;
    if (sessionId == null || sessionId <= 0) return;
    try {
      final response = await _equalizerChannel.invokeMethod<dynamic>(
        'attachToAudioSession',
        <String, dynamic>{'sessionId': sessionId},
      );
      _applyEqualizerPayload(response, notify: false);
      await _equalizerChannel.invokeMethod<dynamic>(
        'setEnabled',
        <String, dynamic>{'enabled': _equalizerEnabled},
      );
      for (final band in _equalizerBands) {
        await _equalizerChannel.invokeMethod<dynamic>(
          'setBandLevel',
          <String, dynamic>{'band': band.index, 'level': band.level},
        );
      }
      await _refreshEqualizerState(notify: true);
    } catch (_) {
      _equalizerAttached = false;
      notifyListeners();
    }
  }

  Future<void> _refreshEqualizerState({bool notify = true}) async {
    if (!Platform.isAndroid) return;
    try {
      final response = await _equalizerChannel.invokeMethod<dynamic>('getState');
      _applyEqualizerPayload(response, notify: notify);
    } catch (_) {}
  }

  void _applyEqualizerPayload(dynamic payload, {bool notify = true}) {
    if (payload is! Map) return;
    final map = payload.cast<Object?, Object?>();
    _equalizerSupported = map['supported'] == true;
    _equalizerAttached = map['attached'] == true;
    _equalizerEnabled = map['enabled'] != false;
    final sessionId = map['sessionId'];
    if (sessionId is num) {
      _audioSessionId = sessionId.toInt();
    }
    final bandsRaw = map['bands'];
    if (bandsRaw is List) {
      final parsed = <EqualizerBandSetting>[];
      for (final item in bandsRaw) {
        if (item is Map) {
          parsed.add(EqualizerBandSetting.fromJson(item.cast<String, dynamic>()));
        }
      }
      if (parsed.isNotEmpty) {
        final savedLevels = _equalizerBands.map((band) => band.level).toList(growable: false);
        for (var i = 0; i < parsed.length && i < savedLevels.length; i++) {
          parsed[i] = parsed[i].copyWith(level: savedLevels[i].clamp(parsed[i].minLevel, parsed[i].maxLevel));
        }
        _equalizerBands = parsed;
      }
    }
    if (notify) notifyListeners();
  }


  String equalizerPresetStorageLabel(EqualizerPreset preset) {
    switch (preset) {
      case EqualizerPreset.balanced:
        return 'balanced';
      case EqualizerPreset.bassBoost:
        return 'bassBoost';
      case EqualizerPreset.soft:
        return 'soft';
      case EqualizerPreset.dynamic:
        return 'dynamic';
      case EqualizerPreset.crisp:
        return 'crisp';
      case EqualizerPreset.trebleBoost:
        return 'trebleBoost';
      case EqualizerPreset.custom:
        return 'custom';
    }
  }

  Future<void> applyEqualizerPreset(EqualizerPreset preset) async {
    if (_equalizerBands.isEmpty) {
      _equalizerPreset = preset;
      await _prefs?.setInt(_equalizerPresetKey, preset.index);
      notifyListeners();
      return;
    }
    if (preset == EqualizerPreset.custom) {
      _equalizerPreset = EqualizerPreset.custom;
      await _prefs?.setInt(_equalizerPresetKey, _equalizerPreset.index);
      notifyListeners();
      return;
    }
    final updated = <EqualizerBandSetting>[];
    for (final band in _equalizerBands) {
      final centerHz = band.centerMilliHz > 0 ? band.centerMilliHz / 1000.0 : 1000.0;
      final targetDb = _targetEqualizerGainDb(preset, centerHz);
      final targetMb = (targetDb * 100).round().clamp(band.minLevel, band.maxLevel);
      updated.add(band.copyWith(level: targetMb));
    }
    _equalizerBands = updated;
    _equalizerPreset = preset;
    await _persistEqualizerBandLevels();
    await _prefs?.setInt(_equalizerPresetKey, preset.index);
    notifyListeners();
    if (_equalizerSupported && Platform.isAndroid) {
      for (final band in _equalizerBands) {
        final response = await _equalizerChannel.invokeMethod<dynamic>(
          'setBandLevel',
          <String, dynamic>{'band': band.index, 'level': band.level},
        );
        _applyEqualizerPayload(response, notify: false);
      }
      notifyListeners();
    }
  }

  double _targetEqualizerGainDb(EqualizerPreset preset, double frequencyHz) {
    final f = frequencyHz <= 0 ? 1000.0 : frequencyHz;
    switch (preset) {
      case EqualizerPreset.balanced:
        return 0;
      case EqualizerPreset.bassBoost:
        if (f <= 80) return 6.0;
        if (f <= 160) return 5.0;
        if (f <= 320) return 3.5;
        if (f <= 1250) return 1.0;
        if (f <= 5000) return -1.0;
        return -2.0;
      case EqualizerPreset.soft:
        if (f <= 125) return 1.5;
        if (f <= 500) return 1.0;
        if (f <= 2000) return 0.5;
        if (f <= 8000) return -1.0;
        return -1.8;
      case EqualizerPreset.dynamic:
        if (f <= 80) return 4.5;
        if (f <= 160) return 3.5;
        if (f <= 320) return 2.0;
        if (f <= 1250) return 0.0;
        if (f <= 5000) return 2.8;
        if (f <= 10000) return 3.8;
        return 2.4;
      case EqualizerPreset.crisp:
        if (f <= 125) return -1.0;
        if (f <= 320) return -0.5;
        if (f <= 800) return 0.5;
        if (f <= 2000) return 2.0;
        if (f <= 5000) return 4.0;
        if (f <= 10000) return 3.2;
        return 1.8;
      case EqualizerPreset.trebleBoost:
        if (f <= 125) return -1.5;
        if (f <= 320) return -1.0;
        if (f <= 1250) return 0.0;
        if (f <= 5000) return 3.0;
        if (f <= 10000) return 4.8;
        return 6.0;
      case EqualizerPreset.custom:
        return 0;
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    _equalizerEnabled = enabled;
    await _prefs?.setBool(_equalizerEnabledKey, enabled);
    notifyListeners();
    if (!_equalizerSupported || !Platform.isAndroid) return;
    final response = await _equalizerChannel.invokeMethod<dynamic>(
      'setEnabled',
      <String, dynamic>{'enabled': enabled},
    );
    _applyEqualizerPayload(response, notify: true);
  }

  Future<void> setEqualizerBandLevel(int bandIndex, int level) async {
    final targetIndex = _equalizerBands.indexWhere((band) => band.index == bandIndex);
    if (targetIndex == -1) return;
    final band = _equalizerBands[targetIndex];
    final clamped = level.clamp(band.minLevel, band.maxLevel);
    _equalizerBands = [
      for (final item in _equalizerBands)
        item.index == bandIndex ? item.copyWith(level: clamped) : item,
    ];
    _equalizerPreset = EqualizerPreset.custom;
    await _persistEqualizerBandLevels();
    await _prefs?.setInt(_equalizerPresetKey, _equalizerPreset.index);
    notifyListeners();
    if (!_equalizerSupported || !Platform.isAndroid) return;
    final response = await _equalizerChannel.invokeMethod<dynamic>(
      'setBandLevel',
      <String, dynamic>{'band': bandIndex, 'level': clamped},
    );
    _applyEqualizerPayload(response, notify: true);
  }

  Future<void> resetEqualizer() async {
    _equalizerBands = [for (final band in _equalizerBands) band.copyWith(level: 0)];
    _equalizerPreset = EqualizerPreset.balanced;
    await _persistEqualizerBandLevels();
    await _prefs?.setInt(_equalizerPresetKey, _equalizerPreset.index);
    notifyListeners();
    if (!_equalizerSupported || !Platform.isAndroid) return;
    final response = await _equalizerChannel.invokeMethod<dynamic>('reset');
    _applyEqualizerPayload(response, notify: true);
  }

  Future<void> _persistEqualizerBandLevels() async {
    final levels = _equalizerBands.map((band) => band.level).toList(growable: false);
    await _prefs?.setString(_equalizerBandLevelsKey, jsonEncode(levels));
  }

  Future<void> prepareTrack(int index, {int autoSeekMs = 0}) async {
    if (index < 0 || index >= _tracks.length) return;
    await _prepareTrackInternal(
      _tracks[index],
      queue: _tracks,
      queueIndex: index,
      autoSeekMs: autoSeekMs,
    );
  }

  /// Prepares an online track immediately when selected (for immediate loading)
  Future<void> prepareOnlineTrack(AudioTrack track) async {
    if (!track.isRemote) return;
    await _prepareTrackInternal(
      track,
      autoSeekMs: 0,
    );
  }

  Future<void> playTrack(AudioTrack track, {List<AudioTrack>? queue}) async {
    final downloaded = track.isRemote ? downloadedVersionOf(track) : null;
    if (downloaded != null) {
      final effectiveQueue = (queue ?? <AudioTrack>[track])
          .map((item) => downloadedVersionOf(item) ?? item)
          .toList(growable: false);
      await playTrack(downloaded, queue: effectiveQueue);
      return;
    }
    if (track.isRemote) {
      await playOnlineTrack(track, queue: queue);
      return;
    }
    final effectiveQueue = _dedupeTracks(queue ?? (_queue.isNotEmpty ? _queue : _tracks));
    if (effectiveQueue.isEmpty) return;

    var queueIndex = effectiveQueue.indexWhere((item) => item.libraryKey == track.libraryKey);
    AudioTrack? targetTrack;

    if (queueIndex != -1) {
      targetTrack = effectiveQueue[queueIndex];
    } else {
      final libraryIndex = _tracks.indexWhere((item) => item.libraryKey == track.libraryKey || item.id == track.id);
      if (libraryIndex == -1) return;
      targetTrack = _tracks[libraryIndex];
      queueIndex = effectiveQueue.indexWhere((item) => item.libraryKey == targetTrack!.libraryKey);
    }

    final expectedGeneration = _trackLoadGeneration + 1;
    await _prepareTrackInternal(
      targetTrack!,
      queue: effectiveQueue,
      queueIndex: queueIndex,
    );
    if (_trackLoadGeneration != expectedGeneration) {
      return;
    }
    await _rememberPlaybackHistory(targetTrack!);
    await _startPlayback();
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    if (_currentTrack == null || player.audioSource == null) {
      final target = _currentTrack;
      if (target != null) {
        await playTrack(target, queue: _queue.isNotEmpty ? _queue : _tracks);
      } else {
        final visibleTracks = filteredTracks;
        if (visibleTracks.isNotEmpty) {
          await playTrack(visibleTracks.first, queue: visibleTracks);
        } else if (_tracks.isNotEmpty) {
          await playTrack(_tracks.first, queue: _tracks);
        }
      }
      return;
    }

    if (player.playing) {
      await player.pause();
    } else {
      await _startPlayback();
    }
    await _persistCurrentTrack();
    notifyListeners();
  }

  List<AudioTrack> get _activeQueue => _queue.isNotEmpty ? _queue : _tracks;

  Future<void> previousTrack({bool wrap = true}) async {
    final queue = _repeatMode == RepeatMode.album && _currentTrack != null
        ? albumTracksFor(_currentTrack!.albumGroupKey)
        : _activeQueue;
    if (queue.isEmpty) return;

    if (_shuffleEnabled && queue.length > 1) {
      final randomIndex = Random().nextInt(queue.length);
      await _prepareTrackInternal(queue[randomIndex], queue: queue, queueIndex: randomIndex);
      await _startPlayback();
      return;
    }

    final currentQueueIndex = _currentTrack == null
        ? -1
        : queue.indexWhere((track) => track.libraryKey == _currentTrack!.libraryKey);
    if (currentQueueIndex <= 0) {
      if (!wrap) {
        await player.seek(Duration.zero);
        notifyListeners();
        return;
      }
      await _prepareTrackInternal(queue.last, queue: queue, queueIndex: queue.length - 1);
      await _startPlayback();
      return;
    }

    final targetIndex = currentQueueIndex - 1;
    await _prepareTrackInternal(queue[targetIndex], queue: queue, queueIndex: targetIndex);
    await _startPlayback();
  }

  Future<bool> nextTrack({bool wrap = true}) async {
    final queue = _repeatMode == RepeatMode.album && _currentTrack != null
        ? albumTracksFor(_currentTrack!.albumGroupKey)
        : _activeQueue;
    if (queue.isEmpty) return false;

    if (_shuffleEnabled && queue.length > 1) {
      final randomIndex = Random().nextInt(queue.length);
      await _prepareTrackInternal(queue[randomIndex], queue: queue, queueIndex: randomIndex);
      await _startPlayback();
      return true;
    }

    final currentQueueIndex = _currentTrack == null
        ? -1
        : queue.indexWhere((track) => track.libraryKey == _currentTrack!.libraryKey);
    if (currentQueueIndex == -1) {
      await _prepareTrackInternal(queue.first, queue: queue, queueIndex: 0);
      await _startPlayback();
      return true;
    }

    if (currentQueueIndex >= queue.length - 1) {
      if (!wrap) {
        await player.pause();
        final duration = player.duration;
        if (duration != null) {
          await player.seek(duration);
        }
        notifyListeners();
        return false;
      }
      await _prepareTrackInternal(queue.first, queue: queue, queueIndex: 0);
      await _startPlayback();
      return true;
    }

    final targetIndex = currentQueueIndex + 1;
    await _prepareTrackInternal(queue[targetIndex], queue: queue, queueIndex: targetIndex);
    await _startPlayback();
    return true;
  }

  Future<void> _startPlayback() async {
    try {
      // just_audio's play() future may stay pending until playback stops. Do not
      // await it here, otherwise every tap can keep the app in a long loading
      // chain even after the player already started.
      unawaited(
        player.play().catchError((Object error, StackTrace stackTrace) {
          unawaited(_handleAsyncPlaybackError(error));
        }),
      );
      _error = null;
      final current = _currentTrack;
      if (current != null) {
        final queue = _queue.isNotEmpty ? _queue : <AudioTrack>[current];
        final index = (_currentIndex >= 0 && _currentIndex < queue.length) ? _currentIndex : 0;
        unawaited(_syncNotificationQueue(queue, index, currentTrack: current));
        if (current.isRemote) {
          unawaited(_watchRemotePlaybackStartup(current, _trackLoadGeneration));
        }
      }
    } catch (error) {
      await _handleAsyncPlaybackError(error);
      return;
    }
    notifyListeners();
  }

  Future<void> _watchRemotePlaybackStartup(AudioTrack track, int generation) async {
    await Future<void>.delayed(const Duration(seconds: 7));
    if (generation != _trackLoadGeneration) return;
    final current = _currentTrack;
    if (current == null || !current.isRemote || current.libraryKey != track.libraryKey) return;
    final pos = player.position;
    final state = player.processingState;
    if (pos <= const Duration(milliseconds: 500) &&
        (state == ProcessingState.loading || state == ProcessingState.buffering || state == ProcessingState.ready)) {
      unawaited(_handlePlaybackException('remote_stuck_at_zero'));
    }
  }

  Future<void> _handleAsyncPlaybackError(Object error) async {
    if (_currentTrack?.isRemote == true) {
      await _handlePlaybackException(error);
      return;
    }
    final recovered = await _handleLocalPlaybackException(error);
    if (recovered) return;
    _error = 'Falha ao reproduzir a música: $error';
    notifyListeners();
  }

  Future<bool> _handleLocalPlaybackException(Object error) async {
    final track = _currentTrack;
    if (track == null || track.isRemote) return false;
    if (_isRecoveringLocalSource || _lastRecoveredLocalTrackKey == track.libraryKey) {
      return false;
    }

    _isRecoveringLocalSource = true;
    _lastRecoveredLocalTrackKey = track.libraryKey;
    try {
      final resolvedPath = await _resolvePlayablePath(track);
      if (resolvedPath == null || resolvedPath.trim().isEmpty) {
        return false;
      }
      final fallbackTrack = track.copyWith(uri: Uri.file(resolvedPath.trim()).toString());
      final queueIndex = _queue.indexWhere((item) => item.libraryKey == track.libraryKey);
      if (queueIndex >= 0 && queueIndex < _queue.length) {
        _queue[queueIndex] = fallbackTrack;
      }
      _currentTrack = fallbackTrack;
      _pendingTrack = fallbackTrack;
      _error = null;
      _isPreparingTrack = true;
      notifyListeners();

      await _setBestAudioSource(fallbackTrack);
      unawaited(
        player.play().catchError((Object playError, StackTrace stackTrace) {
          unawaited(_handleAsyncPlaybackError(playError));
        }),
      );
      _pendingTrack = null;
      _isPreparingTrack = false;
      _error = null;
      return true;
    } catch (_) {
      return false;
    } finally {
      _isRecoveringLocalSource = false;
      notifyListeners();
    }
  }

  Future<void> _handlePlaybackException(Object error) async {
    final track = _currentTrack;
    if (track == null || !track.isRemote) {
      _error = 'Falha ao reproduzir a música: $error';
      notifyListeners();
      return;
    }

    _remoteProxyFallbackKeys.add(track.libraryKey);

    if (_isRecoveringRemoteSource) {
      return;
    }

    _isRecoveringRemoteSource = true;
    _lastRecoveredRemoteTrackKey = track.libraryKey;
    try {
      var baseTrack = track;
      for (var attempt = 0; attempt < 6; attempt++) {
        _markRemoteStreamFailure(baseTrack);
        AudioTrack refreshedTrack;
        try {
          refreshedTrack = await _resolveMetrolistStream(baseTrack, forceRefresh: true).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw Exception('Timeout ao renovar stream'),
          );
        } catch (_) {
          continue;
        }

        final queueIndex = _queue.indexWhere((item) => item.libraryKey == track.libraryKey);
        if (queueIndex >= 0 && queueIndex < _queue.length) {
          _queue[queueIndex] = refreshedTrack;
        }
        _currentTrack = refreshedTrack;
        _pendingTrack = refreshedTrack;
        _error = null;
        _isPreparingTrack = true;
        notifyListeners();

        try {
          _remoteProxyFallbackKeys.add(refreshedTrack.libraryKey);
          await _setBestAudioSource(refreshedTrack).timeout(
            const Duration(seconds: 7),
            onTimeout: () => throw Exception('Timeout ao preparar stream renovado'),
          );
          unawaited(
            player.play().catchError((Object playError, StackTrace stackTrace) {
              unawaited(_handleAsyncPlaybackError(playError));
            }),
          );
          _pendingTrack = null;
          _isPreparingTrack = false;
          _error = null;
          return;
        } catch (_) {
          baseTrack = refreshedTrack;
          _markRemoteStreamFailure(refreshedTrack);
        }
      }

      // Do not surface ExoPlayer's generic "Source error" to the UI. Keep the
      // player screen open and let the user tap again or skip while cached
      // stream failures are already invalidated for the next attempt.
      _pendingTrack = null;
      _isPreparingTrack = false;
      _error = null;
    } finally {
      _isRecoveringRemoteSource = false;
      notifyListeners();
    }
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
    await _persistCurrentTrack();
    notifyListeners();
  }

  Future<void> _persistCurrentTrack() async {
    if (_currentTrack == null) return;
    await _prefs?.setString(_lastTrackIdKey, _currentTrack!.libraryKey);
    await _prefs?.setInt(_lastPositionKey, player.position.inMilliseconds);
  }

  void _handleCurrentIndexChanged(int? index) {
    if (_manualRemoteQueueMode) return;
    if (_isPreparingTrack && (_currentTrack?.isRemote == true || _pendingTrack?.isRemote == true)) return;
    if (index == null || index < 0) return;
    final queue = _activeQueue;
    if (index >= queue.length) return;
    final nextTrack = queue[index];
    if (_currentTrack?.libraryKey == nextTrack.libraryKey && _currentIndex == index) {
      return;
    }
    _pendingTrack = null;
    _currentTrack = nextTrack;
    _currentIndex = index;
    unawaited(ensureArtwork(nextTrack));
    unawaited(ensureLyrics(nextTrack));
    unawaited(_persistCurrentTrack());
    unawaited(_syncNotificationCurrent(nextTrack));
    notifyListeners();
  }

  void _handlePlayerState(PlayerState state) {
    if (!_bootstrapped) {
      notifyListeners();
      return;
    }

    unawaited(_refreshWakeLockForPlaybackAndDownloads());

    if (state.processingState == ProcessingState.ready || state.processingState == ProcessingState.buffering) {
      if (_isPreparingTrack && _currentTrack != null) {
        _isPreparingTrack = false;
      }
    }

    if (state.processingState == ProcessingState.idle && !state.playing && _currentTrack != null && !_isPreparingTrack && player.audioSource != null) {
      if (_currentTrack!.isRemote) {
        unawaited(_handlePlaybackException('idle_source'));
      } else {
        _error ??= 'A música foi carregada, mas o Android não conseguiu iniciar a reprodução.';
      }
    }

    if (state.processingState == ProcessingState.completed) {
      if (_repeatMode == RepeatMode.track && _currentTrack != null) {
        unawaited(seek(Duration.zero));
        unawaited(_startPlayback());
      } else {
        unawaited(nextTrack(wrap: true));
      }
      return;
    }

    notifyListeners();
  }

  List<AudioTrack> albumTracksFor(String albumGroupKey) {
    final list = _tracks.where((track) => track.albumGroupKey == albumGroupKey).toList();
    final deduped = _dedupeTracks(list);
    deduped.sort((a, b) {
      final discCmp = a.discNumberInt.compareTo(b.discNumberInt);
      if (discCmp != 0) return discCmp;
      final trackCmp = a.trackNumberInt.compareTo(b.trackNumberInt);
      if (trackCmp != 0) return trackCmp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return deduped;
  }

  @override
  void dispose() {
    AudioRuntime.setNavigationCallbacks();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _currentIndexSub?.cancel();
    _playbackEventSub?.cancel();
    _audioSessionIdSub?.cancel();
    searchController.dispose();
    unawaited(_setPlaybackWakeLock(false));
    super.dispose();
  }
}
