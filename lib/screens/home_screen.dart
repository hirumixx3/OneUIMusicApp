import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/audio_track.dart';
import '../models/user_playlist.dart';
import '../providers/music_player_provider.dart';
import '../screens/about_app_screen.dart';
import '../screens/equalizer_screen.dart';
import '../screens/player_screen.dart';
import '../widgets/floating_player_bar.dart';
import '../widgets/lazy_artwork.dart';
import '../widgets/music_list_tile.dart';
import '../widgets/search_bar.dart';
import '../models/online_models.dart';

enum HomeMenuAction { sortLaunch, sortAlphabetical, sortArtist, equalizer, about }

Future<void> _runPlaylistActionAfterDialog(
  BuildContext context,
  Future<void> Function(MusicPlayerProvider provider) action,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
  if (!context.mounted) return;
  final completer = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      if (!context.mounted) return;
      await action(context.read<MusicPlayerProvider>());
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  });
  await completer.future;
}

List<AudioTrack> _playlistCandidateTracks(MusicPlayerProvider provider) {
  final seen = <String>{};
  final source = <AudioTrack>[
    ...provider.playHistory,
    ...provider.tracks,
    ...provider.onlineSongs,
    ...provider.onlineRecentTracks,
    ...provider.onlineFavoriteTracks,
  ];
  return source.where((track) => seen.add(track.libraryKey)).toList(growable: false);
}

Future<void> _showCreatePlaylistDialog(BuildContext context) async {
  final t = AppStrings.of(context);
  final controller = TextEditingController();
  String? createdName;
  try {
    createdName = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.newPlaylist),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: t.playlistName),
            onSubmitted: (_) {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(dialogContext, rootNavigator: true).pop(name);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
              child: Text(t.cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.of(dialogContext, rootNavigator: true).pop(name);
              },
              child: Text(t.create),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }

  final name = (createdName ?? '').trim();
  if (name.isEmpty || !context.mounted) return;
  await _runPlaylistActionAfterDialog(
    context,
    (provider) => provider.createUserPlaylist(name),
  );
}

Future<void> _showRenamePlaylistDialog(BuildContext context, UserPlaylist playlist) async {
  final t = AppStrings.of(context);
  final controller = TextEditingController(text: playlist.name);
  String? renamedName;
  try {
    renamedName = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.renamePlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: t.playlistName),
          onSubmitted: (_) {
            final name = controller.text.trim();
            if (name.isEmpty) return;
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.of(dialogContext, rootNavigator: true).pop(name);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              FocusManager.instance.primaryFocus?.unfocus();
            Navigator.of(dialogContext, rootNavigator: true).pop(name);
            },
            child: Text(t.save),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }

  final name = (renamedName ?? '').trim();
  if (name.isEmpty || !context.mounted) return;
  await _runPlaylistActionAfterDialog(
    context,
    (provider) => provider.renameUserPlaylist(playlist.id, name),
  );
}

Future<void> _showAddTracksToPlaylistSheet(BuildContext context, UserPlaylist playlist) async {
  final provider = context.read<MusicPlayerProvider>();
  final allTracks = _playlistCandidateTracks(provider);
  final searchController = TextEditingController();
  String query = '';

  List<AudioTrack> filteredTracks() {
    final q = query.trim().toLowerCase();
    final tracks = allTracks.where((track) {
      if (q.isEmpty) return true;
      return track.title.toLowerCase().contains(q) ||
          track.artist.toLowerCase().contains(q) ||
          track.album.toLowerCase().contains(q);
    }).toList(growable: false);
    return tracks.take(120).toList(growable: false);
  }

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final visible = filteredTracks();
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.82,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Adicionar músicas a ${playlist.name}',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Buscar música para adicionar',
                        ),
                        onChanged: (value) => setSheetState(() => query = value),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: visible.isEmpty
                            ? const Center(child: Text('Nenhuma música disponível para adicionar.'))
                            : ListView.separated(
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final track = visible[index];
                                  final alreadyAdded = playlist.tracks.any((item) => item.libraryKey == track.libraryKey);
                                  return MusicListTile(
                                    track: track,
                                    isDark: Theme.of(context).brightness == Brightness.dark,
                                    isFavorite: provider.isFavorite(track),
                                    onFavoriteTap: () => provider.toggleFavorite(track),
                                    onTap: () async {
                                      await provider.addTrackToUserPlaylist(playlist.id, track);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('"${track.title}" adicionada à playlist.')),
                                        );
                                      }
                                    },
                                    leadingLabel: alreadyAdded ? '✓' : null,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    searchController.dispose();
  }
}


void _showOnlineAccountSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return _OnlineAccountSheet(parentContext: context);
    },
  );
}

class _OnlineAccountSheet extends StatefulWidget {
  final BuildContext parentContext;
  const _OnlineAccountSheet({required this.parentContext});
  @override
  State<_OnlineAccountSheet> createState() => _OnlineAccountSheetState();
}

class _OnlineAccountSheetState extends State<_OnlineAccountSheet> {
  bool _loading = false;

  Future<bool> _handleSystemBack() async {
    final provider = context.read<MusicPlayerProvider>();
    if (provider.tab == LibraryTab.online) {
      if (provider.onlineActiveQuery.isNotEmpty) {
        await provider.clearOnlineQuery(reloadHome: false);
        return false;
      }
      if (provider.onlineSectionIndex != 0) {
        provider.setOnlineSectionIndex(0);
        return false;
      }
      if (_onlineShellIndex != 0) {
        setState(() => _onlineShellIndex = 0);
        return false;
      }
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    if (provider.tab != LibraryTab.tracks) {
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final loggedIn = provider.isLoggedIn;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── header ──────────────────────────────────────────────────
            Row(
              children: [
                if (loggedIn && provider.accountPhoto.isNotEmpty)
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: NetworkImage(provider.accountPhoto),
                  )
                else
                  const CircleAvatar(radius: 22, child: Icon(Icons.person_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loggedIn && provider.accountName.isNotEmpty
                            ? provider.accountName
                            : 'Conta',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (loggedIn && provider.accountEmail.isNotEmpty)
                        Text(
                          provider.accountEmail,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: isDark ? Colors.white54 : Colors.black45),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── login / logout button ────────────────────────────────────
            if (!loggedIn) ...[
              Text(
                'Entre com sua conta Google para acessar seu YouTube Music: histórico, playlists e recomendações personalizadas.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () async {
                          setState(() => _loading = true);
                          Navigator.of(context).pop();
                          final prov = context.read<MusicPlayerProvider>();
                          final result = await prov.loginWithGoogle();
                          if (widget.parentContext.mounted) {
                            ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  result != null
                                      ? 'Logado como ${result['name'] ?? 'usuário Google'}'
                                      : 'Login cancelado.',
                                ),
                              ),
                            );
                          }
                        },
                  icon: _loading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: const Text('Entrar com Google'),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () async {
                          setState(() => _loading = true);
                          await context.read<MusicPlayerProvider>().logoutGoogle();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                  icon: _loading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout_rounded),
                  label: const Text('Sair da conta'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _openTrackPlayer(
  BuildContext context,
  AudioTrack track, {
  required List<AudioTrack> queue,
}) async {
  final provider = context.read<MusicPlayerProvider>();
  unawaited(
    provider.playTrack(track, queue: queue).catchError((_) {
      // The provider already retries alternate streams silently. Avoid showing
      // ExoPlayer's generic Source error to the user while recovery is running.
    }),
  );

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const PlayerScreen()),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _onlineShellIndex = 0;

  late final TabController _controller = TabController(
    length: 5,
    vsync: this,
    initialIndex: 0,
  )
    ..addListener(() {
      final provider = context.read<MusicPlayerProvider>();
      final nextTab = LibraryTab.values[_controller.index];
      if (provider.tab != nextTab) {
        provider.setTab(nextTab);
      }
    });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final targetIndex = context.read<MusicPlayerProvider>().tab.index;
    if (_controller.index != targetIndex) {
      _controller.index = targetIndex;
    }
  }

  Future<bool> _handleSystemBack() async {
    final provider = context.read<MusicPlayerProvider>();
    if (provider.tab == LibraryTab.online) {
      if (provider.onlineActiveQuery.isNotEmpty) {
        await provider.clearOnlineQuery();
        return false;
      }
      if (provider.onlineSectionIndex != 0) {
        provider.setOnlineSectionIndex(0);
        return false;
      }
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    if (provider.tab != LibraryTab.tracks) {
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF090A0E) : const Color(0xFFF5F6FB);
    final card = isDark ? const Color(0xFF14161D) : Colors.white;
    final subtle = isDark ? Colors.white70 : Colors.black54;

    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final hasFloatingPlayer = provider.currentTrack != null && !keyboardOpen;
    final onlineMain = provider.tab == LibraryTab.online;
    final onlineBottomBarHeight = onlineMain ? 82.0 : 0.0;
    final bottomPlayerReserve = keyboardOpen
        ? 8.0
        : (hasFloatingPlayer ? (onlineMain ? 176.0 : 104.0) : onlineBottomBarHeight + 8.0);

    if (_controller.index != provider.tab.index && !_controller.indexIsChanging) {
      _controller.index = provider.tab.index;
    }

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Scaffold(
        backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            if (onlineMain)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  children: [
                    _OnlineMainHeader(
                      isDark: isDark,
                      shellIndex: _onlineShellIndex,
                      onOpenHistory: () {
                        setState(() => _onlineShellIndex = 0);
                        provider.setOnlineSectionIndex(4);
                      },
                      onSearch: () => setState(() => _onlineShellIndex = 1),
                      onRefresh: () {
                        final query = provider.onlineActiveQuery.isNotEmpty ? provider.searchController.text.trim() : '';
                        provider.searchOnline(forceQuery: query, refresh: true);
                      },
                      onOpenEqualizer: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EqualizerScreen())),
                      onOpenAccount: provider.isLoggedIn ? () => _showOnlineAccountSheet(context) : null,
                      onOpenMenu: () => _showOnlineNavigationSheet(context, provider),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: KeyedSubtree(
                        key: ValueKey('online_shell_$_onlineShellIndex'),
                        child: _OnlineShellBody(
                          index: _onlineShellIndex,
                          card: card,
                          keyboardOpen: keyboardOpen,
                          onGoHome: () => setState(() => _onlineShellIndex = 0),
                          onGoSearch: () => setState(() => _onlineShellIndex = 1),
                          onGoLibrary: () => setState(() => _onlineShellIndex = 2),
                        ),
                      ),
                    ),
                    SizedBox(height: bottomPlayerReserve),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'Music',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.1,
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: provider.scanLibrary,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                        PopupMenuButton<HomeMenuAction>(
                          tooltip: t.menu,
                          icon: const Icon(Icons.menu_rounded),
                          onSelected: (value) {
                            switch (value) {
                              case HomeMenuAction.sortLaunch:
                                provider.setSortMode(SortMode.launch);
                                break;
                              case HomeMenuAction.sortAlphabetical:
                                provider.setSortMode(SortMode.alphabetical);
                                break;
                              case HomeMenuAction.sortArtist:
                                provider.setSortMode(SortMode.artist);
                                break;
                              case HomeMenuAction.equalizer:
                                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EqualizerScreen()));
                                break;
                              case HomeMenuAction.about:
                                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutAppScreen()));
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(value: HomeMenuAction.sortLaunch, child: Text(t.sortRelease)),
                            PopupMenuItem(value: HomeMenuAction.sortAlphabetical, child: Text(t.sortAlphabetical)),
                            PopupMenuItem(value: HomeMenuAction.sortArtist, child: Text(t.sortByArtist)),
                            const PopupMenuDivider(),
                            PopupMenuItem(value: HomeMenuAction.equalizer, child: Text(t.equalizer)),
                            PopupMenuItem(value: HomeMenuAction.about, child: Text(t.aboutApp)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    MusicSearchField(
                      controller: provider.searchController,
                      isDark: isDark,
                      hintText: t.searchHint,
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TabBar(
                        controller: _controller,
                        isScrollable: true,
                        indicatorColor: Colors.transparent,
                        dividerColor: Colors.transparent,
                        tabAlignment: TabAlignment.start,
                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                        labelPadding: const EdgeInsets.only(right: 18),
                        labelStyle: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                        unselectedLabelStyle: Theme.of(context).textTheme.titleLarge?.copyWith(color: subtle),
                        tabs: [
                          Tab(text: t.tracks),
                          Tab(text: t.albums),
                          Tab(text: t.artists),
                          Tab(text: t.favorites),
                          Tab(text: t.online),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: (provider.isLoading && provider.tracks.isEmpty)
                          ? const Center(child: CircularProgressIndicator())
                          : (provider.error != null && provider.tracks.isEmpty)
                              ? _EmptyState(message: provider.error!)
                              : KeyedSubtree(
                                  key: ValueKey(provider.tab),
                                  child: _CurrentLibraryView(card: card, keyboardOpen: keyboardOpen),
                                ),
                    ),
                    SizedBox(height: keyboardOpen ? 12 : (hasFloatingPlayer ? 104 : 12)),
                  ],
                ),
              ),
            if (!keyboardOpen && !onlineMain)
              const Align(
                alignment: Alignment.bottomCenter,
                child: FloatingPlayerBar(),
              ),
            if (!keyboardOpen && onlineMain)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 72,
                child: FloatingPlayerBar(metrolistStyle: true),
              ),
            if (onlineMain)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _MetrolistBottomNavigation(
                  selectedIndex: _onlineShellIndex,
                  onSelected: (index) async {
                    if (index == 0) {
                      await provider.clearOnlineQuery(reloadHome: false);
                      provider.setOnlineSectionIndex(0);
                    }
                    setState(() => _onlineShellIndex = index);
                  },
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }



  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}


void _showOnlineNavigationSheet(BuildContext context, MusicPlayerProvider provider) {
  final t = AppStrings.of(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetContext) {
      Widget item(IconData icon, String label, VoidCallback onTap) {
        return ListTile(
          leading: Icon(icon),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () {
            Navigator.of(sheetContext).pop();
            onTap();
          },
        );
      }

      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              item(Icons.library_music_rounded, t.tracks, () => provider.setTab(LibraryTab.tracks)),
              item(Icons.album_rounded, t.albums, () => provider.setTab(LibraryTab.albums)),
              item(Icons.person_rounded, t.artists, () => provider.setTab(LibraryTab.artists)),
              item(Icons.favorite_rounded, t.favorites, () => provider.setTab(LibraryTab.favorites)),
              const Divider(),
              item(Icons.equalizer_rounded, t.equalizer, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EqualizerScreen()))),
              item(Icons.info_outline_rounded, t.aboutApp, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutAppScreen()))),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _showOnlineSearchSheet(BuildContext context) async {
  final provider = context.read<MusicPlayerProvider>();
  final controller = TextEditingController(text: provider.onlineActiveQuery.isNotEmpty ? provider.searchController.text : '');
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 18 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Buscar músicas online...',
                  ),
                  onSubmitted: (value) {
                    final query = value.trim();
                    provider.searchController.text = query;
                    provider.setOnlineSectionIndex(0);
                    if (query.isEmpty) {
                      provider.clearOnlineQuery();
                    } else {
                      provider.searchOnline(forceQuery: query, refresh: true);
                    }
                    Navigator.of(sheetContext).pop();
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      final query = controller.text.trim();
                      provider.searchController.text = query;
                      provider.setOnlineSectionIndex(0);
                      if (query.isEmpty) {
                        provider.clearOnlineQuery();
                      } else {
                        provider.searchOnline(forceQuery: query, refresh: true);
                      }
                      Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Pesquisar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

class _OnlineMainHeader extends StatelessWidget {
  const _OnlineMainHeader({
    required this.isDark,
    required this.shellIndex,
    required this.onOpenHistory,
    required this.onSearch,
    required this.onRefresh,
    required this.onOpenEqualizer,
    required this.onOpenMenu,
    required this.onOpenAccount,
  });

  final bool isDark;
  final int shellIndex;
  final VoidCallback onOpenHistory;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;
  final VoidCallback onOpenEqualizer;
  final VoidCallback onOpenMenu;
  final VoidCallback? onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final foreground = isDark ? const Color(0xFFE1E4C4) : const Color(0xFF202416);
    Widget iconButton(IconData icon, VoidCallback onTap, {String? tooltip}) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        color: foreground.withOpacity(0.90),
        icon: Icon(icon),
        iconSize: 24,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            shellIndex == 1 ? 'Pesquisar' : shellIndex == 2 ? 'Biblioteca' : 'Início',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: foreground,
                ),
          ),
        ),
        iconButton(Icons.history_rounded, onOpenHistory, tooltip: 'Histórico'),
        iconButton(Icons.search_rounded, onSearch, tooltip: 'Pesquisar'),
        iconButton(Icons.refresh_rounded, onRefresh, tooltip: 'Atualizar'),
        if (provider.isLoggedIn && onOpenAccount != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onOpenAccount,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF8BAA3F),
                backgroundImage: provider.accountPhoto.trim().isNotEmpty ? NetworkImage(provider.accountPhoto) : null,
                child: provider.accountPhoto.trim().isEmpty
                    ? Text(
                        provider.accountName.trim().isNotEmpty ? provider.accountName.trim()[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                      )
                    : null,
              ),
            ),
          )
        else
          Icon(Icons.person_outline_rounded, color: foreground.withOpacity(0.52)),
        iconButton(Icons.menu_rounded, onOpenMenu, tooltip: 'Menu'),
      ],
    );
  }
}

class _CurrentLibraryView extends StatelessWidget {
  const _CurrentLibraryView({required this.card, required this.keyboardOpen});

  final Color card;
  final bool keyboardOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final tab = context.select<MusicPlayerProvider, LibraryTab>((p) => p.tab);
    switch (tab) {
      case LibraryTab.tracks:
        return _TracksTab(card: card);
      case LibraryTab.albums:
        return _AlbumsTab(card: card);
      case LibraryTab.artists:
        return _ArtistsTab(card: card);
      case LibraryTab.favorites:
        return _FavoritesTab(card: card);
      case LibraryTab.online:
        return _OnlineTab(card: card, keyboardOpen: keyboardOpen);
    }
  }
}



List<Widget> _metrolistSongRailSlivers({
  required BuildContext context,
  required String title,
  required List<AudioTrack> songs,
  int skip = 0,
  int take = 12,
}) {
  final visible = songs.skip(skip).take(take).toList(growable: false);
  if (visible.isEmpty) return const <Widget>[];
  return <Widget>[
    const SliverToBoxAdapter(child: SizedBox(height: 26)),
    SliverToBoxAdapter(
      child: _YoutubeSectionHeader(
        title: title,
        actionLabel: 'Reproduzir tudo',
        onActionTap: () => _openTrackPlayer(context, visible.first, queue: songs),
      ),
    ),
    SliverToBoxAdapter(
      child: SizedBox(
        height: 184,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final track = visible[index];
            return SizedBox(
              width: 142,
              child: _YoutubeMusicTile(
                title: track.title,
                subtitle: track.artist,
                imageUrl: track.artworkUrl ?? '',
                onTap: () => _openTrackPlayer(context, track, queue: songs),
              ),
            );
          },
        ),
      ),
    ),
  ];
}

List<Widget> _metrolistPlaylistRailSlivers({
  required BuildContext context,
  required String title,
  required List<OnlinePlaylist> playlists,
  int skip = 0,
  int take = 12,
}) {
  final visible = playlists.skip(skip).take(take).toList(growable: false);
  if (visible.isEmpty) return const <Widget>[];
  return <Widget>[
    const SliverToBoxAdapter(child: SizedBox(height: 26)),
    SliverToBoxAdapter(child: _YoutubeSectionHeader(title: title, actionLabel: 'Ver tudo')),
    SliverToBoxAdapter(
      child: SizedBox(
        height: 206,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final playlist = visible[index];
            return SizedBox(
              width: 150,
              child: _YoutubeMusicTile(
                title: playlist.title,
                subtitle: playlist.author,
                imageUrl: playlist.thumbnailUrl,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlinePlaylistScreen(playlist: playlist))),
              ),
            );
          },
        ),
      ),
    ),
  ];
}

List<Widget> _metrolistAlbumRailSlivers({
  required BuildContext context,
  required String title,
  required List<OnlineAlbum> albums,
  int skip = 0,
  int take = 12,
}) {
  final visible = albums.skip(skip).take(take).toList(growable: false);
  if (visible.isEmpty) return const <Widget>[];
  return <Widget>[
    const SliverToBoxAdapter(child: SizedBox(height: 26)),
    SliverToBoxAdapter(child: _YoutubeSectionHeader(title: title, actionLabel: 'Ver tudo')),
    SliverToBoxAdapter(
      child: SizedBox(
        height: 222,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final album = visible[index];
            return SizedBox(
              width: 152,
              child: _OnlineAlbumCard(
                album: album,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlineAlbumScreen(album: album))),
              ),
            );
          },
        ),
      ),
    ),
  ];
}

class _OnlineShellBody extends StatelessWidget {
  const _OnlineShellBody({
    required this.index,
    required this.card,
    required this.keyboardOpen,
    required this.onGoHome,
    required this.onGoSearch,
    required this.onGoLibrary,
  });

  final int index;
  final Color card;
  final bool keyboardOpen;
  final VoidCallback onGoHome;
  final VoidCallback onGoSearch;
  final VoidCallback onGoLibrary;

  @override
  Widget build(BuildContext context) {
    switch (index) {
      case 1:
        return _OnlineSearchTab(onGoHome: onGoHome);
      case 2:
        return _OnlineLibraryTab(onGoHome: onGoHome, onGoSearch: onGoSearch);
      case 0:
      default:
        return _OnlineTab(card: card, keyboardOpen: keyboardOpen);
    }
  }
}

class _MetrolistBottomNavigation extends StatelessWidget {
  const _MetrolistBottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xF0101117) : const Color(0xF7FFFFFF);
    final selected = Theme.of(context).colorScheme.primary;
    final unselected = isDark ? Colors.white70 : Colors.black54;
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: bg,
            border: Border(top: BorderSide(color: Colors.white.withOpacity(isDark ? 0.06 : 0.0))),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -10)),
            ],
          ),
          child: Row(
            children: [
              _MetrolistNavItem(
                icon: Icons.home_rounded,
                label: 'Início',
                selected: selectedIndex == 0,
                selectedColor: selected,
                unselectedColor: unselected,
                onTap: () => onSelected(0),
              ),
              _MetrolistNavItem(
                icon: Icons.search_rounded,
                label: 'Pesquisar',
                selected: selectedIndex == 1,
                selectedColor: selected,
                unselectedColor: unselected,
                onTap: () => onSelected(1),
              ),
              _MetrolistNavItem(
                icon: Icons.library_music_rounded,
                label: 'Biblioteca',
                selected: selectedIndex == 2,
                selectedColor: selected,
                unselectedColor: unselected,
                onTap: () => onSelected(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetrolistNavItem extends StatelessWidget {
  const _MetrolistNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : unselectedColor;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? selectedColor.withOpacity(0.18) : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: color, size: 27),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineSearchTab extends StatefulWidget {
  const _OnlineSearchTab({required this.onGoHome});

  final VoidCallback onGoHome;

  @override
  State<_OnlineSearchTab> createState() => _OnlineSearchTabState();
}

class _OnlineSearchTabState extends State<_OnlineSearchTab> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = provider.currentTrack == null ? 92.0 : 188.0;
    final active = provider.onlineActiveQuery.isNotEmpty;
    final songs = provider.onlineDisplaySongs;
    final albums = provider.onlineAlbums;
    final artists = provider.onlineDisplayArtists;
    final playlists = provider.onlineDisplayPlaylists;
    final historyTracks = provider.onlineHistoryTracks;
    final searchHistory = provider.onlineSearchHistory;
    return Column(
      children: [
        _OnlineInlineSearchBar(
          controller: provider.searchController,
          onSubmitted: (query) {
            final cleaned = query.trim();
            provider.searchController.text = cleaned;
            provider.searchController.selection = TextSelection.collapsed(offset: cleaned.length);
            provider.setOnlineSectionIndex(0);
            if (cleaned.isEmpty) {
              provider.clearOnlineQuery(reloadHome: false);
            } else {
              provider.searchOnline(forceQuery: cleaned, refresh: true);
            }
          },
          onClear: () => provider.clearOnlineQuery(reloadHome: false),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: const ['Tudo', 'Músicas', 'Álbuns', 'Artistas', 'Playlists'].length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final labels = const ['Tudo', 'Músicas', 'Álbuns', 'Artistas', 'Playlists'];
              return _YoutubeMusicChip(label: labels[index], onTap: () {});
            },
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (!active) ...[
                if (searchHistory.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: _YoutubeSectionHeader(title: 'Histórico de pesquisa')),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final term = searchHistory[index];
                        return _OnlineSearchHistoryRow(
                          label: term,
                          onTap: () {
                            provider.searchController.text = term;
                            provider.searchController.selection = TextSelection.collapsed(offset: term.length);
                            provider.searchOnline(forceQuery: term, refresh: true);
                          },
                        );
                      },
                      childCount: searchHistory.length,
                    ),
                  ),
                ],
                if (historyTracks.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  const SliverToBoxAdapter(child: _YoutubeSectionHeader(title: 'Ouvir de novo')),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, rawIndex) {
                        if (rawIndex.isOdd) return const SizedBox(height: 6);
                        final index = rawIndex ~/ 2;
                        final track = historyTracks[index];
                        return _YoutubeSongRow(
                          track: track,
                          isFavorite: provider.isFavorite(track),
                          onTap: () => _openTrackPlayer(context, track, queue: historyTracks),
                          onFavoriteTap: () => provider.toggleFavorite(track),
                        );
                      },
                      childCount: (historyTracks.take(8).length * 2 - 1).clamp(0, 99).toInt(),
                    ),
                  ),
                ],
                if (searchHistory.isEmpty && historyTracks.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(message: 'Pesquise músicas, artistas, álbuns e playlists online.'),
                  ),
              ] else ...[
                if (provider.isOnlineLoading && songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
                if (songs.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _YoutubeSectionHeader(title: 'Músicas')),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, rawIndex) {
                        if (rawIndex.isOdd) return const SizedBox(height: 6);
                        final index = rawIndex ~/ 2;
                        final track = songs[index];
                        return _YoutubeSongRow(
                          track: track,
                          isFavorite: provider.isFavorite(track),
                          onTap: () => _openTrackPlayer(context, track, queue: songs),
                          onFavoriteTap: () => provider.toggleFavorite(track),
                        );
                      },
                      childCount: (songs.take(20).length * 2 - 1).clamp(0, 99).toInt(),
                    ),
                  ),
                ],
                if (albums.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 22)),
                  const SliverToBoxAdapter(child: _YoutubeSectionHeader(title: 'Álbuns')),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 205,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: albums.take(12).length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final album = albums[index];
                          return SizedBox(
                            width: 145,
                            child: _OnlineAlbumCard(
                              album: album,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlineAlbumScreen(album: album))),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                if (artists.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 22)),
                  const SliverToBoxAdapter(child: _YoutubeSectionHeader(title: 'Artistas')),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 160,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: artists.take(12).length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, index) => _YoutubeArtistBubble(
                          artist: artists[index],
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlineArtistScreen(artist: artists[index]))),
                        ),
                      ),
                    ),
                  ),
                ],
                if (playlists.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 22)),
                  const SliverToBoxAdapter(child: _YoutubeSectionHeader(title: 'Playlists')),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 190,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: playlists.take(12).length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          return SizedBox(
                            width: 142,
                            child: _YoutubeMusicTile(
                              title: playlist.title,
                              subtitle: playlist.author,
                              imageUrl: playlist.thumbnailUrl,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlinePlaylistScreen(playlist: playlist))),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
              SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
            ],
          ),
        ),
      ],
    );
  }
}

class _OnlineSearchHistoryRow extends StatelessWidget {
  const _OnlineSearchHistoryRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(Icons.history_rounded, color: subtle),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
      trailing: const Icon(Icons.north_west_rounded, size: 20),
      onTap: onTap,
    );
  }
}

class _OnlineLibraryTab extends StatelessWidget {
  const _OnlineLibraryTab({required this.onGoHome, required this.onGoSearch});

  final VoidCallback onGoHome;
  final VoidCallback onGoSearch;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final bottomPadding = provider.currentTrack == null ? 92.0 : 188.0;
    final favorites = provider.onlineFavoriteTracks;
    final history = provider.onlineHistoryTracks;
    final playlists = provider.userPlaylists;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFF78A33E),
                  backgroundImage: provider.isLoggedIn && provider.accountPhoto.trim().isNotEmpty ? NetworkImage(provider.accountPhoto) : null,
                  child: provider.isLoggedIn && provider.accountPhoto.trim().isNotEmpty
                      ? null
                      : Text(
                          provider.isLoggedIn && provider.accountName.trim().isNotEmpty ? provider.accountName.trim()[0].toUpperCase() : 'H',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.white),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HIRUMISU', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
                      Text('Biblioteca online', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
            childAspectRatio: 1.05,
          ),
          delegate: SliverChildListDelegate([
            _LibraryShortcutCard(
              icon: Icons.thumb_up_rounded,
              title: 'Música marcada',
              subtitle: 'Playlist automática',
              onTap: () {
                provider.setOnlineSectionIndex(3);
                onGoHome();
              },
            ),
            _LibraryShortcutCard(
              icon: Icons.history_rounded,
              title: 'Histórico',
              subtitle: '${history.length} músicas',
              onTap: () {
                provider.setOnlineSectionIndex(4);
                onGoHome();
              },
            ),
          ]),
        ),
        if (history.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 26)),
          SliverToBoxAdapter(
            child: _YoutubeSectionHeader(
              title: 'Ouvir de novo',
              actionLabel: 'Reproduzir tudo',
              onActionTap: () => _openTrackPlayer(context, history.first, queue: history),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: history.take(12).length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final track = history[index];
                  return SizedBox(
                    width: 138,
                    child: _YoutubeMusicTile(
                      title: track.title,
                      subtitle: track.artist,
                      imageUrl: track.artworkUrl ?? '',
                      onTap: () => _openTrackPlayer(context, track, queue: history),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        if (favorites.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: _YoutubeSectionHeader(
              title: 'Favoritas online',
              actionLabel: 'Reproduzir tudo',
              onActionTap: () => _openTrackPlayer(context, favorites.first, queue: favorites),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, rawIndex) {
                if (rawIndex.isOdd) return const SizedBox(height: 6);
                final index = rawIndex ~/ 2;
                final track = favorites[index];
                return _YoutubeSongRow(
                  track: track,
                  isFavorite: provider.isFavorite(track),
                  onTap: () => _openTrackPlayer(context, track, queue: favorites),
                  onFavoriteTap: () => provider.toggleFavorite(track),
                );
              },
              childCount: (favorites.take(8).length * 2 - 1).clamp(0, 99).toInt(),
            ),
          ),
        ],
        if (playlists.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          const SliverToBoxAdapter(child: _YoutubeSectionHeader(title: 'Suas playlists')),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, rawIndex) {
                if (rawIndex.isOdd) return const SizedBox(height: 8);
                final index = rawIndex ~/ 2;
                final playlist = playlists[index];
                return _UserPlaylistRow(
                  playlist: playlist,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserPlaylistScreen(playlistId: playlist.id))),
                  onRename: () => _showRenamePlaylistDialog(context, playlist),
                  onDelete: () => provider.deleteUserPlaylist(playlist.id),
                );
              },
              childCount: (playlists.length * 2 - 1).clamp(0, 999).toInt(),
            ),
          ),
        ],
        if (history.isEmpty && favorites.isEmpty && playlists.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(message: 'Sua biblioteca online aparece aqui conforme você ouvir, favoritar e criar playlists.'),
          ),
        SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
      ],
    );
  }
}

class _LibraryShortcutCard extends StatelessWidget {
  const _LibraryShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary),
              const Spacer(),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TracksTab extends StatefulWidget {
  const _TracksTab({required this.card});
  final Color card;

  @override
  State<_TracksTab> createState() => _TracksTabState();
}

class _TracksTabState extends State<_TracksTab> with AutomaticKeepAliveClientMixin {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MusicPlayerProvider>();
    _controller = ScrollController(initialScrollOffset: provider.scrollOffsetFor(LibraryTab.tracks))
      ..addListener(() {
        provider.updateScrollOffset(LibraryTab.tracks, _controller.offset);
      });
  }

  Future<bool> _handleSystemBack() async {
    final provider = context.read<MusicPlayerProvider>();
    if (provider.tab == LibraryTab.online) {
      if (provider.onlineActiveQuery.isNotEmpty) {
        await provider.clearOnlineQuery();
        return false;
      }
      if (provider.onlineSectionIndex != 0) {
        provider.setOnlineSectionIndex(0);
        return false;
      }
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    if (provider.tab != LibraryTab.tracks) {
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final tracks = provider.filteredTracks;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (tracks.isEmpty) {
      return const _EmptyState(message: 'Nenhuma faixa encontrada.');
    }
    return ListView.separated(
      key: const PageStorageKey('tracks_list'),
      controller: _controller,
      padding: EdgeInsets.zero,
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final track = tracks[index];
        return MusicListTile(
          track: track,
          isDark: isDark,
          isFavorite: provider.isFavorite(track),
          onFavoriteTap: () => provider.toggleFavorite(track),
          onTap: () => _openTrackPlayer(context, track, queue: tracks),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _AlbumsTab extends StatefulWidget {
  const _AlbumsTab({required this.card});
  final Color card;

  @override
  State<_AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<_AlbumsTab> with AutomaticKeepAliveClientMixin {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MusicPlayerProvider>();
    _controller = ScrollController(initialScrollOffset: provider.scrollOffsetFor(LibraryTab.albums))
      ..addListener(() {
        provider.updateScrollOffset(LibraryTab.albums, _controller.offset);
      });
  }

  Future<bool> _handleSystemBack() async {
    final provider = context.read<MusicPlayerProvider>();
    if (provider.tab == LibraryTab.online) {
      if (provider.onlineActiveQuery.isNotEmpty) {
        await provider.clearOnlineQuery();
        return false;
      }
      if (provider.onlineSectionIndex != 0) {
        provider.setOnlineSectionIndex(0);
        return false;
      }
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    if (provider.tab != LibraryTab.tracks) {
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final albumEntries = provider.albums.entries.toList();
    if (albumEntries.isEmpty) {
      return const _EmptyState(message: 'Nenhum álbum encontrado.');
    }

    return GridView.builder(
      key: const PageStorageKey('albums_grid'),
      controller: _controller,
      padding: const EdgeInsets.only(top: 8, bottom: 132),
      itemCount: albumEntries.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 14,
        mainAxisExtent: 216,
      ),
      itemBuilder: (context, index) {
        final entry = albumEntries[index];
        final albumTracks = provider.albumTracksFor(entry.key);
        final coverTrack = albumTracks.first;
        return _AlbumCard(
          track: coverTrack,
          tracks: albumTracks,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AlbumDetailScreen(
                  albumKey: entry.key,
                  tracks: albumTracks,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _ArtistsTab extends StatefulWidget {
  const _ArtistsTab({required this.card});
  final Color card;

  @override
  State<_ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends State<_ArtistsTab> with AutomaticKeepAliveClientMixin {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MusicPlayerProvider>();
    _controller = ScrollController(initialScrollOffset: provider.scrollOffsetFor(LibraryTab.artists))
      ..addListener(() {
        provider.updateScrollOffset(LibraryTab.artists, _controller.offset);
      });
  }

  Future<bool> _handleSystemBack() async {
    final provider = context.read<MusicPlayerProvider>();
    if (provider.tab == LibraryTab.online) {
      if (provider.onlineActiveQuery.isNotEmpty) {
        await provider.clearOnlineQuery();
        return false;
      }
      if (provider.onlineSectionIndex != 0) {
        provider.setOnlineSectionIndex(0);
        return false;
      }
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    if (provider.tab != LibraryTab.tracks) {
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final artistEntries = provider.artists.entries.toList();
    final onlineArtists = provider.onlineRecommendedArtists;
    final subtle = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (artistEntries.isEmpty && onlineArtists.isEmpty) {
      return const _EmptyState(message: 'Nenhum artista encontrado.');
    }

    // Build a flat list: optional online section header + online artists + optional local header + local artists
    final items = <_ArtistListItem>[];

    if (onlineArtists.isNotEmpty) {
      items.add(const _ArtistListItem.sectionHeader('Online'));
      for (final artist in onlineArtists) {
        items.add(_ArtistListItem.online(artist));
      }
    }

    if (artistEntries.isNotEmpty) {
      if (onlineArtists.isNotEmpty) {
        items.add(_ArtistListItem.sectionHeader(t.tracks));
      }
      for (final entry in artistEntries) {
        items.add(_ArtistListItem.local(entry.key, entry.value));
      }
    }

    return ListView.separated(
      key: const PageStorageKey('artists_list'),
      controller: _controller,
      padding: EdgeInsets.zero,
      itemCount: items.length,
      separatorBuilder: (_, i) {
        final item = items[i];
        if (item.isHeader) return const SizedBox.shrink();
        final next = (i + 1 < items.length) ? items[i + 1] : null;
        if (next?.isHeader == true) return const SizedBox(height: 4);
        return const SizedBox(height: 12);
      },
      itemBuilder: (context, index) {
        final item = items[index];

        if (item.isHeader) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              item.headerLabel!,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: subtle,
                  ),
            ),
          );
        }

        if (item.onlineArtist != null) {
          final artist = item.onlineArtist!;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => OnlineArtistScreen(artist: artist)),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.card,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: isDark ? const Color(0xFF252632) : const Color(0xFFE4E6EC),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 74,
                      height: 74,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(37),
                        child: (artist.thumbnailUrl.isNotEmpty)
                            ? Image.network(
                                artist.thumbnailUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 40),
                              )
                            : const Icon(Icons.person_rounded, size: 40),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Artista online',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: subtle),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.chevron_right_rounded, size: 28, color: subtle),
                  ],
                ),
              ),
            ),
          );
        }

        // Local artist
        final entry = item.localEntry!;
        final coverTrack = entry.value.first;
        final albumsCount = entry.value.map((e) => e.albumGroupKey).toSet().length;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ArtistDetailScreen(artistName: entry.key),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.card,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: isDark ? const Color(0xFF252632) : const Color(0xFFE4E6EC),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(width: 74, height: 74, child: _ArtworkCard(track: coverTrack)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$albumsCount álbum(ns) • ${entry.value.length} faixa(s)',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: subtle),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.chevron_right_rounded, size: 28, color: subtle),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Represents a single item in the unified artists list.
class _ArtistListItem {
  const _ArtistListItem._({
    this.headerLabel,
    this.onlineArtist,
    this.localEntry,
  });

  const _ArtistListItem.sectionHeader(String label)
      : this._(headerLabel: label);

  const _ArtistListItem.online(OnlineArtist artist)
      : this._(onlineArtist: artist);

  _ArtistListItem.local(String name, List<AudioTrack> tracks)
      : this._(localEntry: MapEntry(name, tracks));

  final String? headerLabel;
  final OnlineArtist? onlineArtist;
  final MapEntry<String, List<AudioTrack>>? localEntry;

  bool get isHeader => headerLabel != null;
}

class _FavoritesTab extends StatefulWidget {
  const _FavoritesTab({required this.card});
  final Color card;

  @override
  State<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<_FavoritesTab> with AutomaticKeepAliveClientMixin {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MusicPlayerProvider>();
    _controller = ScrollController(initialScrollOffset: provider.scrollOffsetFor(LibraryTab.favorites))
      ..addListener(() {
        provider.updateScrollOffset(LibraryTab.favorites, _controller.offset);
      });
  }

  Future<bool> _handleSystemBack() async {
    final provider = context.read<MusicPlayerProvider>();
    if (provider.tab == LibraryTab.online) {
      if (provider.onlineActiveQuery.isNotEmpty) {
        await provider.clearOnlineQuery();
        return false;
      }
      if (provider.onlineSectionIndex != 0) {
        provider.setOnlineSectionIndex(0);
        return false;
      }
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    if (provider.tab != LibraryTab.tracks) {
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final tracks = provider.favoriteTracks;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (tracks.isEmpty) {
      return const _EmptyState(message: 'Nenhuma música favoritada.');
    }
    return ListView.separated(
      key: const PageStorageKey('favorites_list'),
      controller: _controller,
      padding: EdgeInsets.zero,
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final track = tracks[index];
        return MusicListTile(
          track: track,
          isDark: isDark,
          isFavorite: provider.isFavorite(track),
          onFavoriteTap: () => provider.toggleFavorite(track),
          onTap: () => _openTrackPlayer(context, track, queue: tracks),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}


class _OnlineTab extends StatefulWidget {
  const _OnlineTab({required this.card, required this.keyboardOpen});

  final Color card;
  final bool keyboardOpen;

  @override
  State<_OnlineTab> createState() => _OnlineTabState();
}

class _OnlineTabState extends State<_OnlineTab> with AutomaticKeepAliveClientMixin {
  late final ScrollController _controller;
  int _sectionIndex = 0;

  int _normalizeSectionIndex(int value) {
    return value.clamp(0, 5).toInt();
  }

  @override
  void initState() {
    super.initState();
    final provider = context.read<MusicPlayerProvider>();
    _sectionIndex = _normalizeSectionIndex(provider.onlineSectionIndex);
    if (_sectionIndex != provider.onlineSectionIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<MusicPlayerProvider>().setOnlineSectionIndex(_sectionIndex);
      });
    }
    _controller = ScrollController(initialScrollOffset: provider.scrollOffsetFor(LibraryTab.online))
      ..addListener(() {
        provider.updateScrollOffset(LibraryTab.online, _controller.offset);
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<MusicPlayerProvider>();
      final hasImmediateOnlineContent =
          provider.onlineDisplaySongs.isNotEmpty && provider.onlineDisplayArtists.isNotEmpty && provider.onlineDisplayPlaylists.isNotEmpty;
      if (!hasImmediateOnlineContent || provider.onlineActiveQuery.isNotEmpty) {
        final query = provider.onlineActiveQuery.isNotEmpty ? provider.searchController.text.trim() : '';
        provider.searchOnline(forceQuery: query, refresh: !hasImmediateOnlineContent || query.isNotEmpty);
      }
    });
  }

  Future<bool> _handleSystemBack() async {
    final provider = context.read<MusicPlayerProvider>();
    if (provider.tab == LibraryTab.online) {
      if (provider.onlineActiveQuery.isNotEmpty) {
        await provider.clearOnlineQuery();
        return false;
      }
      if (provider.onlineSectionIndex != 0) {
        provider.setOnlineSectionIndex(0);
        return false;
      }
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    if (provider.tab != LibraryTab.tracks) {
      provider.setTab(LibraryTab.tracks);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final requestedSectionIndex = _normalizeSectionIndex(provider.onlineSectionIndex);
    if (requestedSectionIndex != _sectionIndex) {
      _sectionIndex = requestedSectionIndex;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtle = isDark ? Colors.white70 : Colors.black54;
    final keyboardOpen = widget.keyboardOpen;
    final listBottomPadding = keyboardOpen ? 18.0 : (provider.currentTrack == null ? 24.0 : 112.0);

    Widget content;
    if (_sectionIndex == 3) {
      final favorites = provider.onlineFavoriteTracks;
      content = favorites.isEmpty
          ? const _EmptyState(message: 'Nenhuma música online favoritada ainda.')
          : ListView.separated(
              key: const PageStorageKey('online_favorites_list'),
              controller: _controller,
              padding: EdgeInsets.only(top: 8, bottom: listBottomPadding),
              itemCount: favorites.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final track = favorites[index];
                return MusicListTile(
                  track: track,
                  isDark: isDark,
                  isFavorite: provider.isFavorite(track),
                  onFavoriteTap: () => provider.toggleFavorite(track),
                  onTap: () => _openTrackPlayer(context, track, queue: favorites),
                );
              },
            );
    } else if (_sectionIndex == 4) {
      final history = provider.onlineHistoryTracks;
      content = history.isEmpty
          ? const _EmptyState(message: 'Nenhuma música online tocada ainda.')
          : ListView.separated(
              key: const PageStorageKey('online_history_list'),
              controller: _controller,
              padding: EdgeInsets.only(top: 8, bottom: listBottomPadding),
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final track = history[index];
                return MusicListTile(
                  track: track,
                  isDark: isDark,
                  isFavorite: provider.isFavorite(track),
                  onFavoriteTap: () => provider.toggleFavorite(track),
                  onTap: () => _openTrackPlayer(context, track, queue: history),
                );
              },
            );
    } else if (_sectionIndex == 5) {
      final playlists = provider.userPlaylists;
      content = playlists.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    t.noPlaylistsYet,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(t.createPlaylist),
                  ),
                ],
              ),
            )
          : ListView.separated(
              key: const PageStorageKey('user_playlists_list'),
              controller: _controller,
              padding: EdgeInsets.only(top: 8, bottom: listBottomPadding),
              itemCount: playlists.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return _UserPlaylistRow(
                  playlist: playlist,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => UserPlaylistScreen(playlistId: playlist.id)),
                    );
                  },
                  onRename: () => _showRenamePlaylistDialog(context, playlist),
                  onDelete: () => provider.deleteUserPlaylist(playlist.id),
                );
              },
            );
    } else if (provider.isOnlineLoading &&
        _sectionIndex != 0 &&
        provider.onlineDisplaySongs.isEmpty &&
        provider.onlineDisplayArtists.isEmpty &&
        provider.onlineDisplayPlaylists.isEmpty) {
      content = const Center(child: CircularProgressIndicator());
    } else if (provider.onlineError != null &&
        _sectionIndex != 0 &&
        provider.onlineSongs.isEmpty &&
        provider.onlineDisplayArtists.isEmpty &&
        provider.onlineDisplayPlaylists.isEmpty) {
      content = _EmptyState(message: provider.onlineError!);
    } else {
      switch (_sectionIndex) {
        case 0:
          final songs = provider.onlineDisplaySongs;
          if (provider.onlineActiveQuery.isEmpty) {
            content = _buildYoutubeMusicHome(
              context: context,
              provider: provider,
              songs: songs,
              artists: provider.onlineDisplayArtists,
              playlists: provider.onlineDisplayPlaylists,
              isDark: isDark,
              bottomPadding: listBottomPadding,
            );
          } else {
            content = songs.isEmpty
                ? const _EmptyState(message: 'Nenhuma música online encontrada.')
                : ListView.separated(
                    key: const PageStorageKey('online_songs_list'),
                    controller: _controller,
                    padding: EdgeInsets.only(top: 8, bottom: listBottomPadding),
                    itemCount: songs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final track = songs[index];
                      return MusicListTile(
                        track: track,
                        isDark: isDark,
                        isFavorite: provider.isFavorite(track),
                        onFavoriteTap: () => provider.toggleFavorite(track),
                        onTap: () => _openTrackPlayer(context, track, queue: songs),
                      );
                    },
                  );
          }
          break;
        case 1:
          final artists = provider.onlineDisplayArtists;
          content = artists.isEmpty
              ? const _EmptyState(message: 'Nenhum artista online encontrado.')
              : ListView.separated(
                  key: const PageStorageKey('online_artists_list'),
                  controller: _controller,
                  padding: EdgeInsets.only(top: 8, bottom: listBottomPadding),
                  itemCount: artists.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    return _OnlineArtistRow(
                      artist: artist,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => OnlineArtistScreen(artist: artist)),
                        );
                      },
                    );
                  },
                );
          break;
        case 2:
          final playlists = provider.onlineDisplayPlaylists;
          content = playlists.isEmpty
              ? const _EmptyState(message: 'Nenhuma playlist online encontrada.')
              : ListView.separated(
                  key: const PageStorageKey('online_playlists_list'),
                  controller: _controller,
                  padding: EdgeInsets.only(top: 8, bottom: listBottomPadding),
                  itemCount: playlists.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return _OnlinePlaylistRow(
                      playlist: playlist,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => OnlinePlaylistScreen(playlist: playlist)),
                        );
                      },
                    );
                  },
                );
          break;
        default:
          content = const SizedBox.shrink();
      }
    }

    final sectionTitle = switch (_sectionIndex) {
      1 => 'Artistas',
      2 => 'Playlists',
      3 => 'Favoritos online',
      4 => 'Histórico',
      5 => 'Minhas playlists',
      _ => '',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider.onlineActiveQuery.isNotEmpty) ...[
          _OnlineInlineSearchBar(
            controller: provider.searchController,
            onSubmitted: (query) {
              final cleaned = query.trim();
              provider.searchController.text = cleaned;
              provider.searchController.selection = TextSelection.collapsed(offset: cleaned.length);
              setState(() => _sectionIndex = 0);
              provider.setOnlineSectionIndex(0);
              provider.searchOnline(forceQuery: cleaned, refresh: true);
            },
            onClear: () {
              setState(() => _sectionIndex = 0);
              provider.clearOnlineQuery();
            },
          ),
          const SizedBox(height: 12),
        ] else if (_sectionIndex != 0) ...[
          _OnlineSubPageHeader(
            title: sectionTitle,
            onBack: () {
              setState(() => _sectionIndex = 0);
              provider.setOnlineSectionIndex(0);
            },
          ),
          const SizedBox(height: 12),
        ],
        Expanded(child: content),
      ],
    );
  }

  Widget _buildYoutubeMusicHome({
    required BuildContext context,
    required MusicPlayerProvider provider,
    required List<AudioTrack> songs,
    required List<OnlineArtist> artists,
    required List<OnlinePlaylist> playlists,
    required bool isDark,
    required double bottomPadding,
  }) {
    final featuredSongs = songs.take(12).toList(growable: false);
    final featuredPlaylists = playlists.take(12).toList(growable: false);
    final pickSongs = songs.skip(12).take(24).toList(growable: false);
    final moodChips = const <String, String>{
      'Podcasts': 'podcasts música Brasil',
      'Energia': 'músicas animadas energia',
      'Romance': 'músicas românticas',
      'Para treinar': 'músicas para treino',
      'Foco': 'músicas para foco',
      'Para dormir': 'músicas para dormir',
    };
    final loadingEmptyHome = provider.isOnlineLoading && featuredSongs.isEmpty && featuredPlaylists.isEmpty;
    final emptyHome = !loadingEmptyHome && featuredSongs.isEmpty && featuredPlaylists.isEmpty && artists.isEmpty;
    return CustomScrollView(
      key: const PageStorageKey('online_youtube_music_home'),
      controller: _controller,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: moodChips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final label = moodChips.keys.elementAt(index);
                      final query = moodChips[label]!;
                      return _YoutubeMusicChip(
                        label: label,
                        onTap: () {
                          provider.searchController.text = query;
                          provider.searchController.selection = TextSelection.collapsed(offset: query.length);
                          setState(() => _sectionIndex = 0);
                          provider.setOnlineSectionIndex(0);
                          provider.searchOnline(forceQuery: query, refresh: true);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 26),
                _YoutubeSectionHeader(
                  title: 'Acesso rápido',
                  actionLabel: featuredSongs.isEmpty ? null : 'Ver tudo',
                  onActionTap: featuredSongs.isEmpty ? null : () => _openTrackPlayer(context, featuredSongs.first, queue: songs),
                ),
              ],
            ),
          ),
        ),
        if (emptyHome)
          SliverToBoxAdapter(
            child: _OnlineEmptyHomeCard(
              message: provider.onlineError ?? 'Ainda não carreguei recomendações online.',
              onRetry: () => provider.searchOnline(refresh: true),
            ),
          ),
        if (featuredSongs.isNotEmpty || featuredPlaylists.isNotEmpty || loadingEmptyHome)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (featuredSongs.isNotEmpty) {
                    final track = featuredSongs[index];
                    return _YoutubeMusicTile(
                      title: track.title,
                      imageUrl: track.artworkUrl ?? '',
                      onTap: () => _openTrackPlayer(context, track, queue: songs),
                    );
                  }
                  if (featuredPlaylists.isNotEmpty) {
                    final playlist = featuredPlaylists[index];
                    return _YoutubeMusicTile(
                      title: playlist.title,
                      imageUrl: playlist.thumbnailUrl,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlinePlaylistScreen(playlist: playlist))),
                    );
                  }
                  return const _YoutubeLoadingTile();
                },
                childCount: featuredSongs.isNotEmpty
                    ? featuredSongs.length.clamp(0, 9).toInt()
                    : featuredPlaylists.isNotEmpty
                        ? featuredPlaylists.length.clamp(0, 9).toInt()
                        : 9,
              ),
            ),
          ),
        if (songs.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 26)),
          SliverToBoxAdapter(
            child: _YoutubeSectionHeader(
              title: 'Escolhas rápidas',
              actionLabel: 'Ver tudo',
              onActionTap: () => _openTrackPlayer(context, songs.first, queue: songs),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, rawIndex) {
                final list = pickSongs.isEmpty ? songs : pickSongs;
                final itemCount = list.take(12).length;
                if (rawIndex.isOdd) return const SizedBox(height: 6);
                final index = rawIndex ~/ 2;
                if (index >= itemCount) return const SizedBox.shrink();
                final track = list[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _YoutubeSongRow(
                    track: track,
                    isFavorite: provider.isFavorite(track),
                    onTap: () => _openTrackPlayer(context, track, queue: songs),
                    onFavoriteTap: () => provider.toggleFavorite(track),
                  ),
                );
              },
              childCount: ((pickSongs.isEmpty ? songs : pickSongs).take(12).length * 2 - 1).clamp(0, 999).toInt(),
            ),
          ),
        ],
        if (playlists.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 26)),
          const SliverToBoxAdapter(child: _YoutubeSectionHeader(title: 'Mixes e playlists')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: playlists.take(12).length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return SizedBox(
                    width: 142,
                    child: _YoutubeMusicTile(
                      title: playlist.title,
                      subtitle: playlist.author,
                      imageUrl: playlist.thumbnailUrl,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlinePlaylistScreen(playlist: playlist))),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        if (artists.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          const SliverToBoxAdapter(child: _YoutubeSectionHeader(title: 'Artistas para você')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 164,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: artists.take(14).length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  return _YoutubeArtistBubble(
                    artist: artist,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlineArtistScreen(artist: artist))),
                  );
                },
              ),
            ),
          ),
        ],
        ..._metrolistPlaylistRailSlivers(
          context: context,
          title: 'Playlists da comunidade em alta',
          playlists: provider.onlineDisplayPlaylists,
          skip: 12,
          take: 12,
        ),
        ..._metrolistSongRailSlivers(
          context: context,
          title: 'Mixtapes criadas para você',
          songs: songs,
          skip: 18,
          take: 12,
        ),
        ..._metrolistAlbumRailSlivers(
          context: context,
          title: 'Álbuns para você',
          albums: provider.onlineAlbums,
          take: 12,
        ),
        ..._metrolistSongRailSlivers(
          context: context,
          title: 'Ouvir de novo',
          songs: provider.onlineHistoryTracks.isNotEmpty ? provider.onlineHistoryTracks : songs,
          take: 12,
        ),
        ..._metrolistSongRailSlivers(
          context: context,
          title: 'Lançamentos',
          songs: songs,
          skip: 6,
          take: 12,
        ),
        ..._metrolistSongRailSlivers(
          context: context,
          title: 'Em alta nos Shorts',
          songs: songs.reversed.toList(growable: false),
          take: 12,
        ),
        ..._metrolistSongRailSlivers(
          context: context,
          title: songs.isNotEmpty ? 'Parecido com ${songs.first.artist.isEmpty ? songs.first.title : songs.first.artist}' : 'Parecido com o que você ouve',
          songs: songs,
          skip: 3,
          take: 12,
        ),
        ..._metrolistSongRailSlivers(
          context: context,
          title: 'Vídeos de música recomendados',
          songs: songs,
          skip: 9,
          take: 12,
        ),
        ..._metrolistSongRailSlivers(
          context: context,
          title: 'Escolha a dedo',
          songs: songs,
          skip: 1,
          take: 12,
        ),
        SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
      ],
    );
  }


  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}



class _OnlineInlineSearchBar extends StatelessWidget {
  const _OnlineInlineSearchBar({
    required this.controller,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            tooltip: 'Limpar busca',
            icon: const Icon(Icons.close_rounded),
            onPressed: onClear,
          ),
          hintText: 'Buscar músicas online...',
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
        ),
      ),
    );
  }
}

class _OnlineSubPageHeader extends StatelessWidget {
  const _OnlineSubPageHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Voltar',
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _AppAdaptiveIcon extends StatelessWidget {
  const _AppAdaptiveIcon({this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        'assets/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFFF1744),
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: size * 0.7),
        ),
      ),
    );
  }
}

class _YoutubeMusicChip extends StatelessWidget {
  const _YoutubeMusicChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _YoutubeSectionHeader extends StatelessWidget {
  const _YoutubeSectionHeader({required this.title, this.actionLabel, this.onActionTap});

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          if (actionLabel != null)
            OutlinedButton(
              onPressed: onActionTap,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _OnlineEmptyHomeCard extends StatelessWidget {
  const _OnlineEmptyHomeCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded),
          const SizedBox(height: 10),
          Text(
            message,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }
}

class _YoutubeLoadingTile extends StatelessWidget {
  const _YoutubeLoadingTile();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(isDark ? 0.03 : 0.28),
                      Colors.transparent,
                      Colors.white.withOpacity(isDark ? 0.06 : 0.20),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.75),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YoutubeMusicTile extends StatelessWidget {
  const _YoutubeMusicTile({required this.title, required this.imageUrl, required this.onTap, this.subtitle});

  final String title;
  final String? subtitle;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _RemoteArtworkBox(imageUrl: imageUrl, radius: 12),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Colors.transparent, Color(0xAA000000)],
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 8,
                    bottom: 8,
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _YoutubeSongRow extends StatelessWidget {
  const _YoutubeSongRow({
    required this.track,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
  });

  final AudioTrack track;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black54;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 52,
      leading: _RemoteArtworkBox(imageUrl: track.artworkUrl ?? '', size: 54, radius: 8),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${track.artist} • Tocou ${((track.id.hashCode.abs() % 90) + 10)} mi vezes', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: subtle)),
      trailing: IconButton(
        onPressed: onFavoriteTap,
        icon: Icon(isFavorite ? Icons.favorite_rounded : Icons.more_vert_rounded),
      ),
      onTap: onTap,
    );
  }
}

class _YoutubeArtistBubble extends StatelessWidget {
  const _YoutubeArtistBubble({required this.artist, required this.onTap});

  final OnlineArtist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: InkWell(
        borderRadius: BorderRadius.circular(52),
        onTap: onTap,
        child: Column(
          children: [
            _RemoteArtworkBox(imageUrl: artist.thumbnailUrl, size: 94, radius: 47),
            const SizedBox(height: 8),
            Text(artist.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _OnlineSectionChip extends StatelessWidget {
  const _OnlineSectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: isDark ? const Color(0xFF14161D) : Colors.white,
      selectedColor: const Color(0xFF7395FF).withOpacity(0.22),
      side: BorderSide(
        color: selected
            ? const Color(0xFF7395FF)
            : (isDark ? const Color(0xFF252632) : const Color(0xFFE4E6EC)),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
    );
  }
}

class _OnlineAlbumCard extends StatelessWidget {
  const _OnlineAlbumCard({
    required this.album,
    required this.onTap,
  });

  final OnlineAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final subtle = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: _RemoteArtworkBox(
                    imageUrl: album.thumbnailUrl,
                    radius: 26,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 0.98,
                      fontSize: 14.0,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                album.year == null || album.year!.trim().isEmpty
                    ? album.artist
                    : '${album.artist} • ${album.year}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: subtle,
                      fontSize: 12.2,
                      height: 1.0,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineArtistRow extends StatelessWidget {
  const _OnlineArtistRow({
    required this.artist,
    required this.onTap,
  });

  final OnlineArtist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtle = isDark ? Colors.white70 : Colors.black54;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111216) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF252632) : const Color(0xFFE4E6EC),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _RemoteArtworkBox(
                  imageUrl: artist.thumbnailUrl,
                  size: 66,
                  radius: 33,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Abrir artista online',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: subtle),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: subtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnlinePlaylistRow extends StatelessWidget {
  const _OnlinePlaylistRow({
    required this.playlist,
    required this.onTap,
  });

  final OnlinePlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtle = isDark ? Colors.white70 : Colors.black54;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111216) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF252632) : const Color(0xFFE4E6EC),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _RemoteArtworkBox(
                  imageUrl: playlist.thumbnailUrl,
                  size: 74,
                  radius: 18,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        playlist.songCountText == null || playlist.songCountText!.trim().isEmpty
                            ? playlist.author
                            : '${playlist.author} • ${playlist.songCountText}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: subtle),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: subtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteArtworkBox extends StatelessWidget {
  const _RemoteArtworkBox({
    required this.imageUrl,
    this.size,
    this.radius = 24,
  });

  final String imageUrl;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final child = imageUrl.trim().isNotEmpty
        ? Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          )
        : _fallback();

    final wrapped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 1,
        child: child,
      ),
    );

    if (size == null) return wrapped;
    return SizedBox(width: size, height: size, child: wrapped);
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
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white, size: 30),
      ),
    );
  }
}

class OnlineAlbumScreen extends StatelessWidget {
  const OnlineAlbumScreen({super.key, required this.album});

  final OnlineAlbum album;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.read<MusicPlayerProvider>();
    final subtle = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<OnlineAlbumPage>(
          future: provider.loadOnlineAlbum(album.browseId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(child: Text('Falha ao abrir álbum online: ${snapshot.error ?? ''}'));
            }
            final page = snapshot.data!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                      Expanded(child: Text(page.album.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 132),
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: _RemoteArtworkBox(imageUrl: page.album.thumbnailUrl, radius: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              page.album.year == null ? page.album.artist : '${page.album.artist}\n${page.album.year}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: subtle, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ...page.tracks.asMap().entries.map((entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: MusicListTile(
                              track: entry.value,
                              isDark: Theme.of(context).brightness == Brightness.dark,
                              isFavorite: provider.isFavorite(entry.value),
                              onFavoriteTap: () => provider.toggleFavorite(entry.value),
                              onTap: () => _openTrackPlayer(context, entry.value, queue: page.tracks),
                              leadingLabel: '${entry.key + 1}',
                            ),
                          )),
                    ],
                  ),
                ),
                const Align(alignment: Alignment.bottomCenter, child: FloatingPlayerBar()),
              ],
            );
          },
        ),
      ),
    );
  }
}

class OnlineArtistScreen extends StatelessWidget {
  const OnlineArtistScreen({super.key, required this.artist});

  final OnlineArtist artist;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.read<MusicPlayerProvider>();
    final subtle = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<OnlineArtistPage>(
          future: provider.loadOnlineArtist(artist.browseId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(child: Text('Falha ao abrir artista online: ${snapshot.error ?? ''}'));
            }
            final page = snapshot.data!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                      Expanded(child: Text(page.artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 132),
                    children: [
                      if (page.artist.thumbnailUrl.isNotEmpty)
                        Center(
                          child: SizedBox(
                            width: 150,
                            height: 150,
                            child: _RemoteArtworkBox(imageUrl: page.artist.thumbnailUrl, radius: 80),
                          ),
                        ),
                      const SizedBox(height: 18),
                      if (page.artist.name.trim().isNotEmpty) ...[
                        _OnlineSectionHeader(
                          title: t.songs,
                          actionLabel: 'Mostrar tudo',
                          onActionTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => OnlineArtistAllSongsScreen(page: page)),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        ...page.topSongs.map((track) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: MusicListTile(
                                track: track,
                                isDark: Theme.of(context).brightness == Brightness.dark,
                                isFavorite: provider.isFavorite(track),
                                onFavoriteTap: () => provider.toggleFavorite(track),
                                onTap: () => _openTrackPlayer(context, track, queue: page.topSongs),
                              ),
                            )),
                        const SizedBox(height: 18),
                      ],
                      if (page.artist.name.trim().isNotEmpty) ...[
                        _OnlineSectionHeader(
                          title: 'Álbuns',
                          actionLabel: 'Mostrar tudo',
                          onActionTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => OnlineArtistAllAlbumsScreen(page: page)),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        ...page.albums.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _OnlinePlaylistRow(
                                playlist: OnlinePlaylist(
                                  playlistId: item.playlistId ?? item.browseId,
                                  title: item.title,
                                  author: item.artist,
                                  thumbnailUrl: item.thumbnailUrl,
                                  songCountText: item.year,
                                ),
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlineAlbumScreen(album: item)));
                                },
                              ),
                            )),
                        const SizedBox(height: 18),
                      ],
                      if (page.playlists.isNotEmpty) ...[
                        Text(t.playlists, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        ...page.playlists.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _OnlinePlaylistRow(
                                playlist: item,
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlinePlaylistScreen(playlist: item)));
                                },
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
                const Align(alignment: Alignment.bottomCenter, child: FloatingPlayerBar()),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OnlineSectionHeader extends StatelessWidget {
  const _OnlineSectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onActionTap,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onActionTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        TextButton(
          onPressed: onActionTap,
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

class OnlineArtistAllSongsScreen extends StatelessWidget {
  const OnlineArtistAllSongsScreen({super.key, required this.page});

  final OnlineArtistPage page;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<AudioTrack>>(
          future: provider.loadOnlineArtistAllSongs(page),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Falha ao carregar todas as músicas: ${snapshot.error ?? ''}'));
            }
            final tracks = snapshot.data ?? const <AudioTrack>[];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                      Expanded(
                        child: Text(
                          '${page.artist.name} • Músicas',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: tracks.isEmpty
                      ? const Center(child: Text('Nenhuma música encontrada.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 132),
                          itemCount: tracks.length,
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: MusicListTile(
                                track: track,
                                isDark: Theme.of(context).brightness == Brightness.dark,
                                isFavorite: provider.isFavorite(track),
                                onFavoriteTap: () => provider.toggleFavorite(track),
                                onTap: () => _openTrackPlayer(context, track, queue: tracks),
                                leadingLabel: '${index + 1}',
                              ),
                            );
                          },
                        ),
                ),
                const Align(alignment: Alignment.bottomCenter, child: FloatingPlayerBar()),
              ],
            );
          },
        ),
      ),
    );
  }
}

class OnlineArtistAllAlbumsScreen extends StatelessWidget {
  const OnlineArtistAllAlbumsScreen({super.key, required this.page});

  final OnlineArtistPage page;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<OnlineAlbum>>(
          future: provider.loadOnlineArtistAllAlbums(page),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Falha ao carregar todos os álbuns: ${snapshot.error ?? ''}'));
            }
            final albums = snapshot.data ?? const <OnlineAlbum>[];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                      Expanded(
                        child: Text(
                          '${page.artist.name} • Álbuns',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: albums.isEmpty
                      ? const Center(child: Text('Nenhum álbum encontrado.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 132),
                          itemCount: albums.length,
                          itemBuilder: (context, index) {
                            final item = albums[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _OnlinePlaylistRow(
                                playlist: OnlinePlaylist(
                                  playlistId: item.playlistId ?? item.browseId,
                                  title: item.title,
                                  author: item.artist,
                                  thumbnailUrl: item.thumbnailUrl,
                                  songCountText: item.year,
                                ),
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => OnlineAlbumScreen(album: item)));
                                },
                              ),
                            );
                          },
                        ),
                ),
                const Align(alignment: Alignment.bottomCenter, child: FloatingPlayerBar()),
              ],
            );
          },
        ),
      ),
    );
  }
}

class OnlinePlaylistScreen extends StatelessWidget {
  const OnlinePlaylistScreen({super.key, required this.playlist});

  final OnlinePlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.read<MusicPlayerProvider>();
    final subtle = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<OnlinePlaylistPage>(
          future: provider.loadOnlinePlaylist(playlist.playlistId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(child: Text('Falha ao abrir playlist online: ${snapshot.error ?? ''}'));
            }
            final page = snapshot.data!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                      Expanded(child: Text(page.playlist.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 132),
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: _RemoteArtworkBox(imageUrl: page.playlist.thumbnailUrl, radius: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              page.playlist.songCountText == null || page.playlist.songCountText!.trim().isEmpty
                                  ? page.playlist.author
                                  : '${page.playlist.author}\n${page.playlist.songCountText}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: subtle, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ...page.tracks.asMap().entries.map((entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: MusicListTile(
                              track: entry.value,
                              isDark: Theme.of(context).brightness == Brightness.dark,
                              isFavorite: provider.isFavorite(entry.value),
                              onFavoriteTap: () => provider.toggleFavorite(entry.value),
                              onTap: () => _openTrackPlayer(context, entry.value, queue: page.tracks),
                              leadingLabel: '${entry.key + 1}',
                            ),
                          )),
                    ],
                  ),
                ),
                const Align(alignment: Alignment.bottomCenter, child: FloatingPlayerBar()),
              ],
            );
          },
        ),
      ),
    );
  }
}


class _UserPlaylistRow extends StatelessWidget {
  const _UserPlaylistRow({
    required this.playlist,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final UserPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final subtle = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54;
    final coverTrack = playlist.tracks.isNotEmpty ? playlist.tracks.first : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF111216) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF252632) : const Color(0xFFE4E6EC),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 66,
                  height: 66,
                  child: coverTrack == null
                      ? Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8F5BFF), Color(0xFF2C184E)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 34),
                        )
                      : LazyArtwork(
                          track: coverTrack,
                          borderRadius: BorderRadius.circular(18),
                          fallbackIcon: const Icon(Icons.playlist_play_rounded, color: Colors.white, size: 34),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${playlist.tracks.length} faixa${playlist.tracks.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: subtle),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') onRename();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renomear')),
                    PopupMenuItem(value: 'delete', child: Text('Excluir')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UserPlaylistScreen extends StatelessWidget {
  const UserPlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final playlistIndex = provider.userPlaylists.indexWhere((item) => item.id == playlistId);
    final UserPlaylist? playlist = playlistIndex == -1 ? null : provider.userPlaylists[playlistIndex];

    if (playlist == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Playlist não encontrada.')),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtle = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                      Expanded(
                        child: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showRenamePlaylistDialog(context, playlist),
                        icon: const Icon(Icons.edit_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${playlist.tracks.length} faixa${playlist.tracks.length == 1 ? '' : 's'} na playlist',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: subtle),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _showAddTracksToPlaylistSheet(context, playlist),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Adicionar músicas'),
                      ),
                      if (playlist.tracks.isNotEmpty)
                        FilledButton.icon(
                          onPressed: () => _openTrackPlayer(context, playlist.tracks.first, queue: playlist.tracks),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Tocar playlist'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: playlist.tracks.isEmpty
                        ? const _EmptyState(message: 'Adicione músicas para começar essa playlist.')
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 132),
                            itemCount: playlist.tracks.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final track = playlist.tracks[index];
                              return Dismissible(
                                key: ValueKey('${playlist.id}-${track.libraryKey}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 24),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                                ),
                                onDismissed: (_) => provider.removeTrackFromUserPlaylist(playlist.id, track),
                                child: MusicListTile(
                                  track: track,
                                  isDark: isDark,
                                  isFavorite: provider.isFavorite(track),
                                  onFavoriteTap: () => provider.toggleFavorite(track),
                                  onTap: () => _openTrackPlayer(context, track, queue: playlist.tracks),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            const Align(alignment: Alignment.bottomCenter, child: FloatingPlayerBar()),
          ],
        ),
      ),
    );
  }
}

class ArtistDetailScreen extends StatelessWidget {

  const ArtistDetailScreen({
    super.key,
    required this.artistName,
  });

  final String artistName;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final albums = provider.albumsForArtist(artistName).entries.toList();
    final tracksCount = albums.fold<int>(0, (total, entry) => total + entry.value.length);
    final coverTrack = albums.isNotEmpty ? albums.first.value.first : null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtle = isDark ? Colors.white70 : Colors.black54;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (coverTrack != null)
                    Row(
                      children: [
                        SizedBox(width: 108, height: 108, child: _ArtworkCard(track: coverTrack, albumMode: true)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            '${albums.length} álbum(ns)\n$tracksCount faixa(s)',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: subtle,
                                  height: 1.5,
                                ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: albums.isEmpty
                        ? const _EmptyState(message: 'Nenhum álbum encontrado para este artista.')
                        : GridView.builder(
                            padding: const EdgeInsets.only(bottom: 132),
                            itemCount: albums.length,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 14,
                              mainAxisExtent: 216,
                            ),
                            itemBuilder: (context, index) {
                              final entry = albums[index];
                              final albumTracks = provider.albumTracksFor(entry.key);
                              final albumCoverTrack = albumTracks.first;
                              return _AlbumCard(
                                track: albumCoverTrack,
                                tracks: albumTracks,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AlbumDetailScreen(
                                        albumKey: entry.key,
                                        tracks: albumTracks,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  SizedBox(height: keyboardOpen ? 12 : 120),
                ],
              ),
            ),
            if (!keyboardOpen)
              const Align(
                alignment: Alignment.bottomCenter,
                child: FloatingPlayerBar(),
              ),
          ],
        ),
      ),
    );
  }
}

class AlbumDetailScreen extends StatelessWidget {
  const AlbumDetailScreen({
    super.key,
    required this.albumKey,
    required this.tracks,
  });

  final String albumKey;
  final List<AudioTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final sorted = provider.albumTracksFor(albumKey);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtle = isDark ? Colors.white70 : Colors.black54;
    final coverTrack = sorted.isNotEmpty ? sorted.first : tracks.first;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          coverTrack.album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(width: 118, height: 118, child: _ArtworkCard(track: coverTrack, albumMode: true)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '${coverTrack.primaryArtistForAlbum}\n${sorted.length} faixa(s)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: subtle,
                                height: 1.4,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: ListView.separated(
                      key: const PageStorageKey('album_detail_list'),
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final track = sorted[index];
                        return MusicListTile(
                          track: track,
                          leadingLabel: track.trackNumberInt > 0 ? track.trackNumberInt.toString() : '${index + 1}',
                          isDark: isDark,
                          isFavorite: provider.isFavorite(track),
                          onFavoriteTap: () => provider.toggleFavorite(track),
                          onTap: () => _openTrackPlayer(context, track, queue: sorted),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: keyboardOpen ? 12 : 120),
                ],
              ),
            ),
            if (!keyboardOpen)
              const Align(
                alignment: Alignment.bottomCenter,
                child: FloatingPlayerBar(),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.track,
    required this.tracks,
    required this.onTap,
  });

  final AudioTrack track;
  final List<AudioTrack> tracks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final subtle = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: _ArtworkCard(track: track, albumMode: true),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      track.album,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 0.98,
                            fontSize: 14.0,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.primaryArtistForAlbum} | ${tracks.length} faixa${tracks.length == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: subtle,
                            fontSize: 12.2,
                            height: 1.0,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtworkCard extends StatelessWidget {
  const _ArtworkCard({
    required this.track,
    this.albumMode = false,
  });

  final AudioTrack track;
  final bool albumMode;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final radius = BorderRadius.circular(albumMode ? 26 : 22);
    return ClipRRect(
      borderRadius: radius,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF151821)
                : Colors.white,
          ),
          child: LazyArtwork(
            track: track,
            borderRadius: radius,
            fit: BoxFit.cover,
            fallbackIcon: const Icon(Icons.album_rounded, size: 72, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}
