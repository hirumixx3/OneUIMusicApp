import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/audio_track.dart';
import '../providers/music_player_provider.dart' as music_provider;
import '../screens/equalizer_screen.dart';
import '../widgets/lazy_artwork.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showLyrics = false;
  String? _lastLyricsTrackKey;

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _toggleLyrics({required bool hasLyrics}) {
    if (!hasLyrics) return;
    setState(() => _showLyrics = !_showLyrics);
  }

  void _ensureLyricsLoaded(music_provider.MusicPlayerProvider provider, AudioTrack track) {
    if (_lastLyricsTrackKey == track.libraryKey) return;
    _lastLyricsTrackKey = track.libraryKey;
    _showLyrics = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.ensureLyrics(track);
    });
  }

  Future<String?> _promptPlaylistName() async {
    final t = AppStrings.of(context);
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t.newPlaylist),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: t.playlistName),
            onSubmitted: (_) {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dialogContext).pop(name);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t.cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.of(dialogContext).pop(name);
              },
              child: Text(t.create),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showAddToPlaylistSheet(AudioTrack track) async {
    final t = AppStrings.of(context);
    final provider = context.read<music_provider.MusicPlayerProvider>();
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.addToPlaylist,
                        style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (provider.userPlaylists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      t.noPlaylistsYet,
                      style: Theme.of(sheetContext).textTheme.bodyMedium,
                    ),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final playlist in provider.userPlaylists)
                        ListTile(
                          leading: const Icon(Icons.queue_music_rounded),
                          title: Text(playlist.name),
                          subtitle: Text(t.playlistSongCount(playlist.tracks.length)),
                          trailing: playlist.tracks.any((item) => item.libraryKey == track.libraryKey)
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () async {
                            await provider.addTrackToUserPlaylist(playlist.id, track);
                            if (!mounted) return;
                            Navigator.of(sheetContext).pop();
                            messenger.showSnackBar(
                              SnackBar(content: Text(t.addedToPlaylist(track.title, playlist.name))),
                            );
                          },
                        ),
                      ListTile(
                        leading: const Icon(Icons.add_circle_outline_rounded),
                        title: Text(t.createNewPlaylist),
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          final name = (await _promptPlaylistName() ?? '').trim();
                          if (name.isEmpty) return;
                          final created = await provider.createUserPlaylist(name);
                          await provider.addTrackToUserPlaylist(created.id, track);
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text(t.addedToPlaylist(track.title, created.name))),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<MapEntry<String, String>> _detailsFor(AudioTrack track, Duration effectiveDuration) {
    final details = <MapEntry<String, String>>[
      MapEntry('Nome', track.title),
      MapEntry('Artista', track.artist),
      MapEntry('Álbum', track.album),
      if ((track.albumArtist ?? '').trim().isNotEmpty) MapEntry('Artista do álbum', track.albumArtist!.trim()),
      if (track.trackNumberInt > 0) MapEntry('Número da faixa', '${track.trackNumberInt}'),
      if (track.discNumberInt > 0) MapEntry('Número do disco', '${track.discNumberInt}'),
      if (track.yearInt > 0) MapEntry('Ano', '${track.yearInt}'),
      if ((track.genre ?? '').trim().isNotEmpty) MapEntry('Gênero', track.genre!.trim()),
      if ((track.composer ?? '').trim().isNotEmpty) MapEntry('Compositor', track.composer!.trim()),
      if ((track.author ?? '').trim().isNotEmpty) MapEntry('Autor', track.author!.trim()),
      if ((track.writer ?? '').trim().isNotEmpty) MapEntry('Escritor', track.writer!.trim()),
      if ((track.bitrate ?? '').trim().isNotEmpty) MapEntry('Bitrate', track.bitrate!.trim()),
      if (track.mimeType.trim().isNotEmpty) MapEntry('Tipo', track.mimeType.trim()),
      MapEntry('Duração', _format(effectiveDuration)),
      if (track.path.trim().isNotEmpty) MapEntry('Caminho', track.path.trim()),
      if (track.uri.trim().isNotEmpty) MapEntry('URI', track.uri.trim()),
    ];
    return details;
  }

  Widget _queueSection(
    BuildContext context,
    music_provider.MusicPlayerProvider provider,
    AudioTrack currentTrack,
  ) {
    final t = AppStrings.of(context);
    final previousTracks = provider.queuePreviousTracks;
    final nextTracks = provider.queueNextTracks;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF252632) : const Color(0xFFE1E4ED);
    final surface = isDark ? const Color(0xFF12151D) : Colors.white;
    final secondary = isDark ? Colors.white70 : Colors.black54;

    if (previousTracks.isEmpty && nextTracks.isEmpty) {
      return const SizedBox.shrink();
    }

    Future<void> playQueuedTrack(AudioTrack item) async {
      await provider.playTrack(item, queue: provider.playbackQueue);
    }

    Widget buildGroup(String title, List<AudioTrack> tracks, IconData icon) {
      if (tracks.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: secondary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: secondary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...tracks.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => playQueuedTrack(item),
                child: Ink(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF171A24) : const Color(0xFFF7F8FD),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF7395FF).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: LazyArtwork(
                                track: item,
                                borderRadius: BorderRadius.circular(12),
                                fit: BoxFit.cover,
                                fallbackIcon: const Icon(Icons.music_note_rounded, size: 18, color: Colors.white),
                              ),
                            ),
                            if (item.libraryKey == currentTrack.libraryKey)
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF7395FF),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.graphic_eq_rounded,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: secondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _format(item.duration),
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: secondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface.withOpacity(isDark ? 0.72 : 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.playQueue,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (nextTracks.isNotEmpty) ...[
            const SizedBox(height: 14),
            buildGroup(t.nextInQueue, nextTracks, Icons.skip_next_rounded),
          ],
          if (previousTracks.isNotEmpty) ...[
            if (nextTracks.isNotEmpty) const SizedBox(height: 6),
            buildGroup(t.previousInQueue, previousTracks, Icons.skip_previous_rounded),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.watch<music_provider.MusicPlayerProvider>();
    final track = provider.activeDisplayTrack;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (track == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Text(
              t.noTrackPlaying,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      );
    }

    _ensureLyricsLoaded(provider, track);
    final lyricsText = provider.lyricsFor(track);
    final hasLyrics = lyricsText.isNotEmpty;
    final loadingLyrics = provider.isLoadingLyricsFor(track);
    final showLyrics = _showLyrics && hasLyrics;
    final screenWidth = MediaQuery.of(context).size.width;
    final artworkSize = (screenWidth - 56).clamp(260.0, 360.0).toDouble();
    final secondary = isDark ? Colors.white70 : Colors.black54;
    final surface = isDark ? const Color(0xFF12151D) : Colors.white;
    final waitingRemoteStart = false; // não bloqueia a tela com 'preparando' para streams online
    final border = isDark ? const Color(0xFF252632) : const Color(0xFFE1E4ED);

    return Scaffold(
      body: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF090A0E), Color(0xFF111827), Color(0xFF090A0E)]
                  : const [Color(0xFFF5F6FB), Color(0xFFEAEFFF), Color(0xFFF5F6FB)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: StreamBuilder<Duration?>(
              stream: provider.playbackDurationStream,
              builder: (context, durationSnapshot) {
                final totalDuration = durationSnapshot.data ?? provider.playbackDuration;
                final trackDetails = _detailsFor(track, totalDuration);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        _topBarActionButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t.playingNow,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: math.min(MediaQuery.of(context).size.width * 0.5, 210),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _topBarActionButton(
                                    icon: Icons.equalizer_rounded,
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const EqualizerScreen()),
                                    ),
                                  ),
                                  _topBarActionButton(
                                    icon: Icons.playlist_add_rounded,
                                    onPressed: () => _showAddToPlaylistSheet(track),
                                  ),
                                  if (track.isRemote)
                                    _topBarActionButton(
                                      onPressed: provider.isDownloadInProgress(track)
                                          ? null
                                          : () async {
                                              final messenger = ScaffoldMessenger.of(context);
                                              messenger.showSnackBar(
                                                SnackBar(content: Text('Iniciando download de ${track.title}...')),
                                              );
                                              try {
                                                final downloaded = await provider.downloadTrack(track);
                                                if (!mounted) return;
                                                messenger.showSnackBar(
                                                  SnackBar(content: Text('Baixada em ${downloaded.path}')),
                                                );
                                              } catch (error) {
                                                if (!mounted) return;
                                                messenger.showSnackBar(
                                                  SnackBar(content: Text('${t.downloadFailed}: $error')),
                                                );
                                              }
                                            },
                                      iconWidget: provider.isDownloadInProgress(track)
                                          ? SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                value: provider.downloadProgressFor(track),
                                              ),
                                            )
                                          : Icon(
                                              provider.isDownloaded(track)
                                                  ? Icons.download_done_rounded
                                                  : Icons.download_rounded,
                                            ),
                                    ),
                                  _topBarActionButton(
                                    onPressed: () => provider.toggleFavorite(track),
                                    iconWidget: Icon(
                                      provider.isFavorite(track)
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: provider.isFavorite(track) ? Colors.redAccent : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: artworkSize,
                      height: artworkSize,
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(color: border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 24,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: hasLyrics ? () => _toggleLyrics(hasLyrics: hasLyrics) : null,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: showLyrics
                                    ? Padding(
                                        key: ValueKey('lyrics-${track.libraryKey}'),
                                        padding: const EdgeInsets.all(12),
                                        child: _LyricsArtworkCard(
                                          lyrics: lyricsText,
                                          isDark: isDark,
                                        ),
                                      )
                                    : SizedBox.expand(
                                        child: _CoverArtworkCard(
                                          key: ValueKey('cover-${track.libraryKey}'),
                                          track: track,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          if ((hasLyrics || loadingLyrics) && !showLyrics)
                            Positioned(
                              left: 24,
                              bottom: 24,
                              child: GestureDetector(
                                onTap: hasLyrics ? () => _toggleLyrics(hasLyrics: hasLyrics) : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.42),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: Colors.white.withOpacity(0.16)),
                                  ),
                                  child: Text(
                                    loadingLyrics && !hasLyrics ? 'Buscando letra...' : 'Mostrar letra',
                                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ),
                            ),

                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      track.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${track.artist} • ${track.album}',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: secondary,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 18),
                    if (waitingRemoteStart)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Preparando reprodução online...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: secondary),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _smallActionChip(
                          context,
                          icon: provider.shuffleEnabled ? Icons.shuffle_on_rounded : Icons.shuffle_rounded,
                          label: t.shuffle,
                          active: provider.shuffleEnabled,
                          onTap: provider.toggleShuffle,
                        ),
                        const SizedBox(width: 10),
                        _smallActionChip(
                          context,
                          icon: Icons.repeat_rounded,
                          label: provider.repeatLabel,
                          active: provider.repeatMode != music_provider.RepeatMode.off,
                          onTap: provider.cycleRepeatMode,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (waitingRemoteStart)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Preparando reprodução online...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: secondary),
                            ),
                          ],
                        ),
                      ),
                    StreamBuilder<Duration>(
                      stream: provider.playbackPositionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? provider.playbackPosition;
                        final max = totalDuration.inMilliseconds <= 0
                            ? 1.0
                            : totalDuration.inMilliseconds.toDouble();
                        final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();
                        return Column(
                          children: [
                            MonetWavyProgressBar(
                              value: value,
                              min: 0,
                              max: max,
                              onChanged: (newValue) {
                                provider.seek(Duration(milliseconds: newValue.toInt()));
                              },
                              playedColor: const Color(0xFFD2C0FF),
                              remainingColor: isDark ? const Color(0xFF4B4E5A) : const Color(0xFFD7DBE8),
                              height: 34,
                            ),
                            Row(
                              children: [
                                Text(_format(position)),
                                const Spacer(),
                                Text(_format(totalDuration)),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          onPressed: provider.previousTrack,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(62, 62),
                            backgroundColor: surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                              side: BorderSide(color: border),
                            ),
                          ),
                          iconSize: 34,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        const SizedBox(width: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF7395FF),
                            foregroundColor: const Color(0xFF0D172B),
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(24),
                          ),
                          onPressed: provider.togglePlayback,
                          child: Icon(
                            provider.isPlaybackPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 42,
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton.filledTonal(
                          onPressed: provider.nextTrack,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(62, 62),
                            backgroundColor: surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                              side: BorderSide(color: border),
                            ),
                          ),
                          iconSize: 34,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _queueSection(context, provider, track),
                    if (provider.queuePreviousTracks.isNotEmpty || provider.queueNextTracks.isNotEmpty)
                      const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: surface.withOpacity(isDark ? 0.72 : 0.94),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.musicTags,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 14),
                          ...trackDetails.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 118,
                                    child: Text(
                                      '${entry.key}:',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: secondary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      entry.value,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            height: 1.35,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }


  Widget _topBarActionButton({
    IconData? icon,
    Widget? iconWidget,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      splashRadius: 22,
      onPressed: onPressed,
      icon: iconWidget ?? Icon(icon),
    );
  }

  Widget _smallActionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      selected: active,
      onSelected: (_) => onTap(),
      label: Text(label),
      avatar: Icon(icon, size: 18),
      showCheckmark: false,
    );
  }
}

class _CoverArtworkCard extends StatelessWidget {
  const _CoverArtworkCard({super.key, required this.track});

  final AudioTrack track;

  @override
  Widget build(BuildContext context) {
    final artworkUrl = (track.artworkUrl ?? '').trim();
    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: artworkUrl.isNotEmpty
            ? Image.network(
                artworkUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => LazyArtwork(
                  track: track,
                  borderRadius: BorderRadius.circular(28),
                  fit: BoxFit.cover,
                  fallbackIcon: const Icon(Icons.music_note_rounded, size: 120, color: Colors.white),
                ),
              )
            : LazyArtwork(
                track: track,
                borderRadius: BorderRadius.circular(28),
                fit: BoxFit.cover,
                fallbackIcon: const Icon(Icons.music_note_rounded, size: 120, color: Colors.white),
              ),
      ),
    );
  }
}

class _LyricsArtworkCard extends StatelessWidget {
  const _LyricsArtworkCard({
    super.key,
    required this.lyrics,
    required this.isDark,
  });

  final String lyrics;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final lines = _parseSyncedLyrics(lyrics);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF3B2635), Color(0xFF201820)]
              : const [Color(0xFFF5E6F7), Color(0xFFE9D7F3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Letras de LrcLib',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: lines.isEmpty
                ? SingleChildScrollView(
                    child: Text(
                      lyrics.replaceAll(RegExp(r'\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]'), '').trim(),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.45,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                    ),
                  )
                : StreamBuilder<Duration>(
                    stream: context.read<music_provider.MusicPlayerProvider>().playbackPositionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      var active = 0;
                      for (var i = 0; i < lines.length; i++) {
                        if (lines[i].time <= position) active = i;
                      }
                      final start = math.max(0, active - 3);
                      final end = math.min(lines.length, active + 5);
                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: end - start,
                        itemBuilder: (context, rawIndex) {
                          final index = start + rawIndex;
                          final isActive = index == active;
                          return AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.18,
                                  color: isActive
                                      ? (isDark ? Colors.white : Colors.black)
                                      : (isDark ? Colors.white24 : Colors.black26),
                                  fontSize: isActive ? 26 : 22,
                                ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(lines[index].text),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static List<_SyncedLyricLine> _parseSyncedLyrics(String raw) {
    final result = <_SyncedLyricLine>[];
    final regex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)');
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final match = regex.firstMatch(line.trim());
      if (match == null) continue;
      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
      final fracRaw = match.group(3) ?? '0';
      final millis = fracRaw.length == 3
          ? int.tryParse(fracRaw) ?? 0
          : fracRaw.length == 2
              ? (int.tryParse(fracRaw) ?? 0) * 10
              : (int.tryParse(fracRaw) ?? 0) * 100;
      final text = (match.group(4) ?? '').trim();
      if (text.isEmpty) continue;
      result.add(_SyncedLyricLine(Duration(minutes: minutes, seconds: seconds, milliseconds: millis), text));
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }
}

class _SyncedLyricLine {
  const _SyncedLyricLine(this.time, this.text);
  final Duration time;
  final String text;
}


class MonetWavyProgressBar extends StatefulWidget {
  const MonetWavyProgressBar({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.playedColor,
    required this.remainingColor,
    this.height = 34,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final Color playedColor;
  final Color remainingColor;
  final double height;

  @override
  State<MonetWavyProgressBar> createState() => _MonetWavyProgressBarState();
}

class _MonetWavyProgressBarState extends State<MonetWavyProgressBar> with SingleTickerProviderStateMixin {
  bool _dragging = false;
  double? _dragValue;
  late final AnimationController _waveController;

  double get _effectiveValue => (_dragging ? _dragValue : widget.value) ?? widget.value;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  void _updateValue(Offset localPosition, double width) {
    if (width <= 0) return;
    final ratio = (localPosition.dx / width).clamp(0.0, 1.0);
    final next = widget.min + ((widget.max - widget.min) * ratio);
    setState(() {
      _dragValue = next;
    });
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final value = _effectiveValue.clamp(widget.min, widget.max);
    final totalRange = (widget.max - widget.min) <= 0 ? 1.0 : (widget.max - widget.min);
    final playedFraction = ((value - widget.min) / totalRange).clamp(0.0, 1.0);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final thumbX = width * playedFraction;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _updateValue(details.localPosition, width),
            onHorizontalDragStart: (details) {
              setState(() {
                _dragging = true;
              });
              _updateValue(details.localPosition, width);
            },
            onHorizontalDragUpdate: (details) => _updateValue(details.localPosition, width),
            onHorizontalDragEnd: (_) {
              setState(() {
                _dragging = false;
                _dragValue = null;
              });
            },
            onHorizontalDragCancel: () {
              setState(() {
                _dragging = false;
                _dragValue = null;
              });
            },
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MonetWavyProgressPainter(
                        playedFraction: playedFraction,
                        playedColor: widget.playedColor,
                        remainingColor: widget.remainingColor,
                        phase: _waveController.value,
                      ),
                    ),
                  ),
                  Positioned(
                    left: math.max(0, math.min(width - 22, thumbX - 11)),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: widget.playedColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.playedColor.withOpacity(0.45),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MonetWavyProgressPainter extends CustomPainter {
  _MonetWavyProgressPainter({
    required this.playedFraction,
    required this.playedColor,
    required this.remainingColor,
    required this.phase,
  });

  final double playedFraction;
  final Color playedColor;
  final Color remainingColor;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final playedWidth = size.width * playedFraction;

    final remainingPaint = Paint()
      ..color = remainingColor.withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(playedWidth, centerY), Offset(size.width, centerY), remainingPaint);

    if (playedWidth <= 0) return;

    final playedPaint = Paint()
      ..shader = LinearGradient(
        colors: [playedColor.withOpacity(0.82), playedColor],
      ).createShader(Rect.fromLTWH(0, 0, playedWidth, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    final playedPath = _buildWavePath(size, playedWidth);
    final glowPaint = Paint()
      ..color = playedColor.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawPath(playedPath, glowPaint);
    canvas.drawPath(playedPath, playedPaint);
  }

  Path _buildWavePath(Size size, double playedWidth) {
    final path = Path();
    final baseline = size.height / 2;
    final amplitude = math.min(5.2, size.height * 0.17);
    const wavelength = 36.0;
    final phaseShift = phase * wavelength * 1.8;

    for (double x = 0; x <= playedWidth; x += 1) {
      final progress = playedWidth <= 0 ? 0.0 : (x / playedWidth).clamp(0.0, 1.0);
      final envelope = 0.82 + (0.18 * math.sin(progress * math.pi));
      final y = baseline + math.sin(((x + phaseShift) / wavelength) * 2 * math.pi) * amplitude * envelope;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _MonetWavyProgressPainter oldDelegate) {
    return oldDelegate.playedFraction != playedFraction ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.remainingColor != remainingColor ||
        oldDelegate.phase != phase;
  }
}
