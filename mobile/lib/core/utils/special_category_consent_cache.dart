/// In-memory cache of whether the signed-in user currently has granted
/// sexual-orientation/religious-belief ("special-category") data consent -
/// see AuthBootstrapResponse.special_category_consent_granted and
/// 20260802000000_terms_consent_expansion.sql. Populated by AuthGate after
/// every successful bootstrap and read by profile_tab.dart to decide
/// whether setting display_sexuality/religious_beliefs to a real disclosed
/// value should proceed or show an inline consent prompt first. Mirrors
/// SafetyConsentCache exactly - deliberately just an in-memory flag, no
/// PII, re-fetched fresh on every bootstrap.
abstract final class SpecialCategoryConsentCache {
  static bool isGranted = false;

  /// Cached alongside isGranted so an inline consent prompt can submit
  /// POST /api/v1/auth/accept-terms without a round-trip to re-fetch it.
  static String currentTermsVersion = '1';

  static void clear() {
    isGranted = false;
  }
}
