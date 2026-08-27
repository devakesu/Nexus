import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a widget in ProviderScope and MaterialApp for widget testing.
Widget buildTestWidget({
  required Widget child,
  List<dynamic> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

/// Pumps a test widget wrapped in ProviderScope and MaterialApp.
Future<void> pumpTestWidget(
  WidgetTester tester,
  Widget child, {
  List<dynamic> overrides = const [],
  Duration? duration,
}) async {
  await tester.pumpWidget(
    buildTestWidget(
      child: child,
      overrides: overrides,
    ),
  );
  if (duration != null) {
    await tester.pump(duration);
  }
}
