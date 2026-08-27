import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/theme/app_theme.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 100 - Capstone All Systems Comprehensive Mega Tests', () {
    test('GhostColors extension holds correct theme tokens', () {
      const ghost = GhostColors();
      expect(ghost.brandPrimary, AppColors.pulsarPink);
      expect(ghost.brandAccent, AppColors.primaryTeal);
      expect(ghost.successGreen, AppColors.success);
      expect(ghost.warningYellow, AppColors.warning);
      expect(ghost.dangerRed, AppColors.error);
    });

    testWidgets('NexusOrbitLoader and aesthetic loaders render smoothly', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NexusOrbitLoader(),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(NexusOrbitLoader), findsOneWidget);
    });

    test('ErrorHandler handles generic exceptions cleanly', () {
      ErrorHandler.handleError(
        Exception('Network failure'),
        customMessage: 'Profile Sync Error',
      );
    });
  });
}
