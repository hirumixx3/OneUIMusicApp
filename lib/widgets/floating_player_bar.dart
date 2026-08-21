import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../providers/music_player_provider.dart';
import '../screens/player_screen.dart';
import '../ui/one_ui_9.dart';
import 'lazy_artwork.dart';

class FloatingPlayerBar extends StatelessWidget {
  const FloatingPlayerBar({
    super.key,
    this.metrolistStyle = false,
    this.embedded = false,
  });

  final bool metrolistStyle;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final track = provider.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final duration = provider.playbackDuration;
    final position = provider.playbackPosition;
    final totalMs = duration.inMilliseconds;
    final progress = totalMs <= 0
        ? 0.0
        : (position.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble();
    final bufferedProgress = totalMs <= 0
        ? progress
        : (provider.playbackBufferedPosition.inMilliseconds / totalMs)
              .clamp(progress, 1.0)
              .toDouble();

    return _MetrolistFloatingPlayer(
      track: track,
      progress: progress,
      bufferedProgress: bufferedProgress,
      provider: provider,
      embedded: embedded,
    );
  }
}

class _MetrolistFloatingPlayer extends StatelessWidget {
  const _MetrolistFloatingPlayer({
    required this.track,
    required this.progress,
    required this.bufferedProgress,
    required this.provider,
    required this.embedded,
  });

  final AudioTrack track;
  final double progress;
  final double bufferedProgress;
  final MusicPlayerProvider provider;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final title = track.title.trim().isEmpty ? '-' : track.title;
    final artist = track.artist.trim().isEmpty ? track.album : track.artist;
    final bar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 88,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 82,
              child: OneUi9Glass(
                radius: 34,
                blur: 32,
                clear: true,
                showShadow: true,
                tint: context.oneUiFloatingGlassStrong,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 8, 17),
                  child: Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PlayerScreen(),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(19),
                                    border: Border.all(
                                      color: context.oneUiOutline,
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: context.oneUiShadow.withOpacity(
                                          0.78,
                                        ),
                                        blurRadius: 17,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: LazyArtwork(
                                    track: track,
                                    borderRadius: BorderRadius.circular(19),
                                    fallbackIcon: const Icon(
                                      Icons.music_note_rounded,
                                      color: Colors.white70,
                                      size: 25,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              height: 1.05,
                                              letterSpacing: -0.1,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: context.oneUiSecondary,
                                              fontWeight: FontWeight.w600,
                                              height: 1,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      _MiniPlayerAction(
                        icon: provider.isFavorite(track)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        onTap: () => provider.toggleFavorite(track),
                        active: provider.isFavorite(track),
                      ),
                      const SizedBox(width: 6),
                      _MiniPlayerAction(
                        icon: provider.isPlaybackPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onTap: provider.togglePlayback,
                        large: true,
                        active: true,
                      ),
                      const SizedBox(width: 6),
                      _MiniPlayerAction(
                        icon: Icons.skip_next_rounded,
                        onTap: provider.nextTrack,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 70,
              right: 142,
              bottom: 6,
              child: OneUi9FloatingProgressBar(
                value: progress,
                bufferedValue: bufferedProgress,
                onChanged: (fraction) {
                  final duration = provider.playbackDuration;
                  if (duration.inMilliseconds <= 0) return;
                  provider.seek(
                    Duration(
                      milliseconds: (duration.inMilliseconds * fraction)
                          .round(),
                    ),
                  );
                },
                height: 9,
                trackHeight: 4,
                showThumb: false,
                showShadow: true,
              ),
            ),
          ],
        ),
      ),
    );

    if (embedded) return bar;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 7),
      child: bar,
    );
  }
}

class _MiniPlayerAction extends StatelessWidget {
  const _MiniPlayerAction({
    required this.icon,
    required this.onTap,
    this.large = false,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool large;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final size = large ? 42.0 : 37.0;
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        iconSize: large ? 28 : 22,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          side: BorderSide.none,
          minimumSize: Size.square(size),
          shape: const CircleBorder(),
          highlightColor: accent.withOpacity(0.12),
        ),
        icon: Icon(icon, color: active ? accent : context.oneUiForeground),
      ),
    );
  }
}
