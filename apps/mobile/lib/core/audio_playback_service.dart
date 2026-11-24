import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// A small app-facing contract so screens do not own audio engine instances.
abstract interface class AppAudioPlayback {
  Stream<PlaybackState> get playbackStateStream;
  bool get isPlaying;

  /// Emits the current playback position (G16 player progress).
  Stream<Duration> get positionStream;

  /// The duration of the current track, when known.
  Duration? get duration;

  /// The playback speed currently applied (G16 speed control).
  double get speed;

  Future<void> playRemote({
    required Uri uri,
    required String id,
    required String title,
    String artist = 'خزائن الهدى',
    String album = 'المكتبة الصوتية',
  });

  Future<void> playLocal({
    required String path,
    required String id,
    required String title,
    String artist = 'خزائن الهدى',
    String album = 'القرآن الكريم',
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> setLoopMode(LoopMode mode);

  /// Seeks to [position] inside the current track.
  Future<void> seekTo(Duration position);

  /// Applies a playback speed between 0.75 and 1.25 (G16).
  Future<void> setPlaybackSpeed(double speed);
}

final appAudioPlaybackProvider = Provider<AppAudioPlayback>((ref) {
  throw UnimplementedError(
    'AppAudioPlayback must be initialized with AudioService in main.dart.',
  );
});

/// One process-wide playback engine for the audio library and Quran reader.
/// AudioService owns the handler lifetime; screens must never dispose it.
class KhazainAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements AppAudioPlayback {
  KhazainAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _subscriptions.add(_player.playbackEventStream.listen(
      (_) => _publishPlaybackState(),
      onError: (Object error, StackTrace stackTrace) {
        _publishPlaybackError();
      },
    ));
    _subscriptions.add(_player.playerStateStream.listen((_) => _publishPlaybackState()));
  }

  final AudioPlayer _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  Stream<PlaybackState> get playbackStateStream => playbackState;

  @override
  bool get isPlaying => _player.playing;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Duration? get duration => _player.duration;

  @override
  double get speed => _player.speed;

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  @override
  Future<void> setPlaybackSpeed(double speed) {
    final clamped = speed.clamp(0.75, 1.25).toDouble();
    return _player.setSpeed(clamped);
  }

  @override
  Future<void> playRemote({
    required Uri uri,
    required String id,
    required String title,
    String artist = 'خزائن الهدى',
    String album = 'المكتبة الصوتية',
  }) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Only HTTPS audio sources are allowed.');
    }
    await _player.setAudioSource(AudioSource.uri(uri));
    mediaItem.add(MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: _player.duration,
    ));
    // AudioPlayer.play() completes when the track ends; do not block the UI
    // action that starts playback. Errors are reflected by errorStream above.
    unawaited(_player.play());
  }

  @override
  Future<void> playLocal({
    required String path,
    required String id,
    required String title,
    String artist = 'خزائن الهدى',
    String album = 'القرآن الكريم',
  }) async {
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      throw ArgumentError.value(path, 'path', 'Audio file is missing or empty.');
    }
    await _player.setAudioSource(AudioSource.file(file.path));
    mediaItem.add(MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: _player.duration,
    ));
    unawaited(_player.play());
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    mediaItem.add(null);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);

  @override
  Future<void> onTaskRemoved() async {
    // Keep playback active while Android removes the task from Recents.
    // The foreground media service remains responsible for its lifecycle.
  }

  void _publishPlaybackError() {
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.error,
      errorCode: 1,
      errorMessage: 'Audio playback failed.',
    ));
  }

  void _publishPlaybackState() {
    final playing = _player.playing;
    final processingState = switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    playbackState.add(PlaybackState(
      controls: [
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1],
      processingState: processingState,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: 0,
    ));
  }
}
