import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

void main() {
  group('EventAllowlist.v1 — exact family-wide set (00-AILE-MIMARISI.md §8.4)', () {
    const expected = {
      'onboarding_complete',
      'device_check_result',
      'session_started',
      'session_completed',
      'value_event',
      'paywall_viewed',
      'purchase_state_changed',
      'restore_state_changed',
    };

    test('contains exactly the eight authoritative event names', () {
      expect(EventAllowlist.v1.eventNames, expected);
    });

    test('allows every authoritative name', () {
      for (final name in expected) {
        expect(EventAllowlist.v1.allows(name), isTrue, reason: name);
      }
    });

    test('fail-closed: an arbitrary event name is not allowed', () {
      expect(EventAllowlist.v1.allows('lissom_pose_frame_captured'), isFalse);
    });
  });
}
