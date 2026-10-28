package com.example.sea_guard

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "fish_ai"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ask" -> {
                        val q = call.argument<String>("question") ?: ""
                        val englishName = call.argument<String>("englishName") ?: ""
                        val scientificName = call.argument<String>("scientificName") ?: ""
                        val habitat = call.argument<String>("habitat") ?: ""
                        val diet = call.argument<String>("diet") ?: ""
                        val culinary = call.argument<String>("culinary") ?: ""
                        val description = call.argument<String>("description") ?: ""
                        val imageUrl = call.argument<String>("imageUrl") ?: ""

                        val answer = buildString {
                            append("Check out this fish: ")
                            append(if (englishName.isNotEmpty()) englishName else "this species")
                            if (scientificName.isNotEmpty()) append(" ($scientificName)")
                            if (description.isNotEmpty()) {
                                append("\n\n")
                                append(description)
                            }
                            if (habitat.isNotEmpty()) append("\nHabitat: $habitat")
                            if (diet.isNotEmpty()) append("\nDiet: $diet")
                            if (culinary.isNotEmpty()) append("\nCulinary use: $culinary")
                            if (imageUrl.isNotEmpty()) append("\nImage: $imageUrl")
                            if (q.isNotEmpty()) {
                                append("\n\nYour question: $q")
                            }
                        }
                        result.success(answer.ifEmpty { "No AI answer available right now." })
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
