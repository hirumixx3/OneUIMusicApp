import 'package:flutter/material.dart';

import '../models/audio_track.dart';
import 'lazy_artwork.dart';

class MusicListTile extends StatelessWidget {
  const MusicListTile({
    super.key,
    required this.track,
    required this.onTap,
    required this.onFavoriteTap,
    required this.isFavorite,
    required this.isDark,
    this.leadingLabel,
  });

  final AudioTrack track;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;
  final bool isFavorite;
  final bool isDark;
  final String? leadingLabel;

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final tileColor = isDark ? const Color(0xFF111216) : Colors.white;
    final secondaryText = isDark ? Colors.white70 : Colors.black54;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF252632) : const Color(0xFFE4E6EC),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                if (leadingLabel != null) ...[
                  SizedBox(
                    width: 30,
                    child: Text(
                      leadingLabel!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: secondaryText,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                SizedBox(
                  width: 66,
                  height: 66,
                  child: LazyArtwork(
                    track: track,
                    borderRadius: BorderRadius.circular(18),
                    fallbackIcon: const Icon(
                      Icons.music_note_rounded,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${track.artist} • ${track.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: secondaryText,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onFavoriteTap,
                  icon: Icon(
                    isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isFavorite ? Colors.redAccent : secondaryText,
                  ),
                ),
                Text(
                  _formatDuration(track.durationMs),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: secondaryText,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
