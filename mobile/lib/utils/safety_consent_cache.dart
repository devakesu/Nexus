/// In-memory cache of whether the signed-in user currently has granted
/// Meetup Safety/SOS/Digital Witness data-consent - see
/// AuthBootstrapResponse.safety_data_consent_granted and
/// 20260802000000_terms_consent_expansion.sql. Populated by AuthGate after
/// every successful bootstrap and read by SafetyCenterPage/EventPlannerSheet
/// to decide whether to show their safety features unlocked or gated behind
/// an inline consent prompt. Deliberately just an in-memory flag (not
/// secure-storage-backed like SecureProfileCache/DiscoveryHubCache) since
/// it holds no PII, only a boolean UI-gating decision that's re-fetched
/// fresh on every bootstrap anyway.
abstract final class SafetyConsentCache {
  static bool isGranted = false;

  /// Cached alongside isGranted so an inline "Enable Safety Features"
  /// prompt (shown from SafetyCenterPage/EventPlannerSheet) can submit
  /// POST /api/v1/auth/accept-terms without a round-trip to re-fetch it.
  static String currentTermsVersion = '1';

  static void clear() {
    isGranted = false;
  }
}
