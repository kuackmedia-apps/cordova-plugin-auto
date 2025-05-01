var exec = require('cordova/exec');

var MyMusicPlugin = {
    play: function(success, error) {
        exec(success, error, "MyMusicPlugin", "play", []);
    },
    pause: function(success, error) {
        exec(success, error, "MyMusicPlugin", "pause", []);
    },
    setMetadata: function(title, artist, album, success, error) {
        exec(success, error, "MyMusicPlugin", "setMetadata", [title, artist, album]);
    }
};

module.exports = MyMusicPlugin;
