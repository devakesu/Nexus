/// Unified in-memory cache for user consent flags (Safety Data and Special Category Data).
/// Deliberately an in-memory flag as it holds no PII, only boolean UI-gating decisions
/// re-fetched fresh on every bootstrap.
abstract final class ConsentCacheManager {
  static bool safetyConsentGranted = false;
  static bool specialCategoryConsentGranted = false;
  static String currentTermsVersion = '1';

  static void clear() {
    safetyConsentGranted = false;
    specialCategoryConsentGranted = false;
  }
}
