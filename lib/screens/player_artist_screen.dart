import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../models/online_models.dart';
import '../providers/music_player_provider.dart';
import '../ui/one_ui_9.dart';
import '../widgets/floating_player_bar.dart';
import '../widgets/lazy_artwork.dart';

/// Full artist destination opened when the artist name in the player is tapped.
/// All Futures are cached by [MusicPlayerProvider], so returning to this page
/// does not repeat the same Innertube requests or invalidate the Online Home.
class PlayerArtistScreen extends StatelessWidget {
  const PlayerArtistScreen({super.key, required this.artist});

  final OnlineArtist artist;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<OnlineArtistPage>(
          future: provider.loadOnlineArtist(artist.browseId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _ArtistLoadError(
                artistName: artist.name,
                onBack: () => Navigator.of(context).pop(),
              );
            }
            return _ArtistPageBody(page: snapshot.data!);
          },
        ),
      ),
    );
  }
}

class _ArtistPageBody extends StatelessWidget {
  const _ArtistPageBody({required this.page});

  final OnlineArtistPage page;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final songs = page.topSongs;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: Row(
                  children: [
                    OneUi9IconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Voltar',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    if (songs.isNotEmpty)
                      OneUi9GlassButton(
                        onPressed: () => provider.playTrack(
                          songs.first,
                          queue: songs,
                        ),
                        compact: true,
                        active: true,
                        icon: const Icon(Icons.play_arrow_rounded),
                        child: const Text('Reproduzir'),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  children: [
                    RepaintBoundary(
                      child: ClipOval(
                        child: SizedBox(
                          width: 188,
                          height: 188,
                          child: page.artist.thumbnailUrl.trim().isEmpty
                              ? _artistFallback(context)
                              : Image.network(
                                  page.artist.thumbnailUrl,
                                  fit: BoxFit.cover,
                                  cacheWidth: 520,
                                  cacheHeight: 520,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (_, __, ___) =>
                                      _artistFallback(context),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      page.artist.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Artista • YouTube Music',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: context.oneUiSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            if (songs.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _ArtistSectionHeader(
                  title: 'Músicas',
                  action: 'Mostrar tudo',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _PlayerArtistAllSongsScreen(page: page),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverList.builder(
                  itemCount: songs.take(8).length,
                  itemBuilder: (context, index) {
                    final track = songs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OneUi9Glass(
                        radius: 20,
                        blur: 16,
                        clear: true,
                        showShadow: false,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          leading: SizedBox(
                            width: 54,
                            height: 54,
                            child: LazyArtwork(
                              track: track,
                              size: 54,
                              borderRadius: BorderRadius.circular(14),
                              fallbackIcon:
                                  const Icon(Icons.music_note_rounded),
                            ),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            track.album.isEmpty ? track.artist : track.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            onPressed: () => provider.toggleFavorite(track),
                            icon: Icon(
                              provider.isFavorite(track)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: provider.isFavorite(track)
                                  ? Colors.redAccent
                                  : null,
                            ),
                          ),
                          onTap: () => provider.playTrack(track, queue: songs),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (page.albums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _ArtistSectionHeader(
                  title: 'Álbuns',
                  action: 'Mostrar tudo',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _PlayerArtistAllAlbumsScreen(page: page),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 224,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: page.albums.take(14).length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final album = page.albums[index];
                      return _ArtistMediaCard(
                        title: album.title,
                        subtitle: [album.artist, album.year]
                            .whereType<String>()
                            .where((value) => value.trim().isNotEmpty)
                            .join(' • '),
                        imageUrl: album.thumbnailUrl,
                        circular: false,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _PlayerAlbumScreen(album: album),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (page.playlists.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: _ArtistSectionHeader(title: 'Playlists'),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 224,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: page.playlists.take(14).length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final playlist = page.playlists[index];
                      return _ArtistMediaCard(
                        title: playlist.title,
                        subtitle: playlist.author,
                        imageUrl: playlist.thumbnailUrl,
                        circular: false,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                _PlayerPlaylistScreen(playlist: playlist),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: _playerOverlayPadding(context, provider),
              ),
            ),
          ],
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: FloatingPlayerBar(),
        ),
      ],
    );
  }

  Widget _artistFallback(BuildContext context) => Container(
        color: context.oneUiDark
            ? const Color(0xFF202838)
            : const Color(0xFFE8EDFA),
        alignment: Alignment.center,
        child: const Icon(Icons.person_rounded, size: 88),
      );

  double _playerOverlayPadding(
    BuildContext context,
    MusicPlayerProvider provider,
  ) {
    // Keep content clear of the app-wide floating mini player without
    // subscribing the complete artist page to playback position updates.
    return (provider.currentTrack == null ? 40.0 : 130.0) +
        MediaQuery.paddingOf(context).bottom;
  }
}

class _ArtistSectionHeader extends StatelessWidget {
  const _ArtistSectionHeader({
    required this.title,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          if (action != null)
            OneUi9GlassButton(
              onPressed: onAction,
              compact: true,
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

class _ArtistMediaCard extends StatelessWidget {
  const _ArtistMediaCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.circular,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final bool circular;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 154,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(circular ? 74 : 20),
              child: SizedBox(
                width: 154,
                height: 154,
                child: imageUrl.trim().isEmpty
                    ? const ColoredBox(
                        color: Color(0x332F69FF),
                        child: Icon(Icons.album_rounded, size: 54),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 420,
                        cacheHeight: 420,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.album_rounded,
                          size: 54,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (subtitle.trim().isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.oneUiSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerArtistAllSongsScreen extends StatelessWidget {
  const _PlayerArtistAllSongsScreen({required this.page});

  final OnlineArtistPage page;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    return _TrackFutureScreen(
      title: '${page.artist.name} • Músicas',
      future: provider.loadOnlineArtistAllSongs(page),
    );
  }
}

class _PlayerArtistAllAlbumsScreen extends StatelessWidget {
  const _PlayerArtistAllAlbumsScreen({required this.page});

  final OnlineArtistPage page;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<OnlineAlbum>>(
          future: provider.loadOnlineArtistAllAlbums(page),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final albums = snapshot.data ?? const <OnlineAlbum>[];
            return Column(
              children: [
                _DetailTopBar(title: '${page.artist.name} • Álbuns'),
                Expanded(
                  child: albums.isEmpty
                      ? const Center(child: Text('Nenhum álbum encontrado.'))
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 18,
                            childAspectRatio: 0.74,
                          ),
                          itemCount: albums.length,
                          itemBuilder: (context, index) {
                            final album = albums[index];
                            return _ArtistMediaCard(
                              title: album.title,
                              subtitle: album.artist,
                              imageUrl: album.thumbnailUrl,
                              circular: false,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      _PlayerAlbumScreen(album: album),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayerAlbumScreen extends StatelessWidget {
  const _PlayerAlbumScreen({required this.album});

  final OnlineAlbum album;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    return _TrackPageFutureScreen(
      title: album.title,
      future: provider.loadOnlineAlbum(album.browseId).then((page) => page.tracks),
    );
  }
}

class _PlayerPlaylistScreen extends StatelessWidget {
  const _PlayerPlaylistScreen({required this.playlist});

  final OnlinePlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    return _TrackPageFutureScreen(
      title: playlist.title,
      future: provider
          .loadOnlinePlaylist(playlist.playlistId)
          .then((page) => page.tracks),
    );
  }
}

class _TrackPageFutureScreen extends StatelessWidget {
  const _TrackPageFutureScreen({required this.title, required this.future});

  final String title;
  final Future<List<AudioTrack>> future;

  @override
  Widget build(BuildContext context) {
    return _TrackFutureScreen(title: title, future: future);
  }
}

class _TrackFutureScreen extends StatelessWidget {
  const _TrackFutureScreen({required this.title, required this.future});

  final String title;
  final Future<List<AudioTrack>> future;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<AudioTrack>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final tracks = snapshot.data ?? const <AudioTrack>[];
            return Column(
              children: [
                _DetailTopBar(title: title),
                Expanded(
                  child: tracks.isEmpty
                      ? const Center(child: Text('Nenhuma música encontrada.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                          itemCount: tracks.length,
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              leading: SizedBox(
                                width: 52,
                                height: 52,
                                child: LazyArtwork(
                                  track: track,
                                  size: 52,
                                  borderRadius: BorderRadius.circular(12),
                                  fallbackIcon:
                                      const Icon(Icons.music_note_rounded),
                                ),
                              ),
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () =>
                                  provider.playTrack(track, queue: tracks),
                            );
                          },
                        ),
                ),
                const FloatingPlayerBar(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          OneUi9IconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Voltar',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistLoadError extends StatelessWidget {
  const _ArtistLoadError({required this.artistName, required this.onBack});

  final String artistName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 54),
            const SizedBox(height: 14),
            Text(
              'Não foi possível carregar $artistName.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OneUi9GlassButton(
              onPressed: onBack,
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
