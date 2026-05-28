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

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: SizedBox(
        height: 92,
        width: MediaQuery.sizeOf(context).width - 36,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerLeft,
          children: [
            Positioned.fill(
              left: 34,
              top: 10,
              bottom: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(38),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
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
                        padding: const EdgeInsets.only(left: 54, right: 12, top: 10, bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0x8A1A1B17),
                          borderRadius: BorderRadius.circular(38),
                          border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x45000000),
                              blurRadius: 30,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
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
                                        ),
                                  ),
                                  const SizedBox(height: 2),
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
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayerScreen()),
                  );
                },
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Color(0x66000000), blurRadius: 22, offset: Offset(0, 10)),
                    ],
                  ),
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        LazyArtwork(
                          track: track,
                          borderRadius: BorderRadius.circular(999),
                          fallbackIcon: const Icon(Icons.music_note_rounded, color: Colors.white, size: 28),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.14)),
                        ),
                      ],
                    ),
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
      width: emphasized ? 48 : 42,
      height: 48,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Icon(
            icon,
            size: emphasized ? 32 : 25,
            color: Colors.white.withOpacity(emphasized ? 0.96 : 0.80),
          ),
        ),
      ),
    );
  }
}
