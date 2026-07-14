# Play / launcher: nunca remover ou ofuscar a Activity principal (ClassNotFoundException).
-keep class com.gestaoyahweh.app.MainActivity { *; }
-keep class io.flutter.embedding.android.** { *; }

# Flutter deferred components referenciam Play Core; biblioteca opcional no AAB.
-dontwarn com.google.android.play.core.**

# ML Kit text recognition (Utilitários) — scripts opcionais não empacotados no AAB.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
