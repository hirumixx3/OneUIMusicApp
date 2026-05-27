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
        height: 96,
        width: MediaQuery.sizeOf(context).width - 36,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(34),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayerScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xA814171F),
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: LazyArtwork(
                            track: track,
                            borderRadius: BorderRadius.circular(18),
                            fallbackIcon: const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title.trim().isEmpty ? '-' : track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artist.trim().isEmpty ? track.album : track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      _MiniControlButton(
                        icon: Icons.skip_previous_rounded,
                        onTap: provider.previousTrack,
                      ),
                      const SizedBox(width: 4),
                      _MiniControlButton(
                        icon: provider.isPlaybackPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        onTap: provider.togglePlayback,
                        filled: true,
                      ),
                      const SizedBox(width: 4),
                      _MiniControlButton(
                        icon: Icons.skip_next_rounded,
                        onTap: provider.nextTrack,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniControlButton extends StatelessWidget {
  const _MiniControlButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: filled ? 52 : 42,
      height: filled ? 52 : 42,
      child: Material(
        color: filled ? const Color(0xFF7E98FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(filled ? 26 : 21),
        child: InkWell(
          borderRadius: BorderRadius.circular(filled ? 26 : 21),
          onTap: onTap,
          child: Icon(
            icon,
            size: filled ? 30 : 26,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
