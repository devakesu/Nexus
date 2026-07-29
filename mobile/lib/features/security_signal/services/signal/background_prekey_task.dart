// The background task isolate entry point causes the analyzer to
// misidentify this file as an executable entry point.

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/secure_session_storage.dart';
import 'package:nexus/features/security_signal/services/pending_evidence_upload_queue.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

/// Must stay in sync with `BGTaskSchedulerPermittedIdentifiers` in
/// ios/Runner/Info.plist - iOS refuses to run any BGTaskScheduler
/// identifier that isn't declared there.
const String kPrekeyReplenishTaskName = 'com.devakesu.nexus.prekeyReplenish';
const String _kPrekeyReplenishUniqueName = 'prekey-replenish-periodic';

/// Entry point Android/iOS invokes, in a fresh background isolate, whenever
/// any registered background task fires - including when the app is fully
/// closed. This isolate shares no state with the main app isolate, so every
/// dependency (Supabase session, Signal identity/session store) has to be
/// bootstrapped from scratch here.
///
/// This is the single Workmanager callback dispatcher for the whole app
/// (native only holds one global entry point, set via the one
/// `Workmanager().initialize()` call in [schedulePrekeyReplenishment]) - it
/// routes on the fired task's name to whichever background job actually ran,
/// rather than each job registering its own dispatcher.
@pragma('vm:entry-point')
void prekeyReplenishCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final config = AppConfig.current;
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
        authOptions: const FlutterAuthClientOptions(
          localStorage: SecureLocalStorage(),
          pkceAsyncStorage: SecureGotrueAsyncStorage(),
        ),
      );

      if (task == kEvidenceUploadRetryTaskName) {
        // No signed-in check here - PendingEvidenceUploadQueue.drain()
        // already treats "not signed in" as "nothing to do yet" and leaves
        // the queue in place for a later attempt.
        return await PendingEvidenceUploadQueue.drain();
      }

      if (task != kPrekeyReplenishTaskName) return true;
      if (Supabase.instance.client.auth.currentSession == null) {
        // Not signed in on this device - nothing to replenish.
        return true;
      }
      try {
        await SignalKeyService.instance.replenishOneTimePrekeysIfNeeded();
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          // Profile not found (not onboarded yet). Stop trying and return success.
          return true;
        }
        rethrow;
      }
      return true;
    } on Exception catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        level: ErrorLevel.warning,
        showUi: false,
        customMessage: 'Background task failed for task: $task',
      );
      return false;
    }
  });
}

/// Registers the periodic background top-up. Call once from `main()`.
/// Idempotent: re-registering the same unique name with `keep` no-ops if a
/// task is already scheduled, so it's safe to call on every app launch
/// regardless of sign-in state - the task itself checks for a session and
/// bails out early if there isn't one.
Future<void> schedulePrekeyReplenishment() async {
  await Workmanager().initialize(prekeyReplenishCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _kPrekeyReplenishUniqueName,
    kPrekeyReplenishTaskName,
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
