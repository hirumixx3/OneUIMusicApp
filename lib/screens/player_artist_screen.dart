import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
import '../providers/music_player_provider.dart';
import '../ui/one_ui_9.dart';
import '../widgets/lazy_artwork.dart';

/// Lightweight artist destination used by the player. It intentionally reuses
/// the provider's cached artist Future, so opening/closing it does not trigger
/// another network request or rebuild the Online home.
class PlayerArtistScreen extends StatelessWidget {
  const PlayerArtistScreen({super.key, required this.artist});

  final OnlineArtist artist;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<OnlineArtistPage>(
          future: provider.loadOnlineArtist(artist.browseId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Não foi possível carregar ${artist.name}.'),
                ),
              );
            }
            final page = snapshot.data!;
            return CustomScrollView(
              slivers: [
                SliverAppBar.large(title: Text(page.artist.name)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: Center(
                      child: ClipOval(
                        child: SizedBox(
                          width: 176,
                          height: 176,
                          child: page.artist.thumbnailUrl.isEmpty
                              ? const Icon(Icons.person_rounded, size: 88)
                              : Image.network(
                                  page.artist.thumbnailUrl,
                                  fit: BoxFit.cover,
                                  cacheWidth: 420,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 88),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  sliver: SliverToBoxAdapter(
                    child: Text('Músicas', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  ),
                ),
                SliverList.builder(
                  itemCount: page.topSongs.length,
                  itemBuilder: (context, index) {
                    final track = page.topSongs[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: SizedBox(
                        width: 54,
                        height: 54,
                        child: LazyArtwork(
                          track: track,
                          size: 54,
                          borderRadius: BorderRadius.circular(12),
                          fallbackIcon: const Icon(Icons.music_note_rounded),
                        ),
                      ),
                      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () async {
                        await provider.playTrack(track, queue: page.topSongs);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    );
                  },
                ),
                if (page.albums.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 150),
                    sliver: SliverToBoxAdapter(
                      child: OneUi9Glass(
                        padding: const EdgeInsets.all(18),
                        child: Text('${page.albums.length} álbuns disponíveis', style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
