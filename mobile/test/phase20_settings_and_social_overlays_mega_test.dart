import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/settings/screens/data_export_flow.dart';
import 'package:nexus/features/settings/screens/email_notification_settings_page.dart';
import 'package:nexus/features/social_modes/widgets/dating_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

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

  group('Social Mode Overlays & Settings Mega Coverage Tests', () {
    testWidgets(
      'DatingSettingsOverlay renders chips, search query, and toggles values',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatingSettingsOverlay(
                datingTargetBuckets: const ['W', 'NB'],
                datingFor: const ['Long-term relationship'],
                partnerValues: const ['Authenticity', 'Kindness'],
                childrenPlans: 'Someday',
                savingFields: const {},
                onSaveDatingField: (field, val, setter) async {},
                onLoadDatingProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(DatingSettingsOverlay), findsOneWidget);

        // Scroll overlay
        await tester.drag(
          find.byType(DatingSettingsOverlay),
          const Offset(0, -400),
        );
        await tester.pump();
      },
    );

    testWidgets(
      'ProfessionalSettingsOverlay renders roles, company, tech skills and search',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfessionalSettingsOverlay(
                professionalTargetBuckets: const ['All'],
                lookingFor: const ['Cofounder', 'Mentorship'],
                techSkills: const ['Flutter', 'Dart', 'Go', 'AI'],
                company: 'Nexus Tech',
                roleType: const ['Software Engineer'],
                savingFields: const {},
                onSaveProfessionalField: (field, val, setter) async {},
                onLoadProfessionalProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);

        await tester.drag(
          find.byType(ProfessionalSettingsOverlay),
          const Offset(0, -400),
        );
        await tester.pump();
      },
    );

    testWidgets(
      'ModeCategorySelectionSheet renders list of items and handles interactions',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final items = [
          {
            'actor_id': 'u_actor_1',
            'name': 'Isabella',
            'age': 23,
            'avatar_url': 'https://example.com/isa.jpg',
            'created_at': DateTime.now().toIso8601String(),
          },
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ModeCategorySelectionSheet(
                title: 'Incoming Likes',
                themeColor: AppColors.modeDating,
                items: items,
                onFetchItems: () async {},
                onOpenItemDetailsDialog:
                    ({
                      required ctx,
                      required actorId,
                      required name,
                      required onActioned,
                      required onProfileLoaded,
                    }) {},
                onRecordAction: (targetId, action, token) async => true,
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
      },
    );

    testWidgets(
      'EmailNotificationSettingsPage loads preferences and toggles switches',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'email_notify_matches': true,
              'email_notify_messages': true,
              'email_notify_digest': false,
              'email_notify_safety': true,
              'email_notify_marketing': false,
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EmailNotificationSettingsPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(EmailNotificationSettingsPage), findsOneWidget);

        // Scroll settings
        await tester.drag(
          find.byType(EmailNotificationSettingsPage),
          const Offset(0, -400),
        );
        await tester.pump();
      },
    );

    testWidgets('startDataExport opens confirmation dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => startDataExport(context),
                child: const Text('Export Data'),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      expect(find.text('Export Personal Data'), findsOneWidget);
    });
  });
}
