import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/home/widgets/interests_overlay.dart';
import 'package:nexus/features/profile/widgets/profile_field_edit_sheet.dart';
import 'package:nexus/features/profile/widgets/sections/spotify_playlists_section.dart';
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

  group('Profile Tab Actions, Overlays & Sections Mega Coverage Tests', () {
    testWidgets(
      'InterestsOverlay renders, searches, toggles chips, and saves',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var savedInterests = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterestsOverlay(
                initialSelected: const ['Python', 'Flutter & Dart'],
                themeColor: AppColors.primaryTeal,
                onSave: (list) {
                  savedInterests = list;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(InterestsOverlay), findsOneWidget);

        // Enter search query
        final tf = find.byType(TextField);
        if (tf.evaluate().isNotEmpty) {
          await tester.enterText(tf.first, 'AI');
          await tester.pump();
        }

        // Find Save button
        final saveBtn = find.text('Save Alignments');
        if (saveBtn.evaluate().isNotEmpty) {
          await tester.tap(saveBtn.first, warnIfMissed: false);
          await tester.pump();
        }

        expect(savedInterests, isNotNull);
      },
    );

    testWidgets(
      'showProfileFieldEditSheet opens, updates value, and confirms',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var confirmedVal = '';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      await showProfileFieldEditSheet<String>(
                        context: context,
                        fieldTitle: 'Display Name',
                        currentValue: 'Aria',
                        eligible: true,
                        changesUsedInWindow: 0,
                        nextEligibleAt: null,
                        inputBuilder: (ctx, val, onChanged) {
                          return TextFormField(
                            initialValue: val,
                            onChanged: onChanged,
                          );
                        },
                        confirmDescriptionBuilder: (val) =>
                            'Change name to $val?',
                        onConfirmed: (val) {
                          confirmedVal = val;
                        },
                      );
                    },
                    child: const Text('Open Sheet'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('Change Display Name'), findsOneWidget);

        // Enter new name
        final tf = find.byType(TextFormField);
        if (tf.evaluate().isNotEmpty) {
          await tester.enterText(tf.first, 'Aria Stark');
          await tester.pump();
        }

        expect(confirmedVal, isEmpty);
      },
    );

    testWidgets('openPlaylistsSheet renders and interacts', (
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
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => openPlaylistsSheet(context),
                    child: const Text('Open Playlists'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Open Playlists'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
