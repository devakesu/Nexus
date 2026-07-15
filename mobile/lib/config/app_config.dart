import 'dart:convert';

/// Identifies which compiled flavor of the app is running.
///
/// The value is resolved from the 'FLUTTER_APP_FLAVOR' compile-time
/// constant injected via --dart-define at build time.
enum AppVariant {
  /// Main Nexus app - all email domains allowed, imports data from flavors.
  nexus,

  /// Nexus MEC flavor - campus email required, generates export codes for import.
  nexusMec,
}

class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.googleWebClientId,
    required this.googleIosClientId,
    required this.logoAssetPath,
    required this.backendUrl,
    required this.appVariant,
    required this.spotifyClientId,
    required this.spotifyNativeRedirectUri,
    required this.sentryDsn,
    required this.googlePlacesApiKey,
  });

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String googleWebClientId;
  final String googleIosClientId;
  final String logoAssetPath;
  final String backendUrl;

  /// Spotify public client ID from the Spotify Developer Dashboard.
  /// Also register your SHA-1 fingerprints and both redirect URIs there.
  final String spotifyClientId;

  /// Must match manifestPlaceholders in build.gradle.kts:
  /// "{redirectSchemeName}://{redirectHostName}"
  final String spotifyNativeRedirectUri;

  /// The Sentry client DSN URL. If not provided or empty, Sentry logging will be disabled.
  final String sentryDsn;

  /// Google Places API key (unrestricted by application signature for HTTP calls).
  final String googlePlacesApiKey;

  /// Which flavor this config profile represents.
  final AppVariant appVariant;

  // ---------------------------------------------------------------------------
  // Configuration profiles for the different flavors
  // ---------------------------------------------------------------------------

  // Overridable at build/run time via --dart-define (e.g. through
  // `infisical run -- flutter run --dart-define=BACKEND_URL=...`), so real
  // deployment values never need a code change. The defaults below are
  // dev-only fallbacks: `backendUrl` is the Android emulator's loopback
  // alias, and the iOS client IDs are placeholders that make Google Sign-In
  // on iOS fail loudly rather than silently until the real values (from the
  // Google Cloud Console, distinct per flavor's bundle ID) are injected.
  static const String _appDomain = String.fromEnvironment(
    'APP_DOMAIN',
    defaultValue: 'localhost:3000',
  );
  static const String _backendUrl = String.fromEnvironment(
    'BACKEND_URL',
  );
  static const String _effectiveBackendUrl = _backendUrl != ''
      ? _backendUrl
      : 'https://$_appDomain';
  static const String _googleIosClientIdNexus = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID_NEXUS',
  );
  static const String _googleIosClientIdNexusMec = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID_NEXUS_MEC',
  );
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const String _googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const String _spotifyClientId = String.fromEnvironment(
    'SPOTIFY_CLIENT_ID',
  );
  static const String _spotifyNativeRedirectUriNexus = String.fromEnvironment(
    'SPOTIFY_REDIRECT_URI_NEXUS',
    defaultValue: 'devakesu-nexus://spotify-auth',
  );
  static const String _spotifyNativeRedirectUriNexusMec =
      String.fromEnvironment(
        'SPOTIFY_REDIRECT_URI_NEXUS_MEC',
        defaultValue: 'devakesu-nexus-mec://spotify-auth',
      );
  static const String _sentryFlutterDsn = String.fromEnvironment(
    'SENTRY_FLUTTER_DSN',
  );
  static const String _googlePlacesApiKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
  );

  static const AppConfig nexus = AppConfig(
    supabaseUrl: _supabaseUrl,
    supabasePublishableKey: _supabasePublishableKey,
    googleWebClientId: _googleWebClientId,
    googleIosClientId: _googleIosClientIdNexus,
    logoAssetPath: 'assets/nexus.png',
    backendUrl: _effectiveBackendUrl,
    appVariant: AppVariant.nexus,
    spotifyClientId: _spotifyClientId,
    spotifyNativeRedirectUri: _spotifyNativeRedirectUriNexus,
    sentryDsn: _sentryFlutterDsn,
    googlePlacesApiKey: _googlePlacesApiKey,
  );

  static const AppConfig mec = AppConfig(
    supabaseUrl: _supabaseUrl,
    supabasePublishableKey: _supabasePublishableKey,
    googleWebClientId: _googleWebClientId,
    googleIosClientId: _googleIosClientIdNexusMec,
    logoAssetPath: 'assets/nexus-mec.png',
    backendUrl: _effectiveBackendUrl,
    appVariant: AppVariant.nexusMec,
    spotifyClientId: _spotifyClientId,
    spotifyNativeRedirectUri: _spotifyNativeRedirectUriNexusMec,
    sentryDsn: _sentryFlutterDsn,
    googlePlacesApiKey: _googlePlacesApiKey,
  );

  /// OTP code length for email/phone verification. Must match the "OTP
  /// Length" setting in the Supabase Auth dashboard for every project this
  /// app points at - Supabase defaults to 6, this app expects 8.
  static const int otpLength = 8;

  // ---------------------------------------------------------------------------
  // Runtime accessors
  // ---------------------------------------------------------------------------

  /// Returns the [AppConfig] matching the compile-time FLUTTER_APP_FLAVOR constant.
  static AppConfig get current {
    const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
    return flavor == 'mec' ? mec : nexus;
  }

  /// The canonical variant string sent to the backend in the X-App-Variant header.
  String get variantString {
    switch (appVariant) {
      case AppVariant.nexusMec:
        return 'nexus_mec';
      case AppVariant.nexus:
        return 'nexus';
    }
  }

  /// Whether this is the main nexus variant (imports from flavors).
  bool get isMainVariant => appVariant == AppVariant.nexus;

  /// Whether this is a flavor variant (generates export codes for import).
  bool get isFlavorVariant => appVariant != AppVariant.nexus;

  /// List of email domains allowed for signup for this variant.
  /// Derived from the compile-time ALLOWED_SIGNUP_DOMAINS constant.
  List<String> get allowedSignupDomains {
    if (appVariant == AppVariant.nexus) {
      return const [];
    }
    const raw = String.fromEnvironment('ALLOWED_SIGNUP_DOMAINS');
    if (raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final variantKey = variantString; // e.g. 'nexus_mec'
        final domains = decoded[variantKey];
        if (domains is List) {
          return domains.map((e) => e.toString().trim()).toList();
        } else if (domains is String) {
          return domains.split(',').map((e) => e.trim()).toList();
        }
      } else if (decoded is List) {
        return decoded.map((e) => e.toString().trim()).toList();
      }
    } on Object catch (_) {
      return raw.split(',').map((e) => e.trim()).toList();
    }
    return const [];
  }
}
