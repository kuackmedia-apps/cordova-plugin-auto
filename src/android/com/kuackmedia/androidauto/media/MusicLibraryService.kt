package com.kuackmedia.androidauto.media

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.media.MediaBrowserServiceCompat
import androidx.media.session.MediaButtonReceiver
import androidx.media.utils.MediaConstants
import com.kuackmedia.androidauto.CordovaEventBridge
import com.kuackmedia.androidauto.CordovaEvents
import com.kuackmedia.androidauto.api.ServiceFactory
import com.kuackmedia.androidauto.tree.MediaItemFactory
import com.kuackmedia.androidauto.tree.MediaItemTree
import com.kuackmedia.androidauto.utils.TextsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File


class MusicLibraryService : MediaBrowserServiceCompat() {

    companion object {
        const val TAG = "MusicLibraryService"
        const val AT_EXP_TIME_KEY = "AT_EXP_TIME_KEY"
        const val REFRESH_TOKEN_KEY = "REFRESH_TOKEN_KEY"
        const val ACCESS_TOKEN_KEY = "AT_TOKEN_KEY"
        const val APP_KUACK_CODE = "APP_KUACK_CODE"
        const val API_URL = "API_URL"
        const val DEVICE_ID = "DEVICE_ID"
        const val ROOT_ID = "[rootID]"
        const val CURRENT_TRACK_KEY = "current_track"
        const val QUEUE_ITEMS_KEY = "QUEUE_ITEMS_KEY"
        const val PLAYLIST_DATA = "playlist_data"
        const val OFFLINE_ROOT = "[offline_root]"
        const val LIBRARY_ROOT = "AUTO_NAVIGATION_LIBRARY_MENU"

        // Allowed packages that can connect to this MediaBrowserService
        // Android Auto and Google Assistant packages
        private val ALLOWED_PACKAGES = setOf(
            "com.google.android.projection.gearhead",  // Android Auto
            "com.google.android.gms",                   // Google Play Services (Assistant)
            "com.google.android.googlequicksearchbox", // Google App (Assistant)
            "com.google.android.carassistant"          // Android Auto standalone
        )

        // Hold a reference to the active service instance
        private var instance: MusicLibraryService? = null

        fun isNetworkEnabled(context: Context): Boolean {
            return isNetworkAvailable(context)
        }

        private fun isNetworkAvailable(context: Context): Boolean {
            val connectivityManager =
                context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = connectivityManager.activeNetwork ?: return false
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
            return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        }

        /**
         * Refresh the Android Auto navigation tree.
         * This reloads navigation data from files and notifies Android Auto to update the UI.
         */
        fun refreshNavigation() {
            instance?.refreshNavigationInternal()
        }
    }

    private var currentTrackName: String? = null
    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)

    private lateinit var mediaSession: MediaSessionCompat
    private lateinit var playerAdapter: IPlayerAdapter
    private lateinit var networkCallback: ConnectivityManager.NetworkCallback
    private var networkAvailable: Boolean = false
    private var isAndroidAutoConnected: Boolean = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaButtonReceiver.handleIntent(mediaSession, intent)
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onCreate() {
        super.onCreate()

        // Register this instance
        instance = this

        // NOTE: We no longer send ON_CONNECTION_CHANGE here.
        // The event is now sent in onGetRoot() only when a valid Android Auto client connects.
        // This prevents the "car icon" from appearing when Bluetooth or other non-Auto clients
        // trigger the service.

        TextsManager.init(applicationContext)
        initApiData()

        val musicApi = ServiceFactory.create(applicationContext)

        playerAdapter = MediaPlayerAdapter()

        MediaItemTree.initialize(applicationContext, musicApi)

        // Clear preloaded cache from previous session
        TrackPreloader.clearCache(applicationContext)

        if (!::mediaSession.isInitialized) {
            mediaSession = MediaSessionCompat(this, TAG)
            mediaSession.setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                        MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            mediaSession.setCallback(
                MediaSessionCallback(
                    playerAdapter,
                    mediaSession,
                    applicationContext
                )
            )

            // Agrega acciones de voz/search al PlaybackStateCompat
            val actions = (PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackStateCompat.ACTION_SEEK_TO or
                    PlaybackStateCompat.ACTION_PLAY_FROM_SEARCH or
                    PlaybackStateCompat.ACTION_PREPARE or
                    PlaybackStateCompat.ACTION_PREPARE_FROM_SEARCH)

            mediaSession.setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setActions(actions)
                    .setState(PlaybackStateCompat.STATE_NONE, 0L, 1f)
                    .build()
            )
        }

        setSessionToken(mediaSession.sessionToken)

        MediaControlBridge.mediaSession = mediaSession
        MediaControlBridge.mediaPlayer = playerAdapter

        // NOTE: We no longer call prepare() automatically here.
        // This was causing the player to load a track when Bluetooth connected,
        // even if it wasn't Android Auto. Now prepare() is only called when
        // Android Auto actually connects and requests playback.

        networkAvailable = isNetworkAvailable(this)
        val connectivityManager = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val newNetworkAvailability = isNetworkAvailable(applicationContext)
                networkAvailable = true
                notifyChildrenChanged(ROOT_ID)
                MediaItemTree.getChildren(ROOT_ID).forEach { mediaItem ->
                    mediaItem?.mediaId?.let {
                        if (mediaItem.isBrowsable) {
                            notifyChildrenChanged(it)
                        }
                    }
                }
            }

            override fun onLost(network: Network) {
                val newNetworkAvailability = isNetworkAvailable(applicationContext)
                networkAvailable = false
                notifyChildrenChanged(ROOT_ID)
                MediaItemTree.getChildren(ROOT_ID).forEach { mediaItem ->
                    mediaItem?.mediaId?.let {
                        if (mediaItem.isBrowsable) {
                            notifyChildrenChanged(it)
                        }
                    }
                }
            }
        }
        connectivityManager.registerDefaultNetworkCallback(networkCallback)
    }

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?
    ): BrowserRoot? {
        // Check if the client is an allowed Android Auto package
        val isAllowedClient = ALLOWED_PACKAGES.contains(clientPackageName)

        if (!isAllowedClient) {
            // Reject connections from non-Android Auto clients (e.g., com.android.bluetooth)
            // This prevents the service from activating when Bluetooth connects
            return null
        }

        val extras = Bundle()
        extras.putInt(
            MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_BROWSABLE,
            MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM
        )
        extras.putInt(
            MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_PLAYABLE,
            MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM
        )
        extras.putBoolean(MediaConstants.BROWSER_SERVICE_EXTRAS_KEY_SEARCH_SUPPORTED, true)

        // Only set connected and send event for valid Android Auto connections
        if (!isAndroidAutoConnected) {
            isAndroidAutoConnected = true
            MediaControlBridge.setConnected(true)
            CordovaEventBridge.sendEvent(
                CordovaEvents.ON_CONNECTION_CHANGE,
                JSONObject().put("connected", true)
            )

            // Prepare the player and load the queue only when Android Auto really connects
            // This was previously in onCreate() but caused issues with Bluetooth triggering it
            mediaSession.controller.transportControls.prepare()
        }

        return BrowserRoot(ROOT_ID, extras)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        if (isAndroidAutoConnected) {
            isAndroidAutoConnected = false
            MediaControlBridge.setConnected(false)
            CordovaEventBridge.sendEvent(
                CordovaEvents.ON_CONNECTION_CHANGE,
                JSONObject().put("connected", false)
            )
        }
        return super.onUnbind(intent)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<List<MediaBrowserCompat.MediaItem?>?>
    ) {

        if (parentId == OFFLINE_ROOT) {
            //OFFLINE ITEMS
            result.sendResult(MediaItemTree.getOfflineItems())
            return
        }

        // Handle login required placeholder - don't navigate into it
        if (parentId == "[login_required]") {
            result.sendResult(mutableListOf())
            return
        }

        // Check if this is the ROOT and user is not logged in - BEFORE getting children
        val isLoggedIn = MediaItemTree.isUserLoggedIn(applicationContext)

        if (parentId == ROOT_ID && !isLoggedIn) {
            val loginItem = MediaItemTree.getLoginRequiredMediaItem(applicationContext)
            result.sendResult(mutableListOf(loginItem))
            return
        }

        var localChildren = MediaItemTree.getChildren(parentId)

        // If ROOT has no children, try refreshing the tree from files
        // This handles the race condition where the service initialized before JS wrote the navigation files
        if (parentId == ROOT_ID && localChildren.isEmpty()) {
            MediaItemTree.refresh(applicationContext)
            localChildren = MediaItemTree.getChildren(parentId)
        }

        // ROOT level + offline: show offline entry point
        if (parentId == ROOT_ID && !isNetworkAvailable(this)) {
            val offlineMediaItem = MediaItemTree.getOfflineMediaItem(applicationContext)
            result.sendResult(mutableListOf(offlineMediaItem))
            return
        }

        // Return cached children if available (works both online and offline)
        if (localChildren.isNotEmpty()) {
            result.sendResult(localChildren)
            return
        }

        // No cached children — try to load (getRemoteChildren handles both online and offline)
        result.detach()
        val resultSent = java.util.concurrent.atomic.AtomicBoolean(false)

        serviceScope.launch {
            try {
                val remoteChildren =
                    MediaItemTree.getRemoteChildren(parentId, applicationContext)

                if (remoteChildren.isNotEmpty()) {
                    QueueManager.buildQueue(remoteChildren)
                    if (resultSent.compareAndSet(false, true)) {
                        result.sendResult(remoteChildren)
                    }
                } else if (!isNetworkAvailable(applicationContext)) {
                    // Offline and no offline tracks found — show "No Internet"
                    if (resultSent.compareAndSet(false, true)) {
                        val offlineMediaItem = MediaItemTree.getOfflineMediaItem(applicationContext)
                        result.sendResult(mutableListOf(offlineMediaItem))
                    }
                } else {
                    if (resultSent.compareAndSet(false, true)) {
                        result.sendResult(mutableListOf())
                    }
                }
            } catch (e: Exception) {
                Log.e("MusicService", "Error loading children", e)
                if (resultSent.compareAndSet(false, true)) {
                    result.sendResult(mutableListOf())
                }
            }
        }
    }

    /**
     * Internal method to refresh navigation.
     * Reloads MediaItemTree and notifies Android Auto of changes.
     */
    private fun refreshNavigationInternal() {
        try {
            // Refresh the MediaItemTree
            MediaItemTree.refresh(applicationContext)

            // Notify Android Auto that the root has changed
            notifyChildrenChanged(ROOT_ID)

            // Notify all browsable children that they have changed
            MediaItemTree.getChildren(ROOT_ID).forEach { mediaItem ->
                mediaItem?.mediaId?.let {
                    if (mediaItem.isBrowsable) {
                        notifyChildrenChanged(it)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "[REFRESH_NAVIGATION] Error refreshing navigation: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        // Unregister this instance
        instance = null

        playerAdapter.stop()
        playerAdapter.reset()
        mediaSession.release()
        playerAdapter.release()

        // Send disconnect event if Android Auto was connected (safety check)
        if (isAndroidAutoConnected) {
            isAndroidAutoConnected = false
            CordovaEventBridge.sendEvent(
                CordovaEvents.ON_CONNECTION_CHANGE,
                JSONObject().put("connected", false)
            )
        }

        // Remove audio controls notification
        stopForeground(STOP_FOREGROUND_REMOVE)
        NotificationManagerCompat.from(this).cancel(1)
        (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(
            networkCallback
        )
        super.onDestroy()
    }

    override fun onSearch(
        query: String, extras: Bundle?,
        result: Result<MutableList<MediaBrowserCompat.MediaItem?>?>
    ) {
        result.detach() // Notify the system you'll send the result asynchronously
        serviceScope.launch {
            try {
                val items = MediaItemTree.search(query, applicationContext)
                result.sendResult(items.toMutableList<MediaBrowserCompat.MediaItem?>())
            } catch (e: Exception) {
                Log.e("MusicLibraryService", "Search failed", e)
                result.sendResult(mutableListOf())
            }
        }
    }

    private fun initApiData() {
        val prefs = applicationContext.getSharedPreferences("NativeStorage", MODE_PRIVATE)
        val refreshToken = prefs.getString(REFRESH_TOKEN_KEY, null)
        val accessToken = prefs.getString(ACCESS_TOKEN_KEY, null)
        val accessTokenExpiration = prefs.getString(AT_EXP_TIME_KEY, null)
        val appKuackCode = prefs.getString(APP_KUACK_CODE, null)
        val deviceId = prefs.getString(DEVICE_ID, null)
        val baseUrl = prefs.getString(API_URL, null)

        this.currentTrackName =
            prefs.getString(CURRENT_TRACK_KEY, null).toString().replace("\"", "")
    }
}
