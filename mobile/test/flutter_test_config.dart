import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/mock_network_interceptor.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupGlobalMockNetwork();
  await testMain();
}
