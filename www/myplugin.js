var exec = require('cordova/exec');
  // Select correct native service per platform
  var SERVICE = (typeof cordova !== 'undefined' && cordova.platformId === 'ios')
    ? 'AutoMusicPlugin'  // iOS feature name in plugin.xml
    : 'AndroidAutoPlugin'; // Android feature name in plugin.xml

  var AutoPlugin = {
    onConnectionChangeCallback: null,
    onMediaUpdateCallback: null,

    onConnectionChange: function (callback) {
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
      cordova.exec(
        function success(result) {
          console.log('Track isConnected successfully:', result);
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
    
    // ---- Auth Config bridge (iOS) ----
    setAuthConfig: function(accessToken, refreshToken, appCode, baseUrl, expirationAt, cb, errorCb) {
      exec(
        function success(result) {
          if (typeof cb === 'function') cb(result);
        },
        function error(err) {
          console.error('setAuthConfig error:', err);
          if (typeof errorCb === 'function') errorCb(err);
        },
        SERVICE,
        'setAuthConfig',
        [accessToken, refreshToken, appCode, baseUrl, expirationAt]
      );
    },

    getAuthConfig: function(cb, errorCb) {
      exec(
        function success(result) {
          if (typeof cb === 'function') cb(result);
        },
        function error(err) {
          console.error('getAuthConfig error:', err);
          if (typeof errorCb === 'function') errorCb(err);
        },
        SERVICE,
        'getAuthConfig',
        []
      );
    },
  }

  module.exports = AutoPlugin;
