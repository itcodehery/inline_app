class LyricLine {
  final double time; // in seconds
  final String text;

  const LyricLine({
    required this.time,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'text': text,
      };

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      time: (json['time'] as num).toDouble(),
      text: json['text'] as String,
    );
  }

  @override
  String toString() => '[$time] $text';
}

class SongLyrics {
  final int? id;
  final String trackName;
  final String artistName;
  final String? albumName;
  final double? duration;
  final bool isSynced;
  final List<LyricLine> lines;
  final String? rawPlainLyrics;

  const SongLyrics({
    this.id,
    required this.trackName,
    required this.artistName,
    this.albumName,
    this.duration,
    required this.isSynced,
    required this.lines,
    this.rawPlainLyrics,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackName': trackName,
        'artistName': artistName,
        'albumName': albumName,
        'duration': duration,
        'isSynced': isSynced,
        'lines': lines.map((l) => l.toJson()).toList(),
        'rawPlainLyrics': rawPlainLyrics,
      };

  factory SongLyrics.fromJson(Map<String, dynamic> json) {
    return SongLyrics(
      id: json['id'] as int?,
      trackName: json['trackName'] as String? ?? '',
      artistName: json['artistName'] as String? ?? '',
      albumName: json['albumName'] as String?,
      duration: (json['duration'] as num?)?.toDouble(),
      isSynced: json['isSynced'] as bool? ?? false,
      lines: (json['lines'] as List<dynamic>?)
              ?.map((item) => LyricLine.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList() ??
          [],
      rawPlainLyrics: json['rawPlainLyrics'] as String?,
    );
  }
}
