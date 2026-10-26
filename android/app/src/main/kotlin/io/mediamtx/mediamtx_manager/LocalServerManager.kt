package io.mediamtx.mediamtx_manager

import android.content.Context
import android.util.Log
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.io.RandomAccessFile
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Owns the MediaMTX child process and its log file. The process is started by
 * [LocalServerService] so it can outlive the Flutter UI.
 */
object LocalServerManager {
    private const val TAG = "MtxLocalServer"
    private const val MAX_LOG_BYTES = 4L * 1024 * 1024

    private var process: Process? = null
    private var logWriter: BufferedWriter? = null
    private var logReaderThread: Thread? = null
    private var monitorThread: Thread? = null
    private var startedAt: Long = 0L
    private var logPath: String? = null
    private var appContext: Context? = null
    private val sessionPaths = mutableMapOf<String, String>()

    /** Updated by MainActivity; foreground events are shown inside the app instead. */
    @Volatile
    var appForeground: Boolean = false

    @Synchronized
    fun start(
        context: Context,
        executablePath: String,
        workDir: String,
        configPath: String,
        logPath: String,
    ): Boolean {
        stopInternal()
        appContext = context.applicationContext
        sessionPaths.clear()
        LocalEventNotifications.ensureChannel(context)
        val executable = File(executablePath)
        if (!executable.isFile) {
            throw IllegalStateException("找不到 MediaMTX 可执行文件")
        }
        if (!executable.setExecutable(true, false) && !executable.canExecute()) {
            throw IllegalStateException("无法赋予可执行权限")
        }
        val directory = File(workDir)
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("无法创建服务目录")
        }
        val logFile = File(logPath)
        logFile.parentFile?.mkdirs()
        rotateLogIfNeeded(logFile)

        val builder = ProcessBuilder(executable.absolutePath, configPath)
            .directory(directory)
            .redirectErrorStream(true)
        builder.environment()["MTX_CONSOLE"] = "1"
        val child = builder.start()
        process = child
        startedAt = System.currentTimeMillis()
        this.logPath = logFile.absolutePath

        val writer = BufferedWriter(FileWriter(logFile, true))
        logWriter = writer
        writer.write(
            "\n===== ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())} " +
                "start ${executable.absolutePath} =====\n",
        )
        writer.flush()

        logReaderThread = Thread {
            try {
                child.inputStream.bufferedReader().use { reader: BufferedReader ->
                    var line = reader.readLine()
                    while (line != null) {
                        synchronized(this) {
                            try {
                                logWriter?.write(line)
                                logWriter?.write("\n")
                                logWriter?.flush()
                            } catch (error: Exception) {
                                Log.w(TAG, "write log failed", error)
                            }
                        }
                        handleSessionEvent(line)
                        line = reader.readLine()
                    }
                }
            } catch (error: Exception) {
                Log.w(TAG, "read process output failed", error)
            }
        }.apply {
            name = "mtx-log-reader"
            isDaemon = true
            start()
        }

        monitorThread = Thread {
            try {
                val exit = child.waitFor()
                synchronized(this) {
                    if (process === child) {
                        process = null
                        try {
                            logWriter?.write("\n===== exited with code $exit =====\n")
                            logWriter?.flush()
                            logWriter?.close()
                        } catch (_: Exception) {
                        }
                        logWriter = null
                    }
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }.apply {
            name = "mtx-process-monitor"
            isDaemon = true
            start()
        }
        return true
    }

    @Synchronized
    fun stop() {
        stopInternal()
    }

    private fun stopInternal() {
        monitorThread?.interrupt()
        monitorThread = null
        logReaderThread?.interrupt()
        logReaderThread = null
        val child = process
        process = null
        if (child != null) {
            try {
                child.destroy()
                if (!child.waitFor(3, java.util.concurrent.TimeUnit.SECONDS)) {
                    child.destroyForcibly()
                }
            } catch (_: Exception) {
            }
        }
        try {
            logWriter?.flush()
            logWriter?.close()
        } catch (_: Exception) {
        }
        logWriter = null
        startedAt = 0L
    }

    @Synchronized
    fun status(): Map<String, Any?> {
        val child = process
        val running = child != null && child.isAlive
        return mapOf(
            "running" to running,
            "pid" to null,
            "startedAt" to if (running) startedAt else null,
        )
    }

    @Synchronized
    fun isRunning(): Boolean = process?.isAlive == true

    @Synchronized
    fun readLog(maxBytes: Int = 200_000): String {
        val file = logPath?.let { File(it) } ?: return ""
        if (!file.isFile) return ""
        return try {
            RandomAccessFile(file, "r").use { access ->
                val length = access.length()
                val start = maxOf(0L, length - maxBytes)
                access.seek(start)
                val bytes = ByteArray((length - start).toInt())
                access.readFully(bytes)
                String(bytes, Charsets.UTF_8)
            }
        } catch (error: Exception) {
            "读取日志失败：${error.message}"
        }
    }

    fun updateLogPath(path: String) {
        logPath = path
    }

    private fun handleSessionEvent(line: String) {
        if (appForeground) return
        val context = appContext ?: return
        val idMatch = Regex("""\[(?:session|conn) ([^\]]+)\]""").find(line)
        val pathMatch = Regex("""(?:publishing to|reading from) path '([^']+)'""").find(line)
        val path = pathMatch?.groupValues?.getOrNull(1)
        val id = idMatch?.groupValues?.getOrNull(1)
        if (id != null && path != null) {
            sessionPaths[id] = path
        }

        when {
            line.contains("is publishing to path") && path != null -> {
                LocalEventNotifications.post(context, "开始推流 · $path", "路径 $path 已收到新的推流")
            }

            line.contains("is reading from path") &&
                path != null &&
                !line.contains("[HLS]") -> {
                LocalEventNotifications.post(context, "新增观看 · $path", "有客户端开始观看路径 $path")
            }

            line.contains("stream is offline") -> {
                val offlinePath =
                    Regex("""\[path ([^\]]+)\]""").find(line)?.groupValues?.getOrNull(1)
                if (offlinePath != null) {
                    sessionPaths.values.removeAll { it == offlinePath }
                    LocalEventNotifications.post(
                        context,
                        "流已离线 · $offlinePath",
                        "路径 $offlinePath 的推流已结束",
                    )
                }
            }

            line.contains("] closed") && !line.contains("[HLS]") -> {
                val knownPath = id?.let { sessionPaths.remove(it) }
                val text = if (knownPath != null) {
                    "路径 $knownPath 的一个会话已断开"
                } else {
                    "一个媒体会话已断开"
                }
                LocalEventNotifications.post(context, "会话已断开", text)
            }
        }
    }

    private fun rotateLogIfNeeded(file: File) {
        if (file.isFile && file.length() > MAX_LOG_BYTES) {
            val previous = File(file.parentFile, "${file.name}.1")
            if (previous.exists()) previous.delete()
            file.renameTo(previous)
        }
    }
}
