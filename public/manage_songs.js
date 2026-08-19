(function () {
  var list = document.getElementById('userSongs');
  var status = document.getElementById('status');

  function setStatus(text, kind) {
    status.className = 'status' + (kind ? ' ' + kind : '');
    status.textContent = text;
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>"]/g, function (ch) {
      return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;' }[ch];
    });
  }

  function render(songs) {
    if (!songs.length) {
      list.innerHTML = '<p>No user songs installed yet.</p>';
      return;
    }

    list.innerHTML = songs.map(function (song) {
      var name = escapeHtml(song.song_name || song.filename);
      var filename = escapeHtml(song.filename);
      var bpm = escapeHtml(song.bpm || '?');
      return '<div class="song" data-filename="' + filename + '">' +
        '<div><strong>' + name + '</strong>' +
        '<div class="meta">' + filename + ' · ' + bpm + ' BPM · ID ' + escapeHtml(song.song_number || '?') + '</div></div>' +
        '<button class="remove" data-filename="' + filename + '" data-name="' + name + '">Remove</button>' +
        '</div>';
    }).join('');

    Array.prototype.forEach.call(document.querySelectorAll('button.remove'), function (button) {
      button.addEventListener('click', function () { removeSong(button); });
    });
  }

  async function loadSongs() {
    try {
      var response = await fetch('/dev/song_imports', { credentials: 'same-origin' });
      var payload = await response.json();
      if (!response.ok || !payload.ok) throw new Error(payload.error || 'Could not load songs.');
      render(payload.songs || []);
      setStatus('Loaded ' + (payload.songs || []).length + ' user song(s).', 'good');
    } catch (error) {
      list.innerHTML = '<p>Could not load user songs.</p>';
      setStatus(error.message, 'bad');
    }
  }

  async function removeSong(button) {
    var filename = button.getAttribute('data-filename');
    var name = button.getAttribute('data-name') || filename;
    if (!window.confirm('Remove "' + name + '"?\n\nIts song.json and sound ZIP will be deleted from user_data.')) return;

    button.disabled = true;
    button.textContent = 'Removing…';

    try {
      var response = await fetch('/dev/song_imports/' + encodeURIComponent(filename), {
        method: 'DELETE',
        credentials: 'same-origin',
        headers: { 'X-Requested-With': 'XMLHttpRequest' }
      });
      var payload = await response.json();
      if (!response.ok || !payload.ok) throw new Error(payload.error || 'Remove failed.');

      var row = button.closest('.song');
      if (row) row.parentNode.removeChild(row);
      if (!document.querySelector('#userSongs .song')) {
        list.innerHTML = '<p>No user songs installed yet.</p>';
      }
      setStatus('Removed: ' + name + '. Reload Launchpad to refresh its song list.', 'good');
    } catch (error) {
      button.disabled = false;
      button.textContent = 'Remove';
      setStatus('REMOVE FAILED\n' + error.message, 'bad');
    }
  }

  loadSongs();
})();
