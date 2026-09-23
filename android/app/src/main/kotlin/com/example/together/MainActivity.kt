package com.example.together

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Subclassing AudioServiceActivity (instead of FlutterActivity directly) is
// what just_audio_background needs to hook into the Activity lifecycle for
// background playback and lock-screen controls.
class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "together/background"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "moveTaskToBack") {
                    // Sends the app to the background without destroying the
                    // Activity, so the running party (audio + local server)
                    // stays alive instead of being torn down.
                    moveTaskToBack(false)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}