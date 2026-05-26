import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class AudioRuntime {
  AudioRuntime._();

  static AudioPlayer? _sharedPlayer;
  static AppAudioHandler? _handler;
  static Future<void>? _initFuture;
  static Future<void> Function()? _skipNextCallback;
  static Future<void> Function()? _skipPreviousCallback;

  static AudioPlayer get sharedPlayer => _sharedPlayer ??= AudioPlayer(
        handleInterruptions: true,
        androidApplyAudioAttributes: true,
      );

  static AppAudioHandler? get handler => _handler;
  static bool get handlerReady => _handler != null;

  static Future<void> init({
    Duration? timeout,
  }) {
    _initFuture ??= _doInit();
    if (timeout == null) {
      return _initFuture!;
    }
    return _initFuture!.timeout(timeout, onTimeout: () {});
  }

  static Future<void> _doInit() async {
    if (_handler != null) return;
    try {
      final created = await AudioService.init(
        builder: () => AppAudioHandler(sharedPlayer),
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.hirumisu.musicapp.channel.audio',
          androidNotificationChannelName: 'Reprodução de música',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          preloadArtwork: true,
        ),
      );
      _handler = created is AppAudioHandler ? created : null;
    } catch (_) {
      _handler = null;
    }
  }

  static Future<void> updateQueue(
    List<MediaItem> items, {
    required int initialIndex,
  }) async {
    final current = _handler;
    if (current == null) return;
    await current.updateQueueItems(items, initialIndex: initialIndex);
  }

  static Future<void> updateCurrentItem(MediaItem item) async {
    final current = _handler;
    if (current == null) return;
    await current.updateCurrentItem(item);
  }
  static void setNavigationCallbacks({
    Future<void> Function()? onSkipNext,
    Future<void> Function()? onSkipPrevious,
  }) {
    _skipNextCallback = onSkipNext;
    _skipPreviousCallback = onSkipPrevious;
  }
}


class AppAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  AppAudioHandler(this.player) {
    _playbackEventSub = player.playbackEventStream.listen((_) => _broadcastState());
    _currentIndexSub = player.currentIndexStream.listen(_handleCurrentIndexChanged);
    _sequenceStateSub = player.sequenceStateStream.listen(_handleSequenceStateChanged);
    _durationSub = player.durationStream.listen((_) => _broadcastState());
    _broadcastState();
  }

  final AudioPlayer player;
  late final StreamSubscription<PlaybackEvent> _playbackEventSub;
  late final StreamSubscription<int?> _currentIndexSub;
  late final StreamSubscription<SequenceState?> _sequenceStateSub;
  late final StreamSubscription<Duration?> _durationSub;
  List<MediaItem> _queueItems = const <MediaItem>[];

  Future<void> updateQueueItems(List<MediaItem> items, {required int initialIndex}) async {
    _queueItems = List<MediaItem>.unmodifiable(items);
    queue.add(_queueItems);
    _broadcastState();
  }

  Future<void> updateCurrentItem(MediaItem item) async {
    if (_queueItems.isEmpty) {
      _queueItems = List<MediaItem>.unmodifiable(<MediaItem>[item]);
      queue.add(_queueItems);
    }
    mediaItem.add(item);
    _broadcastState();
  }


  void _handleSequenceStateChanged(SequenceState? state) {
    final source = state?.currentSource;
    final tag = source?.tag;
    if (tag is MediaItem) {
      mediaItem.add(tag);
      _broadcastState();
    }
  }

  void _handleCurrentIndexChanged(int? index) {
    final tagged = player.sequenceState?.currentSource?.tag;
    if (tagged is MediaItem) {
      mediaItem.add(tagged);
    }
    _broadcastState();
  }

  AudioProcessingState _mapState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  void _broadcastState() {
    final playing = player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const <int>[0, 1, 2],
        processingState: _mapState(player.processingState),
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: player.currentIndex ?? 0,
      ),
    );
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    final callback = AudioRuntime._skipNextCallback;
    if (callback != null) {
      await callback();
      return;
    }
    if (player.hasNext) {
      await player.seekToNext();
      await player.play();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final callback = AudioRuntime._skipPreviousCallback;
    if (callback != null) {
      await callback();
      return;
    }
    if (player.hasPrevious) {
      await player.seekToPrevious();
      await player.play();
    } else {
      await player.seek(Duration.zero);
      await player.play();
    }
  }

  @override
  Future<void> stop() async {
    await player.stop();
    return super.stop();
  }
}
