// User-installed songs are data, not source code.
// This synchronous read intentionally happens before keyboard.js initializes.
// It keeps the legacy Rails/Sprockets bootstrap intact while removing the need
// to edit keyboard.js every time a song is installed or removed.
window.userSongDatas = [];

(function () {
  try {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/dev/song_imports', false);
    xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    xhr.send(null);

    if (xhr.status >= 200 && xhr.status < 300) {
      var payload = JSON.parse(xhr.responseText);
      if (payload && payload.ok && Array.isArray(payload.songs)) {
        window.userSongDatas = payload.songs;
      }
    }
  } catch (error) {
    if (window.console && console.warn) {
      console.warn('Could not load user songs:', error);
    }
  }
})();
