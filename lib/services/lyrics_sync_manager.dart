import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/lyric_model.dart';
import '../utils/transliteration_helper.dart';
import 'lrclib_service.dart';
import 'native_media_listener.dart';

enum OverlayThemeStyle {
  pill,      // Dynamic Pill: 1-line capsule
  squircle,  // Box 2L: nearly squared off 2-line box
  ticker,    // Ticker: ultra-slim compact bar
  neon,      // Neon: glowing dynamic border
  brutalist, // Monolith: sharp with accent strip
  card,      // Notch Card: top-docked card
}

enum LyricTransitionStyle {
  slide, // Smooth vertical glide up with fade
  scale, // Subtle zoom in & fade (Apple Music style)
  fade,  // Elegant crossfade glow
  pop,   // Springy bounce pop
}

class OverlaySettings {
  final bool showProgress;
  final bool multiLinePreview;
  final double fontSize;
  final double opacity;
  final OverlayThemeStyle themeStyle;
  final LyricTransitionStyle transitionStyle;
  final bool autoHideWhenPaused;

  const OverlaySettings({
    this.showProgress = true,
    this.multiLinePreview = true,
    this.fontSize = 14.0,
    this.opacity = 0.95,
    this.themeStyle = OverlayThemeStyle.pill,
    this.transitionStyle = LyricTransitionStyle.slide,
    this.autoHideWhenPaused = false,
  });

  Map<String, dynamic> toJson() => {
        'showProgress': showProgress,
        'multiLinePreview': multiLinePreview,
        'fontSize': fontSize,
        'opacity': opacity,
        'themeStyle': themeStyle.index,
        'transitionStyle': transitionStyle.index,
        'autoHideWhenPaused': autoHideWhenPaused,
      };

  factory OverlaySettings.fromJson(Map<String, dynamic> json) => OverlaySettings(
        showProgress: json['showProgress'] as bool? ?? true,
        multiLinePreview: json['multiLinePreview'] as bool? ?? true,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 0.95,
        themeStyle: OverlayThemeStyle.values[json['themeStyle'] as int? ?? 0],
        transitionStyle: LyricTransitionStyle.values[json['transitionStyle'] as int? ?? 0],
        autoHideWhenPaused: json['autoHideWhenPaused'] as bool? ?? false,
      );
}

class LyricsSyncManager extends ChangeNotifier {
  static final LyricsSyncManager _instance = LyricsSyncManager._internal();
  factory LyricsSyncManager() => _instance;
  LyricsSyncManager._internal();

  // State
  String? _trackTitle;
  String? _artistName;
  String? _albumName;
  String _accentColor = '#D4FF70';
  Duration _trackDuration = Duration.zero;
  Duration _currentPosition = Duration.zero;
  int _timingOffsetMs = 0;
  bool _isPlaying = false;
  bool _isLoadingLyrics = false;
  bool _isOverlayActive = false;
  bool _hasNotificationAccess = false;
  bool _hasOverlayAccess = false;
  bool _isRomajiEnabled = false;
  bool _isManualLyricsPinned = false;

  SongLyrics? _currentLyrics;
  int _currentLyricIndex = -1;
  Timer? _positionTimer;
  DateTime? _lastSyncTimestamp;

  OverlaySettings _settings = const OverlaySettings();

  // Getters
  String? get trackTitle => _trackTitle;
  String? get artistName => _artistName;
  String? get albumName => _albumName;
  String get accentColor => _accentColor;
  Duration get trackDuration => _trackDuration;
  Duration get currentPosition => _currentPosition;
  int get timingOffsetMs => _timingOffsetMs;
  bool get isPlaying => _isPlaying;
  bool get isLoadingLyrics => _isLoadingLyrics;
  bool get isOverlayActive => _isOverlayActive;
  bool get hasNotificationAccess => _hasNotificationAccess;
  bool get hasOverlayAccess => _hasOverlayAccess;
  bool get isRomajiEnabled => _isRomajiEnabled;
  bool get isManualLyricsPinned => _isManualLyricsPinned;
  SongLyrics? get currentLyrics => _currentLyrics;
  int get currentLyricIndex => _currentLyricIndex;
  OverlaySettings get settings => _settings;
  LyricTransitionStyle get transitionStyle => _settings.transitionStyle;
  OverlayThemeStyle get chipStyle => _settings.themeStyle;

  String get currentLyricText {
    if (_currentLyrics == null) {
      return _trackTitle != null ? '$_trackTitle • $_artistName' : 'No track playing';
    }
    String text;
    if (!_currentLyrics!.isSynced) {
      text = _currentLyrics!.rawPlainLyrics?.split('\n').firstWhere(
                (l) => l.trim().isNotEmpty,
                orElse: () => 'Lyrics available (unsynced)',
              ) ??
          'Lyrics available (unsynced)';
    } else if (_currentLyricIndex >= 0 && _currentLyricIndex < _currentLyrics!.lines.length) {
      text = _currentLyrics!.lines[_currentLyricIndex].text.trim();
      if (text.isEmpty) text = '♪ ♪ ♪';
    } else {
      text = '♪ ♪ ♪';
    }

    return _isRomajiEnabled ? TransliterationHelper.toRomaji(text) : text;
  }

  String get nextLyricText {
    if (_currentLyrics != null &&
        _currentLyrics!.isSynced &&
        _currentLyricIndex + 1 < _currentLyrics!.lines.length) {
      final next = _currentLyrics!.lines[_currentLyricIndex + 1].text.trim();
      final str = next.isEmpty ? '...' : next;
      return _isRomajiEnabled ? TransliterationHelper.toRomaji(str) : str;
    }
    return '';
  }

  void updateSettings(OverlaySettings newSettings) {
    _settings = newSettings;
    _broadcastStateToOverlay();
    notifyListeners();
  }

  void setTransitionStyle(LyricTransitionStyle style) {
    _settings = OverlaySettings(
      fontSize: _settings.fontSize,
      opacity: _settings.opacity,
      showProgress: _settings.showProgress,
      multiLinePreview: _settings.multiLinePreview,
      themeStyle: _settings.themeStyle,
      transitionStyle: style,
      autoHideWhenPaused: _settings.autoHideWhenPaused,
    );
    _broadcastStateToOverlay();
    notifyListeners();
  }

  void setChipStyle(OverlayThemeStyle style) {
    _settings = OverlaySettings(
      fontSize: _settings.fontSize,
      opacity: _settings.opacity,
      showProgress: _settings.showProgress,
      multiLinePreview: _settings.multiLinePreview,
      themeStyle: style,
      transitionStyle: _settings.transitionStyle,
      autoHideWhenPaused: _settings.autoHideWhenPaused,
    );
    _broadcastStateToOverlay();
    notifyListeners();
  }

  void adjustTimingOffset(int deltaMs) {
    _timingOffsetMs += deltaMs;
    NativeMediaListener.instance.setTimingOffset(_timingOffsetMs);
    _syncLyricIndex();
    _broadcastStateToOverlay();
    notifyListeners();
  }

  void resetTimingOffset() {
    _timingOffsetMs = 0;
    NativeMediaListener.instance.setTimingOffset(0);
    _syncLyricIndex();
    _broadcastStateToOverlay();
    notifyListeners();
  }

  void toggleRomaji() {
    _isRomajiEnabled = !_isRomajiEnabled;
    _broadcastStateToOverlay();
    notifyListeners();
  }

  void setOpacity(double value) {
    _settings = OverlaySettings(
      fontSize: _settings.fontSize,
      opacity: value,
      showProgress: _settings.showProgress,
      multiLinePreview: _settings.multiLinePreview,
      themeStyle: _settings.themeStyle,
      transitionStyle: _settings.transitionStyle,
      autoHideWhenPaused: _settings.autoHideWhenPaused,
    );
    NativeMediaListener.instance.setOverlayOpacity(value);
    notifyListeners();
  }

  void toggleAutoHideWhenPaused() {
    final next = !_settings.autoHideWhenPaused;
    _settings = OverlaySettings(
      fontSize: _settings.fontSize,
      opacity: _settings.opacity,
      showProgress: _settings.showProgress,
      multiLinePreview: _settings.multiLinePreview,
      themeStyle: _settings.themeStyle,
      transitionStyle: _settings.transitionStyle,
      autoHideWhenPaused: next,
    );
    NativeMediaListener.instance.setAutoHideWhenPaused(next);
    notifyListeners();
  }

  Future<void> skipNext() async {
    await NativeMediaListener.instance.sendMediaAction('next');
  }

  Future<void> skipPrevious() async {
    await NativeMediaListener.instance.sendMediaAction('previous');
  }

  Future<void> toggleMediaPlay() async {
    await NativeMediaListener.instance.sendMediaAction('toggle');
  }

  Future<List<SongLyrics>> searchCandidates(String query) => LrclibService.searchCandidates(query);

  void pinManualLyrics(SongLyrics lyrics) {
    _currentLyrics = lyrics;
    _isManualLyricsPinned = true;
    _syncLyricIndex();
    _broadcastStateToOverlay();
    notifyListeners();
  }

  void unpinManualLyrics() {
    _isManualLyricsPinned = false;
    _fetchLyricsForCurrentTrack();
  }

  /// Initialize native MediaSession listener
  Future<void> init() async {
    await refreshPermissions();
    NativeMediaListener.instance.stream.listen(_handleTrackEvent);
    NativeMediaListener.instance.onTimingOffsetChanged = (offset) {
      _timingOffsetMs = offset;
      _syncLyricIndex();
      notifyListeners();
    };
    await NativeMediaListener.instance.checkActiveTrack();
    _startPositionTicker();
  }

  Future<void> refreshPermissions() async {
    _hasNotificationAccess = await NativeMediaListener.instance.hasNotificationPermission();
    _hasOverlayAccess = await NativeMediaListener.instance.hasOverlayPermission();
    _isOverlayActive = await NativeMediaListener.instance.isOverlayActive();
    notifyListeners();
  }

  Future<void> openNotificationSettings() async {
    await NativeMediaListener.instance.openNotificationSettings();
    await refreshPermissions();
  }

  Future<void> openOverlaySettings() async {
    await NativeMediaListener.instance.openOverlaySettings();
    await refreshPermissions();
  }

  void _handleTrackEvent(MediaTrackEvent track) {
    final title = track.title.trim();
    final artist = track.artist.trim().isNotEmpty ? track.artist.trim() : 'Unknown Artist';
    final isNowPlaying = track.isPlaying;

    if (title.isEmpty) return;

    final isNewTrack = (title != _trackTitle || artist != _artistName);

    _trackTitle = title;
    _artistName = artist;
    _albumName = track.album;
    _accentColor = track.accentColor;
    _trackDuration = track.duration;
    _isPlaying = isNowPlaying;

    if (track.position > Duration.zero) {
      _currentPosition = track.position;
      _lastSyncTimestamp = DateTime.now();
    }

    if (isNewTrack) {
      if (!_isManualLyricsPinned) {
        _timingOffsetMs = 0;
        NativeMediaListener.instance.setTimingOffset(0);
        _fetchLyricsForCurrentTrack();
      } else {
        _syncLyricIndex();
        _broadcastStateToOverlay();
        notifyListeners();
      }
    } else {
      _syncLyricIndex();
      _broadcastStateToOverlay();
      notifyListeners();
    }
  }

  /// Fetch lyrics from LRCLIB
  Future<void> _fetchLyricsForCurrentTrack() async {
    final title = _trackTitle;
    final artist = _artistName;
    if (title == null) return;

    _isLoadingLyrics = true;
    _currentLyrics = null;
    _currentLyricIndex = -1;
    notifyListeners();
    _broadcastStateToOverlay();

    final durSec = _trackDuration.inSeconds > 0 ? _trackDuration.inSeconds.toDouble() : null;
    final lyrics = await LrclibService.fetchLyrics(
      trackName: title,
      artistName: artist ?? '',
      durationSeconds: durSec,
    );

    if (_trackTitle == title) {
      _currentLyrics = lyrics;
      _isLoadingLyrics = false;
      _syncLyricIndex();
      _broadcastStateToOverlay();
      notifyListeners();
    }
  }

  /// Local 250ms extrapolation timer matching Quickshell MprisPanel
  void _startPositionTicker() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!_isPlaying) return;

      if (_lastSyncTimestamp != null) {
        final elapsed = DateTime.now().difference(_lastSyncTimestamp!);
        if (elapsed.inSeconds > 10) {
          _currentPosition += const Duration(milliseconds: 250);
        } else {
          _currentPosition = _currentPosition + const Duration(milliseconds: 250);
        }
      } else {
        _currentPosition += const Duration(milliseconds: 250);
      }

      if (_trackDuration > Duration.zero && _currentPosition > _trackDuration) {
        _currentPosition = _trackDuration;
      }

      _syncLyricIndex();
    });
  }

  /// Matches current timestamp to lyric line
  void _syncLyricIndex() {
    if (_currentLyrics == null || !_currentLyrics!.isSynced || _currentLyrics!.lines.isEmpty) {
      if (_currentLyricIndex != -1) {
        _currentLyricIndex = -1;
        notifyListeners();
        _broadcastStateToOverlay();
      }
      return;
    }

    final curSeconds = (_currentPosition.inMilliseconds + _timingOffsetMs) / 1000.0;
    final lines = _currentLyrics!.lines;

    int newIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (curSeconds >= lines[i].time) {
        newIndex = i;
      } else {
        break;
      }
    }

    if (newIndex != _currentLyricIndex) {
      _currentLyricIndex = newIndex;
      notifyListeners();
      _broadcastStateToOverlay();
    }
  }

  void seekTo(Duration position) {
    _currentPosition = position;
    _lastSyncTimestamp = DateTime.now();
    _syncLyricIndex();
    notifyListeners();
    _broadcastStateToOverlay();
  }

  void togglePlayPause() {
    _isPlaying = !_isPlaying;
    _lastSyncTimestamp = DateTime.now();
    notifyListeners();
    _broadcastStateToOverlay();
  }

  /// Overlay Management using rock-solid native WindowManager
  Future<bool> checkOverlayPermission() async {
    _hasOverlayAccess = await NativeMediaListener.instance.hasOverlayPermission();
    notifyListeners();
    return _hasOverlayAccess;
  }

  Future<void> showOverlayWindow() async {
    // Attempt launch immediately; native service verifies and displays
    final success = await NativeMediaListener.instance.showOverlay();
    if (success) {
      _isOverlayActive = true;
      _broadcastStateToOverlay();
    } else {
      await openOverlaySettings();
    }
    await refreshPermissions();
    notifyListeners();
  }

  Future<void> closeOverlayWindow() async {
    await NativeMediaListener.instance.closeOverlay();
    _isOverlayActive = false;
    notifyListeners();
  }

  void _broadcastStateToOverlay() {
    NativeMediaListener.instance.updateOverlayLyric(
      text: currentLyricText,
      isSynced: _currentLyrics?.isSynced ?? false,
      isPlaying: _isPlaying,
      fontSize: _settings.fontSize,
      transitionStyle: _settings.transitionStyle.name,
      chipStyle: _settings.themeStyle.name,
      accentColor: _accentColor,
      nextLyricText: nextLyricText,
      trackTitle: _trackTitle ?? '',
      artistName: _artistName ?? '',
    );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }
}
