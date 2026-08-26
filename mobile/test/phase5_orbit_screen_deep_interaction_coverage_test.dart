import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/screens/orbit_screen.dart';
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

  final mockNodes = [
    OrbitNode(
      id: 'node_1',
      name: 'Maya Lin',
      x: 0.25,
      y: 0.35,
      orbitTier: 1,
      score: 95,
      profilePic: 'https://example.com/maya.jpg',
      gender: 'Woman',
      sexuality: 'Straight',
      connectionType: 'Dating',
    ),
    OrbitNode(
      id: 'node_2',
      name: 'Julian Vance',
      x: -0.45,
      y: 0.20,
      orbitTier: 2,
      score: 82.5,
      profilePic: 'https://example.com/julian.jpg',
      gender: 'Man',
      sexuality: 'Bisexual',
      connectionType: 'Dating',
    ),
  ];

  final mockPrefetch = OrbitPrefetchResult(
    nodes: mockNodes,
    sessionId: 'orbit_sess_101',
    profilePicUrl: 'https://example.com/my_pic.jpg',
    showBuckets: ['Women', 'Men'],
    datingFor: ['Long-term'],
    partnerValues: ['Kindness'],
  );

  group('OrbitScreen Deep Interaction Coverage Tests', () {
    testWidgets('renders OrbitScreen with nodes in Dating mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'Dating',
                themeColor: Colors.pinkAccent,
                prefetchFuture: Future.value(mockPrefetch),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(OrbitScreen), findsOneWidget);

      await tester.drag(find.byType(OrbitScreen), const Offset(100, -100));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(OrbitScreen), findsOneWidget);
    });

    testWidgets('renders OrbitScreen in Friends mode', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'Friends',
                themeColor: Colors.tealAccent,
                prefetchFuture: Future.value(mockPrefetch),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(OrbitScreen), findsOneWidget);
    });

    testWidgets('renders OrbitScreen in Professional mode', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'Professional',
                themeColor: Colors.indigoAccent,
                prefetchFuture: Future.value(mockPrefetch),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(OrbitScreen), findsOneWidget);
    });
  });
}
