class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.googleWebClientId,
    required this.googleIosClientId,
    required this.logoAssetPath,
    required this.backendUrl,
  });

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String googleWebClientId;
  final String googleIosClientId;
  final String logoAssetPath;
  final String backendUrl;

  // Configuration profiles for the different flavors
  static const AppConfig nexus = AppConfig(
    supabaseUrl: 'https://xqysznugzwkwfhwgxckr.supabase.co',
    supabasePublishableKey: 'sb_publishable_aysVO0aF2hY6DZcd9WtBsg_3NPQduEU',
    googleWebClientId:
        '360032447327-ijma9pp8i1m9263smgdo5u2i0fhj7nal.apps.googleusercontent.com',
    googleIosClientId: 'your-nexus-ios-client-id.apps.googleusercontent.com',
    logoAssetPath: 'assets/nexus.png',
    backendUrl: 'https://192.168.0.103:8000',
  );

  static const AppConfig mec = AppConfig(
    supabaseUrl: 'https://xqysznugzwkwfhwgxckr.supabase.co',
    supabasePublishableKey: 'sb_publishable_aysVO0aF2hY6DZcd9WtBsg_3NPQduEU',
    googleWebClientId:
        '360032447327-ijma9pp8i1m9263smgdo5u2i0fhj7nal.apps.googleusercontent.com',
    googleIosClientId: 'your-mec-ios-client-id.apps.googleusercontent.com',
    logoAssetPath: 'assets/nexus-mec.png',
    backendUrl: 'https://192.168.0.103:8000',
  );

  // Get configuration corresponding to compile-time flavor
  static AppConfig get current {
    const flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
    return flavor == 'mec' ? mec : nexus;
  }
}
