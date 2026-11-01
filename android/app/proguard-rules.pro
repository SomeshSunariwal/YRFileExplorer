# SMB uses password-based NTLM only in this app. Java SE Kerberos/GSS and the
# MBassador optional expression-language filtering are not Android features and
# are not called. Keep this list limited to these unused optional integrations.
-dontwarn org.ietf.jgss.**
-dontwarn javax.el.**

# JSch resolves crypto and authentication algorithms from class-name strings.
-keep class com.jcraft.jsch.** { *; }
# Password-only SFTP does not use JSch's optional desktop SSH-agent adapters or
# Log4j bridge. Their Java SE dependencies are deliberately not packaged.
-dontwarn com.sun.jna.**
-dontwarn org.newsclub.net.unix.**
-dontwarn org.apache.logging.log4j.**

# MBassador discovers SMB's event handlers from runtime annotations.
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault,Signature
-keepclassmembers class * {
    @net.engio.mbassy.listener.Handler <methods>;
}
