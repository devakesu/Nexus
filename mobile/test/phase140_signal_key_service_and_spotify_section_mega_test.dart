import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/profile/widgets/sections/spotify_playlists_section.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';

import 'helpers/mock_network_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  setUpAll(setupGlobalMockNetwork);

  group(
    'Phase 140 - Signal Key Service & Spotify Playlists Sheet Mega Tests',
    () {
      test('SignalKeyService singleton has isNewLocalIdentity flag', () {
        final service = SignalKeyService.instance;
        expect(service.isNewLocalIdentity, isFalse);
      });

      testWidgets('openPlaylistsSheet renders bottom sheet content', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => openPlaylistsSheet(context),
                    child: const Text('Open Playlists'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.text('Open Playlists'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(DraggableScrollableSheet), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    },
  );
}
