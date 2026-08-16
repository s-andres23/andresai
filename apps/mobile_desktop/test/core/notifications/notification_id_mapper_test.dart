import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/core/notifications/notification_id_mapper.dart';

void main() {
  group('reminderNotificationId', () {
    test('is deterministic: the same UUID always maps to the same int', () {
      const reminderId = 'a1b2c3d4-e5f6-4789-a012-3456789abcde';

      final first = reminderNotificationId(reminderId);
      final second = reminderNotificationId(reminderId);
      final third = reminderNotificationId(reminderId);

      expect(first, second);
      expect(second, third);
    });

    test('different UUIDs map to different ids', () {
      const uuids = [
        'a1b2c3d4-e5f6-4789-a012-3456789abcde',
        'b2c3d4e5-f6a7-4890-b123-456789abcdef',
        '00000000-0000-4000-8000-000000000000',
        'ffffffff-ffff-4fff-bfff-ffffffffffff',
        '11111111-1111-4111-8111-111111111111',
      ];

      final ids = uuids.map(reminderNotificationId).toSet();

      expect(ids, hasLength(uuids.length));
    });

    test('always returns a non-negative 32-bit-safe int', () {
      const uuids = [
        'a1b2c3d4-e5f6-4789-a012-3456789abcde',
        '00000000-0000-4000-8000-000000000000',
        'ffffffff-ffff-4fff-bfff-ffffffffffff',
      ];

      for (final uuid in uuids) {
        final id = reminderNotificationId(uuid);
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0x7FFFFFFF));
      }
    });
  });
}
