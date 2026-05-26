import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audio_track.dart';
import '../providers/music_player_provider.dart';

class LazyArtwork extends StatelessWidget {
  const LazyArtwork({
    super.key,
    required this.track,
    required this.borderRadius,
    required this.fallbackIcon,
    this.fit = BoxFit.cover,
    this.large = false,
  });

  final AudioTrack track;
  final BorderRadius borderRadius;
  final Widget fallbackIcon;
  final BoxFit fit;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    final cached = provider.cachedArtworkFor(track);

    return ClipRRect(
      borderRadius: borderRadius,
      child: cached != null
          ? _buildImage(cached)
          : FutureBuilder<Uint8List?>(
              future: provider.ensureArtwork(track),
              builder: (context, snapshot) {
                final bytes = snapshot.data ?? provider.cachedArtworkFor(track);
                if (bytes != null) {
                  return _buildImage(bytes);
                }
                if ((track.artworkUrl ?? '').trim().isNotEmpty) {
                  return _networkImage(track.artworkUrl!.trim());
                }
                return _fallback();
              },
            ),
    );
  }

  Widget _buildImage(Uint8List bytes) {
    return Image.memory(
      bytes,
      width: double.infinity,
      height: double.infinity,
      fit: fit,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }

  Widget _networkImage(String url) {
    return Image.network(
      url,
      width: double.infinity,
      height: double.infinity,
      fit: fit,
      filterQuality: FilterQuality.high,
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8F5BFF), Color(0xFF2C184E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: fallbackIcon),
    );
  }
}
