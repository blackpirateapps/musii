# NewPipe uses Rhino to evaluate player JavaScript.
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.ClassFileWriter
-dontwarn org.mozilla.javascript.tools.**

# Rhino's optional JavaBean and desktop scripting integrations are absent on Android.
-dontwarn org.mozilla.javascript.JavaToJSONConverters
-dontwarn javax.script.**
-dontwarn jdk.dynalink.**

# The extractor's protobuf-lite messages look up their fields reflectively.
-keepclassmembers class org.schabi.newpipe.extractor.** extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}
