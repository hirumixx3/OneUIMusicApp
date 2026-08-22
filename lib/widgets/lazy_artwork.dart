import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../providers/music_player_provider.dart';
import '../ui/one_ui_9.dart';

class LazyArtwork extends StatelessWidget {
  const LazyArtwork({
    super.key,
    required this.track,
    required this.borderRadius,
    required this.fallbackIcon,
    this.fit = BoxFit.cover,
    this.large = false,
    this.size,
  });

  final AudioTrack track;
  final BorderRadius borderRadius;
  final Widget fallbackIcon;
  final BoxFit fit;
  final bool large;

  /// Logical-pixel hint for the largest side this artwork renders at.
  /// Used to downsample the decoded image so we never decode a
  /// multi-megapixel embedded/network cover just to paint a small
  /// thumbnail. Defaults to a sensible thumbnail size, or a larger
  /// size when [large] is true.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    final cached = provider.cachedArtworkFor(track);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final logicalSize = size ?? (large ? 480 : 160);
    final cachePixels = (logicalSize * dpr).round().clamp(64, 960);

    return ClipRRect(
      borderRadius: borderRadius,
      child: cached != null
          ? _buildImage(cached, cachePixels)
          : FutureBuilder<Uint8List?>(
              future: provider.ensureArtwork(track),
              builder: (context, snapshot) {
                final bytes = snapshot.data ?? provider.cachedArtworkFor(track);
                if (bytes != null) {
                  return _buildImage(bytes, cachePixels);
                }
                if ((track.artworkUrl ?? '').trim().isNotEmpty) {
                  return _networkImage(track.artworkUrl!.trim(), cachePixels);
                }
                return _fallback();
              },
            ),
    );
  }

  Widget _buildImage(Uint8List bytes, int cachePixels) {
    return Image.memory(
      bytes,
      width: double.infinity,
      height: double.infinity,
      fit: fit,
      cacheWidth: cachePixels,
      cacheHeight: cachePixels,
      filterQuality: large ? FilterQuality.high : FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }

  Widget _networkImage(String url, int cachePixels) {
    return Image.network(
      url,
      width: double.infinity,
      height: double.infinity,
      fit: fit,
      cacheWidth: cachePixels,
      cacheHeight: cachePixels,
      filterQuality: large ? FilterQuality.high : FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _fallback(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _fallback();
      },
    );
  }

  Widget _fallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            OneUi9.accentSoft,
            OneUi9.violet,
            OneUi9.accent.withOpacity(0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: fallbackIcon),
    );
  }
}
