import 'dart:async';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'helpers/mock_network_interceptor.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Animate.restartOnHotReload = false;
  GoogleFonts.config.allowRuntimeFetching = false;
  setupGlobalMockNetwork();
  await testMain();
}
