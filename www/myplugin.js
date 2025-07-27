var exec = require('cordova/exec');
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
        'AndroidAutoPlugin',
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
          'AndroidAutoPlugin',
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
        'AndroidAutoPlugin',
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
        'AndroidAutoPlugin',
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
          'AndroidAutoPlugin',
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
        'AndroidAutoPlugin',
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
        'AndroidAutoPlugin',
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
           'AndroidAutoPlugin',
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
           'AndroidAutoPlugin',
           'playCurrentTrack',
           [],
         );
    },
  }

  module.exports = AutoPlugin;
