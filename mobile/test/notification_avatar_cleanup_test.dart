import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cleanStaleNotificationAvatars deletes avatar files older than maxAge',
    () async {
      final tempDir = Directory.systemTemp;

      // Create a stale avatar file
      final staleFile = File(
        '${tempDir.path}/notification_avatar_stale_123.jpg',
      );
      await staleFile.writeAsString('stale_avatar_data');
      expect(staleFile.existsSync(), isTrue);

      // Set its modified timestamp to 48 hours ago
      final pastTime = DateTime.now().subtract(const Duration(hours: 48));
      await staleFile.setLastModified(pastTime);

      // Create a fresh avatar file
      final freshFile = File(
        '${tempDir.path}/notification_avatar_fresh_456.jpg',
      );
      await freshFile.writeAsString('fresh_avatar_data');
      expect(freshFile.existsSync(), isTrue);

      // Run cleanup using default 24-hour maxAge
      final deleted = await NotificationService.cleanStaleNotificationAvatars();

      expect(deleted >= 1, isTrue);
      expect(staleFile.existsSync(), isFalse);
      expect(freshFile.existsSync(), isTrue);

      // Cleanup fresh file
      if (freshFile.existsSync()) {
        await freshFile.delete();
      }
    },
  );
}
