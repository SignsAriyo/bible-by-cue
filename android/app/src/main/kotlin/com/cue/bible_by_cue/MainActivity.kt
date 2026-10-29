package com.cue.bible_by_cue

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts the Flutter UI and provides the few native services the app needs:
 * the system share sheet, the system document picker for backups and exports,
 * and the daily reading reminder. No network access is used or requested.
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private var pendingReminder: Triple<Boolean, Int, Int>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cue/platform").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "shareText" -> {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                            call.argument<String>("subject")?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                        }
                        startActivity(Intent.createChooser(send, null))
                        result.success(true)
                    }
                    "shareImage" -> {
                        val dir = File(cacheDir, "shared").apply { mkdirs() }
                        dir.listFiles()?.forEach { it.delete() }
                        val file = File(dir, call.argument<String>("name") ?: "verse.png")
                        file.writeBytes(call.argument<ByteArray>("bytes")!!)
                        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "image/png"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            call.argument<String>("text")?.let { putExtra(Intent.EXTRA_TEXT, it) }
                            clipData = ClipData.newRawUri(null, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(send, null))
                        result.success(true)
                    }
                    "saveDocument" -> {
                        if (pending != null) return@setMethodCallHandler result.error("busy", "Another file dialog is open", null)
                        pending = result
                        pendingBytes = call.argument<ByteArray>("bytes")
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = call.argument<String>("mime") ?: "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                        }
                        startActivityForResult(intent, REQ_SAVE)
                    }
                    "openDocument" -> {
                        if (pending != null) return@setMethodCallHandler result.error("busy", "Another file dialog is open", null)
                        pending = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            call.argument<List<String>>("mimes")?.let { putExtra(Intent.EXTRA_MIME_TYPES, it.toTypedArray()) }
                        }
                        startActivityForResult(intent, REQ_OPEN)
                    }
                    "setReminder" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val hour = call.argument<Int>("hour") ?: 7
                        val minute = call.argument<Int>("minute") ?: 0
                        if (enabled && Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                        ) {
                            if (pending != null) return@setMethodCallHandler result.error("busy", "Busy", null)
                            pending = result
                            pendingReminder = Triple(enabled, hour, minute)
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFY)
                        } else {
                            Reminder.configure(this, enabled, hour, minute)
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                pending = null
                result.error("failed", e.message, null)
            }
        }
    }

    private fun displayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0)
        }
        return uri.lastPathSegment ?: "file"
    }

    @Deprecated("Uses the platform activity result API to avoid extra dependencies")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_SAVE && requestCode != REQ_OPEN) return
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingBytes = null
            return result.success(null)
        }
        try {
            if (requestCode == REQ_SAVE) {
                contentResolver.openOutputStream(uri, "wt")!!.use { it.write(pendingBytes!!); it.flush() }
                pendingBytes = null
                result.success(displayName(uri))
            } else {
                val bytes = contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                result.success(mapOf("name" to displayName(uri), "bytes" to bytes))
            }
        } catch (e: Exception) {
            pendingBytes = null
            result.error("io", e.message, null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_NOTIFY) return
        val result = pending ?: return
        val r = pendingReminder ?: return
        pending = null
        pendingReminder = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        Reminder.configure(this, granted && r.first, r.second, r.third)
        result.success(granted)
    }

    companion object {
        const val REQ_SAVE = 4101
        const val REQ_OPEN = 4102
        const val REQ_NOTIFY = 4103
    }
}
