# ── Firebase IID ─────────────────────────────────────────────────────────────
# FirebaseInstanceId was deprecated and removed, but google_mlkit_image_labeling
# pulls in mlkit-linkfirebase which still references it at the class level.
# The class is never actually called at runtime so it's safe to suppress.
-dontwarn com.google.firebase.iid.FirebaseInstanceId
-dontwarn com.google.firebase.iid.**

# ── WorkManager / Room ────────────────────────────────────────────────────────
# Keep the WorkManager internal database implementation to avoid NoSuchMethodException
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# Keep the Worker constructors required by WorkManager
-keep class * extends androidx.work.ListenableWorker {
    <init>(android.content.Context, androidx.work.WorkerParameters);
}

# ── Flutter & Plugins ────────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ── App Native Classes & Services ─────────────────────────────────────────────
-keep class com.devakesu.apps.nexus.** { *; }

# ── Spotify SDK ───────────────────────────────────────────────────────────────
-keep class com.spotify.sdk.** { *; }
-keep class com.spotify.android.auth.** { *; }

