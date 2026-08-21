import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../providers/music_player_provider.dart';
import '../screens/player_screen.dart';
import '../ui/one_ui_9.dart';
import 'lazy_artwork.dart';

class FloatingPlayerBar extends StatelessWidget {
  const FloatingPlayerBar({super.key, this.metrolistStyle = false});

  final bool metrolistStyle;

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

    if (metrolistStyle) {
      return _MetrolistFloatingPlayer(track: track, progress: progress, provider: provider);
    }
    return _MetrolistFloatingPlayer(track: track, progress: progress, provider: provider);
  }
}

class _MetrolistFloatingPlayer extends StatelessWidget {
  const _MetrolistFloatingPlayer({
    required this.track,
    required this.progress,
    required this.provider,
  });

  final AudioTrack track;
  final double progress;
  final MusicPlayerProvider provider;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final title = track.title.trim().isEmpty ? '-' : track.title;
    final artist = track.artist.trim().isEmpty ? track.album : track.artist;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 7),
      child: SizedBox(
        height: 94,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 27,
              right: 0,
              top: 9,
              bottom: 5,
              child: OneUi9Glass(
                radius: 31,
                blur: 24,
                strong: true,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(31),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PlayerScreen()),
                      );
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Row(
                            children: [
                              const SizedBox(width: 78),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            height: 1.05,
                                            letterSpacing: -0.15,
                                          ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: context.oneUiSecondary,
                                            fontWeight: FontWeight.w600,
                                            height: 1.0,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              _GlassRoundButton(
                                icon: provider.isFavorite(track) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                onTap: () => provider.toggleFavorite(track),
                                active: provider.isFavorite(track),
                              ),
                              _GlassRoundButton(
                                icon: provider.isPlaybackPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                onTap: provider.togglePlayback,
                                large: true,
                              ),
                              _GlassRoundButton(icon: Icons.skip_next_rounded, onTap: provider.nextTrack),
                              const SizedBox(width: 9),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 70,
                          right: 24,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 2.5,
                              backgroundColor: primary.withOpacity(0.10),
                              valueColor: AlwaysStoppedAnimation<Color>(primary.withOpacity(0.92)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 1,
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayerScreen()),
                  );
                },
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 82,
                        height: 82,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 2.6,
                          backgroundColor: context.oneUiOutline.withOpacity(0.55),
                          valueColor: AlwaysStoppedAnimation<Color>(primary.withOpacity(0.95)),
                        ),
                      ),
                      Container(
                        width: 73,
                        height: 73,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(color: context.oneUiShadow, blurRadius: 20, offset: const Offset(0, 10)),
                          ],
                          border: Border.all(color: context.oneUiOutline),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: LazyArtwork(
                          track: track,
                          borderRadius: BorderRadius.circular(25),
                          fallbackIcon: const Icon(Icons.music_note_rounded, color: Colors.white70, size: 28),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
      width: large ? 45 : 38,
      height: 52,
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
            size: large ? 31 : 24,
          ),
        ),
      ),
    );
  }
}
