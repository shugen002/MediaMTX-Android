package io.mediamtx.mediamtx_manager

import android.Manifest
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.os.PowerManager
import android.provider.Settings
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.io.File
import java.net.NetworkInterface
import java.util.Collections

class MainActivity : FlutterActivity() {
    private val channelName = "io.mediamtx.console/local_server"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                4201,
            )
        }
    }

    override fun onResume() {
        super.onResume()
        LocalServerManager.appForeground = true
    }

    override fun onPause() {
        LocalServerManager.appForeground = false
        super.onPause()
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val power = getSystemService(POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    private fun shareLatestLog() {
        val versions = File(filesDir, "mediamtx/versions")
        val log = versions.listFiles()
            ?.sortedByDescending { it.lastModified() }
            ?.asSequence()
            ?.mapNotNull { File(it, "server.log").takeIf(File::isFile) }
            ?.firstOrNull()
            ?: throw IllegalStateException("暂无服务日志")
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            log,
        )
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "MediaMTX 服务日志")
            clipData = ClipData.newRawUri("MediaMTX 服务日志", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(send, "导出服务日志").apply {
            clipData = send.clipData
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(chooser)
    }

    private fun openDocumentTree() {
        val authority = "$packageName.documents"
        val initial = DocumentsContract.buildRootUri(authority, "root")
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            putExtra(DocumentsContract.EXTRA_INITIAL_URI, initial)
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
            val fallback = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                type = "*/*"
                addCategory(Intent.CATEGORY_OPENABLE)
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, initial)
            }
            startActivity(fallback)
        }
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    private fun findLanIp(): String? {
        return try {
            Collections.list(NetworkInterface.getNetworkInterfaces())
                .filter { it.isUp && !it.isLoopback }
                .flatMap { Collections.list(it.inetAddresses) }
                .filterIsInstance<Inet4Address>()
                .firstOrNull { !it.isLoopbackAddress && it.isSiteLocalAddress }
                ?.hostAddress
        } catch (_: Exception) {
            null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "abi" -> {
                        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: Build.CPU_ABI
                        result.success(abi)
                    }

                    "start" -> {
                        val executable = call.argument<String>("executable")
                        val workdir = call.argument<String>("workdir")
                        val config = call.argument<String>("config")
                        val log = call.argument<String>("log")
                        if (executable == null || workdir == null || config == null || log == null) {
                            result.error("bad_args", "缺少启动参数", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(this, LocalServerService::class.java).apply {
                            action = LocalServerService.ACTION_START
                            putExtra(LocalServerService.EXTRA_EXECUTABLE, executable)
                            putExtra(LocalServerService.EXTRA_WORKDIR, workdir)
                            putExtra(LocalServerService.EXTRA_CONFIG, config)
                            putExtra(LocalServerService.EXTRA_LOG, log)
                        }
                        LocalServerManager.updateLogPath(log)
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("start_failed", error.message, null)
                        }
                    }

                    "stop" -> {
                        val intent = Intent(this, LocalServerService::class.java).apply {
                            action = LocalServerService.ACTION_STOP
                        }
                        try {
                            startService(intent)
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }

                    "status" -> {
                        result.success(LocalServerManager.status())
                    }

                    "readLog" -> {
                        val maxBytes = call.argument<Int>("maxBytes") ?: 200_000
                        result.success(LocalServerManager.readLog(maxBytes))
                    }

                    "lanIp" -> {
                        result.success(findLanIp())
                    }

                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }

                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            requestIgnoreBatteryOptimizations()
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("settings_failed", error.message, null)
                        }
                    }

                    "openAppSettings" -> {
                        try {
                            openAppSettings()
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("settings_failed", error.message, null)
                        }
                    }

                    "shareLog" -> {
                        try {
                            shareLatestLog()
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("share_failed", error.message, null)
                        }
                    }

                    "openDocuments" -> {
                        try {
                            openDocumentTree()
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("documents_failed", error.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
