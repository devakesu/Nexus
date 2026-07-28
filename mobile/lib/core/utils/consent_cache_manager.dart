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

/// Backward compatibility class alias for SafetyConsentCache
abstract final class SafetyConsentCache {
  static bool get isGranted => ConsentCacheManager.safetyConsentGranted;
  static set isGranted(bool value) =>
      ConsentCacheManager.safetyConsentGranted = value;

  static String get currentTermsVersion =>
      ConsentCacheManager.currentTermsVersion;
  static set currentTermsVersion(String value) =>
      ConsentCacheManager.currentTermsVersion = value;

  static void clear() => ConsentCacheManager.clear();
}

/// Backward compatibility class alias for SpecialCategoryConsentCache
abstract final class SpecialCategoryConsentCache {
  static bool get isGranted =>
      ConsentCacheManager.specialCategoryConsentGranted;
  static set isGranted(bool value) =>
      ConsentCacheManager.specialCategoryConsentGranted = value;

  static String get currentTermsVersion =>
      ConsentCacheManager.currentTermsVersion;
  static set currentTermsVersion(String value) =>
      ConsentCacheManager.currentTermsVersion = value;

  static void clear() => ConsentCacheManager.clear();
}
