import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

void main() {
  group('EventAllowlist — versioned family-wide contract', () {
    const v1Names = {
      'onboarding_complete',
      'device_check_result',
      'session_started',
      'session_completed',
      'value_event',
      'paywall_viewed',
      'purchase_state_changed',
      'restore_state_changed',
    };
    const v2Names = {...v1Names, 'content_validation_result'};

    test('v1 remains immutable and v2 adds exactly content validation', () {
      expect(EventAllowlist.v1.version, 1);
      expect(EventAllowlist.v1.eventNames, v1Names);
      expect(EventAllowlist.v2.version, 2);
      expect(EventAllowlist.v2.eventNames, v2Names);
    });

    test('v2 allows every authoritative name', () {
      for (final name in v2Names) {
        expect(EventAllowlist.v2.allows(name), isTrue, reason: name);
      }
    });

    test('fail-closed: an arbitrary event name is not allowed', () {
      expect(EventAllowlist.v1.allows('lissom_pose_frame_captured'), isFalse);
    });

    test('content validation exposes only the privacy-safe field contract', () {
      const expectedAttributes = {
        'appVersion',
        'buildNumber',
        'schemaVersion',
        'contentVersion',
        'result',
        'errorCode',
        'contentId',
        'expectedHashPrefix',
        'actualHashPrefix',
      };
      expect(
        EventAllowlist.v2.attributeNamesFor('content_validation_result'),
        expectedAttributes,
      );
      for (final attribute in expectedAttributes) {
        expect(
          EventAllowlist.v2.allowsAttribute(
            'content_validation_result',
            attribute,
          ),
          isTrue,
          reason: attribute,
        );
      }
      expect(
        EventAllowlist.v2.allowsAttribute(
          'content_validation_result',
          'localPath',
        ),
        isFalse,
      );
      expect(
        EventAllowlist.v1.allowsAttribute(
          'content_validation_result',
          'result',
        ),
        isFalse,
      );
    });

    test('custom policies are copied and remain fail-closed per event', () {
      final names = <String>{'custom_event', 'content_validation_result'};
      final customAttributes = <String>{'allowed'};
      final contentAttributes = <String>{'result', 'debugValue'};
      final attributes = <String, Set<String>>{
        'custom_event': customAttributes,
        'content_validation_result': contentAttributes,
      };
      final policy = EventAllowlist(
        version: 99,
        eventNames: names,
        attributeNamesByEvent: attributes,
      );

      names.add('later_event');
      customAttributes.add('later_field');
      contentAttributes.add('localPath');
      attributes['custom_event'] = {'replacement'};

      expect(policy.allows('later_event'), isFalse);
      expect(policy.allowsAttribute('custom_event', 'allowed'), isTrue);
      expect(policy.allowsAttribute('custom_event', 'later_field'), isFalse);
      expect(policy.allowsAttribute('custom_event', 'replacement'), isFalse);
      expect(
        policy.allowsAttribute('content_validation_result', 'debugValue'),
        isFalse,
      );
      expect(
        policy.allowsAttribute('content_validation_result', 'localPath'),
        isFalse,
      );
      expect(() => policy.eventNames.add('mutation'), throwsUnsupportedError);
      expect(
        () => policy.attributeNamesFor('custom_event')!.add('mutation'),
        throwsUnsupportedError,
      );
    });

    test('an event without an attribute contract allows no attributes', () {
      final policy = EventAllowlist(
        version: 99,
        eventNames: const {'custom_event'},
      );

      expect(policy.allows('custom_event'), isTrue);
      expect(policy.allowsAttribute('custom_event', 'anything'), isFalse);
    });
  });
}
