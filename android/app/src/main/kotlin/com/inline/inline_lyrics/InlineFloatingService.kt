package com.inline.inline_lyrics

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import java.util.Locale

class InlineFloatingService : Service() {
    companion object {
        private const val TAG = "InlineFloatingService"
        private const val CHANNEL_ID = "inline_lyrics_overlay_channel"
        private const val NOTIFICATION_ID = 4040

        var isRunning = false
        var instance: InlineFloatingService? = null
        var currentFontSize = 14.5f
        var currentTransition = "slide"
        var currentChipStyle = "pill"
        var currentAccentColor = "#D4FF70"
        var currentNextLyric = ""
        var currentTrackTitle = ""
        var currentArtistName = ""

        var currentTimingOffsetMs: Int = 0
            set(value) {
                field = value
                instance?.updateOffsetDisplay(value)
            }
        var onOffsetChanged: ((Int) -> Unit)? = null
        var currentOpacity: Float = 1.0f
        var autoHideWhenPaused: Boolean = true

        fun setOpacity(alpha: Float) {
            currentOpacity = alpha
            instance?.applyOpacity(alpha)
        }

        fun updateLyricText(
            text: String,
            isSynced: Boolean,
            isPlaying: Boolean,
            fontSize: Float = currentFontSize,
            transitionStyle: String = currentTransition,
            chipStyle: String = currentChipStyle,
            accentColor: String = currentAccentColor,
            nextLyricText: String = currentNextLyric,
            trackTitle: String = currentTrackTitle,
            artistName: String = currentArtistName
        ) {
            currentFontSize = fontSize
            currentTransition = transitionStyle
            currentChipStyle = chipStyle
            currentAccentColor = accentColor
            currentNextLyric = nextLyricText
            if (trackTitle.isNotBlank()) currentTrackTitle = trackTitle
            if (artistName.isNotBlank()) currentArtistName = artistName
            instance?.updateLyrics(
                text,
                isSynced,
                isPlaying,
                fontSize,
                transitionStyle,
                chipStyle,
                accentColor,
                nextLyricText
            )
        }
    }

    private var windowManager: WindowManager? = null
    private var floatView: LinearLayout? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    // Collapsed Lyric Views
    private var collapsedLayout: LinearLayout? = null
    private var rowActive: LinearLayout? = null
    private var leftAccentBar: View? = null
    private var dotIndicator: View? = null
    private var tvLyric: TextView? = null
    private var rowNext: LinearLayout? = null
    private var tvNextLyric: TextView? = null

    // Expanded Track Info & Controls Views
    private var expandedLayout: LinearLayout? = null
    private var tvExpandedTitle: TextView? = null
    private var tvExpandedArtist: TextView? = null
    private var expandedDot: View? = null
    private var btnPlayPause: ImageView? = null
    private var tvOffsetValue: TextView? = null

    private var isExpanded = false
    private var isPlayingState = true
    private val collapseHandler = Handler(Looper.getMainLooper())
    private val autoCollapseRunnable = Runnable {
        if (isExpanded) {
            toggleExpanded()
        }
    }

    private val pauseHideHandler = Handler(Looper.getMainLooper())
    private val pauseHideRunnable = Runnable {
        if (!isPlayingState && autoHideWhenPaused) {
            fadeOverlay(0.20f)
        }
    }

    private var alphaAnimator: ValueAnimator? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        Log.d(TAG, "InlineFloatingService onCreate")

        startForegroundServiceNotification()
        createFloatingPillView()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "InlineFloatingService onStartCommand")
        if (floatView != null) {
            try {
                windowManager?.removeView(floatView)
            } catch (_: Exception) {}
            floatView = null
        }
        createFloatingPillView()
        return START_STICKY
    }

    private fun startForegroundServiceNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Inline Floating Lyrics",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Displays live synchronized lyrics floating over other apps"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Inline Lyrics Active")
            .setContentText("Displaying live floating lyrics pill")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp, resources.displayMetrics).toInt()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createFloatingPillView() {
        if (floatView != null) return

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val displayMetrics = resources.displayMetrics
        val screenWidth = displayMetrics.widthPixels

        // Outer Container (Pill / Box / Ticker / Neon / Brutalist / Card)
        val pillContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            elevation = dpToPx(14f).toFloat()
        }

        // ==========================================
        // 1. COLLAPSED VIEW (Row 1 Active + Row 2 Upcoming)
        // ==========================================
        collapsedLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        // Row 1: Left Accent Bar + Status Dot + Lyric
        rowActive = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        // Neo-Brutalist vertical accent pillar
        leftAccentBar = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dpToPx(4f), dpToPx(16f)).apply {
                marginEnd = dpToPx(8f)
            }
            visibility = View.GONE
        }
        rowActive?.addView(leftAccentBar)

        // Status Dot Indicator
        dotIndicator = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dpToPx(7f), dpToPx(7f)).apply {
                marginEnd = dpToPx(8f)
            }
        }
        rowActive?.addView(dotIndicator)

        // Active Lyric TextView (Multi-Line support, upright Serif)
        tvLyric = TextView(this).apply {
            text = "Inline Lyrics Ready"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, currentFontSize)
            setTypeface(Typeface.SERIF, Typeface.NORMAL)
            maxLines = 5
            maxWidth = screenWidth - dpToPx(60f)
            setLineSpacing(dpToPx(2f).toFloat(), 1.15f)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        rowActive?.addView(tvLyric)
        collapsedLayout?.addView(rowActive)

        // Row 2: Upcoming Next Lyric (for 2-line squircle and card styles)
        rowNext = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dpToPx(3f)
            }
        }

        tvNextLyric = TextView(this).apply {
            text = ""
            setTextColor(Color.parseColor("#9E9EA4"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            setTypeface(Typeface.SANS_SERIF, Typeface.NORMAL)
            maxLines = 3
            maxWidth = screenWidth - dpToPx(60f)
            setLineSpacing(dpToPx(2f).toFloat(), 1.15f)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                marginStart = dpToPx(15f) // Indent to align cleanly under the primary lyric
            }
        }
        rowNext?.addView(tvNextLyric)
        collapsedLayout?.addView(rowNext)

        pillContainer.addView(collapsedLayout)

        // ==========================================
        // 2. EXPANDED VIEW (Track Details + Media Controls + Timing Offset)
        // ==========================================
        expandedLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            visibility = View.GONE
            setPadding(dpToPx(6f), dpToPx(4f), dpToPx(6f), dpToPx(4f))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        // Title Row: Status Dot + Track Title (Serif Bold)
        val titleRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        expandedDot = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dpToPx(7f), dpToPx(7f)).apply {
                marginEnd = dpToPx(8f)
            }
        }
        titleRow.addView(expandedDot)

        tvExpandedTitle = TextView(this).apply {
            text = if (currentTrackTitle.isNotBlank()) currentTrackTitle else "Inline Lyrics"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16.5f)
            setTypeface(Typeface.SERIF, Typeface.BOLD)
            maxLines = 2
            maxWidth = screenWidth - dpToPx(90f)
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        titleRow.addView(tvExpandedTitle)
        expandedLayout?.addView(titleRow)

        // Artist Row: Artist Name (Sans-Serif, tinted in dynamic Accent)
        tvExpandedArtist = TextView(this).apply {
            text = if (currentArtistName.isNotBlank()) currentArtistName else "Now Playing"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTypeface(Typeface.SANS_SERIF, Typeface.BOLD)
            maxLines = 1
            maxWidth = screenWidth - dpToPx(90f)
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(dpToPx(15f), dpToPx(3f), 0, 0)
        }
        expandedLayout?.addView(tvExpandedArtist)

        // Row 3: Mini Media Controls (Previous, Play/Pause, Next)
        val transportRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dpToPx(10f), 0, dpToPx(4f))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        val createMediaIconBtn = { resId: Int, isPrimary: Boolean ->
            ImageView(this).apply {
                setImageResource(resId)
                scaleType = ImageView.ScaleType.FIT_CENTER
                setColorFilter(Color.WHITE)
                val padH = if (isPrimary) dpToPx(14f) else dpToPx(12f)
                val padV = if (isPrimary) dpToPx(8f) else dpToPx(8f)
                setPadding(padH, padV, padH, padV)
                val btnW = if (isPrimary) dpToPx(52f) else dpToPx(44f)
                val btnH = if (isPrimary) dpToPx(38f) else dpToPx(34f)
                layoutParams = LinearLayout.LayoutParams(btnW, btnH)
                background = GradientDrawable().apply {
                    setColor(if (isPrimary) Color.parseColor("#323238") else Color.parseColor("#222226"))
                    cornerRadius = dpToPx(10f).toFloat()
                    if (isPrimary) {
                        setStroke(dpToPx(1.2f), Color.parseColor(currentAccentColor))
                    }
                }
            }
        }

        val btnPrev = createMediaIconBtn(R.drawable.ic_inline_previous, false).apply {
            setOnClickListener {
                InlineNotificationListener.sendMediaAction("previous")
                resetAutoCollapseTimer()
            }
        }
        transportRow.addView(btnPrev)

        val btnPlayPauseView = createMediaIconBtn(
            if (isPlayingState) R.drawable.ic_inline_pause else R.drawable.ic_inline_play,
            true
        ).apply {
            (layoutParams as? LinearLayout.LayoutParams)?.apply {
                marginStart = dpToPx(10f)
                marginEnd = dpToPx(10f)
            }
            setOnClickListener {
                // Optimistically toggle isPlaying state immediately
                val nextState = !isPlayingState
                updatePlayPauseState(nextState)
                InlineNotificationListener.sendMediaAction("toggle")
                resetAutoCollapseTimer()
            }
        }
        btnPlayPause = btnPlayPauseView
        transportRow.addView(btnPlayPauseView)

        val btnNext = createMediaIconBtn(R.drawable.ic_inline_next, false).apply {
            setOnClickListener {
                InlineNotificationListener.sendMediaAction("next")
                resetAutoCollapseTimer()
            }
        }
        transportRow.addView(btnNext)
        expandedLayout?.addView(transportRow)

        // Row 4: Micro-Timing Offset Controls (-0.5s, ±0.0s, +0.5s, ↺)
        val offsetRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dpToPx(6f), 0, dpToPx(2f))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        val createOffsetBtn = { textStr: String ->
            TextView(this).apply {
                text = textStr
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
                setTextColor(Color.WHITE)
                setTypeface(Typeface.SANS_SERIF, Typeface.BOLD)
                gravity = Gravity.CENTER
                setPadding(dpToPx(8f), dpToPx(4f), dpToPx(8f), dpToPx(4f))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#222226"))
                    cornerRadius = dpToPx(8f).toFloat()
                }
            }
        }

        val btnMinus = createOffsetBtn("-0.5s").apply {
            setOnClickListener {
                currentTimingOffsetMs -= 500
                updateOffsetDisplay(currentTimingOffsetMs)
                onOffsetChanged?.invoke(currentTimingOffsetMs)
                resetAutoCollapseTimer()
            }
        }
        offsetRow.addView(btnMinus)

        tvOffsetValue = TextView(this).apply {
            text = formatOffset(currentTimingOffsetMs)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
            setTypeface(Typeface.SANS_SERIF, Typeface.BOLD)
            setTextColor(Color.parseColor(currentAccentColor))
            setPadding(dpToPx(8f), 0, dpToPx(8f), 0)
        }
        offsetRow.addView(tvOffsetValue)

        val btnPlus = createOffsetBtn("+0.5s").apply {
            setOnClickListener {
                currentTimingOffsetMs += 500
                updateOffsetDisplay(currentTimingOffsetMs)
                onOffsetChanged?.invoke(currentTimingOffsetMs)
                resetAutoCollapseTimer()
            }
        }
        offsetRow.addView(btnPlus)

        val btnReset = createOffsetBtn("↺").apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                marginStart = dpToPx(6f)
            }
            setOnClickListener {
                currentTimingOffsetMs = 0
                updateOffsetDisplay(0)
                onOffsetChanged?.invoke(0)
                resetAutoCollapseTimer()
            }
        }
        offsetRow.addView(btnReset)
        expandedLayout?.addView(offsetRow)

        pillContainer.addView(expandedLayout)
        floatView = pillContainer

        // Initial styling application
        applyStyleAndColors(currentChipStyle, currentAccentColor, isPlaying = true)

        // WindowManager LayoutParams: Perfectly centered
        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            x = 0
            y = dpToPx(68f) // Gracefully centered below the punch-hole camera/status bar
            alpha = currentOpacity
        }

        // Setup touch to move vertically + tap to expand bouncily
        setupTouchAndExpandListener(pillContainer)

        try {
            windowManager?.addView(floatView, layoutParams)
            Log.d(TAG, "Floating view added to WindowManager centered successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add floating view to WindowManager", e)
        }
    }

    private fun formatOffset(offsetMs: Int): String {
        val sec = offsetMs / 1000.0
        val sign = if (sec > 0) "+" else if (sec < 0) "" else "±"
        return "Offset: $sign${String.format(Locale.US, "%.1fs", sec)}"
    }

    private fun updatePlayPauseState(isPlaying: Boolean) {
        isPlayingState = isPlaying
        btnPlayPause?.setImageResource(
            if (isPlaying) R.drawable.ic_inline_pause else R.drawable.ic_inline_play
        )
        val accent = try {
            Color.parseColor(currentAccentColor)
        } catch (_: Exception) {
            Color.parseColor("#D4FF70")
        }
        val dotBg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(if (isPlaying) accent else Color.parseColor("#555555"))
        }
        dotIndicator?.background = dotBg
        expandedDot?.background = dotBg
    }

    fun updateOffsetDisplay(offsetMs: Int) {
        mainHandler.post {
            tvOffsetValue?.text = formatOffset(offsetMs)
        }
    }

    fun applyOpacity(alpha: Float) {
        mainHandler.post {
            val lp = layoutParams ?: return@post
            val v = floatView ?: return@post
            lp.alpha = alpha
            try {
                windowManager?.updateViewLayout(v, lp)
            } catch (_: Exception) {}
        }
    }

    private fun fadeOverlay(targetAlpha: Float) {
        val lp = layoutParams ?: return
        val v = floatView ?: return
        alphaAnimator?.cancel()
        alphaAnimator = ValueAnimator.ofFloat(lp.alpha, targetAlpha).apply {
            duration = 320
            addUpdateListener { anim ->
                lp.alpha = anim.animatedValue as Float
                try {
                    windowManager?.updateViewLayout(v, lp)
                } catch (_: Exception) {}
            }
            start()
        }
    }

    private fun resetAutoCollapseTimer() {
        collapseHandler.removeCallbacks(autoCollapseRunnable)
        collapseHandler.postDelayed(autoCollapseRunnable, 6000)
    }

    private fun applyStyleAndColors(chipStyle: String, accentHex: String, isPlaying: Boolean) {
        val container = floatView ?: return
        val accent = try {
            Color.parseColor(accentHex)
        } catch (_: Exception) {
            Color.parseColor("#D4FF70")
        }

        val r = Color.red(accent)
        val g = Color.green(accent)
        val b = Color.blue(accent)

        val dotColor = if (isPlaying) accent else Color.parseColor("#555555")
        val dotBg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(dotColor)
        }
        dotIndicator?.background = dotBg
        expandedDot?.background = dotBg

        // Expanded Artist text
        tvExpandedArtist?.setTextColor(accent)
        tvOffsetValue?.setTextColor(accent)

        // Highlight play/pause button border with accent
        btnPlayPause?.background = GradientDrawable().apply {
            setColor(Color.parseColor("#323238"))
            cornerRadius = dpToPx(10f).toFloat()
            setStroke(dpToPx(1.2f), accent)
        }

        // Left accent bar for brutalist
        leftAccentBar?.background = GradientDrawable().apply {
            setColor(accent)
            cornerRadius = dpToPx(2f).toFloat()
        }

        // Apply container geometry & decoration based on chipStyle
        when (chipStyle) {
            "squircle" -> {
                // Style 2: Nearly squared-off box with 2 lines of lyrics
                container.setPadding(dpToPx(16f), dpToPx(10f), dpToPx(16f), dpToPx(10f))
                container.background = GradientDrawable().apply {
                    setColor(Color.parseColor("#18181B"))
                    cornerRadius = dpToPx(14f).toFloat()
                    setStroke(dpToPx(1.2f), Color.argb(90, r, g, b))
                }
                leftAccentBar?.visibility = View.GONE
                dotIndicator?.visibility = View.VISIBLE
                if (currentNextLyric.isNotBlank()) {
                    rowNext?.visibility = View.VISIBLE
                    tvNextLyric?.text = currentNextLyric
                } else {
                    rowNext?.visibility = View.GONE
                }
            }
            "ticker" -> {
                // Style 3: Ultra-slim minimalist ticker bar
                container.setPadding(dpToPx(10f), dpToPx(5f), dpToPx(10f), dpToPx(5f))
                container.background = GradientDrawable().apply {
                    setColor(Color.parseColor("#141416"))
                    cornerRadius = dpToPx(8f).toFloat()
                    setStroke(dpToPx(1f), Color.parseColor("#26262B"))
                }
                leftAccentBar?.visibility = View.GONE
                dotIndicator?.visibility = View.VISIBLE
                rowNext?.visibility = View.GONE
            }
            "neon" -> {
                // Style 4: Cyberpunk glowing neon border
                container.setPadding(dpToPx(14f), dpToPx(8f), dpToPx(14f), dpToPx(8f))
                container.background = GradientDrawable().apply {
                    setColor(Color.parseColor("#121216"))
                    cornerRadius = dpToPx(22f).toFloat()
                    setStroke(dpToPx(2f), accent)
                }
                leftAccentBar?.visibility = View.GONE
                dotIndicator?.visibility = View.VISIBLE
                rowNext?.visibility = View.GONE
            }
            "brutalist" -> {
                // Style 5: Neo-Brutalist sharp monolith with vertical accent strip
                container.setPadding(dpToPx(12f), dpToPx(8f), dpToPx(14f), dpToPx(8f))
                container.background = GradientDrawable().apply {
                    setColor(Color.parseColor("#161619"))
                    cornerRadius = dpToPx(4f).toFloat()
                    setStroke(dpToPx(1.5f), Color.parseColor("#2E2E34"))
                }
                leftAccentBar?.visibility = View.VISIBLE
                dotIndicator?.visibility = View.GONE
                rowNext?.visibility = View.GONE
            }
            "card" -> {
                // Style 6: Notch docked card with rounded bottom corners & 2 lines
                container.setPadding(dpToPx(16f), dpToPx(10f), dpToPx(16f), dpToPx(10f))
                container.background = GradientDrawable().apply {
                    setColor(Color.parseColor("#19191E"))
                    cornerRadii = floatArrayOf(
                        dpToPx(4f).toFloat(), dpToPx(4f).toFloat(),
                        dpToPx(4f).toFloat(), dpToPx(4f).toFloat(),
                        dpToPx(18f).toFloat(), dpToPx(18f).toFloat(),
                        dpToPx(18f).toFloat(), dpToPx(18f).toFloat()
                    )
                    setStroke(dpToPx(1.2f), Color.argb(80, r, g, b))
                }
                leftAccentBar?.visibility = View.GONE
                dotIndicator?.visibility = View.VISIBLE
                if (currentNextLyric.isNotBlank()) {
                    rowNext?.visibility = View.VISIBLE
                    tvNextLyric?.text = currentNextLyric
                } else {
                    rowNext?.visibility = View.GONE
                }
            }
            else -> { // "pill"
                // Style 1: Dynamic Pill capsule (Default)
                container.setPadding(dpToPx(14f), dpToPx(8f), dpToPx(14f), dpToPx(8f))
                container.background = GradientDrawable().apply {
                    setColor(Color.parseColor("#1C1C1E"))
                    cornerRadius = dpToPx(24f).toFloat()
                    setStroke(dpToPx(1f), Color.parseColor("#2E2E32"))
                }
                leftAccentBar?.visibility = View.GONE
                dotIndicator?.visibility = View.VISIBLE
                rowNext?.visibility = View.GONE
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupTouchAndExpandListener(view: View) {
        var initialY = 0
        var initialTouchY = 0f
        var isDragging = false

        view.setOnTouchListener { v, event ->
            val lp = layoutParams ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialY = lp.y
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = (event.rawY - initialTouchY).toInt()
                    if (Math.abs(dy) > 10) {
                        isDragging = true
                    }
                    lp.x = 0 // Always maintain center alignment
                    lp.y = (initialY + dy).coerceAtLeast(0)
                    try {
                        windowManager?.updateViewLayout(floatView, lp)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error updating overlay layout", e)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging) {
                        v.performClick()
                    }
                    true
                }
                else -> false
            }
        }

        view.setOnClickListener {
            toggleExpanded()
        }

        view.setOnLongClickListener {
            try {
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                if (launchIntent != null) {
                    startActivity(launchIntent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error bringing app to front", e)
            }
            true
        }
    }

    private fun toggleExpanded() {
        val container = floatView ?: return
        isExpanded = !isExpanded
        collapseHandler.removeCallbacks(autoCollapseRunnable)

        if (isExpanded) {
            tvExpandedTitle?.text = if (currentTrackTitle.isNotBlank()) currentTrackTitle else "Inline Lyrics"
            tvExpandedArtist?.text = if (currentArtistName.isNotBlank()) currentArtistName else "Now Playing"
            tvOffsetValue?.text = formatOffset(currentTimingOffsetMs)

            collapsedLayout?.visibility = View.GONE
            expandedLayout?.visibility = View.VISIBLE
            container.setPadding(dpToPx(18f), dpToPx(12f), dpToPx(18f), dpToPx(12f))

            // Bouncy Spring overshoot animation
            container.scaleX = 0.82f
            container.scaleY = 0.82f
            container.animate()
                .scaleX(1.0f)
                .scaleY(1.0f)
                .setDuration(340)
                .setInterpolator(OvershootInterpolator(1.8f))
                .start()

            reCenterOverlay()
            resetAutoCollapseTimer()
        } else {
            expandedLayout?.visibility = View.GONE
            collapsedLayout?.visibility = View.VISIBLE
            applyStyleAndColors(currentChipStyle, currentAccentColor, isPlaying = isPlayingState)

            // Spring back to compact pill
            container.scaleX = 1.08f
            container.scaleY = 1.08f
            container.animate()
                .scaleX(1.0f)
                .scaleY(1.0f)
                .setDuration(220)
                .setInterpolator(DecelerateInterpolator())
                .start()

            reCenterOverlay()
        }
    }

    private var widthAnimator: ValueAnimator? = null

    private fun animateWidthChange(startWidth: Int, targetWidth: Int) {
        if (startWidth <= 0 || targetWidth <= 0 || Math.abs(startWidth - targetWidth) < 4) {
            val lp = layoutParams ?: return
            lp.width = WindowManager.LayoutParams.WRAP_CONTENT
            reCenterOverlay()
            return
        }

        widthAnimator?.cancel()
        widthAnimator = ValueAnimator.ofInt(startWidth, targetWidth).apply {
            duration = 260
            interpolator = DecelerateInterpolator(1.4f)
            addUpdateListener { animator ->
                val w = animator.animatedValue as Int
                val lp = layoutParams ?: return@addUpdateListener
                val v = floatView ?: return@addUpdateListener
                lp.width = w
                lp.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                lp.x = 0
                try {
                    windowManager?.updateViewLayout(v, lp)
                } catch (_: Exception) {}
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    val lp = layoutParams ?: return
                    lp.width = WindowManager.LayoutParams.WRAP_CONTENT
                    reCenterOverlay()
                }
            })
            start()
        }
    }

    fun updateLyrics(
        text: String,
        isSynced: Boolean,
        isPlaying: Boolean,
        fontSize: Float = currentFontSize,
        transitionStyle: String = currentTransition,
        chipStyle: String = currentChipStyle,
        accentColor: String = currentAccentColor,
        nextLyricText: String = currentNextLyric
    ) {
        mainHandler.post {
            tvLyric?.setTextSize(TypedValue.COMPLEX_UNIT_SP, fontSize)
            val newText = if (text.isBlank()) "♪ ♪ ♪" else text
            val textChanged = (tvLyric != null && tvLyric?.text.toString() != newText)
            val transitionChanged = (transitionStyle != currentTransition)
            val styleChanged = (chipStyle != currentChipStyle)
            val colorChanged = (accentColor != currentAccentColor)

            currentFontSize = fontSize
            currentTransition = transitionStyle
            currentChipStyle = chipStyle
            currentAccentColor = accentColor
            currentNextLyric = nextLyricText
            updatePlayPauseState(isPlaying)

            // Smart Hide when paused
            if (isPlaying) {
                pauseHideHandler.removeCallbacks(pauseHideRunnable)
                if (layoutParams != null && layoutParams!!.alpha < currentOpacity) {
                    fadeOverlay(currentOpacity)
                }
            } else {
                pauseHideHandler.removeCallbacks(pauseHideRunnable)
                if (autoHideWhenPaused) {
                    pauseHideHandler.postDelayed(pauseHideRunnable, 15000)
                }
            }

            if (!isExpanded) {
                applyStyleAndColors(chipStyle, accentColor, isPlaying)
            }

            if (tvLyric != null && (textChanged || transitionChanged || styleChanged)) {
                val startWidth = floatView?.width ?: 0

                // Smoothly animate width expansion/contraction
                if (!isExpanded && startWidth > 0) {
                    val maxWidth = resources.displayMetrics.widthPixels - dpToPx(32f)
                    tvLyric?.text = newText
                    if (chipStyle == "squircle" || chipStyle == "card") {
                        tvNextLyric?.text = nextLyricText
                    }
                    floatView?.measure(
                        View.MeasureSpec.makeMeasureSpec(maxWidth, View.MeasureSpec.AT_MOST),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
                    )
                    val targetWidth = floatView?.measuredWidth ?: startWidth
                    animateWidthChange(startWidth, targetWidth)
                }

                when (transitionStyle) {
                    "scale" -> {
                        tvLyric?.animate()
                            ?.alpha(0f)
                            ?.scaleX(0.85f)
                            ?.scaleY(0.85f)
                            ?.setDuration(120)
                            ?.withEndAction {
                                tvLyric?.text = newText
                                if (chipStyle == "squircle" || chipStyle == "card") {
                                    tvNextLyric?.text = nextLyricText
                                }
                                reCenterOverlay()
                                tvLyric?.animate()
                                    ?.alpha(1f)
                                    ?.scaleX(1f)
                                    ?.scaleY(1f)
                                    ?.setDuration(180)
                                    ?.start()
                            }
                            ?.start()
                    }
                    "fade" -> {
                        tvLyric?.animate()
                            ?.alpha(0f)
                            ?.setDuration(120)
                            ?.withEndAction {
                                tvLyric?.text = newText
                                if (chipStyle == "squircle" || chipStyle == "card") {
                                    tvNextLyric?.text = nextLyricText
                                }
                                reCenterOverlay()
                                tvLyric?.animate()
                                    ?.alpha(1f)
                                    ?.setDuration(180)
                                    ?.start()
                            }
                            ?.start()
                    }
                    "pop" -> {
                        tvLyric?.animate()
                            ?.alpha(0f)
                            ?.scaleX(0.7f)
                            ?.scaleY(0.7f)
                            ?.setDuration(100)
                            ?.withEndAction {
                                tvLyric?.text = newText
                                if (chipStyle == "squircle" || chipStyle == "card") {
                                    tvNextLyric?.text = nextLyricText
                                }
                                reCenterOverlay()
                                tvLyric?.animate()
                                    ?.alpha(1f)
                                    ?.scaleX(1.08f)
                                    ?.scaleY(1.08f)
                                    ?.setDuration(140)
                                    ?.withEndAction {
                                        tvLyric?.animate()
                                            ?.scaleX(1f)
                                            ?.scaleY(1f)
                                            ?.setDuration(80)
                                            ?.start()
                                    }
                                    ?.start()
                            }
                            ?.start()
                    }
                    else -> { // "slide"
                        tvLyric?.animate()
                            ?.alpha(0f)
                            ?.translationY(-10f)
                            ?.setDuration(120)
                            ?.withEndAction {
                                tvLyric?.text = newText
                                if (chipStyle == "squircle" || chipStyle == "card") {
                                    tvNextLyric?.text = nextLyricText
                                }
                                reCenterOverlay()
                                tvLyric?.translationY = 10f
                                tvLyric?.animate()
                                    ?.alpha(1f)
                                    ?.translationY(0f)
                                    ?.setDuration(180)
                                    ?.start()
                            }
                            ?.start()
                    }
                }
            } else {
                tvLyric?.text = newText
                if (chipStyle == "squircle" || chipStyle == "card") {
                    tvNextLyric?.text = nextLyricText
                }
                reCenterOverlay()
            }
        }
    }

    private fun reCenterOverlay() {
        val lp = layoutParams ?: return
        val v = floatView ?: return
        lp.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        lp.x = 0
        try {
            v.requestLayout()
            windowManager?.updateViewLayout(v, lp)
        } catch (e: Exception) {
            Log.e(TAG, "Error centering overlay layout", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        instance = null
        widthAnimator?.cancel()
        alphaAnimator?.cancel()
        collapseHandler.removeCallbacks(autoCollapseRunnable)
        pauseHideHandler.removeCallbacks(pauseHideRunnable)
        if (floatView != null) {
            try {
                windowManager?.removeView(floatView)
            } catch (e: Exception) {
                Log.e(TAG, "Error removing floatView", e)
            }
            floatView = null
        }
        Log.d(TAG, "InlineFloatingService destroyed")
    }
}
