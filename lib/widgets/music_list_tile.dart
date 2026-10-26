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
    this.onDelete,
  });

  final AudioTrack track;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;
  final bool isFavorite;
  final bool isDark;
  final String? leadingLabel;
  final VoidCallback? onDelete;

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
          // A smaller per-row blur avoids stacking costly high-sigma filters while scrolling.
          blur: 13,
          clear: true,
          showShadow: true,
          tint: context.oneUiFloatingGlass,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(25),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 12,
                  11,
                  compact ? 6 : 8,
                  11,
                ),
                child: Row(
                  children: [
                    if (leadingLabel != null) ...[
                      SizedBox(
                        width: compact ? 24 : 30,
                        child: Text(
                          leadingLabel!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
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
                        size: compact ? 56 : 62,
                        fallbackIcon: const Icon(
                          Icons.music_note_rounded,
                          size: 30,
                          color: Colors.white,
                        ),
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
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${track.artist} • ${track.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: context.oneUiSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          if (compact) ...[
                            const SizedBox(height: 3),
                            Text(
                              _formatDuration(track.durationMs),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: context.oneUiSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onDelete != null)
                      OneUi9IconButton(
                        tooltip: 'Excluir música do dispositivo',
                        onPressed: onDelete,
                        icon: Icons.delete_outline_rounded,
                        size: compact ? 36 : 40,
                        iconSize: compact ? 18 : 20,
                        showShadow: false,
                      ),
                    OneUi9IconButton(
                      tooltip: isFavorite
                          ? 'Remover dos favoritos'
                          : 'Adicionar aos favoritos',
                      onPressed: onFavoriteTap,
                      icon: isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      active: isFavorite,
                      size: compact ? 38 : 42,
                      iconSize: compact ? 19 : 21,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 2),
                      Text(
                        _formatDuration(track.durationMs),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
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
