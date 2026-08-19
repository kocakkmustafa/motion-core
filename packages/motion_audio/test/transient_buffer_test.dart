import 'package:flutter_test/flutter_test.dart';
import 'package:motion_audio/motion_audio.dart';

void main() {
  group('TransientBuffer — bounded ring buffer', () {
    test('holds up to capacity items in insertion order', () {
      final buffer = TransientBuffer<int>(capacity: 3);
      buffer.push(1);
      buffer.push(2);
      buffer.push(3);
      expect(buffer.items, [1, 2, 3]);
      expect(buffer.length, 3);
    });

    test('pushing beyond capacity drops the oldest item, never throws', () {
      final buffer = TransientBuffer<int>(capacity: 3);
      for (final i in [1, 2, 3, 4, 5]) {
        buffer.push(i);
      }
      expect(buffer.items, [3, 4, 5]);
      expect(buffer.length, 3);
    });

    test('fail-closed: zero capacity accepts pushes without storing or throwing', () {
      final buffer = TransientBuffer<int>(capacity: 0);
      expect(() => buffer.push(1), returnsNormally);
      expect(buffer.items, isEmpty);
      expect(buffer.length, 0);
    });

    test('fail-closed: negative capacity behaves like zero capacity, never throws', () {
      final buffer = TransientBuffer<int>(capacity: -5);
      expect(() => buffer.push(1), returnsNormally);
      expect(buffer.items, isEmpty);
      expect(buffer.capacity, 0);
    });
  });
}
