/**
 * AutoMusicPlugin.js
 *
 * Interface for controlling music playback in Android Auto and Apple CarPlay.
 * Provides methods and events for synchronization and playback control.
 */
var exec = require('cordova/exec');
const AutoMusicPlugin = {
  // ---------------------------
  // 1. Connectivity
  // ---------------------------
  /**
   * Checks if the device is connected to Android Auto or CarPlay.
   * @param {function(boolean): void} successCallback - Callback with connection status
   * @param {function(string): void} errorCallback - Error callback
   */
  isConnected(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'isConnected', []);
  },

  /**
   * Listens for connection changes to Android Auto or CarPlay.
   * @param {function({connected: boolean}): void} callback - Connection status callback
   */
  onConnectionChange(callback) {
    exec(function(data) {
      callback(data);
    }, function(error) {
      console.error('Error in connection change listener:', error);
    }, 'AutoMusicPlugin', 'registerAutoConnectListener', []);
  },
  
  /**
   * Stops listening for connection changes.
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  stopConnectionListener(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'unregisterAutoConnectListener', []);
  },

  // ---------------------------
  // 2. MediaSession
  // ---------------------------
  /**
   * Notifies about changes in the current track.
   * @param {function(Object): void} callback - Track metadata callback
   */
  onMediaUpdate(callback) {
    exec(function(data) {
      callback(data);
    }, function(error) {
      console.error('Error in media update listener:', error);
    }, 'AutoMusicPlugin', 'onMediaUpdate', []);
  },

  /**
   * Notifies about changes in playback state.
   * @param {function('playing'|'paused'|'stopped'|'buffering'): void} callback - Playback state callback
   */
  onPlaybackStateChange(callback) {
    exec(function(data) {
      callback(data);
    }, function(error) {
      console.error('Error in playback state listener:', error);
    }, 'AutoMusicPlugin', 'onPlaybackStateChange', []);
  },

  /**
   * Notifies about updates to the playback queue.
   * @param {function(Array<Object>): void} callback - Queue update callback
   */
  onQueueUpdate(callback) {
    exec(function(data) {
      callback(data);
    }, function(error) {
      console.error('Error in queue update listener:', error);
    }, 'AutoMusicPlugin', 'onQueueUpdate', []);
  },

  /**
   * Triggered when seeking position within a track.
   * @param {function(number): void} callback - Position in milliseconds
   */
  onSeek(callback) {
    exec(function(position) {
      callback(position);
    }, function(error) {
      console.error('Error in seek listener:', error);
    }, 'AutoMusicPlugin', 'onSeek', []);
  },

  /**
   * Event for custom actions.
   * @param {function(string, any=): void} callback - Custom action callback
   */
  onCustomAction(callback) {
    exec(function(data) {
      callback(data.action, data.data);
    }, function(error) {
      console.error('Error in custom action listener:', error);
    }, 'AutoMusicPlugin', 'onCustomAction', []);
  },

  /**
   * Starts or resumes playback.
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  play(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'play', []);
  },

  /**
   * Pauses playback.
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  pause(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'pause', []);
  },

  /**
   * Skips to the next track.
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  skipToNext(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'skipToNext', []);
  },

  /**
   * Skips to the previous track.
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  skipToPrevious(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'skipToPrevious', []);
  },

  /**
   * Seeks to the specified position.
   * @param {number} position - Position in milliseconds
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  seekTo(position, successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'seekTo', [position]);
  },

  /**
   * Updates the entire playback queue.
   * @param {Array<Object>} queue - Array of track objects
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  updateQueue(queue, successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'updateQueue', [queue]);
  },

  // ---------------------------
  // 3. Queue and Current Track Synchronization
  // ---------------------------
  /**
   * Event: triggered when the queue storage content changes.
   * @param {function(Array<Object>): void} callback - Queue storage update callback
   */
  onQueueStorageChange(callback) {
    exec(function(data) {
      callback(data);
    }, function(error) {
      console.error('Error in queue storage change listener:', error);
    }, 'AutoMusicPlugin', 'onQueueStorageChange', []);
  },

  /**
   * Event: triggered when the current track changes.
   * @param {function(number): void} callback - Current track index callback
   */
  onCurrentTrackChange(callback) {
    exec(function(data) {
      callback(data);
    }, function(error) {
      console.error('Error in current track change listener:', error);
    }, 'AutoMusicPlugin', 'onCurrentTrackChange', []);
  },

  /**
   * Method: notifies the service to reload the queue.
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  notifyQueueStorageUpdated(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'notifyQueueStorageUpdated', []);
  },

  /**
   * Method: notifies the service to change the current track.
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  notifyCurrentTrackUpdated(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'notifyCurrentTrackUpdated', []);
  },

  /**
   * Returns the current playback position.
   * @param {function(number): void} successCallback - Position callback in milliseconds
   * @param {function(string): void} errorCallback - Error callback
   */
  getPosition(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'getPosition', []);
  },

  /**
   * Returns the current playback state.
   * @param {function('playing'|'paused'|'stopped'|'buffering'): void} successCallback - Playback state callback
   * @param {function(string): void} errorCallback - Error callback
   */
  getCurrentPlaybackState(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'getCurrentPlaybackState', []);
  },
  
  /**
   * Starts the auto service (Android only).
   * @param {function(string): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  startService(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'startService', []);
  },

  // ---------------------------
  // 5. Hardcoded Content
  // ---------------------------
  /**
   * Gets the hardcoded playlists available in the plugin.
   * @param {function(Array<Object>): void} successCallback - Success callback with playlists
   * @param {function(string): void} errorCallback - Error callback
   */
  getHardcodedPlaylists(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'getHardcodedPlaylists', []);
  },

  /**
   * Gets tracks for a hardcoded playlist.
   * @param {string} playlistId - ID of the hardcoded playlist
   * @param {function(Array<Object>): void} successCallback - Success callback with tracks
   * @param {function(string): void} errorCallback - Error callback
   */
  getHardcodedPlaylistTracks(playlistId, successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'getHardcodedPlaylistTracks', [playlistId]);
  },

  /**
   * Plays a hardcoded track directly.
   * @param {string} trackId - ID of the hardcoded track
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  playHardcodedTrack(trackId, successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'playHardcodedTrack', [trackId]);
  },

  // ---------------------------
  // 6. Debugging and Logging
  // ---------------------------
  /**
   * Gets all the collected logs from the native side.
   * @param {function(Array<string>): void} successCallback - Success callback with logs array
   * @param {function(string): void} errorCallback - Error callback
   */
  getLogs(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'getLogs', []);
  },

  /**
   * Clears all collected logs.
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  clearLogs(successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'clearLogs', []);
  },

  /**
   * Adds a custom log entry.
   * @param {string} message - Message to log
   * @param {function(): void} successCallback - Success callback
   * @param {function(string): void} errorCallback - Error callback
   */
  addLog(message, successCallback, errorCallback) {
    exec(successCallback, errorCallback, 'AutoMusicPlugin', 'addLog', [message]);
  }
};
module.exports = AutoMusicPlugin;