# R8 이 지우면 안 되는 것들. 릴리스에서만 터지는 종류의 버그라 미리 막아 둔다.

# Flutter 임베딩 — 리플렉션으로 찾는다.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_local_notifications 는 예약된 알림을 Gson 으로 직렬화해 두었다가
# 부팅/재개 시점에 되살린다. 필드 이름이 난독화되면 되살리지 못한다.
-keep class com.dexterous.** { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-dontwarn com.google.errorprone.annotations.**

# Play Core(인앱 업데이트/스플릿). Flutter 가 참조만 하고 우리는 안 쓴다 — 경고만 끈다.
-dontwarn com.google.android.play.core.**
