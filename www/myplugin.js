var exec = require('cordova/exec');
  // Select correct native service per platform
  var SERVICE = (typeof cordova !== 'undefined' && cordova.platformId === 'ios')
    ? 'AutoMusicPlugin'  // iOS feature name in plugin.xml
    : 'AndroidAutoPlugin'; // Android feature name in plugin.xml

  var AutoPlugin = {
    onConnectionChangeCallback: null,
    onMediaUpdateCallback: null,

    onConnectionChange: function (callback) {
      console.log('[auto] onConnectionChange called');
      AutoPlugin.onConnectionChangeCallback = callback;

      exec(
        function(data) {
          if (typeof AutoPlugin.onConnectionChangeCallback === 'function') {
            AutoPlugin.onConnectionChangeCallback(data);
          }
        },
        function(err) {
          console.error('AutoPlugin listener error:', err);
        },
        SERVICE,
        'registerEvents',
        ['onConnectionChange']
      );
    },

    onMediaUpdate: function (callback) {
      console.log('[auto] onMediaUpdate called');
      AutoPlugin.onMediaUpdateCallback = callback;

      exec(
        function (data) {
          if (typeof AutoPlugin.onMediaUpdateCallback === 'function') {
            AutoPlugin.onMediaUpdateCallback(data);
          }
        },
        function (err) {
          console.error('AutoPlugin onMediaUpdate error:', err);
        },
        SERVICE,
        'registerEvents',
        ['onMediaUpdate']
      );
    },

    onPlaybackStateChange: function (callback) {
      console.log('[auto] onPlaybackStateChange called');
      AutoPlugin.onPlaybackStateChange = callback;

      exec(
        function (data) {
          if (typeof AutoPlugin.onPlaybackStateChange === 'function') {
            AutoPlugin.onPlaybackStateChange(data);
          }
        },
        function (err) {
          console.error('AutoPlugin onPlaybackStateChange error:', err);
        },
        SERVICE,
        'registerEvents',
        ['onPlaybackStateChange']
      );
    },

    play: function(cb, errorCb) {
      console.log('[auto] play called');
      cordova.exec(
        function success(result) {
          if (typeof cb === 'function') {
            cb(result);
          }
        },
        function error(err) {
          console.error('Error playing track:', err);
          if (typeof errorCb === 'function') {
            errorCb(err);
          }
        },
        SERVICE,
        'play',
        [],
      );
    },

    pause: function(cb, errorCb) {
      console.log('[auto] pause called');
      cordova.exec(
        function success(result) {
          console.log('Track paused successfully:', result);
          if (typeof cb === 'function') {
            cb(result);
          }
        },
        function error(err) {
          console.error('Error paused track:', err);
          if (typeof errorCb === 'function') {
            errorCb(err);
          }
        },
        SERVICE,
        'pause',
        [],
      );
    },

    getCurrentPlaybackState: function(cb, errorCb) {
      console.log('[auto] getCurrentPlaybackState called');
      cordova.exec(
        function success(result) {
          console.log('Track getCurrentPlaybackState successfully:', result);
          cb(result);
        },
        function error(err) {
          console.error('Error getCurrentPlaybackState track:', err);
          if (typeof errorCb === 'function') {
            errorCb(err);
          }
        },
        SERVICE,
        'getCurrentPlaybackState',
        [],
      );
    },

    isConnected: function (cb, errorCb) {
      console.log('[auto] about to call isConnected');
      cordova.exec(
        function success(result) {
          // Align log format with requested snippet
          console.log('[auto] isConnected ->', result);
          if (typeof cb === 'function') {
            cb(result);
          }
        },
        function error(err) {
          console.error('Error isConnected track:', err);
          if (typeof errorCb === 'function') {
            errorCb(err);
          }
        },
        SERVICE,
        'isConnected',
        [],
      );
    },

    getPosition: function (cb, errorCb) {
      console.log('[auto] getPosition called');
      cordova.exec(
        function success(result) {
          if (typeof cb === 'function') {
            cb(result);
          }
        },
        function error(err) {
          console.error('Error getPosition track:', err);
          if (typeof errorCb === 'function') {
            errorCb(err);
          }
        },
        SERVICE,
        'getPosition',
        [],
      );
    },

    playCurrentTrack: function (cb, errorCb) {
      console.log('[auto] playCurrentTrack called');
      cordova.exec(
        function success(result) {
          if (typeof cb === 'function') {
            cb(result);
          }
        },
        function error(err) {
          console.error('Error playCurrentTrack :', err);
          if (typeof errorCb === 'function') {
            errorCb(err);
          }
        },
        SERVICE,
        'playCurrentTrack',
        [],
      );
    },
    updateNavigation: function (cb, errorCb) {
         cordova.exec(
           function success(result) {
              if (typeof cb === 'function') {
                cb(result);
              }
           },
           function error(err) {
             console.error('Error updateNavigation :', err);
              if (typeof errorCb === 'function') {
                errorCb(err);
              }
           },
           SERVICE,
           'updateNavigation',
           [],
         );
    },

    // ---- Auth Config bridge (iOS) ----
    setAuthConfig: function(accessToken, refreshToken, appCode, baseUrl, expirationAt, cb, errorCb) {
      console.log('[auto] setAuthConfig called', {
        hasAccessToken: !!accessToken,
        hasRefreshToken: !!refreshToken,
        appCode: appCode,
        baseUrl: baseUrl,
        expirationAt: expirationAt
      });
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('setAuthConfig error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'setAuthConfig',
        [accessToken, refreshToken, appCode, baseUrl, expirationAt]
      );
    },

    getAuthConfig: function(cb, errorCb) {
      console.log('[auto] getAuthConfig called');
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('getAuthConfig error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'getAuthConfig',
        []
      );
    },
  
    // ---- Queue and Playback Controls ----
    updateQueue: function(queue, cb, errorCb) {
      console.log('[auto] updateQueue called', { count: Array.isArray(queue) ? queue.length : 'n/a' });
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('updateQueue error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'updateQueue',
        [Array.isArray(queue) ? queue : []]
      );
    },

    notifyQueueStorageUpdated: function(cb, errorCb) {
      console.log('[auto] notifyQueueStorageUpdated called');
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('notifyQueueStorageUpdated error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'notifyQueueStorageUpdated',
        []
      );
    },

    notifyCurrentTrackUpdated: function(cb, errorCb) {
      console.log('[auto] notifyCurrentTrackUpdated called');
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('notifyCurrentTrackUpdated error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'notifyCurrentTrackUpdated',
        []
      );
    },

    skipToNext: function(cb, errorCb) {
      console.log('[auto] skipToNext called');
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('skipToNext error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'skipToNext',
        []
      );
    },

    skipToPrevious: function(cb, errorCb) {
      console.log('[auto] skipToPrevious called');
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('skipToPrevious error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'skipToPrevious',
        []
      );
    },

    seekTo: function(positionMs, cb, errorCb) {
      console.log('[auto] seekTo called', { positionMs });
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('seekTo error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'seekTo',
        [Number(positionMs) || 0]
      );
    },

    // ---- Hardcoded content helpers (diagnostics) ----
    getHardcodedPlaylists: function(cb, errorCb) {
      console.log('[auto] getHardcodedPlaylists called');
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('getHardcodedPlaylists error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'getHardcodedPlaylists',
        []
      );
    },

    getHardcodedPlaylistTracks: function(playlistId, cb, errorCb) {
      console.log('[auto] getHardcodedPlaylistTracks called', { playlistId });
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('getHardcodedPlaylistTracks error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'getHardcodedPlaylistTracks',
        [playlistId]
      );
    },

    playHardcodedTrack: function(url, metadata, cb, errorCb) {
      console.log('[auto] playHardcodedTrack called', { url, hasMetadata: !!metadata });
      exec(
        function success(result) { if (typeof cb === 'function') cb(result); },
        function error(err) { console.error('playHardcodedTrack error:', err); if (typeof errorCb === 'function') errorCb(err); },
        SERVICE,
        'playHardcodedTrack',
        [url, metadata || {}]
      );
    },

    // ---- Siri Integration (iOS only) ----
    
    /**
     * Request Siri authorization from the user.
     * This should be called early in your app to prompt for Siri permissions.
     * @param {function} callback - Called with status: 'authorized', 'denied', 'restricted', 'notDetermined', or 'unknown'
     * @param {function} errorCb - Called on error
     */
    requestSiriAuthorization: function(callback, errorCb) {
      console.log('[auto] requestSiriAuthorization called');
      if (cordova.platformId !== 'ios') {
        console.warn('[auto] Siri authorization is only supported on iOS');
        if (typeof errorCb === 'function') errorCb('Not supported on this platform');
        return;
      }

      exec(
        function(status) {
          console.log('[auto] Siri authorization status:', status);
          if (typeof callback === 'function') callback(status);
        },
        function(err) {
          console.error('[auto] Siri authorization error:', err);
          if (typeof errorCb === 'function') errorCb(err);
        },
        SERVICE,
        'requestSiriAuthorization',
        []
      );
    },

    /**
     * Get current Siri authorization status without prompting the user.
     * @param {function} callback - Called with status: 'authorized', 'denied', 'restricted', 'notDetermined', or 'unknown'
     * @param {function} errorCb - Called on error
     */
    getSiriAuthorizationStatus: function(callback, errorCb) {
      console.log('[auto] getSiriAuthorizationStatus called');
      if (cordova.platformId !== 'ios') {
        console.warn('[auto] Siri authorization is only supported on iOS');
        if (typeof errorCb === 'function') errorCb('Not supported on this platform');
        return;
      }

      exec(
        function(status) {
          console.log('[auto] Current Siri status:', status);
          if (typeof callback === 'function') callback(status);
        },
        function(err) {
          console.error('[auto] Siri status check error:', err);
          if (typeof errorCb === 'function') errorCb(err);
        },
        SERVICE,
        'getSiriAuthorizationStatus',
        []
      );
    },

    onSiriIntent: function(callback) {
      console.log('[auto] onSiriIntent called');
      if (cordova.platformId !== 'ios') {
        console.warn('[auto] Siri intents are only supported on iOS');
        return;
      }

      exec(
        function(data) {
          console.log('[auto] Siri intent received:', data);
          if (typeof callback === 'function') {
            callback(data);
          }
        },
        function(err) {
          console.error('[auto] Siri intent listener error:', err);
        },
        SERVICE,
        'registerSiriIntentListener',
        []
      );
    },

    playSiriSearchResults: function(cb, errorCb) {
      console.log('[auto] playSiriSearchResults called');
      if (cordova.platformId !== 'ios') {
        console.warn('[auto] Siri is only supported on iOS');
        if (typeof errorCb === 'function') errorCb('Not supported on this platform');
        return;
      }

      exec(
        function success(result) {
          console.log('[auto] Siri search results playback started');
          if (typeof cb === 'function') cb(result);
        },
        function error(err) {
          console.error('[auto] Error starting Siri playback:', err);
          if (typeof errorCb === 'function') errorCb(err);
        },
        SERVICE,
        'playSiriSearchResults',
        []
      );
    },

    /**
     * Search for music and start playback (works like Siri search)
     * Can be used to add a search button in the app that triggers CarPlay/Auto search
     * @param {object} searchParams - Search parameters
     * @param {string} searchParams.query - The search query (e.g., artist name, song title)
     * @param {string} [searchParams.artistName] - Optional artist name hint
     * @param {string} [searchParams.albumName] - Optional album name hint
     * @param {function} callback - Called on success
     * @param {function} errorCb - Called on error
     */
    searchAndPlay: function(searchParams, callback, errorCb) {
      console.log('[auto] searchAndPlay called', searchParams);
      
      var params = {
        mediaName: searchParams.query || searchParams.mediaName || '',
        artistName: searchParams.artistName || null,
        albumName: searchParams.albumName || null,
        mediaType: searchParams.mediaType || 0,
        isCarPlayConnected: false // Will be determined by native side
      };

      exec(
        function success(result) {
          console.log('[auto] searchAndPlay success:', result);
          if (typeof callback === 'function') callback(result);
        },
        function error(err) {
          console.error('[auto] searchAndPlay error:', err);
          if (typeof errorCb === 'function') errorCb(err);
        },
        SERVICE,
        'searchAndPlay',
        [params]
      );
    },
  }

  module.exports = AutoPlugin;
