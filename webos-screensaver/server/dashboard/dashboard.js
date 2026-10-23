(function () {
  'use strict';

  var state = null;
  var mediaItems = [];

  function $(id) { return document.getElementById(id); }

  function api(path, opts) {
    opts = opts || {};
    return fetch(path, opts).then(function (r) {
      return r.json().then(function (j) {
        if (!r.ok) throw new Error((j && j.error) || r.statusText);
        return j;
      });
    });
  }

  function setMsg(id, text, isError) {
    var el = $(id);
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (isError ? ' error' : '');
  }

  function refreshInfo() {
    api('/api/info').then(function (info) {
      $('lan-ip').textContent = info.lanIp || '?';
      $('instr-ip').textContent = info.lanIp || '?';
      $('lan-port').textContent = String(info.port || 8787);
    }).catch(function () {
      $('lan-ip').textContent = 'server error';
    });
  }

  function refreshState() {
    return api('/api/state').then(function (st) {
      state = st;
      $('opt-clock').checked = !!st.showClock;
      $('opt-date').checked = !!st.showDate;
      $('opt-quotes').checked = !!st.showQuotes;
      $('opt-interval').value = st.intervalSec || 30;
      var np = $('now-playing');
      if (st.media && st.media.name) {
        np.textContent = (st.media.type || 'file') + ': ' + st.media.name;
      } else {
        np.textContent = 'Local gradients / offline (no remote media selected)';
      }
      renderLibrary();
      renderPlaylistBuilder();
      return st;
    });
  }

  function refreshMedia() {
    return api('/api/media').then(function (res) {
      mediaItems = res.items || [];
      renderLibrary();
      renderPlaylistBuilder();
    });
  }

  function renderLibrary() {
    var box = $('library');
    if (!mediaItems.length) {
      box.textContent = 'No media yet — upload images or MP4 videos.';
      return;
    }
    box.innerHTML = '';
    var activeName = state && state.media ? state.media.name : '';
    mediaItems.forEach(function (item) {
      var card = document.createElement('div');
      card.className = 'media-card' + (item.name === activeName ? ' active' : '');
      var thumb = document.createElement('div');
      thumb.className = 'thumb';
      if (item.type === 'image') {
        var img = document.createElement('img');
        img.src = item.url;
        img.alt = item.name;
        thumb.appendChild(img);
      } else {
        thumb.textContent = 'VIDEO';
      }
      var meta = document.createElement('div');
      meta.className = 'meta';
      meta.innerHTML = '<div class="name" title="' + item.name + '">' + item.name + '</div>';
      var actions = document.createElement('div');
      actions.className = 'actions';

      var playBtn = document.createElement('button');
      playBtn.type = 'button';
      playBtn.className = 'btn btn-sm';
      playBtn.textContent = 'Show on TV';
      playBtn.onclick = function (e) {
        e.stopPropagation();
        selectMedia(item.name);
      };

      var delBtn = document.createElement('button');
      delBtn.type = 'button';
      delBtn.className = 'btn btn-sm btn-danger';
      delBtn.textContent = 'Delete';
      delBtn.onclick = function (e) {
        e.stopPropagation();
        if (!confirm('Delete ' + item.name + '?')) return;
        fetch('/api/media/' + encodeURIComponent(item.name), { method: 'DELETE' })
          .then(function (r) { return r.json(); })
          .then(function () { return Promise.all([refreshMedia(), refreshState()]); })
          .catch(function (err) { alert(err.message || err); });
      };

      actions.appendChild(playBtn);
      actions.appendChild(delBtn);
      meta.appendChild(actions);
      card.appendChild(thumb);
      card.appendChild(meta);
      card.onclick = function () { selectMedia(item.name); };
      box.appendChild(card);
    });
  }

  function renderPlaylistBuilder() {
    var box = $('playlist-builder');
    box.innerHTML = '';
    var selected = {};
    if (state && state.playlist) {
      state.playlist.forEach(function (p) { selected[p.name] = true; });
    }
    mediaItems.forEach(function (item) {
      var lab = document.createElement('label');
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.value = item.name;
      cb.checked = !!selected[item.name];
      cb.className = 'pl-check';
      lab.appendChild(cb);
      lab.appendChild(document.createTextNode(item.name + ' (' + item.type + ')'));
      box.appendChild(lab);
    });
  }

  function selectMedia(name) {
    api('/api/select', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: name })
    }).then(function () {
      setMsg('display-msg', 'Now showing: ' + name);
      return refreshState();
    }).catch(function (err) {
      setMsg('display-msg', err.message || String(err), true);
    });
  }

  function saveDisplay() {
    var body = {
      showClock: $('opt-clock').checked,
      showDate: $('opt-date').checked,
      showQuotes: $('opt-quotes').checked,
      intervalSec: parseInt($('opt-interval').value, 10) || 30
    };
    api('/api/state', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    }).then(function () {
      setMsg('display-msg', 'Display settings saved — TV picks up within a few seconds.');
      return refreshState();
    }).catch(function (err) {
      setMsg('display-msg', err.message || String(err), true);
    });
  }

  function clearMedia() {
    api('/api/clear-media', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
      .then(function () {
        setMsg('display-msg', 'Cleared. TV will use local backgrounds.');
        return refreshState();
      });
  }

  function uploadFiles() {
    var input = $('file-input');
    var files = input.files;
    if (!files || !files.length) {
      setMsg('upload-msg', 'Choose one or more files first.', true);
      return;
    }
    setMsg('upload-msg', 'Uploading…');
    var chain = Promise.resolve();
    Array.prototype.forEach.call(files, function (file) {
      chain = chain.then(function () {
        var fd = new FormData();
        fd.append('file', file, file.name);
        return fetch('/api/upload', { method: 'POST', body: fd }).then(function (r) {
          return r.json().then(function (j) {
            if (!r.ok) throw new Error(j.error || 'upload failed');
            return j;
          });
        });
      });
    });
    chain.then(function () {
      setMsg('upload-msg', 'Upload complete.');
      input.value = '';
      return Promise.all([refreshMedia(), refreshState()]);
    }).catch(function (err) {
      setMsg('upload-msg', err.message || String(err), true);
    });
  }

  function savePlaylist() {
    var checks = document.querySelectorAll('.pl-check');
    var names = [];
    Array.prototype.forEach.call(checks, function (cb) {
      if (cb.checked) names.push(cb.value);
    });
    api('/api/playlist', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ names: names, playlistIndex: 0 })
    }).then(function () {
      setMsg('playlist-msg', names.length ? 'Playlist saved (' + names.length + ' items).' : 'Playlist cleared.');
      return refreshState();
    }).catch(function (err) {
      setMsg('playlist-msg', err.message || String(err), true);
    });
  }

  $('btn-save-display').onclick = saveDisplay;
  $('btn-clear').onclick = clearMedia;
  $('btn-upload').onclick = uploadFiles;
  $('btn-save-playlist').onclick = savePlaylist;

  refreshInfo();
  Promise.all([refreshMedia(), refreshState()]);
  setInterval(function () {
    refreshState().catch(function () {});
  }, 5000);
})();
