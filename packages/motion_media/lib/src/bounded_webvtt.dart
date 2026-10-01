import 'dart:convert';
import 'dart:io';

import 'verified_media_cache.dart';

final class WebVttContractError implements Exception {
  const WebVttContractError(this.code);

  final String code;

  @override
  String toString() => 'WebVttContractError: $code';
}

/// A deliberately bounded cue check before either caption is passed to native.
/// It does not certify translation, accessibility, or video decoder duration.
final class BoundedWebVtt {
  const BoundedWebVtt._();

  static final RegExp _timing = RegExp(
    r'^(?:(\d{2}):)?(\d{2}):(\d{2})\.(\d{3}) --> (?:(\d{2}):)?(\d{2}):(\d{2})\.(\d{3})(?: .*)?$',
  );

  static Future<int> validate(File file, {required int durationMs}) async {
    if (durationMs <= 0) throw const WebVttContractError('DURATION');
    if (await file.length() > MediaFileKind.vtt.maxBytes) {
      throw const WebVttContractError('BYTE_CAP');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > MediaFileKind.vtt.maxBytes) {
      throw const WebVttContractError('BYTE_CAP');
    }
    String value;
    try {
      value = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const WebVttContractError('UTF8');
    }
    final normalized = value.replaceAll('\r\n', '\n');
    // Lone CR is also a WebVTT line break. Reject it rather than letting it
    // hide another timing line inside cue text.
    if (normalized.contains('\r')) {
      throw const WebVttContractError('LINE_ENDING');
    }
    final lines = normalized.split('\n');
    if (lines.isEmpty ||
        !(lines.first == 'WEBVTT' || lines.first.startsWith('WEBVTT '))) {
      throw const WebVttContractError('HEADER');
    }
    if (lines.length < 3 || lines[1].isNotEmpty) {
      throw const WebVttContractError('HEADER');
    }
    var index = 2;
    var count = 0;
    var previousStart = -1;
    while (index < lines.length) {
      if (lines[index].isEmpty) {
        index++;
        continue;
      }
      var timing = _timing.firstMatch(lines[index]);
      if (timing == null) {
        index++;
        if (index >= lines.length) throw const WebVttContractError('CUE');
        timing = _timing.firstMatch(lines[index]);
      }
      if (timing == null) throw const WebVttContractError('CUE_TIMING');
      final start = _millis(timing, 1);
      final end = _millis(timing, 5);
      if (start == null ||
          end == null ||
          start < previousStart ||
          start >= end ||
          end > durationMs) {
        throw const WebVttContractError('CUE_RANGE');
      }
      previousStart = start;
      index++;
      var textLines = 0;
      while (index < lines.length && lines[index].isNotEmpty) {
        textLines++;
        index++;
      }
      if (textLines == 0) throw const WebVttContractError('CUE_TEXT');
      count++;
    }
    if (count == 0) throw const WebVttContractError('NO_CUES');
    return count;
  }

  static int? _millis(RegExpMatch match, int first) {
    final hours = int.tryParse(match.group(first) ?? '0');
    final minutes = int.tryParse(match.group(first + 1)!);
    final seconds = int.tryParse(match.group(first + 2)!);
    final millis = int.tryParse(match.group(first + 3)!);
    if (hours == null ||
        minutes == null ||
        seconds == null ||
        millis == null ||
        minutes > 59 ||
        seconds > 59) {
      return null;
    }
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis;
  }
}
