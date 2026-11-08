import 'package:flutter_test/flutter_test.dart';
import 'package:inline_lyrics/services/lrclib_service.dart';
import 'package:inline_lyrics/utils/transliteration_helper.dart';

void main() {
  group('LrclibService Tests', () {
    test('cleanTrackTitle cleans featured artists and tags', () {
      expect(
        LrclibService.cleanTrackTitle('Blinding Lights (feat. Rosalía) - Remastered'),
        'Blinding Lights',
      );
      expect(
        LrclibService.cleanTrackTitle('Starboy [Official Audio]'),
        'Starboy',
      );
      expect(
        LrclibService.cleanTrackTitle('Hotel California - 2013 Remaster'),
        'Hotel California',
      );
      expect(
        LrclibService.cleanTrackTitle('Shape of You (with Stormzy)'),
        'Shape of You',
      );
    });

    test('parseLrc correctly parses timestamps and offsets', () {
      const lrcSample = '''
[ti:Never Gonna Give You Up]
[ar:Rick Astley]
[offset:+500]
[00:18.50]We're no strangers to love
[00:22.80]You know the rules and so do I
''';

      final lines = LrclibService.parseLrc(lrcSample);
      expect(lines.length, 2);
      // 18.50 + 0.50 offset = 19.0s
      expect(lines[0].time, closeTo(19.0, 0.01));
      expect(lines[0].text, "We're no strangers to love");

      // 22.80 + 0.50 offset = 23.3s
      expect(lines[1].time, closeTo(23.3, 0.01));
      expect(lines[1].text, "You know the rules and so do I");
    });

    test('TransliterationHelper transliterates Kana to Romaji accurately', () {
      expect(TransliterationHelper.toRomaji('さくら'), 'sa ku ra');
      expect(TransliterationHelper.toRomaji('アニメ'), 'a ni me');
      expect(TransliterationHelper.toRomaji('ちょっと'), 'cho tto');
      expect(TransliterationHelper.toRomaji('English text'), 'English text');
    });
  });
}
