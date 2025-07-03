var exec = require('cordova/exec');

var AutoPlugin = (function () {
  let mediaUpdateCallback = null;

  function registerNativeListener() {
    exec(
      function success(data) {
        if (data.event === 'mediaUpdate' && mediaUpdateCallback) {
          mediaUpdateCallback(data.track);
        }
      },
      function error(err) {
        console.error("Error receiving native events", err);
      },
      "AndroidAutoPlugin",       // <- Java plugin name in plugin.xml
      "registerEvents",   // <- Kotlin `execute` action
      []
    );
  }

  return {
    // ---------------------------
    // 1. Conectividad
    // ---------------------------
    /**
     * Verifica si el servicio de Android Auto está conectado.
     * @param {function(boolean): void} callback
     */
    isConnected(callback) {
      // TODO: Consultar estado de conexión y ejecutar callback(status)
    },

    /**
     * Escucha cambios de conexión al servicio.
     * @param {function('connecting'|'connected'|'disconnected'): void} callback
     */
    onConnectionChange(callback) {
      // TODO: Registrar listener para cambios de estado
    },

    // ---------------------------
    // 2. MediaSession
    // ---------------------------
    /**
     * Notifica cambios en la pista actual.
     * @param {function(Track): void} callback
     */
    onMediaUpdate: function (callback) {
      mediaUpdateCallback = callback;
      registerNativeListener(); // connect with native
    },

    /**
     * Indica cambios en el estado de reproducción.
     * @param {function('playing'|'paused'|'stopped'|'buffering'): void} callback
     */
    onPlaybackStateChange(callback) {
      // TODO: Emitir al cambiar estado de playback
    },

    /**
     * Entrega la cola de reproducción actualizada.
     * @param {function(Array<Track>): void} callback
     */
    onQueueUpdate(callback) {
      // TODO: Emitir cuando la cola cambie
    },

    /**
     * Se dispara al buscar posición dentro de la pista.
     * @param {function(number): void} callback - posición en ms
     */
    onSeek(callback) {
      // TODO: Emitir cuando usuario seek
    },

    /**
     * Evento para acciones personalizadas.
     * @param {function(string, any=): void} callback
     */
    onCustomAction(callback) {
      // TODO: Emitir acciones como 'repeat', 'shuffle', etc.
    },

    /** Inicia o reanuda reproducción. */
    play(callback, errorCallback) {
      // TODO: Implementar play
    },

    /** Pausa reproducción. */
    pause(callback, errorCallback) {
      // TODO: Implementar pause
    },


    /** Avanza a la siguiente pista. */
    skipToNext(callback, errorCallback) {
      // TODO: Implementar siguiente track
    },

    /** Retrocede a la pista anterior. */
    skipToPrevious(callback, errorCallback) {
      // TODO: Implementar pista anterior
    },

    /** Salta a la posición indicada. */
    seekTo(position, callback, errorCallback) {
      // TODO: Implementar seekTo
    },

    /** Actualiza la cola completa de reproducción. */
    updateQueue(queue, callback, errorCallback) {
      // TODO: Enviar nueva cola al servicio
    },

    // ---------------------------
    // 5. Sincronización de Cola y Pista Actual
    // ---------------------------
    /**
     * Evento: disparado cuando cambia el contenido del almacenamiento de la cola.
     * @param {function(Array<Track>): void} callback
     */
    onQueueStorageChange(callback) {
      // TODO: Escuchar cambios en QUEUE_ITEMS_QUEUE o playlist_data
    },

    /**
     * Evento: disparado al cambiar el track actual.
     * @param {function(number): void} callback
     */
    onCurrentTrackChange(callback) {
      // TODO: Escuchar cambios en current_track
    },

    /** Método: notifica al servicio que recargue la cola. */
    notifyQueueStorageUpdated() {
      // TODO: Notificar recarga de cola al servicio
    },

    /** Método: notifica al servicio que cambie la pista actual. */
    notifyCurrentTrackUpdated() {
      // TODO: Notificar cambio de pista al servicio
    },

    /**
     * Retorna la posición actual de reproducción.
     * @param {function(position): void} successCallback
     */
    getPosition (successCallback, errorCallback) {

    },
    /**
     * Indica cambios en el estado de reproducción.
     * @param {function('playing'|'paused'|'stopped'|'buffering'): void} successCallback
     */
    getCurrentPlaybackState (successCallback, errorCallback) {

    }
  };
})();

module.exports = AutoPlugin;
