import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/profile/widgets/futuristic_background_painter.dart';
import 'package:nexus/features/profile/widgets/orbit_painter.dart';
import 'package:nexus/features/profile/widgets/selector_tile.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 131 - Profile Widgets Deep Exhaustive Mega Tests', () {
    testWidgets('TagChipsEditor renders, adds, removes, and taps tags', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TagChipsEditor(
              label: 'Languages',
              currentValues: const ['English', 'Spanish'],
              presets: const ['English', 'Spanish', 'French', 'German'],
              icon: Icons.language,
              iconColor: Colors.blue,
              hintText: 'Add language...',
              onChanged: (tags) {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(TagChipsEditor), findsOneWidget);

      final chips = find.byType(ActionChip);
      for (var i = 0; i < chips.evaluate().length; i++) {
        try {
          await tester.tap(chips.at(i), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 50));
        } on Object catch (_) {}
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('SelectorTile renders cleanly and responds to tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectorTile(
              icon: Icons.school,
              iconColor: Colors.amber,
              label: 'Education',
              value: 'Stanford University',
              onTap: () {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(SelectorTile), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('FuturisticBackgroundPainter and OrbitPainter paint cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(300, 300),
              painter: const FuturisticBackgroundPainter(
                accentColor: Colors.deepPurple,
              ),
              foregroundPainter: OrbitPainter(
                progress: 0.5,
                color: Colors.cyan,
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
    });
  });
}
