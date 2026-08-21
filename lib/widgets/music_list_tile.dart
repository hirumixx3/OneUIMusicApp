import 'package:flutter/material.dart';

import '../models/audio_track.dart';
import '../ui/one_ui_9.dart';
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 350;
        return OneUi9Glass(
          radius: 25,
          blur: 12,
          showShadow: false,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(25),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.fromLTRB(compact ? 10 : 12, 11, compact ? 6 : 8, 11),
                child: Row(
                  children: [
                    if (leadingLabel != null) ...[
                      SizedBox(
                        width: compact ? 24 : 30,
                        child: Text(
                          leadingLabel!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: context.oneUiSecondary,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      width: compact ? 56 : 62,
                      height: compact ? 56 : 62,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(19),
                        boxShadow: [
                          BoxShadow(
                            color: context.oneUiShadow,
                            blurRadius: 15,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: LazyArtwork(
                        track: track,
                        borderRadius: BorderRadius.circular(19),
                        fallbackIcon: const Icon(Icons.music_note_rounded, size: 30, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${track.artist} • ${track.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: context.oneUiSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          if (compact) ...[
                            const SizedBox(height: 3),
                            Text(
                              _formatDuration(track.durationMs),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.oneUiSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: isFavorite ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
                      onPressed: onFavoriteTap,
                      icon: Icon(
                        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isFavorite ? const Color(0xFFFF6B8A) : context.oneUiSecondary,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 2),
                      Text(
                        _formatDuration(track.durationMs),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: context.oneUiSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
