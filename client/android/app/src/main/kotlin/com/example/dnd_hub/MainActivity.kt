package com.example.dnd_hub

import android.app.backup.BackupManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "dnd_hub/android_backup"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dataChanged" -> {
                        try {
                            BackupManager(this).dataChanged()
                            result.success(true)
                        } catch (error: Throwable) {
                            result.error(
                                "BACKUP_MANAGER_ERROR",
                                error.message ?: "Не удалось уведомить Android Backup Manager",
                                null
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
