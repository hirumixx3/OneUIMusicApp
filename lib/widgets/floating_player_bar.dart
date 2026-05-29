import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../providers/music_player_provider.dart';
import '../screens/player_screen.dart';
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
    final title = '${track.title}'.trim().isEmpty ? '-' : '${track.title}';
    final artist = '${track.artist}'.trim().isEmpty ? '${track.album}' : '${track.artist}';
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: SizedBox(
        height: 92,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 34,
              right: 0,
              top: 13,
              bottom: 7,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(38),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(38),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const PlayerScreen()),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xD012141A),
                          borderRadius: BorderRadius.circular(38),
                          border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
                          boxShadow: const [
                            BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12)),
                          ],
                        ),
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
                                          color: Colors.white,
                                          height: 1.05,
                                          letterSpacing: 0.1,
                                        ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w600,
                                          height: 1.0,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            _GlassRoundButton(icon: Icons.devices_rounded, onTap: () {}),
                            _GlassRoundButton(
                              icon: provider.isFavorite(track) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              onTap: () => provider.toggleFavorite(track),
                            ),
                            _GlassRoundButton(
                              icon: provider.isPlaybackPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              onTap: provider.togglePlayback,
                              large: true,
                            ),
                            const SizedBox(width: 13),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayerScreen()),
                  );
                },
                child: SizedBox(
                  width: 86,
                  height: 86,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 84,
                        height: 84,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 3,
                          backgroundColor: Colors.white.withOpacity(0.14),
                          valueColor: AlwaysStoppedAnimation<Color>(primary.withOpacity(0.95)),
                        ),
                      ),
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Color(0xAA000000), blurRadius: 20, offset: Offset(0, 10)),
                          ],
                          border: Border.all(color: Colors.white.withOpacity(0.10)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: LazyArtwork(
                          track: track,
                          borderRadius: BorderRadius.circular(40),
                          fallbackIcon: const Icon(Icons.music_note_rounded, color: Colors.white70, size: 28),
                        ),
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.28),
                        ),
                        child: Icon(
                          provider.isPlaybackPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 24,
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
  const _GlassRoundButton({required this.icon, required this.onTap, this.large = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: large ? 48 : 42,
      height: 56,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            icon,
            color: Colors.white.withOpacity(large ? 0.96 : 0.76),
            size: large ? 32 : 25,
          ),
        ),
      ),
    );
  }
}
