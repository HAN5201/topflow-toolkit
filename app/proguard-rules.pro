# 保护 JavascriptInterface 映射类不被混淆
-keepattributes *Annotation*
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

-keep class com.topflow.toolkit.MainActivity$TopflowJSBridge { *; }
-keep class com.topflow.toolkit.AdbManager { *; }
