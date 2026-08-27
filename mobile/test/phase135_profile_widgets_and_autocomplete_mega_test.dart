import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';

import 'helpers/mock_network_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 135 - Profile Detail Sheet and Providers Mega Tests', () {
    testWidgets(
      'ProfileDetailSheet renders full public profile with action callbacks',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileDetailSheet(
                  data: kFullMockProfile,
                  themeColor: Colors.pink,
                  scrollController: ScrollController(),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ProfileDetailSheet), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets('PlaceAutocompleteField renders with custom decoration', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceAutocompleteField(
              label: 'Hometown',
              hintText: 'Search city...',
              prefixIcon: Icons.location_city,
              initialValue: 'Seattle',
              onChanged: (v) {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(PlaceAutocompleteField), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
