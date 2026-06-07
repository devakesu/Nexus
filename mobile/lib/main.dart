import 'dart:async';
import 'dart:io';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/firebase_options_mec.dart' as mec_opts;
import 'package:nexus/firebase_options_nexus.dart' as nexus_opts;
import 'package:nexus/screens/auth_gate.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set global HTTP overrides to handle custom certificate validation in debug mode
  HttpOverrides.global = MyHttpOverrides();

  // Get current flavor configuration
  final config = AppConfig.current;
  const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');

  // Initialize Firebase dynamically based on flavor
  final firebaseOptions = flavor == 'mec'
      ? mec_opts.DefaultFirebaseOptions.currentPlatform
      : nexus_opts.DefaultFirebaseOptions.currentPlatform;

  // Initialize Firebase and Supabase in parallel to speed up app startup
  await Future.wait([
    Firebase.initializeApp(
      options: firebaseOptions,
    ).then((_) {
      // Initialize Firebase App Check on app open to prevent delays
      return FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode ? const AppleDebugProvider() : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
    }),
    Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
    ),
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
    const isMec = flavor == 'mec';
    const appName = isMec ? 'Nexus MEC' : 'Nexus';

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00ADB5),
          brightness: Brightness.dark,
          primary: const Color(0xFF00ADB5),
          surface: const Color(0xFF0D0E12),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const AuthGate(appName: appName),
    );
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..connectionTimeout = kDebugMode
          ? const Duration(seconds: 45)
          : const Duration(seconds: 30);

    // In debug mode, we allow untrusted certificates ONLY if they match our expected hostname.
    // In release mode, standard certificate validation is enforced.
    if (kDebugMode) {
      client.badCertificateCallback = NetworkUtils.validateCertificateHostname;
    }

    return client;
  }
}
