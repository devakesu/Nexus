import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/widgets/constellation_loader.dart';
import 'package:nexus/features/orbit/widgets/orbit_painters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'Phase 132 - Orbit Screen Deep Interactions and Painters Mega Tests',
    () {
      testWidgets('ConstellationLoader mounts and animates', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ConstellationLoader(
                themeColor: Colors.purple,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(ConstellationLoader), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      testWidgets(
        'CelestialBackgroundPainter and ConstellationLinesPainter paint cleanly',
        (
          tester,
        ) async {
          final nodes = [
            OrbitNode(
              id: 'node_1',
              name: 'Elena',
              x: 100,
              y: 50,
              orbitTier: 1,
              score: 95,
              profilePic: 'https://example.com/pic1.jpg',
              gender: 'Woman',
            ),
            OrbitNode(
              id: 'node_2',
              name: 'Lucas',
              x: -80,
              y: -120,
              orbitTier: 2,
              score: 88,
              profilePic: 'https://example.com/pic2.jpg',
              gender: 'Man',
            ),
          ];

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CustomPaint(
                  size: const Size(400, 400),
                  painter: CelestialBackgroundPainter(
                    themeColor: Colors.deepPurple,
                    pulseValue: 0.5,
                  ),
                  foregroundPainter: ConstellationLinesPainter(
                    nodes: nodes,
                    themeColor: Colors.deepPurple,
                    pulseValue: 0.5,
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byType(CustomPaint), findsWidgets);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    },
  );
}
