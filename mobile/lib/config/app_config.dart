/// Identifies which compiled flavor of the app is running.
///
/// The value is resolved from the 'FLUTTER_APP_FLAVOR' compile-time
/// constant injected via --dart-define at build time.
enum AppVariant {
  /// Main Nexus app — all email domains allowed, imports data from flavors.
  nexus,

  /// Nexus MEC flavor — campus email required, generates export codes for import.
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
    this.allowedEmailDomain,
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

  /// Which flavor this config profile represents.
  final AppVariant appVariant;

  /// Optional campus email domain enforced for this flavor.
  /// Null means all email domains are allowed (used by the main nexus flavor).
  final String? allowedEmailDomain;

  // ---------------------------------------------------------------------------
  // Configuration profiles for the different flavors
  // ---------------------------------------------------------------------------

  static const AppConfig nexus = AppConfig(
    supabaseUrl: 'https://xqysznugzwkwfhwgxckr.supabase.co',
    supabasePublishableKey: 'sb_publishable_aysVO0aF2hY6DZcd9WtBsg_3NPQduEU',
    googleWebClientId:
        '360032447327-ijma9pp8i1m9263smgdo5u2i0fhj7nal.apps.googleusercontent.com',
    googleIosClientId: 'your-nexus-ios-client-id.apps.googleusercontent.com',
    logoAssetPath: 'assets/nexus.png',
    backendUrl: 'https://192.168.0.103:8000',
    appVariant: AppVariant.nexus,
    spotifyClientId: '8e7bcea5271449448e4458fcbd91bca6',
    spotifyNativeRedirectUri: 'devakesu-nexus://spotify-auth',
  );

  static const AppConfig mec = AppConfig(
    supabaseUrl: 'https://xqysznugzwkwfhwgxckr.supabase.co',
    supabasePublishableKey: 'sb_publishable_aysVO0aF2hY6DZcd9WtBsg_3NPQduEU',
    googleWebClientId:
        '360032447327-ijma9pp8i1m9263smgdo5u2i0fhj7nal.apps.googleusercontent.com',
    googleIosClientId: 'your-mec-ios-client-id.apps.googleusercontent.com',
    logoAssetPath: 'assets/nexus-mec.png',
    backendUrl: 'https://192.168.0.103:8000',
    appVariant: AppVariant.nexusMec,
    spotifyClientId: '8e7bcea5271449448e4458fcbd91bca6',
    spotifyNativeRedirectUri: 'devakesu-nexus-mec://spotify-auth',
    allowedEmailDomain: 'mec.ac.in',
  );

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
}
