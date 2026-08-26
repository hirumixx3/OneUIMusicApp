# OneUIMusicApp v1.5.0 — Online/Performance pass

- Online Home expanded in the MetroList/YouTube Music style with quick access, listen again, account likes/library, hand-picked tracks, mixes/playlists, artists, discoveries, releases, similar music and mood/genre cards.
- Google/YouTube Music authenticated Innertube path retained and used for history, LM liked songs, library songs/albums/artists/playlists and personalized home when the account cookie is present.
- Artist name in Player is now interactive and opens a dedicated artist destination using cached provider requests.
- Liquid Glass remains enabled. Glass widgets now subscribe only to blur/transparency settings instead of every MusicPlayerProvider notification, substantially reducing needless rebuilds during playback/scrolling.
- Atmospheric liquid orbs respect the blur setting and skip ImageFiltered work when blur is disabled.
- Blur-off surfaces become opaque and drop the glass highlight gradient, preserving text/icon contrast and avoiding the expensive backdrop pass.
- Existing RepaintBoundary and artwork downsampling/cache paths are preserved.
