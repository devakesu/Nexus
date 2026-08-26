import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/config/filter_options.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/theme/app_theme.dart';
import 'package:nexus/core/utils/type_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig & AppVariant Tests', () {
    test('AppVariant and AppConfig profiles are correctly defined', () {
      const nexusConfig = AppConfig.nexus;
      expect(nexusConfig.appVariant, equals(AppVariant.nexus));
      expect(nexusConfig.variantString, equals('nexus'));
      expect(nexusConfig.isMainVariant, isTrue);
      expect(nexusConfig.isFlavorVariant, isFalse);
      expect(nexusConfig.packageName, equals('com.devakesu.apps.nexus'));
      expect(nexusConfig.allowedSignupDomains, isEmpty);

      const mecConfig = AppConfig.nexusMec;
      expect(mecConfig.appVariant, equals(AppVariant.nexusMec));
      expect(mecConfig.variantString, equals('nexus_mec'));
      expect(mecConfig.isMainVariant, isFalse);
      expect(mecConfig.isFlavorVariant, isTrue);
      expect(mecConfig.packageName, equals('com.devakesu.apps.nexus.mec'));
      expect(mecConfig.logoAssetPath, equals('assets/nexus-mec.png'));
    });

    test('AppConfig static accessors return valid fallbacks', () {
      expect(AppConfig.current, isNotNull);
      expect(AppConfig.otpLength, equals(6));
      expect(AppConfig.githubUrl, contains('github.com'));
      expect(
        AppConfig.playStoreUrl,
        contains('play.google.com/store/apps/details'),
      );
      expect(AppConfig.webUrl, contains('http'));
      expect(AppConfig.legalEmail, contains('legal@'));
      expect(AppConfig.isReleaseBuild, isFalse);
      expect(AppConfig.appCommitSha, isNotEmpty);
      expect(AppConfig.buildTimestamp, isNotEmpty);
      expect(AppConfig.githubRunNumber, isNotEmpty);
      expect(AppConfig.githubRunId, isNotEmpty);
      expect(AppConfig.runtimeVersion, isA<String>());
    });

    test('AppConfig initializeRuntime executes gracefully', () async {
      await AppConfig.initializeRuntime();
      expect(AppConfig.runtimeVersion, isA<String>());
    });
  });

  group('FilterOptions & Interests Categories Tests', () {
    test(
      'interestsCategories is populated with categories and subinterests',
      () {
        expect(interestsCategories, isNotEmpty);
        final techCat = interestsCategories.firstWhere(
          (c) => c.name == 'Tech & Science',
        );
        expect(techCat.parents, isNotEmpty);
        expect(techCat.parents.first.name, equals('Coding'));
        expect(techCat.parents.first.subInterests, contains('Flutter & Dart'));
      },
    );
  });

  group('AppColors & GhostColors Theme Tests', () {
    test('GhostColors copyWith and lerp functionality', () {
      const ghost = GhostColors();
      expect(ghost.brandPrimary, equals(AppColors.pulsarPink));
      expect(ghost.brandAccent, equals(AppColors.primaryTeal));

      final modified = ghost.copyWith(
        brandPrimary: Colors.amber,
        dangerRed: Colors.deepOrange,
      );
      expect(modified.brandPrimary, equals(Colors.amber));
      expect(modified.dangerRed, equals(Colors.deepOrange));
      expect(modified.brandAccent, equals(AppColors.primaryTeal));

      final lerped = ghost.lerp(modified, 0.5);
      expect(lerped.brandPrimary, isNotNull);

      // lerp with non-GhostColors returns this
      final same = ghost.lerp(null, 0.5);
      expect(same, equals(ghost));
    });

    test('AppColors palette and helpers', () {
      expect(AppColors.surface, isA<Color>());
      expect(AppColors.canvas, isA<Color>());
      expect(AppColors.modeDating, isA<Color>());
      expect(AppColors.modeFriends, isA<Color>());
      expect(AppColors.modeProfessional, isA<Color>());
      expect(AppColors.safetyBlue, isA<Color>());

      final tinted = AppColors.tint(AppColors.primaryTeal, 0.5);
      expect(tinted, isA<Color>());

      expect(AppColors.foregroundFor(Colors.black), equals(Colors.white));
      expect(AppColors.foregroundFor(Colors.white), equals(Colors.black));
    });
  });

  group('TypeUtils Tests', () {
    test('formatBuildTimestamp formats valid timestamps and fallbacks', () {
      expect(formatBuildTimestamp(''), equals('Local build'));
      expect(formatBuildTimestamp('local'), equals('Local build'));

      const nowIso = '2026-08-26T12:00:00Z';
      final formattedIso = formatBuildTimestamp(nowIso);
      expect(formattedIso, contains('2026'));

      const millis = '1724673600000';
      final formattedMillis = formatBuildTimestamp(millis);
      expect(formattedMillis, isNotEmpty);

      const invalid = 'invalid_date_format';
      expect(formatBuildTimestamp(invalid), equals(invalid));
    });
  });
}
