import 'package:flutter_test/flutter_test.dart';
import 'package:motion_entitlements/motion_entitlements.dart';

void main() {
  group('motionFreeLessonLimit default (paywall A)', () {
    test('is max(first module, ceil(total / 3)) for every course size', () {
      for (var total = 1; total <= 60; total++) {
        for (final first in {0, 1, total ~/ 4, total ~/ 3, total ~/ 2, total}) {
          final third = (total / 3).ceil();
          final expected = first > third ? first : third;
          expect(
            motionFreeLessonLimit(
              totalLessons: total,
              firstModuleLessonCount: first,
            ),
            expected,
            reason: 'total=$total first=$first',
          );
        }
      }
    });

    test('an empty course has no free lesson', () {
      expect(
        motionFreeLessonLimit(totalLessons: 0, firstModuleLessonCount: 0),
        0,
      );
    });

    test('rejects counts outside the course', () {
      expect(
        () =>
            motionFreeLessonLimit(totalLessons: -1, firstModuleLessonCount: 0),
        throwsRangeError,
      );
      expect(
        () => motionFreeLessonLimit(totalLessons: 5, firstModuleLessonCount: 6),
        throwsRangeError,
      );
      expect(
        () => motionFreeLessonLimit(
          totalLessons: 5,
          firstModuleLessonCount: 1,
          freeLessonLimit: -1,
        ),
        throwsRangeError,
      );
    });
  });

  group('freeLessonLimit override', () {
    // Approved per-course counts from a consumer's whole-module prefix rule
    // (free/total). The override must reproduce them exactly, including where
    // the default formula would cut inside a module.
    const approved = <(int, int)>[(24, 60), (6, 15), (5, 14), (5, 12), (7, 19)];

    for (final (free, total) in approved) {
      test('keeps an approved $free/$total split', () {
        for (var index = 0; index < total; index++) {
          expect(
            isLessonUnlocked(
              lessonIndex: index,
              totalLessons: total,
              firstModuleLessonCount: 1,
              entitled: false,
              freeLessonLimit: free,
            ),
            index < free,
            reason: 'lesson $index',
          );
        }
      });
    }

    test(
      'is used as given, below the default too, and capped at the course',
      () {
        expect(
          motionFreeLessonLimit(
            totalLessons: 12,
            firstModuleLessonCount: 6,
            freeLessonLimit: 2,
          ),
          2,
        );
        expect(
          motionFreeLessonLimit(
            totalLessons: 12,
            firstModuleLessonCount: 0,
            freeLessonLimit: 40,
          ),
          12,
        );
      },
    );
  });

  group('isLessonUnlocked', () {
    test('opens only the free prefix without an entitlement', () {
      // 10 lessons, first module of 2: limit = max(2, 4) = 4.
      final open = [
        for (var i = 0; i < 10; i++)
          isLessonUnlocked(
            lessonIndex: i,
            totalLessons: 10,
            firstModuleLessonCount: 2,
            entitled: false,
          ),
      ];
      expect(open, [
        true,
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
      ]);
    });

    test('a long first module stays free as a whole', () {
      expect(
        isLessonUnlocked(
          lessonIndex: 6,
          totalLessons: 12,
          firstModuleLessonCount: 7,
          entitled: false,
        ),
        isTrue,
      );
      expect(
        isLessonUnlocked(
          lessonIndex: 7,
          totalLessons: 12,
          firstModuleLessonCount: 7,
          entitled: false,
        ),
        isFalse,
      );
    });

    test('an entitlement opens every lesson', () {
      for (var total = 1; total <= 60; total++) {
        for (var index = 0; index < total; index++) {
          expect(
            isLessonUnlocked(
              lessonIndex: index,
              totalLessons: total,
              firstModuleLessonCount: 0,
              entitled: true,
              freeLessonLimit: 0,
            ),
            isTrue,
          );
        }
      }
    });

    test('rejects an index outside the course', () {
      for (final index in [-1, 10]) {
        expect(
          () => isLessonUnlocked(
            lessonIndex: index,
            totalLessons: 10,
            firstModuleLessonCount: 2,
            entitled: true,
          ),
          throwsRangeError,
        );
      }
    });
  });

  test('independent practice needs an entitlement', () {
    expect(isPracticeUnlocked(entitled: false), isFalse);
    expect(isPracticeUnlocked(entitled: true), isTrue);
  });
}
