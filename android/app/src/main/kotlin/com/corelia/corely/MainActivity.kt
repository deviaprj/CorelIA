package com.corelia.corely

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val systemChannel = "com.corelia.corely/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openTtsSettings" -> result.success(openTtsSettings())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Ouvre l'écran « Synthèse vocale » où l'utilisateur peut télécharger les
     * données vocales. L'action est non documentée mais stable ; on essaie
     * plusieurs cibles et on se rabat sur les paramètres d'accessibilité.
     *
     * On ne teste pas resolveActivity : la visibilité des paquets sur
     * Android 11+ la rend peu fiable. On tente l'ouverture et on capte l'échec.
     */
    private fun openTtsSettings(): Boolean {
        val candidates = listOf(
            Intent("com.android.settings.TTS_SETTINGS"),
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )

        for (intent in candidates) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Cible indisponible : on essaie la suivante.
            }
        }
        return false
    }
}
