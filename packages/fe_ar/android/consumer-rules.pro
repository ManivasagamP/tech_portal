# The app ships with minification off (android/app/build.gradle.kts), but keep
# these in case that changes: JNI binds FeArCore's external methods by name.
-keep class com.fusionapps.fe_ar.FeArCore { *; }
-keepclasseswithmembernames class * { native <methods>; }
