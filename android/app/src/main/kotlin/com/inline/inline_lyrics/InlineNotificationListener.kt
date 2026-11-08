package com.inline.inline_lyrics

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class InlineNotificationListener : NotificationListenerService() {
    companion object {
        private const val TAG = "InlineListener"
        var instance: InlineNotificationListener? = null
        var onTrackChanged: ((Map<String, Any>) -> Unit)? = null

        fun sendMediaAction(action: String) {
            val controller = instance?.activeController ?: return
            try {
                when (action.lowercase()) {
                    "play" -> controller.transportControls.play()
                    "pause" -> controller.transportControls.pause()
                    "toggle" -> {
                        val state = controller.playbackState?.state
                        if (state == PlaybackState.STATE_PLAYING) {
                            controller.transportControls.pause()
                        } else {
                            controller.transportControls.play()
                        }
                    }
                    "next" -> controller.transportControls.skipToNext()
                    "previous" -> controller.transportControls.skipToPrevious()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error executing media action $action", e)
            }
        }

        fun requestRefresh(context: Context? = null) {
            if (instance != null) {
                instance?.queryActiveSessions()
            } else if (context != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    requestRebind(ComponentName(context, InlineNotificationListener::class.java))
                } catch (e: Exception) {
                    Log.e(TAG, "Failed requestRebind", e)
                }
            }
        }
    }

    private var mediaSessionManager: MediaSessionManager? = null
    private var activeController: MediaController? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val mediaCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) {
            super.onMetadataChanged(metadata)
            Log.d(TAG, "onMetadataChanged fired")
            dispatchCurrentTrack()
        }

        override fun onPlaybackStateChanged(state: PlaybackState?) {
            super.onPlaybackStateChanged(state)
            Log.d(TAG, "onPlaybackStateChanged fired: ${state?.state}")
            dispatchCurrentTrack()
        }
    }

    private val sessionChangedListener = MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
        Log.d(TAG, "OnActiveSessionsChangedListener fired: ${controllers?.size} controllers")
        bindToControllers(controllers)
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
    }

    override fun onDestroy() {
        instance = null
        activeController?.unregisterCallback(mediaCallback)
        try {
            mediaSessionManager?.removeOnActiveSessionsChangedListener(sessionChangedListener)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        Log.d(TAG, "onListenerConnected!")
        registerSessionListener()
        queryActiveSessions()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        val sbnObj = sbn ?: return
        val extras = sbnObj.notification?.extras ?: return

        // 1. Check if notification directly has a MediaSession token
        if (extras.containsKey(Notification.EXTRA_MEDIA_SESSION)) {
            val token = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                extras.getParcelable(Notification.EXTRA_MEDIA_SESSION, MediaSession.Token::class.java)
            } else {
                @Suppress("DEPRECATION")
                extras.getParcelable(Notification.EXTRA_MEDIA_SESSION) as? MediaSession.Token
            }

            if (token != null) {
                try {
                    val controller = MediaController(this, token)
                    bindController(controller)
                    return
                } catch (e: Exception) {
                    Log.e(TAG, "Error creating controller from token", e)
                }
            }
        }

        // 2. Immediate direct metadata fallback from media notification (e.g. Spotify)
        val notifTitle = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val notifArtist = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        if (!notifTitle.isNullOrBlank() && (sbnObj.packageName.contains("spotify") || sbnObj.notification.category == Notification.CATEGORY_TRANSPORT)) {
            val isPlaying = sbnObj.notification.actions?.any { action ->
                action.title?.toString()?.contains("pause", ignoreCase = true) == true
            } ?: true

            val notifBitmap = (extras.get(Notification.EXTRA_LARGE_ICON) as? Bitmap)
                ?: (extras.get(Notification.EXTRA_PICTURE) as? Bitmap)
                ?: run {
                    val icon = extras.get(Notification.EXTRA_LARGE_ICON) as? android.graphics.drawable.Icon
                    icon?.loadDrawable(this)?.let { drawable ->
                        if (drawable is android.graphics.drawable.BitmapDrawable) drawable.bitmap
                        else null
                    }
                }
            val accentColor = extractAccentColor(notifBitmap)

            val map = hashMapOf<String, Any>(
                "title" to notifTitle,
                "artist" to (notifArtist ?: ""),
                "album" to "",
                "durationMs" to 0L,
                "positionMs" to 0L,
                "isPlaying" to isPlaying,
                "packageName" to sbnObj.packageName,
                "accentColor" to accentColor
            )
            InlineFloatingService.currentAccentColor = accentColor
            mainHandler.post {
                onTrackChanged?.invoke(map)
            }
        }

        // 3. Query system active sessions
        queryActiveSessions()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        queryActiveSessions()
    }

    fun registerSessionListener() {
        try {
            val component = ComponentName(this, InlineNotificationListener::class.java)
            mediaSessionManager?.addOnActiveSessionsChangedListener(sessionChangedListener, component)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to addOnActiveSessionsChangedListener", e)
        }
    }

    fun queryActiveSessions() {
        try {
            val component = ComponentName(this, InlineNotificationListener::class.java)
            val controllers = mediaSessionManager?.getActiveSessions(component)
            Log.d(TAG, "queryActiveSessions found ${controllers?.size} sessions")
            bindToControllers(controllers)
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException in queryActiveSessions - notification access not active yet", e)
        } catch (e: Exception) {
            Log.e(TAG, "Exception in queryActiveSessions", e)
        }
    }

    private fun bindToControllers(controllers: List<MediaController>?) {
        if (controllers.isNullOrEmpty()) {
            return
        }

        val playing = controllers.firstOrNull { 
            it.playbackState?.state == PlaybackState.STATE_PLAYING 
        } ?: controllers.first()

        bindController(playing)
    }

    private fun bindController(controller: MediaController) {
        if (activeController?.sessionToken == controller.sessionToken) {
            dispatchCurrentTrack()
            return
        }

        activeController?.unregisterCallback(mediaCallback)
        activeController = controller
        activeController?.registerCallback(mediaCallback)
        Log.d(TAG, "Bound to controller: ${controller.packageName}")
        dispatchCurrentTrack()
    }

    private fun dispatchCurrentTrack() {
        val controller = activeController ?: return
        val metadata = controller.metadata
        val playbackState = controller.playbackState

        val desc = metadata?.description
        val title = desc?.title?.toString()
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
        val artist = desc?.subtitle?.toString()
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_AUTHOR)
        val album = desc?.description?.toString()
            ?: metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM)
        val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L

        val isPlaying = playbackState?.state == PlaybackState.STATE_PLAYING
        val position = playbackState?.position ?: 0L

        val artBitmap = metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: desc?.iconBitmap
        val accentColor = extractAccentColor(artBitmap)

        if (!title.isNullOrBlank()) {
            val map = hashMapOf<String, Any>(
                "title" to title,
                "artist" to (artist ?: ""),
                "album" to (album ?: ""),
                "durationMs" to duration,
                "positionMs" to position,
                "isPlaying" to isPlaying,
                "packageName" to (controller.packageName ?: ""),
                "accentColor" to accentColor
            )

            InlineFloatingService.currentAccentColor = accentColor
            Log.d(TAG, "Dispatching track: $title by $artist (accent=$accentColor)")
            mainHandler.post {
                onTrackChanged?.invoke(map)
            }
        }
    }

    private fun extractAccentColor(bitmap: Bitmap?): String {
        if (bitmap == null) return "#D4FF70"
        try {
            val scaled = Bitmap.createScaledBitmap(bitmap, 24, 24, false)
            var maxScore = -1f
            var bestColor = Color.parseColor("#D4FF70")

            val hsv = FloatArray(3)
            for (x in 0 until scaled.width) {
                for (y in 0 until scaled.height) {
                    val pixel = scaled.getPixel(x, y)
                    Color.colorToHSV(pixel, hsv)
                    val sat = hsv[1]
                    val brightness = hsv[2]

                    // Prioritize vivid, saturated colors; skip dull greys / near-blacks / near-whites
                    if (sat in 0.35f..1.0f && brightness in 0.35f..0.95f) {
                        val score = sat * 2.0f + brightness
                        if (score > maxScore) {
                            maxScore = score
                            bestColor = pixel
                        }
                    }
                }
            }
            return String.format("#%06X", 0xFFFFFF and bestColor)
        } catch (_: Exception) {
            return "#D4FF70"
        }
    }
}
