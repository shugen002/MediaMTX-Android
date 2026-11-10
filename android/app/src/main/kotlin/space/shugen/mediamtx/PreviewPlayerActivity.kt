package space.shugen.mediamtx

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView

/**
 * 路径直播预览（原生全屏播放器）。
 *
 * 为什么不用 Flutter 纹理播放器：这台华为设备（KirinT92 / Android 12）上，
 * 把 MediaCodec 的输出接到 Flutter 的纹理 Surface 时 OMX 解码器起不来
 * （MediaCodec 停在 STARTING 后回滚，ExoPlayer 报 Decoder init failed），
 * 换成 SurfaceTexture 的第三方内核在 Impeller 下又只有黑屏。
 * 这里用 SurfaceView + ExoPlayer：和系统播放器、VLC 走的是同一条原生渲染路径，
 * 硬件解码正常；同时开启 decoder fallback，硬件失败会自动退到软件解码。
 */
@UnstableApi
class PreviewPlayerActivity : Activity() {

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_SUBTITLE = "subtitle"
        const val EXTRA_HLS_URL = "hlsUrl"
        const val EXTRA_RTSP_URL = "rtspUrl"
    }

    private data class Candidate(val label: String, val url: String)

    private var player: ExoPlayer? = null
    private lateinit var playerView: PlayerView
    private lateinit var errorPanel: LinearLayout
    private lateinit var errorText: TextView
    private lateinit var subtitleView: TextView
    private val candidates = mutableListOf<Candidate>()
    private var index = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val hls = intent.getStringExtra(EXTRA_HLS_URL)
        val rtsp = intent.getStringExtra(EXTRA_RTSP_URL)
        if (!hls.isNullOrBlank()) candidates.add(Candidate("HLS", hls))
        if (!rtsp.isNullOrBlank()) candidates.add(Candidate("RTSP", rtsp))
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        buildUi()
        if (candidates.isEmpty()) {
            showError("没有可用的播放地址")
        } else {
            play(0)
        }
    }

    override fun onStart() {
        super.onStart()
        player?.playWhenReady = true
    }

    override fun onStop() {
        player?.playWhenReady = false
        super.onStop()
    }

    override fun onDestroy() {
        releasePlayer()
        super.onDestroy()
    }

    private fun dp(value: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics).toInt()

    private fun buildUi() {
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }

        playerView = PlayerView(this).apply {
            setBackgroundColor(Color.BLACK)
            useController = true
            controllerShowTimeoutMs = 3500
            setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        }
        root.addView(playerView)

        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8f), dp(8f), dp(16f), dp(8f))
            setBackgroundColor(0x99000000.toInt())
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP,
            )
        }
        val close = TextView(this).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setPadding(dp(12f), dp(8f), dp(12f), dp(8f))
            setOnClickListener { finish() }
        }
        val titles = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(4f), 0, 0, 0)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        titles.addView(
            TextView(this).apply {
                text = intent.getStringExtra(EXTRA_TITLE).orEmpty()
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setTypeface(typeface, Typeface.BOLD)
                maxLines = 1
            },
        )
        subtitleView = TextView(this).apply {
            text = intent.getStringExtra(EXTRA_SUBTITLE).orEmpty()
            setTextColor(0x99FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            maxLines = 1
        }
        titles.addView(subtitleView)
        bar.addView(close)
        bar.addView(titles)
        root.addView(bar)

        errorPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28f), dp(28f), dp(28f), dp(28f))
            setBackgroundColor(Color.BLACK)
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        }
        errorText = TextView(this).apply {
            setTextColor(0xFFB0BEC5.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
        }
        errorPanel.addView(errorText)
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(18f), 0, 0)
        }
        actions.addView(
            actionButton("重试") { if (candidates.isNotEmpty()) play(0) },
        )
        actions.addView(
            actionButton("关闭") { finish() },
        )
        errorPanel.addView(actions)
        root.addView(errorPanel)

        setContentView(root)
    }

    private fun actionButton(label: String, action: () -> Unit): TextView =
        TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setPadding(dp(22f), dp(10f), dp(22f), dp(10f))
            setOnClickListener { action() }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginEnd = dp(10f) }
        }

    private fun play(at: Int) {
        index = at
        releasePlayer()
        hideError()
        val candidate = candidates[at]
        subtitleView.text = listOfNotNull(
            intent.getStringExtra(EXTRA_SUBTITLE)?.takeIf { it.isNotBlank() },
            candidate.label,
        ).joinToString(" · ")

        val renderers = DefaultRenderersFactory(this)
            .setEnableDecoderFallback(true)
        val httpFactory = DefaultHttpDataSource.Factory()
            .setConnectTimeoutMs(8_000)
            .setReadTimeoutMs(8_000)
            .setAllowCrossProtocolRedirects(true)
        val exo = ExoPlayer.Builder(this, renderers)
            .setMediaSourceFactory(DefaultMediaSourceFactory(httpFactory))
            .build()
        exo.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            true,
        )
        exo.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                if (at + 1 < candidates.size) {
                    play(at + 1)
                } else {
                    showError("${candidate.label}：${error.errorCodeName}\n${error.message.orEmpty()}")
                }
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) hideError()
            }
        })
        playerView.player = exo
        exo.setMediaItem(MediaItem.fromUri(candidate.url))
        exo.prepare()
        exo.playWhenReady = true
        player = exo
    }

    private fun showError(message: String) {
        errorText.text = message
        errorPanel.visibility = View.VISIBLE
    }

    private fun hideError() {
        errorPanel.visibility = View.GONE
    }

    private fun releasePlayer() {
        playerView.player = null
        player?.release()
        player = null
    }
}
