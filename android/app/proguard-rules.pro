# Règles ProGuard/R8 — CorelIA (chatbot mobile)
# Ne conserver que ce qui est réellement embarqué : Flutter, Firebase,
# Google Sign-In, RevenueCat, image_picker, file_picker, shared_preferences,
# url_launcher, share_plus.

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase / Google Play Services (auth, sign-in)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# Génériques et annotations (utilisés par la sérialisation Firestore)
-keepattributes Signature
-keepattributes *Annotation*

# Méthodes natives
-keepclasseswithmembernames class * {
    native <methods>;
}

# Constructeurs de vues personnalisées
-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet);
}
-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet, int);
}

# Accesseurs et énumérations (sérialisation par réflexion)
-keepclassmembers class * {
    void set*(***);
    *** get*();
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Parcelable / Serializable
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# RevenueCat (purchases_flutter)
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# image_picker / file_picker
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# flutter_image_compress
-keep class com.fluttercandies.** { *; }

# shared_preferences / url_launcher / share_plus
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class io.flutter.plugins.share.** { *; }

# Flutter Play Store Split — classes optionnelles absentes
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.tasks.**
-keep class com.google.android.play.core.** { *; }
