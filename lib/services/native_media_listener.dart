import 'dart:async';
import 'package:flutter/services.dart';

class MediaTrackEvent {
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final Duration position;
  final bool isPlaying;
  final String packageName;
  final String accentColor;

  const MediaTrackEvent({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.position,
    required this.isPlaying,
    required this.packageName,
    this.accentColor = '#D4FF70',
  });

  factory MediaTrackEvent.fromMap(Map<dynamic, dynamic> map) {
    return MediaTrackEvent(
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? '',
      album: map['album'] as String? ?? '',
      duration: Duration(milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0),
      position: Duration(milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0),
      isPlaying: map['isPlaying'] as bool? ?? false,
      packageName: map['packageName'] as String? ?? '',
      accentColor: map['accentColor'] as String? ?? '#D4FF70',
    );
  }
}

class NativeMediaListener {
  static const MethodChannel _methodChannel = MethodChannel('com.inline.lyrics/media_control');
  static const EventChannel _eventChannel = EventChannel('com.inline.lyrics/media_events');

  static final NativeMediaListener instance = NativeMediaListener._();
  NativeMediaListener._() {
    _methodChannel.setMethodCallHandler((call) async {
      if (call.method == 'onTimingOffsetChanged') {
        final offset = (call.arguments as Map<dynamic, dynamic>?)?['offsetMs'] as int? ?? 0;
        onTimingOffsetChanged?.call(offset);
      }
    });
  }

  void Function(int offsetMs)? onTimingOffsetChanged;
  Stream<MediaTrackEvent>? _stream;

  Stream<MediaTrackEvent> get stream {
    _stream ??= _eventChannel.receiveBroadcastStream().map((event) {
      return MediaTrackEvent.fromMap(event as Map<dynamic, dynamic>);
    });
    return _stream!;
  }

  Future<bool> hasNotificationPermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('hasNotificationPermission');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNotificationSettings() async {
    try {
      await _methodChannel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  Future<bool> hasOverlayPermission() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('hasOverlayPermission');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> openOverlaySettings() async {
    try {
      await _methodChannel.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  Future<bool> showOverlay() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('showOverlay');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> closeOverlay() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('closeOverlay');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isOverlayActive() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('isOverlayActive');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateOverlayLyric({
    required String text,
    required bool isSynced,
    required bool isPlaying,
    double fontSize = 14.5,
    String transitionStyle = 'slide',
    String chipStyle = 'pill',
    String accentColor = '#D4FF70',
    String nextLyricText = '',
    String trackTitle = '',
    String artistName = '',
  }) async {
    try {
      await _methodChannel.invokeMethod('updateOverlayLyric', {
        'text': text,
        'isSynced': isSynced,
        'isPlaying': isPlaying,
        'fontSize': fontSize,
        'transitionStyle': transitionStyle,
        'chipStyle': chipStyle,
        'accentColor': accentColor,
        'nextLyricText': nextLyricText,
        'trackTitle': trackTitle,
        'artistName': artistName,
      });
    } catch (_) {}
  }

  Future<void> checkActiveTrack() async {
    try {
      await _methodChannel.invokeMethod('checkActiveTrack');
    } catch (_) {}
  }

  Future<void> sendMediaAction(String action) async {
    try {
      await _methodChannel.invokeMethod('sendMediaAction', {'action': action});
    } catch (_) {}
  }

  Future<void> setOverlayOpacity(double opacity) async {
    try {
      await _methodChannel.invokeMethod('setOverlayOpacity', {'opacity': opacity});
    } catch (_) {}
  }

  Future<void> setTimingOffset(int offsetMs) async {
    try {
      await _methodChannel.invokeMethod('setTimingOffset', {'offsetMs': offsetMs});
    } catch (_) {}
  }

  Future<void> setAutoHideWhenPaused(bool enabled) async {
    try {
      await _methodChannel.invokeMethod('setAutoHideWhenPaused', {'enabled': enabled});
    } catch (_) {}
  }
}
