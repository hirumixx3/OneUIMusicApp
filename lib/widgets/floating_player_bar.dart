import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/music_player_provider.dart';
import '../screens/player_screen.dart';
import 'lazy_artwork.dart';

class FloatingPlayerBar extends StatelessWidget {
  const FloatingPlayerBar({super.key});

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

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlayerScreen()),
                );
              },
              child: Container(
                height: 76,
                constraints: const BoxConstraints(minHeight: 76, maxHeight: 76),
                decoration: BoxDecoration(
                  color: const Color(0xA61A1B17),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 26,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        backgroundColor: Colors.white.withOpacity(0.06),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary.withOpacity(0.85),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 54,
                              height: 54,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: LazyArtwork(
                                  track: track,
                                  borderRadius: BorderRadius.circular(16),
                                  fallbackIcon: const Icon(Icons.music_note_rounded, color: Colors.white70, size: 26),
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
                                    track.title.trim().isEmpty ? '-' : track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: 0.1,
                                          height: 1.05,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    track.artist.trim().isEmpty ? track.album : track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Colors.white70,
                                          height: 1.05,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            _GlassControlButton(
                              icon: Icons.devices_rounded,
                              onTap: () {},
                            ),
                            _GlassControlButton(
                              icon: provider.isFavorite(track) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              onTap: () => provider.toggleFavorite(track),
                            ),
                            _GlassControlButton(
                              icon: provider.isPlaybackPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              onTap: provider.togglePlayback,
                              emphasized: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassControlButton extends StatelessWidget {
  const _GlassControlButton({
    required this.icon,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: emphasized ? 42 : 38,
      height: 48,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Icon(
            icon,
            size: emphasized ? 31 : 24,
            color: Colors.white.withOpacity(emphasized ? 0.96 : 0.78),
          ),
        ),
      ),
    );
  }
}
