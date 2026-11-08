import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models/lyric_model.dart';
import 'services/lyrics_sync_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF141414),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final syncManager = LyricsSyncManager();
  await syncManager.init();

  runApp(const InlineApp());
}

class InlineApp extends StatelessWidget {
  const InlineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF141414),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4FF70),
          secondary: Color(0xFF888888),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const InlineHomeScreen(),
    );
  }
}

class InlineHomeScreen extends StatefulWidget {
  const InlineHomeScreen({super.key});

  @override
  State<InlineHomeScreen> createState() => _InlineHomeScreenState();
}

class _InlineHomeScreenState extends State<InlineHomeScreen> with WidgetsBindingObserver {
  final LyricsSyncManager _manager = LyricsSyncManager();
  final ScrollController _lyricScrollController = ScrollController();

  Color get _accentColor {
    try {
      final hex = _manager.accentColor.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('0xFF$hex'));
      }
    } catch (_) {}
    return const Color(0xFFD4FF70);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _manager.addListener(_onManagerUpdate);
    _manager.refreshPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _manager.refreshPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manager.removeListener(_onManagerUpdate);
    _lyricScrollController.dispose();
    super.dispose();
  }

  void _onManagerUpdate() {
    if (mounted) {
      setState(() {});
      if (_lyricScrollController.hasClients &&
          _manager.currentLyrics != null &&
          _manager.currentLyricIndex >= 0) {
        final targetOffset = (_manager.currentLyricIndex * 40.0).clamp(
          0.0,
          _lyricScrollController.position.maxScrollExtent,
        );
        _lyricScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final title = _manager.trackTitle ?? 'Waiting for Spotify';
    final artist = _manager.artistName ?? 'No playback active';
    final isOverlayOn = _manager.isOverlayActive;
    final total = _manager.trackDuration;
    final current = _manager.currentPosition;
    final progress = total.inMilliseconds > 0
        ? (current.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header (Inline + Romaji Toggle + Search)
              _buildHeader(),
              const SizedBox(height: 12),

              // 1. Hero Bento Card with Animated Transition
              _buildHeroCard(title, artist, progress, current, total),
              const SizedBox(height: 10),

              // 2. Playback Controls & Micro-Timing Offset Row
              _buildPlaybackAndOffsetRow(),
              const SizedBox(height: 10),

              // 3. Chip Style Selector (Pill, Squircle 2-Line, Ticker, Neon, Monolith, Notch)
              _buildChipStylesSelector(),
              const SizedBox(height: 10),

              // 4. Selectable Animated Transitions Row
              _buildTransitionsRow(),
              const SizedBox(height: 10),

              // 5. Opacity Presets & Smart Dimming Row
              _buildSettingsRow(),
              const SizedBox(height: 10),

              // 6. Size Stepper and Big ON/OFF Toggle
              _buildControlsRow(isOverlayOn),
              const SizedBox(height: 10),

              // 7. Permissions Row (Bento style with toggle switches)
              _buildPermissionsRow(),
              const SizedBox(height: 10),

              // 8. Live Lyrics Reel
              _buildLyricsReelCard(),
              const SizedBox(height: 16),

              // 9. Solid Dynamic Accent Action Button
              _buildMainActionButton(isOverlayOn),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _accentColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(Icons.lyrics_rounded, color: Colors.black, size: 16),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Inline',
            style: GoogleFonts.lora(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),

          // Romaji Transliteration Toggle Pill
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _manager.toggleRomaji(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _manager.isRomajiEnabled ? _accentColor.withValues(alpha: 0.18) : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: _manager.isRomajiEnabled ? Border.all(color: _accentColor, width: 1.2) : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.translate_rounded,
                    size: 13,
                    color: _manager.isRomajiEnabled ? _accentColor : const Color(0xFF888888),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Romaji',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _manager.isRomajiEnabled ? _accentColor : const Color(0xFF888888),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Search Manual Lyrics Button
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openManualSearchSheet(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _manager.isManualLyricsPinned ? _accentColor : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  _manager.isManualLyricsPinned ? Icons.push_pin_rounded : Icons.search_rounded,
                  size: 16,
                  color: _manager.isManualLyricsPinned ? Colors.black : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(
    String title,
    String artist,
    double progress,
    Duration current,
    Duration total,
  ) {
    // Dynamic lyric hero font size tied directly to user size setting
    final heroFontSize = (_manager.settings.fontSize * 1.6).clamp(20.0, 36.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _manager.isPlaying ? 'PLAYING NOW' : 'PLAYER IDLE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF777777),
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                '${_formatDuration(current)} / ${_formatDuration(total)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF777777),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Serif Lyric Hero with Animated Transitions (Non-Italic)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, animation) {
                return _buildTransition(child, animation, _manager.transitionStyle);
              },
              child: Text(
                _manager.currentLyricText,
                key: ValueKey<String>(
                  '${_manager.currentLyricText}_${_manager.settings.fontSize}_${_manager.transitionStyle.name}',
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.lora(
                  fontSize: heroFontSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.25,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$title • $artist',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 22),

          _buildDottedStepper(progress),
        ],
      ),
    );
  }

  Widget _buildTransition(
    Widget child,
    Animation<double> animation,
    LyricTransitionStyle style,
  ) {
    switch (style) {
      case LyricTransitionStyle.slide:
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.0, 0.45),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(opacity: animation, child: child),
        );

      case LyricTransitionStyle.scale:
        final scaleAnimation = Tween<double>(begin: 0.88, end: 1.0)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return ScaleTransition(
          scale: scaleAnimation,
          child: FadeTransition(opacity: animation, child: child),
        );

      case LyricTransitionStyle.fade:
        return FadeTransition(opacity: animation, child: child);

      case LyricTransitionStyle.pop:
        final popAnimation = Tween<double>(begin: 0.78, end: 1.0)
            .animate(CurvedAnimation(parent: animation, curve: Curves.elasticOut));
        return ScaleTransition(
          scale: popAnimation,
          child: FadeTransition(opacity: animation, child: child),
        );
    }
  }

  Widget _buildDottedStepper(double progress) {
    const int totalDots = 18;
    final activeIndex = (progress * (totalDots - 1)).round();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        if (_manager.trackDuration > Duration.zero) {
          final box = context.findRenderObject() as RenderBox?;
          final localX = details.localPosition.dx;
          final width = box != null ? box.size.width - 70 : 280.0;
          final pct = (localX / width).clamp(0.0, 1.0);
          final newPos = Duration(milliseconds: (pct * _manager.trackDuration.inMilliseconds).round());
          _manager.seekTo(newPos);
        }
      },
      child: SizedBox(
        height: 24,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 2.5,
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2C),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                height: 2.5,
                decoration: BoxDecoration(
                  color: _accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(totalDots, (index) {
                final isCurrent = index == activeIndex;
                final isPassed = index <= activeIndex;
                return Container(
                  width: isCurrent ? 12 : 5,
                  height: isCurrent ? 12 : 5,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? _accentColor
                        : (isPassed ? _accentColor : const Color(0xFF333333)),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipStylesSelector() {
    final styles = [
      {'name': 'Pill', 'desc': '1-Line Capsule', 'style': OverlayThemeStyle.pill, 'icon': Icons.horizontal_rule_rounded},
      {'name': 'Box 2L', 'desc': 'Squircle 2-Line', 'style': OverlayThemeStyle.squircle, 'icon': Icons.crop_square_rounded},
      {'name': 'Ticker', 'desc': 'Ultra Slim Bar', 'style': OverlayThemeStyle.ticker, 'icon': Icons.linear_scale_rounded},
      {'name': 'Neon', 'desc': 'Glowing Border', 'style': OverlayThemeStyle.neon, 'icon': Icons.blur_on_rounded},
      {'name': 'Monolith', 'desc': 'Brutalist Strip', 'style': OverlayThemeStyle.brutalist, 'icon': Icons.view_sidebar_rounded},
      {'name': 'Notch', 'desc': 'Docked Card', 'style': OverlayThemeStyle.card, 'icon': Icons.vertical_align_top_rounded},
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CHIP STYLE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF777777),
                  letterSpacing: 1.0,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Album Accent Active',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _accentColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: styles.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = styles[index];
                final style = item['style'] as OverlayThemeStyle;
                final isSelected = _manager.chipStyle == style;

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _manager.setChipStyle(style),
                  child: Container(
                    width: 96,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF282828) : const Color(0xFF161616),
                      borderRadius: BorderRadius.circular(14),
                      border: isSelected
                          ? Border.all(color: _accentColor.withValues(alpha: 0.6), width: 1.2)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              item['icon'] as IconData,
                              size: 14,
                              color: isSelected ? _accentColor : const Color(0xFF777777),
                            ),
                            const Spacer(),
                            if (isSelected)
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: _accentColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item['name'] as String,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            color: isSelected ? Colors.white : const Color(0xFF888888),
                          ),
                          maxLines: 1,
                        ),
                        Text(
                          item['desc'] as String,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? _accentColor : const Color(0xFF555555),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackAndOffsetRow() {
    final offsetSec = _manager.timingOffsetMs / 1000.0;
    final sign = offsetSec > 0 ? '+' : (offsetSec < 0 ? '' : '±');
    final offsetText = '$sign${offsetSec.toStringAsFixed(1)}s';

    return Row(
      children: [
        // 1. Mini Transport Controls (⏮, ⏯, ⏭)
        Expanded(
          flex: 5,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _manager.skipPrevious(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.skip_previous_rounded, color: Colors.white, size: 24),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _manager.toggleMediaPlay(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _manager.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _manager.skipNext(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.skip_next_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 2. Micro-Timing Offset Controls (-0.5s, ±0.0s, +0.5s)
        Expanded(
          flex: 6,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _manager.adjustTimingOffset(-500),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF282828),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '-0.5s',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _manager.resetTimingOffset(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'OFFSET',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF666666),
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        offsetText,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: _accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _manager.adjustTimingOffset(500),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF282828),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+0.5s',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransitionsRow() {
    final transitions = [
      {'name': 'Slide', 'style': LyricTransitionStyle.slide},
      {'name': 'Scale', 'style': LyricTransitionStyle.scale},
      {'name': 'Fade', 'style': LyricTransitionStyle.fade},
      {'name': 'Pop', 'style': LyricTransitionStyle.pop},
    ];

    return Row(
      children: transitions.map((t) {
        final isSelected = _manager.transitionStyle == t['style'];
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3.0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _manager.setTransitionStyle(t['style'] as LyricTransitionStyle);
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF282828) : const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(14),
                  border: isSelected
                      ? Border.all(color: _accentColor.withValues(alpha: 0.5), width: 1.2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    t['name'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? _accentColor : const Color(0xFF888888),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSettingsRow() {
    final opacities = [
      {'label': '60%', 'val': 0.60},
      {'label': '80%', 'val': 0.80},
      {'label': '95%', 'val': 0.95},
      {'label': '100%', 'val': 1.00},
    ];
    final currentOpacity = _manager.settings.opacity;
    final autoHide = _manager.settings.autoHideWhenPaused;

    return Row(
      children: [
        // Opacity Presets
        Expanded(
          flex: 6,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  'OPACITY',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF666666),
                  ),
                ),
                ...opacities.map((op) {
                  final val = op['val'] as double;
                  final isSelected = (currentOpacity - val).abs() < 0.05;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _manager.setOpacity(val),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? _accentColor : const Color(0xFF262626),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        op['label'] as String,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? Colors.black : const Color(0xFF999999),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Auto-Hide when paused toggle
        Expanded(
          flex: 4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _manager.toggleAutoHideWhenPaused(),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: autoHide ? _accentColor.withValues(alpha: 0.15) : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: autoHide ? Border.all(color: _accentColor.withValues(alpha: 0.4), width: 1) : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    autoHide ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                    size: 15,
                    color: autoHide ? _accentColor : const Color(0xFF888888),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    autoHide ? 'Smart Dim' : 'Dim Off',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: autoHide ? _accentColor : const Color(0xFF888888),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlsRow(bool isOverlayOn) {
    return Row(
      children: [
        // 1. Counter Bento Card (- 14 +)
        Expanded(
          child: Container(
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_manager.settings.fontSize > 10) {
                          _manager.updateSettings(
                            OverlaySettings(
                              fontSize: _manager.settings.fontSize - 1,
                              opacity: _manager.settings.opacity,
                              showProgress: _manager.settings.showProgress,
                              multiLinePreview: _manager.settings.multiLinePreview,
                              themeStyle: _manager.settings.themeStyle,
                              transitionStyle: _manager.transitionStyle,
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _accentColor,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(Icons.remove, color: Colors.black, size: 14),
                      ),
                    ),
                    Text(
                      '${_manager.settings.fontSize.toInt()}',
                      style: GoogleFonts.lora(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_manager.settings.fontSize < 24) {
                          _manager.updateSettings(
                            OverlaySettings(
                              fontSize: _manager.settings.fontSize + 1,
                              opacity: _manager.settings.opacity,
                              showProgress: _manager.settings.showProgress,
                              multiLinePreview: _manager.settings.multiLinePreview,
                              themeStyle: _manager.settings.themeStyle,
                              transitionStyle: _manager.transitionStyle,
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _accentColor,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(Icons.add, color: Colors.black, size: 14),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Size',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF777777),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),

        // 2. Large Toggle Bento Card (Overlay ON/OFF)
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              if (isOverlayOn) {
                await _manager.closeOverlayWindow();
              } else {
                await _manager.showOverlayWindow();
              }
            },
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: isOverlayOn ? _accentColor.withValues(alpha: 0.15) : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'OVERLAY',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF777777),
                      letterSpacing: 1.0,
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      isOverlayOn ? 'ON' : 'OFF',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: isOverlayOn ? _accentColor : const Color(0xFF444444),
                        letterSpacing: -1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsRow() {
    final hasNotif = _manager.hasNotificationAccess;
    final hasOverlay = _manager.hasOverlayAccess;

    return Row(
      children: [
        // Permission 1: Media Access (Bento Style with Toggle Switch)
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await _manager.openNotificationSettings();
            },
            child: Container(
              height: 90,
              decoration: BoxDecoration(
                color: hasNotif ? _accentColor.withValues(alpha: 0.15) : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MEDIA',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF777777),
                          letterSpacing: 0.8,
                        ),
                      ),
                      // Custom Mini Switch Pill
                      Container(
                        width: 34,
                        height: 18,
                        decoration: BoxDecoration(
                          color: hasNotif ? _accentColor : const Color(0xFF2C2C2C),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: hasNotif ? Alignment.centerRight : Alignment.centerLeft,
                        padding: const EdgeInsets.all(2.5),
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: hasNotif ? Colors.black : const Color(0xFF666666),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Access',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        hasNotif ? 'ON' : 'OFF',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: hasNotif ? _accentColor : const Color(0xFF555555),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Permission 2: Draw Overlay (Bento Style with Toggle Switch)
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await _manager.openOverlaySettings();
            },
            child: Container(
              height: 90,
              decoration: BoxDecoration(
                color: hasOverlay ? _accentColor.withValues(alpha: 0.15) : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'OVERLAY',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF777777),
                          letterSpacing: 0.8,
                        ),
                      ),
                      // Custom Mini Switch Pill
                      Container(
                        width: 34,
                        height: 18,
                        decoration: BoxDecoration(
                          color: hasOverlay ? _accentColor : const Color(0xFF2C2C2C),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: hasOverlay ? Alignment.centerRight : Alignment.centerLeft,
                        padding: const EdgeInsets.all(2.5),
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: hasOverlay ? Colors.black : const Color(0xFF666666),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Draw Over',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        hasOverlay ? 'ON' : 'OFF',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: hasOverlay ? _accentColor : const Color(0xFF555555),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsReelCard() {
    final lyrics = _manager.currentLyrics;

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE LYRICS REEL',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF777777),
                  letterSpacing: 1.0,
                ),
              ),
              if (_manager.isLoadingLyrics)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(_accentColor),
                  ),
                )
              else if (lyrics != null && lyrics.isSynced)
                Text(
                  '${lyrics.lines.length} LINES',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: _accentColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildLyricLinesContent(lyrics),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricLinesContent(SongLyrics? lyrics) {
    if (_manager.isLoadingLyrics) {
      return Center(
        child: Text(
          'Connecting to LRCLIB...',
          style: GoogleFonts.lora(
            fontSize: 17,
            color: const Color(0xFF777777),
          ),
        ),
      );
    }

    if (lyrics == null) {
      return Center(
        child: Text(
          'Play a track in Spotify',
          textAlign: TextAlign.center,
          style: GoogleFonts.lora(
            fontSize: 16,
            color: const Color(0xFF555555),
          ),
        ),
      );
    }

    if (!lyrics.isSynced) {
      return SingleChildScrollView(
        child: Text(
          lyrics.rawPlainLyrics ?? 'No lyrics available',
          style: GoogleFonts.lora(
            fontSize: 15,
            color: const Color(0xFF888888),
            height: 1.4,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _lyricScrollController,
      itemCount: lyrics.lines.length,
      itemBuilder: (context, idx) {
        final line = lyrics.lines[idx];
        final isActive = idx == _manager.currentLyricIndex;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              Text(
                _formatDuration(Duration(seconds: line.time.toInt())),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isActive ? _accentColor : const Color(0xFF444444),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  line.text.isEmpty ? '♪' : line.text,
                  style: GoogleFonts.lora(
                    fontSize: isActive ? 17 : 14.5,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? Colors.white : const Color(0xFF666666),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainActionButton(bool isOverlayOn) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (isOverlayOn) {
          await _manager.closeOverlayWindow();
        } else {
          await _manager.showOverlayWindow();
        }
      },
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: _accentColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isOverlayOn ? 'Hide Overlay' : 'Launch Overlay',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.black,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.sync_rounded, color: Colors.black, size: 20),
          ],
        ),
      ),
    );
  }

  void _openManualSearchSheet() {
    final searchCtrl = TextEditingController(
      text: '${_manager.trackTitle ?? ""} ${_manager.artistName ?? ""}'.trim(),
    );
    List<SongLyrics> searchResults = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void doSearch() async {
              if (searchCtrl.text.trim().isEmpty) return;
              setModalState(() => isSearching = true);
              final results = await _manager.searchCandidates(searchCtrl.text.trim());
              setModalState(() {
                searchResults = results;
                isSearching = false;
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: const BoxDecoration(
                color: Color(0xFF18181A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SEARCH LYRICS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _accentColor,
                          letterSpacing: 1.0,
                        ),
                      ),
                      if (_manager.isManualLyricsPinned)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _manager.unpinManualLyrics();
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            'Reset to Auto',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFF6B6B),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF222225),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            controller: searchCtrl,
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'Search title, artist...',
                              hintStyle: TextStyle(color: Color(0xFF777777), fontSize: 13),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => doSearch(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: doSearch,
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: _accentColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(Icons.search_rounded, color: Colors.black, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isSearching)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: _accentColor),
                      ),
                    )
                  else if (searchResults.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Search LRCLIB for any song or alternate version',
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFF666666), fontSize: 12),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: searchResults.length,
                        separatorBuilder: (context, index) => const Divider(color: Color(0xFF252528), height: 1),
                        itemBuilder: (context, i) {
                          final item = searchResults[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            title: Text(
                              item.trackName,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              '${item.artistName} • ${item.albumName ?? ""}',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFF888888),
                                fontSize: 11.5,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: item.isSynced ? _accentColor.withValues(alpha: 0.15) : const Color(0xFF282828),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.isSynced ? 'SYNCED' : 'PLAIN',
                                style: GoogleFonts.plusJakartaSans(
                                  color: item.isSynced ? _accentColor : const Color(0xFF888888),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            onTap: () {
                              _manager.pinManualLyrics(item);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
