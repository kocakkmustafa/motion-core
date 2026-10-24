/// Generic free-lesson rule shared by every Motion app (paywall A).
///
/// The first module, or at least the first third of a course, is free; the
/// remaining lessons and the independent practice stage need the app's own
/// subscription or Motion+. Reading recorded progress is never gated: these
/// helpers only decide whether a lesson or practice session may start.
///
/// Lessons are counted, never named. An app that has an approved free count
/// for a course (for example a whole-module prefix that covers a third)
/// passes it as `freeLessonLimit`, which replaces the default formula.
library;

/// Number of leading lessons that are free for a course.
///
/// Default: `max(firstModuleLessonCount, ceil(totalLessons / 3))`, capped at
/// [totalLessons]. A non-null [freeLessonLimit] is the app's approved count
/// and is used as given (capped at [totalLessons]).
int motionFreeLessonLimit({
  required int totalLessons,
  required int firstModuleLessonCount,
  int? freeLessonLimit,
}) {
  RangeError.checkNotNegative(totalLessons, 'totalLessons');
  RangeError.checkValueInInterval(
    firstModuleLessonCount,
    0,
    totalLessons,
    'firstModuleLessonCount',
  );
  if (freeLessonLimit != null) {
    RangeError.checkNotNegative(freeLessonLimit, 'freeLessonLimit');
    return freeLessonLimit < totalLessons ? freeLessonLimit : totalLessons;
  }
  final third = (totalLessons + 2) ~/ 3;
  return firstModuleLessonCount > third ? firstModuleLessonCount : third;
}

/// Whether the zero-based [lessonIndex] may start.
///
/// An [entitled] user (app subscription or Motion+) opens every lesson.
/// Otherwise only the free prefix from [motionFreeLessonLimit] opens.
bool isLessonUnlocked({
  required int lessonIndex,
  required int totalLessons,
  required int firstModuleLessonCount,
  required bool entitled,
  int? freeLessonLimit,
}) {
  final limit = motionFreeLessonLimit(
    totalLessons: totalLessons,
    firstModuleLessonCount: firstModuleLessonCount,
    freeLessonLimit: freeLessonLimit,
  );
  RangeError.checkValidIndex(lessonIndex, null, 'lessonIndex', totalLessons);
  return entitled || lessonIndex < limit;
}

/// The independent practice stage is subscription-only.
bool isPracticeUnlocked({required bool entitled}) => entitled;
