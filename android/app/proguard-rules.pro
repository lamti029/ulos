# Flutter/Dart + Android R8 rules for release.
# Goal: allow R8 shrinking while keeping classes required by
# Flutter deferred components / Play Core (splitinstall/splitcompat).

-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.firebase.** { *; }
-keep class id.flutter.flutter_background_service.** { *; }

# Keep Google Play Core classes used by Flutter deferred components.
# These are referenced by FlutterPlayStoreSplitApplication.
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Suppress missing-class warnings for Play Core (splitinstall/splitcompat).
# These are generated automatically in missing_rules.txt on failed builds.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Prevent R8 from removing/renaming JNI entrypoints.
-keepclassmembers class * {
    native <methods>;
}

# Default optimization rules.
-optimizations !code/simplification/arithmetic


