package com.bps.ulos

import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.bps.ulos/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "performSecurityChecks") {
                val checks = mapOf(
                    "isRooted" to isDeviceRooted(),
                    "isDeveloperMode" to isDeveloperModeEnabled(),
                    "isAutoTime" to isAutoTimeEnabled()
                )
                result.success(checks)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun isDeviceRooted(): Boolean {
        val paths = arrayOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su"
        )
        for (path in paths) {
            if (File(path).exists()) return true
        }
        return false
    }

    private fun isDeveloperModeEnabled(): Boolean {
        return try {
            Settings.Global.getInt(contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1
        } catch (e: Exception) {
            false
        }
    }

    private fun isAutoTimeEnabled(): Boolean {
        return try {
            Settings.Global.getInt(contentResolver, Settings.Global.AUTO_TIME, 0) == 1
        } catch (e: Exception) {
            false
        }
    }
}
