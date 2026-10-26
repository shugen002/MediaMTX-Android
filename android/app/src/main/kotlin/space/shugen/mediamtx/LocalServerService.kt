package space.shugen.mediamtx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class LocalServerService : Service() {
    companion object {
        const val ACTION_START = "space.shugen.mediamtx.START_LOCAL_SERVER"
        const val ACTION_STOP = "space.shugen.mediamtx.STOP_LOCAL_SERVER"
        private const val CHANNEL_ID = "mtx_local_server"
        private const val NOTIFICATION_ID = 4312

        const val EXTRA_EXECUTABLE = "executable"
        const val EXTRA_WORKDIR = "workdir"
        const val EXTRA_CONFIG = "config"
        const val EXTRA_LOG = "log"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var monitor: Thread? = null
    private var notificationManager: NotificationManager? = null
    private var executablePath: String? = null
    private var workDir: String? = null
    private var configPath: String? = null
    private var logPath: String? = null
    @Volatile
    private var userStopped = false

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            userStopped = true
            clearStoredArgs()
            stopServer()
            return START_NOT_STICKY
        }

        val prefs = getSharedPreferences("mtx_local_service", Context.MODE_PRIVATE)
        val executable = intent?.getStringExtra(EXTRA_EXECUTABLE)
            ?: prefs.getString(EXTRA_EXECUTABLE, null)
        val workdir = intent?.getStringExtra(EXTRA_WORKDIR)
            ?: prefs.getString(EXTRA_WORKDIR, null)
        val config = intent?.getStringExtra(EXTRA_CONFIG)
            ?: prefs.getString(EXTRA_CONFIG, null)
        val log = intent?.getStringExtra(EXTRA_LOG)
            ?: prefs.getString(EXTRA_LOG, null)

        if (executable == null || workdir == null || config == null || log == null) {
            updateNotification("启动失败：参数不完整", false)
            stopSelf()
            return START_NOT_STICKY
        }

        prefs.edit()
            .putString(EXTRA_EXECUTABLE, executable)
            .putString(EXTRA_WORKDIR, workdir)
            .putString(EXTRA_CONFIG, config)
            .putString(EXTRA_LOG, log)
            .apply()

        startForeground(NOTIFICATION_ID, buildNotification("MediaMTX 正在启动…", true))
        acquireWakeLock()
        this.executablePath = executable
        this.workDir = workdir
        this.configPath = config
        this.logPath = log
        userStopped = false
        try {
            LocalServerManager.start(
                applicationContext,
                executable,
                workdir,
                config,
                log,
            )
            updateNotification("MediaMTX 正在运行", true)
            watchProcess()
        } catch (error: Exception) {
            updateNotification("启动失败：${error.message}", false)
            stopSelf()
            return START_NOT_STICKY
        }
        // Sticky: if the OS kills the process, restore the saved paths and start again.
        return START_STICKY
    }

    private fun clearStoredArgs() {
        getSharedPreferences("mtx_local_service", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }

    private fun watchProcess() {
        monitor?.interrupt()
        monitor = Thread {
            var restarts = 0
            while (true) {
                while (LocalServerManager.isRunning()) {
                    try {
                        Thread.sleep(1000)
                    } catch (_: InterruptedException) {
                        return@Thread
                    }
                }
                if (userStopped) break
                if (restarts >= 3) {
                    updateNotification("MediaMTX 已退出，请查看日志", false)
                    break
                }
                restarts++
                updateNotification("MediaMTX 意外退出，正在恢复 ($restarts/3)…", true)
                try {
                    Thread.sleep(1500)
                    val exe = executablePath
                    val dir = workDir
                    val config = configPath
                    val log = logPath
                    if (exe != null && dir != null && config != null && log != null) {
                        LocalServerManager.start(applicationContext, exe, dir, config, log)
                        updateNotification("MediaMTX 正在运行", true)
                    } else {
                        break
                    }
                } catch (_: InterruptedException) {
                    return@Thread
                } catch (error: Exception) {
                    updateNotification("恢复失败：${error.message}", false)
                    break
                }
            }
            stopForegroundCompat()
            stopSelf()
        }.apply {
            name = "mtx-service-monitor"
            isDaemon = true
            start()
        }
    }

    override fun onDestroy() {
        monitor?.interrupt()
        monitor = null
        LocalServerManager.stop()
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun stopServer() {
        LocalServerManager.stop()
        stopForegroundCompat()
        stopSelf()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "MTXConsole::LocalServer",
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "本机 MediaMTX 服务",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "保持本机 MediaMTX 服务运行"
            setShowBadge(false)
        }
        notificationManager?.createNotificationChannel(channel)
    }

    private fun buildNotification(text: String, ongoing: Boolean): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPending = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = Intent(this, LocalServerService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MTX 控制台")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_mtx)
            .setContentIntent(openPending)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(0, "停止服务", stopPending)
            .build()
    }

    private fun updateNotification(text: String, ongoing: Boolean) {
        try {
            notificationManager?.notify(NOTIFICATION_ID, buildNotification(text, ongoing))
        } catch (_: Exception) {
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
}
