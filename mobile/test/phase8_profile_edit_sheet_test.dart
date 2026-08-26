import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/profile/widgets/profile_field_edit_sheet.dart';
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

  group('ProfileFieldEditSheet Tests', () {
    testWidgets(
      'opens 2-step profile field edit sheet and progresses from intro to confirm',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        String? confirmedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      unawaited(
                        showProfileFieldEditSheet<String>(
                          context: context,
                          fieldTitle: 'Display Name',
                          currentValue: 'Aria',
                          eligible: true,
                          changesUsedInWindow: 0,
                          nextEligibleAt: null,
                          inputBuilder: (ctx, pending, onChanged) {
                            return TextFormField(
                              initialValue: pending,
                              onChanged: onChanged,
                            );
                          },
                          confirmDescriptionBuilder: (pending) =>
                              'Change name to $pending?',
                          onConfirmed: (val) {
                            confirmedResult = val;
                          },
                        ),
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
        expect(find.text('Review Change'), findsOneWidget);

        await tester.enterText(find.byType(TextFormField), 'Aria Vance');
        await tester.pump();

        await tester.tap(find.text('Review Change'));
        await tester.pumpAndSettle();

        expect(find.text('Confirm New Display Name'), findsOneWidget);
        expect(find.text('Change name to Aria Vance?'), findsOneWidget);

        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();

        expect(confirmedResult, 'Aria Vance');
      },
    );

    testWidgets('renders rate limit warning when ineligible', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    unawaited(
                      showProfileFieldEditSheet<int>(
                        context: context,
                        fieldTitle: 'Age',
                        currentValue: 24,
                        eligible: false,
                        changesUsedInWindow: 2,
                        nextEligibleAt: DateTime(2026, 12, 31),
                        inputBuilder: (ctx, pending, onChanged) => Container(),
                        confirmDescriptionBuilder: (pending) => 'Change age',
                        onConfirmed: (_) {},
                      ),
                    );
                  },
                  child: const Text('Open Ineligible Sheet'),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Open Ineligible Sheet'));
      await tester.pumpAndSettle();

      expect(
        find.text('0 of 2 changes remaining (Limit reached)'),
        findsOneWidget,
      );
    });
  });
}
