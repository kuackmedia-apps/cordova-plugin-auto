cordova.define("cordova-plugin-auto.auto", function(require, exports, module) {

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
  
    play: function() {
      cordova.exec(
        function success(result) {
          console.log('Track played successfully:', result);
        },
        function error(err) {
          console.error('Error playing track:', err);
        },
        'AndroidAutoPlugin',
        'play',
        [],
      );
    },
  
    pause: function() {
        cordova.exec(
          function success(result) {
            console.log('Track paused successfully:', result);
          },
          function error(err) {
            console.error('Error paused track:', err);
          },
          'AndroidAutoPlugin',
          'pause',
          [],
        );
    },
  
    getCurrentPlaybackState: function() {
      cordova.exec(
        function success(result) {
          console.log('Track getCurrentPlaybackState successfully:', result);
        },
        function error(err) {
          console.error('Error getCurrentPlaybackState track:', err);
        },
        'AndroidAutoPlugin',
        'getCurrentPlaybackState',
        [],
      );
    },
  
    isConnected: function () {
      cordova.exec(
        function success(result) {
          console.log('Track isConnected successfully:', result);
        },
        function error(err) {
          console.error('Error isConnected track:', err);
        },
        'AndroidAutoPlugin',
        'isConnected',
        [],
      );
    }
  }
  
  module.exports = AutoPlugin;
  
  });
  