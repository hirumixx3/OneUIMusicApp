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

    return _MetrolistFloatingPlayer(
      track: track,
      progress: progress,
      provider: provider,
      embedded: embedded,
    );
  }
}

class _MetrolistFloatingPlayer extends StatelessWidget {
  const _MetrolistFloatingPlayer({
    required this.track,
    required this.progress,
    required this.provider,
    required this.embedded,
  });

  final AudioTrack track;
  final double progress;
  final MusicPlayerProvider provider;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final title = track.title.trim().isEmpty ? '-' : track.title;
    final artist = track.artist.trim().isEmpty ? track.album : track.artist;
    final bar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 72,
        child: OneUi9Glass(
          radius: 30,
          blur: 28,
          strong: true,
          showShadow: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(19),
                              border: Border.all(color: context.oneUiOutline),
                              boxShadow: [
                                BoxShadow(
                                  color: context.oneUiShadow.withOpacity(0.65),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: LazyArtwork(
                              track: track,
                              borderRadius: BorderRadius.circular(18),
                              fallbackIcon: const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white70,
                                size: 25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: context.oneUiSecondary,
                                        fontWeight: FontWeight.w600,
                                        height: 1,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          _GlassRoundButton(
                            icon: provider.isFavorite(track)
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            onTap: () => provider.toggleFavorite(track),
                            active: provider.isFavorite(track),
                          ),
                          _GlassRoundButton(
                            icon: provider.isPlaybackPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onTap: provider.togglePlayback,
                            large: true,
                          ),
                          _GlassRoundButton(
                            icon: Icons.skip_next_rounded,
                            onTap: provider.nextTrack,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 76,
                    right: 22,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2.5,
                        backgroundColor: primary.withOpacity(0.10),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          primary.withOpacity(0.92),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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

class _GlassRoundButton extends StatelessWidget {
  const _GlassRoundButton({required this.icon, required this.onTap, this.large = false, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool large;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: large ? 42 : 36,
      height: 50,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            icon,
            color: active
                ? const Color(0xFFFF6B8A)
                : (large ? context.oneUiForeground : context.oneUiSecondary),
            size: large ? 29 : 23,
          ),
        ),
      ),
    );
  }
}
