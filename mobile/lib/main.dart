import 'dart:async';
import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/navigation/app_router.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/secure_session_storage.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/security_signal/services/notification_service.dart';
import 'package:nexus/features/security_signal/services/pending_evidence_upload_queue.dart';
import 'package:nexus/features/security_signal/services/security_service.dart';
import 'package:nexus/features/security_signal/services/signal/background_prekey_task.dart';
import 'package:nexus/firebase_options_nexus.dart' as nexus_opts;
import 'package:nexus/firebase_options_nexus_mec.dart' as nexus_mec_opts;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  SentryWidgetsFlutterBinding.ensureInitialized();
  SecurityService.initialize();
  await SecurityService.checkDebugger();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

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

  // Set global HTTP overrides to handle custom connection timeout
  HttpOverrides.global = MyHttpOverrides();

  // Get current flavor configuration
  final config = AppConfig.current;
  const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
  assert(
    flavor == 'nexus' || flavor == 'nexus_mec',
    'FLUTTER_APP_FLAVOR environment variable must be specified as either "nexus" or "nexus_mec" at build time via --dart-define=FLUTTER_APP_FLAVOR=...',
  );

  // Initialize Firebase dynamically based on flavor
  final firebaseOptions = flavor == 'nexus_mec'
      ? nexus_mec_opts.DefaultFirebaseOptions.currentPlatform
      : nexus_opts.DefaultFirebaseOptions.currentPlatform;

  // Initialize Firebase sequentially with a safety check
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: firebaseOptions,
      );
    }
  } catch (e) {
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
  }

  // Ensure App Check only runs once Firebase is confirmed active
  if (Firebase.apps.isNotEmpty) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  }

  // Initialize remaining async services in parallel to speed up app startup
  await Future.wait([
    AppConfig.initializeRuntime(),
    Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureLocalStorage(),
        pkceAsyncStorage: SecureGotrueAsyncStorage(),
      ),
    ),
    MeetupSafetySession.instance.init(),
  ]);

  // Must be registered before runApp() so the background isolate can find it.
  NotificationService.registerBackgroundHandler();

  // Handles a cold launch caused by tapping (or Android auto-launching over
  // the lock screen) the Meetup Safety check-in-due notification. Needs a
  // frame to have rendered so ErrorHandler.navigatorKey is attached.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(MeetupSafetySession.instance.handleAppLaunchFromNotification());
  });

  // Keeps the one-time-prekey pool topped up even when the app is fully
  // closed (see background_prekey_task.dart doc comment). Fire-and-forget:
  // scheduling failures shouldn't block app startup.
  unawaited(schedulePrekeyReplenishment());

  // Retries any Digital Witness evidence segments left over from a prior
  // session that couldn't finish uploading (flaky network, app killed
  // mid-upload) - a no-op if the queue is empty. Fire-and-forget: this is a
  // background catch-up, not something app startup should wait on.
  unawaited(PendingEvidenceUploadQueue.drain());

  if (config.sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        const baseEnv = String.fromEnvironment(
          'SENTRY_ENVIRONMENT',
          defaultValue: 'production',
        );
        final isStagingOrDev =
            baseEnv.contains('staging') ||
            baseEnv.contains('dev') ||
            kDebugMode;
        options
          ..dsn = config.sentryDsn
          ..environment = '${baseEnv}_${config.variantString}'
          // Adds request headers and IP for users, for more info visit:
          // https://docs.sentry.io/platforms/dart/guides/flutter/data-management/data-collected/
          ..sendDefaultPii = false
          ..enableLogs = true
          // Set tracesSampleRate dynamically based on environment.
          ..tracesSampleRate = isStagingOrDev ? 1.0 : 0.1
          // The sampling rate for profiling is relative to tracesSampleRate
          // Setting to 1.0 will profile 100% of sampled transactions:
          // ignore: experimental_member_use
          ..profilesSampleRate = isStagingOrDev ? 1.0 : 0.1;

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
      appRunner: () {
        // Explicitly tag the active variant for filtering in Sentry dashboard
        unawaited(
          Future.value(
            Sentry.configureScope(
              (scope) => scope.setTag('variant', config.variantString),
            ),
          ),
        );
        runApp(
          SentryWidget(
            child: const ProviderScope(
              child: MyApp(),
            ),
          ),
        );
      },
    );
  } else {
    runApp(
      const ProviderScope(
        child: MyApp(),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isMec = AppConfig.current.appVariant == AppVariant.nexusMec;
    final appName = isMec ? 'Nexus MEC' : 'Nexus';

    return MaterialApp.router(
      routerConfig: goRouter,
      title: appName,
      debugShowCheckedModeBanner: false,
      // Several fixed-height rows (bottom nav, dialog buttons) weren't built
      // to grow with the OS text-size setting. Clamp system text scaling to
      // a range those layouts can absorb without overflowing, while still
      // giving low-vision users real enlargement.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.8,
        maxScaleFactor: 1.3,
        child: child!,
      ),
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryTeal,
          primary: AppColors.primaryTeal,
          surface: Colors.white,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.light().textTheme.copyWith(
            displayLarge: const TextStyle(color: AppColors.ink),
            displayMedium: const TextStyle(color: AppColors.ink),
            displaySmall: const TextStyle(color: AppColors.ink),
            headlineLarge: const TextStyle(color: AppColors.ink),
            headlineMedium: const TextStyle(color: AppColors.ink),
            headlineSmall: const TextStyle(color: AppColors.ink),
            titleLarge: const TextStyle(color: AppColors.ink),
            titleMedium: const TextStyle(color: AppColors.ink),
            titleSmall: const TextStyle(color: AppColors.ink),
          ),
        ),
        useMaterial3: true,
      ),
    );
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = kDebugMode
          ? const Duration(seconds: 45)
          : const Duration(seconds: 20);
  }
}
