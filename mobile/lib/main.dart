import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/firebase_options_mec.dart' as mec_opts;
import 'package:nexus/firebase_options_nexus.dart' as nexus_opts;
import 'package:nexus/screens/auth_gate.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  SentryWidgetsFlutterBinding.ensureInitialized();

  // Setup uncaught Flutter error handler
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorHandler.handleError(
      details.exception,
      stackTrace: details.stack,
      customMessage: details.exceptionAsString(),
    );
  };

  // Setup uncaught platform / asynchronous error handler
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorHandler.handleError(
      error,
      stackTrace: stack,
      level: ErrorLevel.critical,
    );
    return true;
  };

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
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
    }),
    Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
    ),
  ]);

  await SentryFlutter.init(
    (options) {
      options
        ..dsn =
            'https://b5cd0432aa4dcfbedcffe860e0b90f58@o4510669780287488.ingest.de.sentry.io/4511525319475280'
        // Adds request headers and IP for users, for more info visit:
        // https://docs.sentry.io/platforms/dart/guides/flutter/data-management/data-collected/
        ..sendDefaultPii = false
        ..enableLogs = true
        // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
        // We recommend adjusting this value in production.
        ..tracesSampleRate = 0.1
        // The sampling rate for profiling is relative to tracesSampleRate
        // Setting to 1.0 will profile 100% of sampled transactions:
        // ignore: experimental_member_use
        ..profilesSampleRate = 0.1;
      // Configure Session Replay
      options.replay.sessionSampleRate = kDebugMode ? 0.0 : 0.1;
      options.replay.onErrorSampleRate = kDebugMode ? 0.0 : 1.0;

      // Sanitize sensitive info in all events sent to Sentry
      options.beforeSend = (event, hint) {
        if (event.exceptions != null) {
          for (final exception in event.exceptions!) {
            if (exception.value != null) {
              exception.value = ErrorHandler.sanitize(exception.value!);
            }
          }
        }
        final msg = event.message;
        if (msg != null) {
          msg.formatted = ErrorHandler.sanitize(msg.formatted);
        }
        if (event.contexts.isNotEmpty) {
          event.contexts.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              final sanitized = <String, dynamic>{};
              value.forEach((k, v) {
                if (v is String) {
                  sanitized[k] = ErrorHandler.sanitize(v);
                } else {
                  sanitized[k] = v;
                }
              });
              event.contexts[key] = sanitized;
            } else if (value is String) {
              event.contexts[key] = ErrorHandler.sanitize(value);
            }
          });
        }
        return event;
      };
    },
    appRunner: () => runApp(
      SentryWidget(
        child: const ProviderScope(
          child: MyApp(),
        ),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
    const isMec = flavor == 'mec';
    const appName = isMec ? 'Nexus MEC' : 'Nexus';

    return MaterialApp(
      navigatorKey: ErrorHandler.navigatorKey,
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0891B2),
          primary: const Color(0xFF0891B2),
          surface: Colors.white,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.light().textTheme.copyWith(
            displayLarge: const TextStyle(color: Color(0xFF0F172A)),
            displayMedium: const TextStyle(color: Color(0xFF0F172A)),
            displaySmall: const TextStyle(color: Color(0xFF0F172A)),
            headlineLarge: const TextStyle(color: Color(0xFF0F172A)),
            headlineMedium: const TextStyle(color: Color(0xFF0F172A)),
            headlineSmall: const TextStyle(color: Color(0xFF0F172A)),
            titleLarge: const TextStyle(color: Color(0xFF0F172A)),
            titleMedium: const TextStyle(color: Color(0xFF0F172A)),
            titleSmall: const TextStyle(color: Color(0xFF0F172A)),
          ),
        ),
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
