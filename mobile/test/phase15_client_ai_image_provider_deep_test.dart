import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('ClientAIImageManager Provider Deep Tests', () {
    test('ClientAIProfileState copyWith and initial values', () {
      final state = ClientAIProfileState(
        remotePaths: ['', '', '', '', ''],
        pendingUploads: {},
        slotSpecificVibeTags: {
          0: ['Travel', 'Nature'],
        },
        pendingDeletions: ['old_path_1'],
        isProcessingAI: true,
      );

      final copy = state.copyWith(isProcessingAI: false, isSaving: true);
      expect(copy.isProcessingAI, isFalse);
      expect(copy.isSaving, isTrue);
      expect(copy.pendingDeletions.length, 1);
      expect(copy.slotSpecificVibeTags[0], contains('Travel'));
    });

    test('ClientAIImageManager state transitions and backup/restore', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(clientAIImageManagerProvider.notifier);

      // Initial state
      expect(notifier.state.remotePaths.length, 5);

      // Set remote paths
      notifier.setRemotePaths(['path_0', 'path_1', 'path_2']);
      expect(notifier.state.remotePaths[0], 'path_0');
      expect(notifier.state.remotePaths[1], 'path_1');
      expect(notifier.state.remotePaths[2], 'path_2');
      expect(notifier.state.remotePaths[3], '');

      // Backup & restore
      notifier
        ..backupState()
        ..setRemotePaths(['new_0']);
      expect(notifier.state.remotePaths[0], 'new_0');

      notifier.restoreBackup();
      expect(notifier.state.remotePaths[0], 'path_0');
    });

    test('ClientAIImageManager remove slot / clear pending', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(clientAIImageManagerProvider.notifier)
        ..setRemotePaths(['p0', 'p1', 'p2', 'p3', 'p4'])
        ..clearImageSlot(1);

      expect(notifier.state.remotePaths[4], '');
      expect(notifier.state.pendingDeletions, contains('p1'));
    });
  });
}
