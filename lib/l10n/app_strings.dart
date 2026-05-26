import 'package:flutter/material.dart';

import '../providers/music_player_provider.dart';

class AppStrings {
  AppStrings._(this.languageCode);

  final String languageCode;

  static AppStrings of(BuildContext context) {
    return AppStrings._(Localizations.localeOf(context).languageCode.toLowerCase());
  }

  bool get _en => languageCode.startsWith('en');
  bool get _ja => languageCode.startsWith('ja');

  String _pick(String pt, String en, String ja) {
    if (_ja) return ja;
    if (_en) return en;
    return pt;
  }

  String get appTitle => 'Music';
  String get menu => _pick('Menu', 'Menu', 'メニュー');
  String get searchHint => _pick('Buscar músicas...', 'Search songs...', '曲を検索...');
  String get tracks => _pick('Faixas', 'Tracks', 'トラック');
  String get songs => _pick('Músicas', 'Songs', '曲');
  String get albums => _pick('Álbuns', 'Albums', 'アルバム');
  String get artists => _pick('Artistas', 'Artists', 'アーティスト');
  String get favorites => _pick('Favoritos', 'Favorites', 'お気に入り');
  String get online => _pick('Online', 'Online', 'オンライン');
  String get playlists => _pick('Playlists', 'Playlists', 'プレイリスト');
  String get recentSearches => _pick('Buscas recentes', 'Recent searches', '最近の検索');
  String get clear => _pick('Limpar', 'Clear', 'クリア');
  String get history => _pick('Histórico', 'History', '履歴');
  String get mine => _pick('Minhas', 'Mine', 'マイ');
  String get createPlaylist => _pick('Criar playlist', 'Create playlist', 'プレイリストを作成');
  String get aboutApp => _pick('Sobre o app', 'About the app', 'アプリについて');
  String get equalizer => _pick('Equalizador', 'Equalizer', 'イコライザー');
  String get equalizerOnlyAppAudio => _pick('Afeta apenas o áudio reproduzido neste app.', 'Only affects audio played inside this app.', 'このアプリ内で再生される音声にのみ適用されます。');
  String get equalizerEnable => _pick('Ativar equalizador', 'Enable equalizer', 'イコライザーを有効にする');
  String get equalizerReset => _pick('Zerar bandas', 'Reset bands', 'バンドをリセット');
  String get equalizerNeedsPlayback => _pick('Comece a reproduzir uma música no app para ativar o equalizador.', 'Start playback in the app to activate the equalizer.', 'イコライザーを有効にするには、このアプリで音楽の再生を開始してください。');
  String get equalizerUnsupported => _pick('Seu aparelho não suporta equalizador por sessão de áudio neste app.', 'Your device does not support an app-only audio-session equalizer.', 'この端末はアプリ専用のオーディオセッションイコライザーをサポートしていません。');

  String get equalizerStatusActive => _pick('Ativo no áudio deste app', 'Active for audio in this app', 'このアプリの音声で有効');
  String get equalizerStatusOff => _pick('Desativado', 'Disabled', '無効');
  String get equalizerPresetBalanced => _pick('Equilibrado', 'Balanced', 'バランス');
  String get equalizerPresetBassBoost => _pick('Mais graves', 'More bass', '低音強調');
  String get equalizerPresetSoft => _pick('Suave', 'Soft', 'ソフト');
  String get equalizerPresetDynamic => _pick('Dinâmico', 'Dynamic', 'ダイナミック');
  String get equalizerPresetCrisp => _pick('Nítido', 'Crisp', 'クリア');
  String get equalizerPresetTrebleBoost => _pick('Mais agudos', 'More treble', '高音強調');
  String get equalizerPresetCustom => _pick('Personalizado', 'Custom', 'カスタム');
  String get equalizerDescriptionBalanced => _pick('Um som natural com frequências bem equilibradas.', 'A natural sound with well-balanced frequencies.', '周波数バランスが整った自然なサウンドです。');
  String get equalizerDescriptionBassBoost => _pick('Reforça graves e subgraves para mais peso e impacto.', 'Boosts bass and sub-bass for more weight and impact.', '低音と超低音を強調して、より重厚で迫力のある音にします。');
  String get equalizerDescriptionSoft => _pick('Deixa o som mais suave e confortável por longos períodos.', 'Makes the sound softer and more comfortable for long listening.', '長時間でも聴きやすい柔らかなサウンドにします。');
  String get equalizerDescriptionDynamic => _pick('Curva em V com mais energia nos graves e brilho nos agudos.', 'V-shaped curve with more bass energy and brighter highs.', '低音の迫力と高音のきらめきを強めたV字カーブです。');
  String get equalizerDescriptionCrisp => _pick('Realça presença, vocais e detalhes para um som mais definido.', 'Enhances presence, vocals and details for a clearer sound.', '存在感やボーカル、細部を強調してより明瞭な音にします。');
  String get equalizerDescriptionTrebleBoost => _pick('Aumenta brilho e definição das frequências altas.', 'Increases brightness and definition in the high frequencies.', '高域の明るさと解像感を高めます。');
  String get equalizerDescriptionCustom => _pick('Ajuste manual das bandas do equalizador.', 'Manual adjustment of the equalizer bands.', 'イコライザーの各バンドを手動で調整します。');
  String get developedBy => _pick('Desenvolvido por', 'Developed by', '開発者');
  String get language => _pick('Idioma', 'Language', '言語');
  String get portuguese => 'Português';
  String get english => 'English';
  String get japanese => '日本語';
  String get whatsapp => 'WhatsApp';
  String get telegram => 'Telegram';
  String get tapToOpen => _pick('Toque para abrir', 'Tap to open', 'タップして開く');
  String get tapToCopy => _pick('Toque para copiar', 'Tap to copy', 'タップしてコピー');
  String copied(String label) => _pick('$label copiado.', '$label copied.', '$label をコピーしました。');
  String get couldNotOpenLink => _pick('Não foi possível abrir o link.', 'Could not open the link.', 'リンクを開けませんでした。');
  String get sortRelease => _pick('Lançamento', 'Release date', 'リリース日');
  String get sortAlphabetical => _pick('Ordem alfabética', 'Alphabetical order', 'アルファベット順');
  String get sortByArtist => _pick('Por artista', 'By artist', 'アーティスト順');
  String get newPlaylist => _pick('Nova playlist', 'New playlist', '新しいプレイリスト');
  String get renamePlaylist => _pick('Renomear playlist', 'Rename playlist', 'プレイリスト名を変更');
  String get playlistName => _pick('Nome da playlist', 'Playlist name', 'プレイリスト名');
  String get cancel => _pick('Cancelar', 'Cancel', 'キャンセル');
  String get create => _pick('Criar', 'Create', '作成');
  String get save => _pick('Salvar', 'Save', '保存');
  String get addToPlaylist => _pick('Adicionar à playlist', 'Add to playlist', 'プレイリストに追加');
  String get noPlaylistsYet => _pick(
        'Você ainda não tem playlists. Crie uma agora para adicionar esta música.',
        'You do not have playlists yet. Create one now to add this song.',
        'まだプレイリストがありません。この曲を追加するために新しく作成してください。',
      );
  String get createNewPlaylist => _pick('Criar nova playlist', 'Create new playlist', '新しいプレイリストを作成');
  String addedToPlaylist(String track, String playlist) => _pick(
        '"$track" adicionada à playlist $playlist.',
        '"$track" added to playlist $playlist.',
        '「$track」をプレイリスト「$playlist」に追加しました。',
      );
  String playlistSongCount(int count) => _pick('$count música(s)', '$count song(s)', '$count 曲');
  String get playingNow => _pick('Tocando agora', 'Now playing', '再生中');
  String get noTrackPlaying => _pick('Nenhuma faixa em reprodução.', 'No track is playing.', '再生中の曲はありません。');
  String get shuffle => _pick('Aleatório', 'Shuffle', 'シャッフル');
  String get noRepeat => _pick('Sem repetição', 'No repeat', 'リピートなし');
  String get repeatTrack => _pick('Repetir faixa', 'Repeat track', '1曲リピート');
  String get repeatAlbum => _pick('Repetir álbum', 'Repeat album', 'アルバムをリピート');
  String get musicTags => _pick('Tags da música', 'Song tags', '曲のタグ');
  String get lyrics => _pick('Letra', 'Lyrics', '歌詞');
  String get playQueue => _pick('Fila de reprodução', 'Playback queue', '再生キュー');
  String get previousInQueue => _pick('Anteriores', 'Previous', '前の曲');
  String get nextInQueue => _pick('Próximas', 'Up next', '次の曲');
  String get downloadFailed => _pick('Falha ao baixar', 'Download failed', 'ダウンロードに失敗しました');
  String get onlineIntroRecommendations => _pick(
        'Sugestões online carregadas do YouTube Music com músicas realmente recomendadas pelas suas preferências, artistas favoritos e pesquisas. Você também pode buscar por músicas, artistas, playlists e criar suas próprias playlists.',
        'Online suggestions loaded from YouTube Music with songs recommended from your preferences, favorite artists and searches. You can also search for songs, artists and playlists, and create your own playlists.',
        'YouTube Music から好み、お気に入りのアーティスト、検索に基づくおすすめを読み込みました。曲、アーティスト、プレイリストを検索したり、自分のプレイリストを作成したりできます。',
      );
  String get onlineIntroResults => _pick(
        'Resultados online do YouTube Music com músicas, artistas, playlists, favoritas e histórico.',
        'Online YouTube Music results with songs, artists, playlists, favorites and history.',
        'YouTube Music のオンライン結果です。曲、アーティスト、プレイリスト、お気に入り、履歴を表示します。',
      );

  String labelForEqualizerPreset(EqualizerPreset preset) {
    switch (preset) {
      case EqualizerPreset.balanced:
        return equalizerPresetBalanced;
      case EqualizerPreset.bassBoost:
        return equalizerPresetBassBoost;
      case EqualizerPreset.soft:
        return equalizerPresetSoft;
      case EqualizerPreset.dynamic:
        return equalizerPresetDynamic;
      case EqualizerPreset.crisp:
        return equalizerPresetCrisp;
      case EqualizerPreset.trebleBoost:
        return equalizerPresetTrebleBoost;
      case EqualizerPreset.custom:
        return equalizerPresetCustom;
    }
  }

  String descriptionForEqualizerPreset(EqualizerPreset preset) {
    switch (preset) {
      case EqualizerPreset.balanced:
        return equalizerDescriptionBalanced;
      case EqualizerPreset.bassBoost:
        return equalizerDescriptionBassBoost;
      case EqualizerPreset.soft:
        return equalizerDescriptionSoft;
      case EqualizerPreset.dynamic:
        return equalizerDescriptionDynamic;
      case EqualizerPreset.crisp:
        return equalizerDescriptionCrisp;
      case EqualizerPreset.trebleBoost:
        return equalizerDescriptionTrebleBoost;
      case EqualizerPreset.custom:
        return equalizerDescriptionCustom;
    }
  }


  String labelForLanguage(AppLanguage language) {
    switch (language) {
      case AppLanguage.portuguese:
        return portuguese;
      case AppLanguage.english:
        return english;
      case AppLanguage.japanese:
        return japanese;
    }
  }
}
