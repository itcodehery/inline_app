import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/lyric_model.dart';

class LrclibService {
  static const String _baseUrl = 'https://lrclib.net/api';
  static const String _userAgent = 'Inline-Lyrics/1.0 (Android; Mobile)';

  /// Cleans track title by stripping noise like `(feat. ...)`, `[Remastered]`, etc.
  /// Exactly follows the detection & cleaning pattern from Quickshell MprisPanel.
  static String cleanTrackTitle(String rawTitle) {
    String cleaned = rawTitle;

    // Remove text in parentheses like (feat. X), (with X), (Remastered 2021), etc.
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*\((feat\.|ft\.|featuring|with|remastered|remaster|live|official|deluxe|bonus|radio edit)[^)]*\)',
          caseSensitive: false),
      '',
    );

    // Remove text in brackets like [feat. X], [Remastered], [Official Music Video], etc.
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*\[(feat\.|ft\.|featuring|with|remastered|remaster|live|official|deluxe|bonus|radio edit)[^\]]*\]',
          caseSensitive: false),
      '',
    );

    // Remove trailing " - Remastered...", " - 2013 Remaster...", " - Live...", " - Radio Edit...", " - feat...", " - Single Version"
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*-\s*(\d{4}\s+)?(remastered|remaster|live|feat\.|deluxe|radio edit|single version|mono|stereo).*$',
          caseSensitive: false),
      '',
    );

    // Clean multiple spaces and trim
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned.isEmpty ? rawTitle : cleaned;
  }

  /// Cleans artist name if multiple artists are bundled or featured
  static String cleanArtistName(String rawArtist) {
    String cleaned = rawArtist;
    // Split by comma, feat, ft, &, etc. if too crowded, or preserve primary artist
    cleaned = cleaned.replaceAll(RegExp(r'\s+feat\..*$', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+ft\..*$', caseSensitive: false), '');
    return cleaned.trim();
  }

  /// Parses LRC format string into ordered list of [LyricLine].
  /// Handles timestamps like [mm:ss.xx] or [mm:ss.xxx] and [offset: +/-ms] tags.
  static List<LyricLine> parseLrc(String lrcContent) {
    final lines = lrcContent.split('\n');
    final List<LyricLine> lyricLines = [];

    double offsetSeconds = 0.0;
    final offsetRegex = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
    final timestampRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Check for [offset: +/-ms]
      final offsetMatch = offsetRegex.firstMatch(line);
      if (offsetMatch != null) {
        final offsetMs = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
        offsetSeconds = offsetMs / 1000.0;
        continue;
      }

      // Find all timestamps in this line (LRC lines can have multiple timestamps)
      final matches = timestampRegex.allMatches(line).toList();
      if (matches.isEmpty) continue;

      // Extract the lyric text after all timestamps
      final lyricText = line.replaceAll(timestampRegex, '').trim();

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisStr = match.group(3) ?? '0';

        // Normalize millis string (e.g. 2 digits = centiseconds, 3 digits = milliseconds)
        double fractionalSeconds = 0.0;
        if (millisStr.length == 1) {
          fractionalSeconds = int.parse(millisStr) / 10.0;
        } else if (millisStr.length == 2) {
          fractionalSeconds = int.parse(millisStr) / 100.0;
        } else {
          fractionalSeconds = int.parse(millisStr.padRight(3, '0').substring(0, 3)) / 1000.0;
        }

        double totalTime = (minutes * 60) + seconds + fractionalSeconds + offsetSeconds;
        if (totalTime < 0) totalTime = 0.0;

        lyricLines.add(LyricLine(time: totalTime, text: lyricText));
      }
    }

    // Sort chronologically
    lyricLines.sort((a, b) => a.time.compareTo(b.time));
    return lyricLines;
  }

  /// Fetches lyrics with the 3-step fallback strategy matching Quickshell MprisPanel:
  /// 1. Exact match with duration: /api/get?track_name=...&artist_name=...&duration=...
  /// 2. Search fallback: /api/search?track_name=...&artist_name=... (closest duration)
  /// 3. Fuzzy search fallback: /api/search?q=...
  static Future<SongLyrics?> fetchLyrics({
    required String trackName,
    required String artistName,
    double? durationSeconds,
  }) async {
    final cleanTitle = cleanTrackTitle(trackName);
    final cleanArtist = cleanArtistName(artistName);

    // Step 1: Attempt exact duration match if duration is provided
    if (durationSeconds != null && durationSeconds > 10) {
      try {
        final exactLyrics = await _getExact(cleanTitle, cleanArtist, durationSeconds.round());
        if (exactLyrics != null) return exactLyrics;
      } catch (_) {}
    }

    // Step 2: Search by track_name & artist_name
    try {
      final searchLyrics = await _searchByTrackAndArtist(cleanTitle, cleanArtist, durationSeconds);
      if (searchLyrics != null) return searchLyrics;
    } catch (_) {}

    // Step 3: Fuzzy search fallback
    try {
      final query = '$cleanTitle $cleanArtist'.trim();
      final fuzzyLyrics = await _searchFuzzy(query, durationSeconds);
      if (fuzzyLyrics != null) return fuzzyLyrics;
    } catch (_) {}

    return null;
  }

  static Future<SongLyrics?> _getExact(String track, String artist, int duration) async {
    final uri = Uri.parse('$_baseUrl/get').replace(queryParameters: {
      'track_name': track,
      'artist_name': artist,
      'duration': duration.toString(),
    });

    final res = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return _parseApiResponse(data);
    }
    return null;
  }

  static Future<SongLyrics?> _searchByTrackAndArtist(
    String track,
    String artist,
    double? targetDuration,
  ) async {
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'track_name': track,
      'artist_name': artist,
    });

    final res = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      if (list.isNotEmpty) {
        return _pickBestCandidate(list.cast<Map<String, dynamic>>(), targetDuration);
      }
    }
    return null;
  }

  static Future<SongLyrics?> _searchFuzzy(String query, double? targetDuration) async {
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'q': query,
    });

    final res = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      if (list.isNotEmpty) {
        return _pickBestCandidate(list.cast<Map<String, dynamic>>(), targetDuration);
      }
    }
    return null;
  }

  /// Picks the candidate with synced lyrics first, and closest duration match.
  static SongLyrics? _pickBestCandidate(
    List<Map<String, dynamic>> candidates,
    double? targetDuration,
  ) {
    if (candidates.isEmpty) return null;

    // Prefer candidates that have syncedLyrics
    var validCandidates = candidates.where((c) {
      final synced = c['syncedLyrics'] as String?;
      return synced != null && synced.trim().isNotEmpty;
    }).toList();

    // If no synced lyrics, fallback to plain lyrics
    if (validCandidates.isEmpty) {
      validCandidates = candidates.where((c) {
        final plain = c['plainLyrics'] as String?;
        return plain != null && plain.trim().isNotEmpty;
      }).toList();
    }

    if (validCandidates.isEmpty) return null;

    // If targetDuration is available, find closest duration
    if (targetDuration != null && targetDuration > 0) {
      validCandidates.sort((a, b) {
        final durA = (a['duration'] as num?)?.toDouble() ?? 0.0;
        final durB = (b['duration'] as num?)?.toDouble() ?? 0.0;
        final diffA = (durA - targetDuration).abs();
        final diffB = (durB - targetDuration).abs();
        return diffA.compareTo(diffB);
      });
    }

    return _parseApiResponse(validCandidates.first);
  }

  /// Manual search for track/lyrics candidates
  static Future<List<SongLyrics>> searchCandidates(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {'q': trimmed});
      final res = await http.get(uri, headers: {'User-Agent': _userAgent});
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        return list
            .map((item) => _parseApiResponse(item as Map<String, dynamic>))
            .whereType<SongLyrics>()
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static SongLyrics? _parseApiResponse(Map<String, dynamic> data) {
    final syncedStr = data['syncedLyrics'] as String?;
    final plainStr = data['plainLyrics'] as String?;

    final hasSynced = syncedStr != null && syncedStr.trim().isNotEmpty;
    final lines = hasSynced ? parseLrc(syncedStr) : <LyricLine>[];

    return SongLyrics(
      id: data['id'] as int?,
      trackName: data['trackName'] as String? ?? '',
      artistName: data['artistName'] as String? ?? '',
      albumName: data['albumName'] as String?,
      duration: (data['duration'] as num?)?.toDouble(),
      isSynced: hasSynced,
      lines: lines,
      rawPlainLyrics: plainStr,
    );
  }
}
