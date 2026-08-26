import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  group('ClientAIProfileState Unit Tests', () {
    test('copyWith updates fields accurately', () {
      final state = ClientAIProfileState(
        remotePaths: ['img1.jpg', '', '', '', ''],
        pendingUploads: {0: File('test.jpg')},
        slotSpecificVibeTags: {
          0: ['Cyberpunk', 'Astrophotography'],
        },
        pendingDeletions: ['old.jpg'],
        isProcessingAI: true,
      );

      final updated = state.copyWith(isSaving: true, isProcessingAI: false);
      expect(updated.isSaving, true);
      expect(updated.isProcessingAI, false);
      expect(updated.remotePaths.first, 'img1.jpg');
      expect(updated.pendingDeletions, ['old.jpg']);
    });
  });

  group('ClientAIImageManager Riverpod Provider Tests', () {
    test('manages remote paths and state backups', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final manager = container.read(clientAIImageManagerProvider.notifier);
      expect(
        container.read(clientAIImageManagerProvider).remotePaths.length,
        5,
      );

      manager.setRemotePaths(['pic1.png', 'pic2.png']);
      expect(
        container.read(clientAIImageManagerProvider).remotePaths[0],
        'pic1.png',
      );
      expect(
        container.read(clientAIImageManagerProvider).remotePaths[1],
        'pic2.png',
      );

      manager
        ..backupState()
        ..setRemotePaths(['new.png']);
      expect(
        container.read(clientAIImageManagerProvider).remotePaths[0],
        'new.png',
      );

      manager.restoreBackup();
      expect(
        container.read(clientAIImageManagerProvider).remotePaths[0],
        'pic1.png',
      );
    });
  });
}
