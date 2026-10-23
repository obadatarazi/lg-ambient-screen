/* Ambient Screen — webOS 3.x compatible (ES5, XHR, no modules) */
(function () {
  'use strict';

  var STORAGE_IP = 'ambient_pc_ip';
  var STORAGE_PORT = 'ambient_pc_port';
  var STORAGE_PREFS = 'ambient_prefs';
  var STORAGE_SETTINGS = 'ambient_settings'; /* last settings from the Mac, used offline */
  var STORAGE_WALL = 'ambient_wall';         /* custom wallpaper cached as data URLs */
  var SETTING_KEYS = ['rev', 'showClock', 'showDate', 'showQuotes', 'intervalSec', 'widgets', 'wallpaper',
    'customWallpaper', 'brightness', 'use24h', 'clockOverMedia', 'night', 'quotes', 'clockStyle', 'board',
    'weather', 'worldClock', 'countdowns', 'notes', 'photoFrame', 'tint'];

  var BUILTIN_QUOTES = [
    { t: 'The only way to do great work is to love what you do.', a: 'Steve Jobs' },
    { t: 'Simplicity is the ultimate sophistication.', a: 'Leonardo da Vinci' },
    { t: 'Design is not just what it looks like. Design is how it works.', a: 'Steve Jobs' },
    { t: 'In the middle of every difficulty lies opportunity.', a: 'Albert Einstein' },
    { t: 'It does not matter how slowly you go as long as you do not stop.', a: 'Confucius' },
    { t: 'What we think, we become.', a: 'Buddha' },
    { t: 'The best time to plant a tree was 20 years ago. The second best time is now.', a: 'Chinese Proverb' },
    { t: 'Do what you can, with what you have, where you are.', a: 'Theodore Roosevelt' },
    { t: 'Happiness depends upon ourselves.', a: 'Aristotle' },
    { t: 'Everything you can imagine is real.', a: 'Pablo Picasso' },
    { t: 'Be yourself; everyone else is already taken.', a: 'Oscar Wilde' },
    { t: 'Life is what happens when you are busy making other plans.', a: 'John Lennon' },
    { t: 'The journey of a thousand miles begins with one step.', a: 'Lao Tzu' },
    { t: 'Stay hungry. Stay foolish.', a: 'Stewart Brand' },
    { t: 'We are what we repeatedly do. Excellence, then, is not an act but a habit.', a: 'Will Durant' },
    { t: 'The quieter you become, the more you can hear.', a: 'Ram Dass' },
    { t: 'Not all those who wander are lost.', a: 'J.R.R. Tolkien' },
    { t: 'Courage is grace under pressure.', a: 'Ernest Hemingway' },
    { t: 'Time you enjoy wasting is not wasted time.', a: 'Marthe Troly-Curtin' },
    { t: 'Act as if what you do makes a difference. It does.', a: 'William James' },
    { t: 'Wherever you go, go with all your heart.', a: 'Confucius' },
    { t: 'The future belongs to those who believe in the beauty of their dreams.', a: 'Eleanor Roosevelt' },
    { t: 'Less is more.', a: 'Ludwig Mies van der Rohe' },
    { t: 'Silence is a source of great strength.', a: 'Lao Tzu' },
    { t: 'Innovation distinguishes between a leader and a follower.', a: 'Steve Jobs' },
    { t: 'Well done is better than well said.', a: 'Benjamin Franklin' }
  ];
  var QUOTES = BUILTIN_QUOTES; /* replaced by custom quotes from the Mac app */

  var WALLPAPERS = [
    { img: 'images/bg1.jpg', glass: 'images/bg1-glass.jpg' },
    { img: 'images/bg2.jpg', glass: 'images/bg2-glass.jpg' },
    { img: 'images/bg3.jpg', glass: 'images/bg3-glass.jpg' },
    { img: 'images/bg5.jpg', glass: 'images/bg5-glass.jpg' },
    { img: 'images/bg6.jpg', glass: 'images/bg6-glass.jpg' },
    { img: 'images/bg4.jpg', glass: 'images/bg4-glass.jpg' },
    { img: 'images/bg7.jpg', glass: 'images/bg7-glass.jpg' },
    { img: 'images/bg8.jpg', glass: 'images/bg8-glass.jpg' },
    { img: 'images/bg9.jpg', glass: 'images/bg9-glass.jpg' }
  ];
  var NIGHT_WALLPAPER = 5; /* graphite */
  var WALL_EVERY_QUOTES = 4; /* change wallpaper every N quote rotations */

  var BRIGHTNESS = ['bright-low', 'bright-med', 'bright-high'];
  var BRIGHT_LABELS = ['Brightness: Low', 'Brightness: Medium', 'Brightness: High'];

  var DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  var MONTHS = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  /* webOS / Magic Remote keyCodes */
  var KEY = {
    LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40,
    ENTER: 13, BACK: 461, ESC: 27,
    RED: 403, GREEN: 404, YELLOW: 405, BLUE: 406,
    NUM1: 49, NUM1_PAD: 97
  };

  var state = {
    quoteIndex: 0,
    wallIndex: 0,
    brightIndex: 2,
    use24h: true,
    paused: false,
    helpOpen: false,
    setupOpen: false,
    usingWallA: true,
    rotations: 0,
    quoteTimer: null,
    pollTimer: null,
    clockTimer: null,
    frameTimer: null,
    frameSec: 0,
    playlistKey: '',
    driftTimer: null,
    quoteStartedAt: 0,
    night: null,
    nightCfg: { enabled: true, start: 23, end: 6 },
    wallMode: 'auto', /* auto | fixed | custom */
    custom: null,
    preview: false,
    lastRev: null,
    firstPoll: true,
    lastMsgId: null,
    lastCmdId: null,
    online: false,
    pcIp: '',
    pcPort: '8787',
    remote: {
      showClock: true,
      showDate: true,
      showQuotes: true,
      intervalSec: 30,
      media: null,
      playlist: [],
      playlistIndex: 0
    },
    lastMediaUrl: '',
    lastMediaType: ''
  };

  var el = {};

  function $(id) {
    return document.getElementById(id);
  }

  function pad2(n) {
    return (n < 10 ? '0' : '') + n;
  }

  /* ---- Preferences ---- */

  function loadPrefs() {
    try {
      var p = JSON.parse(localStorage.getItem(STORAGE_PREFS) || '{}');
      if (typeof p.wall === 'number') state.wallIndex = p.wall % WALLPAPERS.length;
      if (typeof p.bright === 'number') state.brightIndex = p.bright % BRIGHTNESS.length;
      if (typeof p.h24 === 'boolean') state.use24h = p.h24;
    } catch (e) { /* ignore */ }
  }

  function savePrefs() {
    try {
      localStorage.setItem(STORAGE_PREFS, JSON.stringify({
        wall: state.wallIndex, bright: state.brightIndex, h24: state.use24h
      }));
    } catch (e) { /* ignore */ }
  }

  /* ---- Dynamic Island ---- */

  function showStatus(msg, ms, kind) {
    Island.status(msg, ms, kind);
  }

  function setOnline(online) {
    if (online === state.online) return;
    state.online = online;
    if (online) {
      showStatus('Connected to PC', 3000, 'ok');
    } else if (state.pcIp) {
      showStatus('PC unavailable', 3000, 'warn');
    }
  }

  /* ---- Clock, calendar, analog dial ---- */

  function buildDial() {
    var i, t;
    for (i = 0; i < 60; i++) {
      t = document.createElement('div');
      t.className = i % 5 === 0 ? 'tick major' : 'tick';
      t.style.webkitTransform = 'rotate(' + (i * 6) + 'deg)';
      t.style.transform = 'rotate(' + (i * 6) + 'deg)';
      el.dial.insertBefore(t, el.dial.firstChild);
    }
  }

  function rotate(node, deg) {
    node.style.webkitTransform = 'rotate(' + deg + 'deg)';
    node.style.transform = 'rotate(' + deg + 'deg)';
  }

  function greeting(h) {
    if (h < 5) return 'Good Night';
    if (h < 12) return 'Good Morning';
    if (h < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  function updateClock() {
    var now = new Date();
    var h = now.getHours();
    var m = now.getMinutes();
    var s = now.getSeconds();

    var hh = h;
    if (!state.use24h) {
      hh = h % 12;
      if (hh === 0) hh = 12;
    }
    el.clock.textContent = (state.use24h ? pad2(hh) : hh) + ':' + pad2(m);
    el.date.textContent = DAYS[now.getDay()] + ', ' + MONTHS[now.getMonth()] + ' ' + now.getDate();

    el.calWeekday.textContent = DAYS[now.getDay()].toUpperCase();
    el.calDay.textContent = now.getDate();
    el.calMonth.textContent = MONTHS[now.getMonth()];
    el.greeting.textContent = greeting(h);

    el.dgTime.textContent = el.clock.textContent;
    el.dgLabel.textContent = state.use24h ? 'Local Time' : 'Local Time \u00b7 ' + (h < 12 ? 'AM' : 'PM');
    el.dgBar.style.webkitTransform = 'scaleX(' + (s / 59) + ')';
    el.dgBar.style.transform = 'scaleX(' + (s / 59) + ')';
    el.stH.textContent = state.use24h ? pad2(hh) : hh;
    el.stM.textContent = pad2(m);

    rotate(el.handH, (h % 12) * 30 + m * 0.5);
    rotate(el.handM, m * 6 + s * 0.1);
    rotate(el.handS, s * 6);

    updateNight(h);
    updateQuoteBar();
    Widgets.tick(now);
  }

  /* Auto-dim during night hours (default 23:00–06:00, set from the Mac app) */
  function updateNight(h) {
    var c = state.nightCfg;
    var night = c.enabled && (c.start > c.end ? (h >= c.start || h < c.end) : (h >= c.start && h < c.end));
    if (night === state.night) return;
    state.night = night;
    if (night) {
      document.body.classList.add('is-night');
      if (state.wallMode === 'auto') setWallpaper(NIGHT_WALLPAPER);
    } else {
      document.body.classList.remove('is-night');
    }
  }

  /* ---- Quotes ---- */

  function applyQuote(index) {
    state.quoteIndex = (index + QUOTES.length) % QUOTES.length;
    var q = QUOTES[state.quoteIndex];
    el.quoteBody.className = 'quote-body fading';
    setTimeout(function () {
      el.quoteText.textContent = q.t;
      el.quoteAuthor.textContent = q.a;
      el.quoteBody.className = 'quote-body';
    }, 450);
    state.quoteStartedAt = new Date().getTime();
    updateQuoteBar();
  }

  function nextQuote(dir) {
    applyQuote(state.quoteIndex + (dir || 1));
    pulse(el.quoteBlock);
  }

  function updateQuoteBar() {
    if (!el.quoteBar) return;
    var span = (state.remote.intervalSec || 30) * 1000;
    var f = state.paused ? 1 : Math.min(1, (new Date().getTime() - state.quoteStartedAt) / span);
    el.quoteBar.style.webkitTransform = 'scaleX(' + f + ')';
    el.quoteBar.style.transform = 'scaleX(' + f + ')';
  }

  /* springy "liquid" press: shrink a little from the widget's own size, then back */
  function pulse(node) {
    if (!node) return;
    var s = node._scale || 1;
    setScale(node, s * 0.965);
    setTimeout(function () { setScale(node, s); }, 130);
  }

  function setScale(node, s) {
    node.style.webkitTransform = 'scale(' + s + ')';
    node.style.transform = 'scale(' + s + ')';
  }

  /* ---- Wallpaper + Liquid Glass ---- */

  function buildDots() {
    var i, d;
    el.dots.innerHTML = '';
    for (i = 0; i < WALLPAPERS.length; i++) {
      d = document.createElement('span');
      d.className = 'dot';
      el.dots.appendChild(d);
    }
  }

  function setWallpaper(index) {
    state.wallIndex = (index + WALLPAPERS.length) % WALLPAPERS.length;
    var wp = state.custom || WALLPAPERS[state.wallIndex];
    var next = state.usingWallA ? el.wallB : el.wallA;
    var prev = state.usingWallA ? el.wallA : el.wallB;
    next.style.backgroundImage = 'url(' + wp.img + ')';
    next.className = 'wall active';
    prev.className = 'wall';
    state.usingWallA = !state.usingWallA;

    var i, glass = 'url(' + wp.glass + ')';
    for (i = 0; i < el.widgets.length; i++) {
      el.widgets[i].style.backgroundImage = glass;
    }
    alignGlass();

    var dots = el.dots.childNodes;
    for (i = 0; i < dots.length; i++) {
      dots[i].className = (!state.custom && i === state.wallIndex) ? 'dot on' : 'dot';
    }
  }

  /* Pin each widget's blurred wallpaper to screen coordinates so the glass
     shows exactly what is "behind" it (no backdrop-filter on webOS 3.x). */
  function alignGlass() {
    var W = window.innerWidth;
    var H = window.innerHeight;
    var i, r, s, node;
    for (i = 0; i < el.widgets.length; i++) {
      node = el.widgets[i];
      if (!node.offsetWidth) continue; /* not on the board */
      r = node.getBoundingClientRect();
      s = r.width / node.offsetWidth; /* widgets are scaled by their size setting */
      node.style.backgroundSize = (W / s) + 'px ' + (H / s) + 'px';
      node.style.backgroundPosition = (-r.left / s) + 'px ' + (-r.top / s) + 'px';
    }
  }

  function nextWallpaper() {
    state.custom = null;
    if (state.wallMode === 'custom') state.wallMode = 'fixed';
    setWallpaper(state.wallIndex + 1);
    savePrefs();
  }

  /* Shift content by a few pixels every minute to protect the panel */
  function drift() {
    var x = Math.round((Math.random() - 0.5) * 24);
    var y = Math.round((Math.random() - 0.5) * 16);
    el.content.style.webkitTransform = 'translate3d(' + x + 'px,' + y + 'px,0)';
    el.content.style.transform = 'translate3d(' + x + 'px,' + y + 'px,0)';
    setTimeout(alignGlass, 6200);
  }

  /* ---- Brightness / pause / help ---- */

  function applyBrightness(index, quiet) {
    state.brightIndex = (index + BRIGHTNESS.length) % BRIGHTNESS.length;
    var i;
    for (i = 0; i < BRIGHTNESS.length; i++) {
      document.body.classList.remove(BRIGHTNESS[i]);
    }
    document.body.classList.add(BRIGHTNESS[state.brightIndex]);
    if (!quiet) {
      showStatus(BRIGHT_LABELS[state.brightIndex]);
      savePrefs();
    }
  }

  function toggle24h() {
    state.use24h = !state.use24h;
    updateClock();
    savePrefs();
    showStatus(state.use24h ? '24-Hour Time' : '12-Hour Time');
  }

  function togglePause() {
    state.paused = !state.paused;
    if (state.paused) {
      document.body.classList.add('paused');
      clearRotateTimer();
      showStatus('Paused', 2000, 'warn');
    } else {
      document.body.classList.remove('paused');
      state.quoteStartedAt = new Date().getTime();
      scheduleRotate();
      showStatus('Resumed', 2000, 'ok');
    }
    updateQuoteBar();
  }

  function clearRotateTimer() {
    if (state.quoteTimer) {
      clearInterval(state.quoteTimer);
      state.quoteTimer = null;
    }
  }

  function scheduleRotate() {
    clearRotateTimer();
    if (state.paused) return;
    var sec = state.remote.intervalSec || 30;
    if (sec < 5) sec = 5;
    state.quoteStartedAt = new Date().getTime();
    state.quoteTimer = setInterval(function () {
      if (state.paused) return;
      if (state.remote.showQuotes !== false) applyQuote(state.quoteIndex + 1);
      state.rotations++;
      if (state.online && state.remote.playlist && state.remote.playlist.length > 1) {
        if (!state.frameSec) advancePlaylist(); /* otherwise the photo frame timer does it */
      } else if (state.wallMode === 'auto' && !state.night && state.rotations % WALL_EVERY_QUOTES === 0) {
        setWallpaper(state.wallIndex + 1);
      }
    }, sec * 1000);
  }

  /* Photo frame: playlists advance on their own timer (photoFrame.seconds) */
  function scheduleFrame() {
    if (state.frameTimer) {
      clearInterval(state.frameTimer);
      state.frameTimer = null;
    }
    if (state.frameSec <= 0) return;
    state.frameTimer = setInterval(function () {
      if (!state.paused && state.online && state.remote.playlist && state.remote.playlist.length > 1) advancePlaylist();
    }, state.frameSec * 1000);
  }

  function toggleHelp() {
    state.helpOpen = !state.helpOpen;
    el.help.className = state.helpOpen ? 'sheet-wrap' : 'sheet-wrap hidden';
  }

  /* ---- Setup / server ---- */

  function baseUrl() {
    if (!state.pcIp) return '';
    return 'http://' + state.pcIp + ':' + (state.pcPort || '8787');
  }

  function loadStoredServer() {
    try {
      state.pcIp = localStorage.getItem(STORAGE_IP) || '';
      state.pcPort = localStorage.getItem(STORAGE_PORT) || '8787';
    } catch (e) {
      state.pcIp = '';
      state.pcPort = '8787';
    }
  }

  function saveServer(ip, port) {
    state.pcIp = ip;
    state.pcPort = port || '8787';
    try {
      localStorage.setItem(STORAGE_IP, state.pcIp);
      localStorage.setItem(STORAGE_PORT, state.pcPort);
    } catch (e) { /* ignore */ }
  }

  function openSetup() {
    state.setupOpen = true;
    el.setup.className = 'sheet-wrap';
    el.setupIp.value = state.pcIp || '192.168.1.103';
    el.setupPort.value = state.pcPort || '8787';
    el.setupMsg.textContent = '';
    el.setupMsg.className = 'alert-msg';
    el.help.className = 'sheet-wrap hidden';
    state.helpOpen = false;
    try {
      el.setupIp.focus();
    } catch (e) { /* TV may ignore */ }
  }

  function closeSetup() {
    state.setupOpen = false;
    el.setup.className = 'sheet-wrap hidden';
    try { el.setupIp.blur(); el.setupPort.blur(); } catch (e) { /* ignore */ }
  }

  function saveSetupFromForm() {
    var ip = String(el.setupIp.value).replace(/\s+/g, '');
    var port = String(el.setupPort.value).replace(/\s+/g, '') || '8787';
    if (!ip) {
      el.setupMsg.textContent = 'Please enter an IP address.';
      el.setupMsg.className = 'alert-msg error';
      return;
    }
    saveServer(ip, port);
    el.setupMsg.textContent = 'Connecting…';
    el.setupMsg.className = 'alert-msg';
    pollOnce(function (ok) {
      if (ok) {
        el.setupMsg.textContent = 'Connected';
        el.setupMsg.className = 'alert-msg ok';
        setTimeout(closeSetup, 600);
        startPolling();
      } else {
        el.setupMsg.textContent = 'Could not reach the server. Check the IP, firewall, and that it is running.';
        el.setupMsg.className = 'alert-msg error';
      }
    });
  }

  function xhrGet(url, timeoutMs, cb) {
    var xhr;
    try {
      xhr = new XMLHttpRequest();
    } catch (e) {
      cb(false, null);
      return;
    }
    var done = false;
    var timer = setTimeout(function () {
      if (done) return;
      done = true;
      try { xhr.abort(); } catch (e2) { /* ignore */ }
      cb(false, null);
    }, timeoutMs || 4000);

    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      if (xhr.status >= 200 && xhr.status < 300) {
        var data = null;
        try {
          data = JSON.parse(xhr.responseText);
        } catch (e3) {
          cb(false, null);
          return;
        }
        cb(true, data);
      } else {
        cb(false, null);
      }
    };
    try {
      xhr.open('GET', url, true);
      xhr.send(null);
    } catch (e4) {
      if (!done) {
        done = true;
        clearTimeout(timer);
        cb(false, null);
      }
    }
  }

  function pollOnce(cb) {
    var base = baseUrl();
    if (!base) {
      if (cb) cb(false);
      return;
    }
    xhrGet(base + '/api/state?t=' + (new Date().getTime()), 4000, function (ok, data) {
      if (ok && data) {
        state.pollFailures = 0;
        applyRemoteState(data);
        setOnline(true);
        if (cb) cb(true);
      } else {
        /* one missed poll on busy Wi-Fi should not blank a photo or screen share */
        state.pollFailures = (state.pollFailures || 0) + 1;
        if (state.pollFailures >= 3) {
          setOnline(false);
          clearRemoteMedia();
        }
        if (cb) cb(false);
      }
    });
  }

  function startPolling() {
    stopPolling();
    if (!baseUrl()) return;
    pollOnce(null);
    state.pollTimer = setInterval(function () {
      pollOnce(null);
    }, 3000);
  }

  function stopPolling() {
    if (state.pollTimer) {
      clearInterval(state.pollTimer);
      state.pollTimer = null;
    }
  }

  function applyRemoteState(data) {
    if (!data) return;
    if (typeof data.showClock === 'boolean') state.remote.showClock = data.showClock;
    if (typeof data.showDate === 'boolean') state.remote.showDate = data.showDate;
    if (typeof data.showQuotes === 'boolean') state.remote.showQuotes = data.showQuotes;
    if (typeof data.intervalSec === 'number' && data.intervalSec > 0 &&
        state.remote.intervalSec !== data.intervalSec) {
      state.remote.intervalSec = data.intervalSec;
      if (!state.paused) scheduleRotate();
    }

    if (typeof data.rev === 'number') {
      /* Mac app: settings only re-apply when they change, so remote-key tweaks stick */
      if (data.rev !== state.lastRev) {
        state.lastRev = data.rev;
        applySettings(data);
      }
      handleEvents(data);
      Island.timer(data.activity || null);
      if (data.live) Widgets.setLive(data.live);
    } else {
      /* legacy Python server */
      setClass('hide-clock', !state.remote.showClock);
      setClass('hide-date', !state.remote.showDate);
      setClass('hide-quotes', !state.remote.showQuotes);
    }

    /* keep our own place in a playlist; only start over when the Mac sends a different one */
    var list = data.playlist || [];
    var key = '', i;
    for (i = 0; i < list.length; i++) key += list[i].url + '|';
    if (key !== state.playlistKey) {
      state.playlistKey = key;
      state.remote.playlistIndex = typeof data.playlistIndex === 'number' ? data.playlistIndex : 0;
    }
    state.remote.playlist = list;

    var media = data.media || null;
    if (!media && state.remote.playlist.length) {
      media = state.remote.playlist[state.remote.playlistIndex % state.remote.playlist.length];
    }
    state.remote.media = media;
    if (media && media.url) {
      showRemoteMedia(media);
    } else {
      state.endedUrl = '';
      clearRemoteMedia();
    }
  }

  function setClass(name, on) {
    document.body.classList[on ? 'add' : 'remove'](name);
  }

  function applySettings(data) {
    var w = data.widgets || {};
    setClass('hide-clock', data.showClock === false);
    setClass('hide-date', data.showDate === false);
    setClass('hide-quotes', data.showQuotes === false);
    setClass('hide-dots', w.dots === false);
    setClass('tint-warm', data.tint === 'warm');
    setClass('corner-clock', !!(data.photoFrame && data.photoFrame.cornerClock));
    applyClockStyle(data.clockStyle);
    var frameSec = data.photoFrame && data.photoFrame.seconds > 0 ? Math.max(5, data.photoFrame.seconds) : 0;
    if (frameSec !== state.frameSec) {
      state.frameSec = frameSec;
      scheduleFrame();
    }
    setClass('face-digital', w.clockFace === 'digital');
    setClass('face-stacked', w.clockFace === 'stacked');
    orderWidgets(w.order);
    if (typeof data.clockOverMedia === 'boolean') setClass('media-no-clock', !data.clockOverMedia);
    if (typeof data.use24h === 'boolean') state.use24h = data.use24h;
    if (typeof data.brightness === 'number') applyBrightness(data.brightness, true);

    if (data.night) {
      state.nightCfg = {
        enabled: data.night.enabled !== false,
        start: typeof data.night.start === 'number' ? data.night.start : 23,
        end: typeof data.night.end === 'number' ? data.night.end : 6
      };
      state.night = null; /* force re-evaluation */
    }

    var oldLen = QUOTES.length;
    QUOTES = (data.quotes && data.quotes.length) ? data.quotes : BUILTIN_QUOTES;
    if (QUOTES.length !== oldLen) applyQuote(0);

    var cw = data.customWallpaper;
    state.custom = (cw && cw.url) ? customWallpaper(cw) : null;
    if (state.custom) {
      state.wallMode = 'custom';
    } else {
      if (typeof data.wallpaper === 'number' && data.wallpaper >= 0) {
        state.wallMode = 'fixed';
        state.wallIndex = data.wallpaper % WALLPAPERS.length;
      } else {
        state.wallMode = 'auto';
      }
    }
    setWallpaper(state.wallIndex);
    savePrefs();
    saveSettings(data);
    Widgets.setSettings(data);
    updateClock();
    setTimeout(alignGlass, 60);
  }

  /* Big clock: position from the layout editor, size, weight and colour */
  function applyClockStyle(cs) {
    cs = cs || {};
    el.clockBlock.style.left = ((typeof cs.x === 'number' ? cs.x : 0.5) * 100) + '%';
    el.clockBlock.style.top = ((typeof cs.y === 'number' ? cs.y : 0.11) * 100) + '%';
    el.clock.className = 'lock-time size-' + (typeof cs.size === 'number' ? cs.size : 1);
    el.clock.style.fontWeight = cs.weight || 600;
    var m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(cs.color || '#ffffff');
    var rgb = m ? parseInt(m[1], 16) + ',' + parseInt(m[2], 16) + ',' + parseInt(m[3], 16) : '255,255,255';
    /* backgroundImage, not background: the shorthand would reset the text clip */
    el.clock.style.backgroundImage = '-webkit-linear-gradient(top, rgb(' + rgb + ') 35%, rgba(' + rgb + ',0.74) 100%)';
  }

  /* Re-append the widgets in the Mac's order (e.g. ['clock','calendar','quote']) */
  function orderWidgets(order) {
    var ids = { calendar: 'w-calendar', quote: 'quote-block', clock: 'w-clock' };
    var i, node;
    if (!order || !order.length) return;
    for (i = 0; i < order.length; i++) {
      node = ids[order[i]] && $(ids[order[i]]);
      if (node) el.widgetRow.appendChild(node);
    }
  }

  /* ---- Offline persistence ---- */

  function saveSettings(data) {
    var o = {};
    var i;
    for (i = 0; i < SETTING_KEYS.length; i++) {
      if (data[SETTING_KEYS[i]] !== undefined) o[SETTING_KEYS[i]] = data[SETTING_KEYS[i]];
    }
    try {
      localStorage.setItem(STORAGE_SETTINGS, JSON.stringify(o));
    } catch (e) { /* ignore */ }
  }

  function loadSettings() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_SETTINGS) || 'null');
    } catch (e) {
      return null;
    }
  }

  /* Custom wallpaper: use the cached copy if we have one, otherwise load it from
     the Mac and cache it so it keeps working when the Mac is away. */
  function customWallpaper(cw) {
    var cached = null;
    try {
      cached = JSON.parse(localStorage.getItem(STORAGE_WALL) || 'null');
    } catch (e) { /* ignore */ }
    if (cached && cached.key === cw.url && cached.img) {
      return { img: cached.img, glass: cached.glass || cached.img };
    }
    if (!baseUrl()) return null;
    var wp = { img: mediaAbsoluteUrl(cw.url), glass: mediaAbsoluteUrl(cw.glass || cw.url) };
    cacheWallpaper(cw.url, wp);
    return wp;
  }

  function cacheWallpaper(key, wp) {
    toDataUrl(wp.img, function (img) {
      if (!img) {
        /* Mac unreachable and nothing cached: fall back to the built-in wallpapers */
        if (state.custom === wp) {
          state.custom = null;
          state.wallMode = 'auto';
          setWallpaper(state.wallIndex);
        }
        return;
      }
      toDataUrl(wp.glass, function (glass) {
        try {
          localStorage.setItem(STORAGE_WALL, JSON.stringify({ key: key, img: img, glass: glass || img }));
        } catch (e) { /* storage full: keep using the network copy */ }
      });
    });
  }

  function toDataUrl(url, cb) {
    var im = new Image();
    im.crossOrigin = 'anonymous';
    im.onload = function () {
      try {
        var c = document.createElement('canvas');
        c.width = im.naturalWidth;
        c.height = im.naturalHeight;
        c.getContext('2d').drawImage(im, 0, 0);
        cb(c.toDataURL('image/jpeg', 0.85));
      } catch (e) {
        cb(null);
      }
    };
    im.onerror = function () { cb(null); };
    im.src = url;
  }

  /* One-shot messages and commands from the Mac app. The first poll only records
     the current ids so old events are not replayed when the TV app starts. */
  function handleEvents(data) {
    var msg = data.message;
    var cmd = data.command;
    if (state.firstPoll) {
      state.firstPoll = false;
      state.lastMsgId = msg ? msg.id : null;
      state.lastCmdId = cmd ? cmd.id : null;
      return;
    }
    if (msg && msg.id !== state.lastMsgId) {
      state.lastMsgId = msg.id;
      Island.notify(msg);
    }
    if (cmd && cmd.id !== state.lastCmdId) {
      state.lastCmdId = cmd.id;
      runCommand(cmd.action);
    }
  }

  function runCommand(action) {
    switch (action) {
      case 'nextWallpaper': nextWallpaper(); break;
      case 'nextQuote': nextQuote(1); scheduleRotate(); break;
      case 'prevQuote': nextQuote(-1); scheduleRotate(); break;
      case 'togglePause': togglePause(); break;
      case 'brightness': applyBrightness(state.brightIndex + 1); break;
      case 'help': toggleHelp(); break;
    }
  }

  function advancePlaylist() {
    if (!state.remote.playlist || state.remote.playlist.length < 2) return;
    state.remote.playlistIndex = (state.remote.playlistIndex + 1) % state.remote.playlist.length;
    var media = state.remote.playlist[state.remote.playlistIndex];
    if (media) showRemoteMedia(media);
  }

  function mediaAbsoluteUrl(pathOrUrl) {
    if (!pathOrUrl) return '';
    if (pathOrUrl.indexOf('http://') === 0 || pathOrUrl.indexOf('https://') === 0) {
      return pathOrUrl;
    }
    var base = baseUrl();
    if (!base) return '';
    if (pathOrUrl.charAt(0) === '/') return base + pathOrUrl;
    return base + '/' + pathOrUrl;
  }

  function showRemoteMedia(media) {
    var url = mediaAbsoluteUrl(media.url || media.path || '');
    var type = media.type || '';
    if (!url) return;
    if (url === state.lastMediaUrl && type === state.lastMediaType) return;
    if (url === state.endedUrl) return; /* finished video still listed by the Mac */

    state.lastMediaUrl = url;
    state.lastMediaType = type;
    document.body.classList.add('media-active');
    el.mediaLayer.className = 'media-layer';

    var isYouTube = type === 'youtube';
    var isScreen = type === 'screen' || isYouTube;
    var isVideo = !isScreen && (type === 'video' || /\.(mp4|webm|m4v)(\?|$)/i.test(url));
    setClass('screen-active', isScreen);
    stopScreen();
    if (isScreen) {
      el.mediaImage.className = 'media-image';
      el.mediaImage.removeAttribute('src');
      try { el.mediaVideo.pause(); } catch (e0) { /* ignore */ }
      el.mediaVideo.removeAttribute('src');
      el.mediaVideo.className = 'media-video';
      startScreen(url, isYouTube ? 'vod' : 'live');
    } else if (isVideo) {
      el.mediaImage.className = 'media-image';
      el.mediaImage.removeAttribute('src');
      el.mediaVideo.className = 'media-video visible';
      try { el.mediaVideo.pause(); } catch (e) { /* ignore */ }
      el.mediaVideo.src = url;
      try {
        el.mediaVideo.load();
        var p = el.mediaVideo.play();
        if (p && typeof p.then === 'function') {
          p.then(function () {}, function () {});
        }
      } catch (e2) { /* ignore */ }
    } else {
      try { el.mediaVideo.pause(); } catch (e3) { /* ignore */ }
      el.mediaVideo.removeAttribute('src');
      el.mediaVideo.className = 'media-video';
      el.mediaImage.className = 'media-image visible';
      el.mediaImage.src = url;
    }
  }

  /* ---- Streamed video: screen share (live) and YouTube (vod) ----
     The Mac sends H.264 in fragmented-MP4 segments; Media Source Extensions hand them to the
     TV's hardware decoder. 'live' long-polls the newest segment and chases the live edge;
     'vod' fetches segments in order from the start and ends cleanly. Both carry sound.
     Live requests report how fast the last segment downloaded and how often playback had to
     jump, so the Mac can pick a bitrate this Wi-Fi can carry (Auto quality). */
  var share = { on: false, url: '', mode: 'live', gen: 0, ms: null, sb: null, queue: [], seq: 0, next: 0,
    ended: false, xhr: null, watchdog: null, lastT: -1, stalls: 0, marks: [], dl: 0, size: 0, jumps: 0,
    target: 1.8, shiftAt: 0, calmSince: 0 };
  var LIVE_MIN = 1.5;
  var LIVE_MAX = 3;

  /* The TV's hardware player stops when it reaches the newest data and does not resume on
     its own. Once a second: if playback is stuck (or drifting too far behind), jump to a
     segment start (always a keyframe) about 2 s before the newest frame. Segment starts are
     recorded as the buffered end after each append. */
  function screenWatchdog() {
    var v = el.screenVideo;
    var b = v.buffered;
    if (!share.on || !b || !b.length) return;
    var start = b.start(b.length - 1);
    var end = b.end(b.length - 1);
    var t = v.currentTime;
    share.stalls = (t === share.lastT && end - t > 0.5) ? share.stalls + 1 : 0;
    share.lastT = t;
    if (share.mode === 'vod') {
      if (share.ended && !share.queue.length && end - t < 0.4) {
        vodFinished();
      } else if (share.stalls >= 2 && end - t > 2) {
        /* stuck with data ahead: re-seek to the last keyframe at or before the playhead */
        share.stalls = 0;
        var back = start;
        var k;
        for (k = 0; k < share.marks.length; k++) {
          if (share.marks[k] <= t && share.marks[k] > back) back = share.marks[k];
        }
        try { v.currentTime = Math.max(back, t - 0.01); v.play(); } catch (e0) { /* ignore */ }
      }
      return;
    }
    if (share.stalls >= 2 || end - t > 5 || t < start) {
      if (share.stalls >= 2) {
        /* ran dry: keep a bigger margin for a while (see catchUp) */
        share.target = Math.min(LIVE_MAX, share.target + 0.5);
        share.calmSince = share.shiftAt = Date.now();
      }
      share.stalls = 0;
      share.jumps++;
      try {
        var target = start;
        var i;
        for (i = 0; i < share.marks.length; i++) {
          if (share.marks[i] >= start && share.marks[i] <= end - 1.5 && share.marks[i] > target) target = share.marks[i];
        }
        v.currentTime = target;
        v.play();
      } catch (e) { /* ignore */ }
    }
  }

  function shareUrl(path, extra) {
    var parts = share.url.split('?');
    return parts[0] + path + '?' + (parts[1] || '') + (extra ? '&' + extra : '');
  }

  function startScreen(url, mode) {
    share.on = true;
    share.url = url;
    share.mode = mode || 'live';
    share.gen++;
    share.seq = 0;
    share.next = 0;
    share.ended = false;
    share.queue = [];
    share.sb = null;
    var gen = share.gen;
    var v = el.screenVideo;
    var ms;
    try {
      ms = new MediaSource();
    } catch (e) {
      showStatus('Screen share is not supported on this TV', 4000, 'warn');
      return;
    }
    share.ms = ms;
    ms.addEventListener('sourceopen', function () {
      if (gen !== share.gen) return;
      try {
        share.sb = ms.addSourceBuffer(share.mode === 'vod'
          ? 'video/mp4; codecs="avc1.640028, mp4a.40.2"'
          : 'video/mp4; codecs="avc1.4d4028, mp4a.40.2"');
      } catch (e) {
        restartScreen(gen);
        return;
      }
      share.sb.addEventListener('updateend', function () {
        if (gen !== share.gen) return;
        keepLive();
        pumpAppend();
      }, false);
      share.sb.addEventListener('error', function () { restartScreen(gen); }, false);
      fetchInit(gen);
    }, false);
    v.className = 'screen-video visible';
    v.volume = 1;
    v.onended = function () { if (share.mode === 'vod') vodFinished(); };
    v.src = URL.createObjectURL(ms);
    applyShareSound();
    share.lastT = -1;
    share.stalls = 0;
    share.marks = [];
    share.dl = 0;
    share.size = 0;
    share.jumps = 0;
    share.target = 1.8;
    share.calmSince = share.shiftAt = Date.now();
    clearInterval(share.watchdog);
    share.watchdog = setInterval(screenWatchdog, 1000);
  }

  function stopScreen() {
    if (!share.on) return;
    share.on = false;
    share.gen++;
    clearInterval(share.watchdog);
    if (share.xhr) {
      try { share.xhr.abort(); } catch (e) { /* ignore */ }
    }
    share.xhr = null;
    share.sb = null;
    share.queue = [];
    var v = el.screenVideo;
    try { v.pause(); } catch (e2) { /* ignore */ }
    v.removeAttribute('src');
    try { v.load(); } catch (e3) { /* ignore */ }
    v.className = 'screen-video';
  }

  function restartScreen(gen) {
    if (gen !== share.gen || !share.on) return;
    var url = share.url;
    stopScreen();
    var mode = share.mode;
    setTimeout(function () {
      if (state.lastMediaUrl === url && !share.on) startScreen(url, mode);
    }, 1500);
  }

  function xhrBinary(url, timeoutMs, cb) {
    var xhr = new XMLHttpRequest();
    share.xhr = xhr;
    xhr.open('GET', url, true);
    xhr.responseType = 'arraybuffer';
    xhr.timeout = timeoutMs;
    /* Download time runs from the first byte, so the long-poll wait is not counted */
    var firstByte = 0;
    xhr.onreadystatechange = function () {
      if (xhr.readyState === 2 && !firstByte) firstByte = Date.now();
    };
    xhr.onload = function () {
      var ok = xhr.status === 200;
      if (ok && firstByte) {
        share.dl = Date.now() - firstByte;
        share.size = xhr.response ? xhr.response.byteLength : 0;
      }
      cb(xhr.status, ok ? xhr.response : null, parseInt(xhr.getResponseHeader('X-Seq') || '0', 10),
        xhr.getResponseHeader('X-End') === '1');
    };
    xhr.onerror = xhr.ontimeout = function () { cb(0, null, 0); };
    xhr.send(null);
  }

  function fetchInit(gen) {
    xhrBinary(shareUrl('/init.mp4'), 6000, function (status, buf) {
      if (gen !== share.gen) return;
      if (status === 200 && buf) {
        enqueue(buf);
        fetchSegment(gen);
      } else {
        setTimeout(function () { if (gen === share.gen) fetchInit(gen); }, 800);
      }
    });
  }

  function fetchSegment(gen) {
    if (share.mode === 'vod') {
      fetchVodSegment(gen);
      return;
    }
    var v = el.screenVideo;
    var b = v.buffered;
    var ahead = b && b.length ? b.end(b.length - 1) - v.currentTime : 0;
    xhrBinary(shareUrl('/seg', 'after=' + share.seq + '&dl=' + share.dl + '&sz=' + share.size +
      '&j=' + share.jumps + '&ahead=' + ahead.toFixed(2)), 9000, function (status, buf, seq) {
      if (gen !== share.gen) return;
      if (status === 200 && buf) {
        share.seq = seq;
        enqueue(buf);
        fetchSegment(gen);
      } else if (status === 204) {
        fetchSegment(gen);
      } else {
        setTimeout(function () { if (gen === share.gen) fetchSegment(gen); }, 1000);
      }
    });
  }

  /* In order from the first segment; the Mac holds a request until that segment is ready */
  function fetchVodSegment(gen) {
    xhrBinary(shareUrl('/seg', 'n=' + share.next), 12000, function (status, buf, seq, end) {
      if (gen !== share.gen) return;
      if (status === 200 && buf) {
        share.next++;
        enqueue(buf);
        fetchVodSegment(gen);
      } else if (end) {
        share.ended = true;
        finishStream();
      } else if (status === 204) {
        fetchVodSegment(gen);
      } else {
        setTimeout(function () { if (gen === share.gen) fetchVodSegment(gen); }, 1000);
      }
    });
  }

  /* All segments appended: tell the decoder there is no more data so the video can end */
  function finishStream() {
    if (!share.ended || share.queue.length || !share.sb || share.sb.updating) return;
    try {
      if (share.ms.readyState === 'open') share.ms.endOfStream();
    } catch (e) { /* ignore */ }
  }

  function vodFinished() {
    if (!share.on || share.mode !== 'vod') return;
    state.endedUrl = state.lastMediaUrl; /* the Mac may still list it; don't replay */
    clearRemoteMedia();
    showStatus('Video finished', 2500);
  }

  function enqueue(buf) {
    share.queue.push(buf);
    pumpAppend();
  }

  function pumpAppend() {
    var sb = share.sb;
    if (!sb || sb.updating) return;
    if (!share.queue.length) {
      finishStream();
      return;
    }
    try {
      sb.appendBuffer(share.queue.shift());
    } catch (e) {
      restartScreen(share.gen);
    }
  }

  /* YouTube and screen share play through the TV speakers. The Mac app's preview is always
     silent so the sound never comes out of the Mac. Re-applied after loading because the TV's
     player can reset it. */
  function applyShareSound() {
    var v = el.screenVideo;
    var want = !!state.preview;
    if (v.muted !== want) v.muted = want;
  }

  /* Start playback and drop old video to save memory */
  function keepLive() {
    var v = el.screenVideo;
    var b = v.buffered;
    if (!b || !b.length) return;
    applyShareSound();
    var mark = b.end(b.length - 1);
    if (share.marks[share.marks.length - 1] !== mark) {
      if (!share.marks.length) share.marks.push(b.start(0));
      share.marks.push(mark);
      if (share.marks.length > 12) share.marks.shift();
    }
    if (v.paused) {
      try { v.play(); } catch (e2) { /* ignore */ }
    } else if (share.mode === 'live') {
      catchUp(b);
    }
    var sb = share.sb;
    if (sb && !sb.updating && v.currentTime - b.start(0) > 30) {
      try { sb.remove(0, v.currentTime - 15); } catch (e3) { /* ignore */ }
    }
  }

  /* The TV's player only starts (or resumes after a jump) with ~3.5 s of video stored, and it
     ignores playbackRate, but once playing it is fine with much less. So new segments are
     placed earlier on the timeline (timestampOffset), replacing stored video that has not been
     shown yet: the picture skips ahead once, without pausing, and then runs ~2 s closer to live.
     After a stall the margin grows; it shrinks again after a calm minute. */
  function catchUp(b) {
    var v = el.screenVideo;
    var now = Date.now();
    if (v.readyState < 3 || now - share.shiftAt < 5000) return;
    if (share.target > LIVE_MIN && now - share.calmSince > 60000) {
      share.target = Math.max(LIVE_MIN, share.target - 0.25);
      share.calmSince = now;
    }
    var skip = Math.round((b.end(b.length - 1) - v.currentTime - share.target) * 10) / 10;
    if (skip < 0.5) return;
    try {
      share.sb.timestampOffset -= skip;
      share.shiftAt = now;
    } catch (e) { /* ignore */ }
  }

  function clearRemoteMedia() {
    if (!state.lastMediaUrl) return;
    state.lastMediaUrl = '';
    state.lastMediaType = '';
    document.body.classList.remove('media-active');
    setClass('screen-active', false);
    stopScreen();
    el.mediaLayer.className = 'media-layer hidden';
    el.mediaImage.className = 'media-image';
    el.mediaImage.removeAttribute('src');
    try { el.mediaVideo.pause(); } catch (e) { /* ignore */ }
    el.mediaVideo.removeAttribute('src');
    el.mediaVideo.className = 'media-video';
    setTimeout(alignGlass, 50);
  }

  /* ---- Input ---- */

  function onKey(ev) {
    var code = ev.keyCode || ev.which;

    if (state.setupOpen) {
      if (code === KEY.RED) {
        saveSetupFromForm();
      } else if (code === KEY.BACK || code === KEY.ESC || code === KEY.GREEN) {
        closeSetup();
      } else {
        return; /* let the inputs handle typing */
      }
      if (ev.preventDefault) ev.preventDefault();
      return;
    }

    if (code === KEY.NUM1 || code === KEY.NUM1_PAD) {
      openSetup();
      if (ev.preventDefault) ev.preventDefault();
      return;
    }

    if (state.helpOpen) {
      if (code === KEY.BACK || code === KEY.ESC || code === KEY.ENTER) {
        toggleHelp();
        if (ev.preventDefault) ev.preventDefault();
      }
      return;
    }

    switch (code) {
      case KEY.LEFT:
        nextQuote(-1);
        break;
      case KEY.RIGHT:
      case KEY.GREEN:
        nextQuote(1);
        break;
      case KEY.UP:
      case KEY.RED:
        nextWallpaper();
        break;
      case KEY.DOWN:
      case KEY.BLUE:
        applyBrightness(state.brightIndex + 1);
        break;
      case KEY.YELLOW:
        toggle24h();
        break;
      case KEY.ENTER:
        togglePause();
        break;
      case KEY.BACK:
      case KEY.ESC:
        toggleHelp();
        break;
      default:
        return;
    }
    if (code === KEY.LEFT || code === KEY.RIGHT || code === KEY.GREEN) scheduleRotate();
    if (ev.preventDefault) ev.preventDefault();
  }

  function cacheEls() {
    el.clock = $('clock');
    el.clockBlock = $('clock-block');
    el.date = $('date');
    el.calWeekday = $('cal-weekday');
    el.calDay = $('cal-day');
    el.calMonth = $('cal-month');
    el.greeting = $('greeting');
    el.quoteText = $('quote-text');
    el.quoteAuthor = $('quote-author');
    el.quoteBody = $('quote-body');
    el.quoteBlock = $('quote-block');
    el.quoteBar = $('quote-bar');
    el.dial = $('dial');
    el.handH = $('hand-h');
    el.handM = $('hand-m');
    el.handS = $('hand-s');
    el.dgTime = $('dg-time');
    el.dgLabel = $('dg-label');
    el.dgBar = $('dg-bar');
    el.stH = $('st-h');
    el.stM = $('st-m');
    el.widgetRow = $('widgets');
    el.wallA = $('wall-a');
    el.wallB = $('wall-b');
    el.content = $('content');
    el.dots = $('dots');
    el.help = $('help');
    el.setup = $('setup');
    el.setupIp = $('setup-ip');
    el.setupPort = $('setup-port');
    el.setupMsg = $('setup-msg');
    el.mediaLayer = $('media-layer');
    el.mediaImage = $('media-image');
    el.mediaVideo = $('media-video');
    el.screenVideo = $('screen-video');
    el.widgets = document.querySelectorAll('.widget');
  }

  function init() {
    cacheEls();
    Island.init();
    Widgets.init(mediaAbsoluteUrl);
    loadStoredServer();
    loadPrefs();

    $('setup-save').onclick = saveSetupFromForm;
    $('setup-skip').onclick = closeSetup;

    buildDial();
    buildDots();
    applyBrightness(state.brightIndex, true);
    setWallpaper(state.wallIndex);
    applyQuote(Math.floor(Math.random() * QUOTES.length));

    updateClock();
    state.clockTimer = setInterval(updateClock, 1000);
    state.driftTimer = setInterval(drift, 60000);
    scheduleRotate();

    document.addEventListener('keydown', onKey, false);
    window.addEventListener('resize', alignGlass, false);

    /* Fonts change widget metrics slightly once loaded */
    setTimeout(alignGlass, 800);

    /* Last settings from the Mac, so the TV looks right even when the Mac is away */
    var saved = loadSettings();
    if (saved) {
      state.lastRev = saved.rev;
      applySettings(saved);
    }

    /* The Mac app passes its address (and settings) as launch parameters, or ?server= in its preview */
    var server = urlServer();
    var params = launchParams();
    if (state.preview) {
      clearInterval(state.driftTimer);
    } else {
      setTimeout(function () {
        /* don't cover a message that arrived with the launch */
        if (!Island.isBusy()) showStatus('Press Back for controls', 3500);
      }, 1200);
    }
    /* Settings pushed from the Mac over Wi-Fi while the app is already open */
    document.addEventListener('webOSRelaunch', function (ev) {
      ingestPush(ev.detail || {});
    }, false);

    if (server) {
      useServer(server);
    } else if (params.server || params.ambient) {
      ingestPush(params);
    } else if (state.pcIp) {
      startPolling();
    }
  }

  function urlServer() {
    var m = /[?&]server=([^&]+)/.exec(location.search);
    if (/[?&]preview=1/.test(location.search)) state.preview = true;
    return m ? decodeURIComponent(m[1]) : '';
  }

  function launchParams() {
    try {
      if (window.PalmSystem && window.PalmSystem.launchParams) {
        return JSON.parse(window.PalmSystem.launchParams) || {};
      }
    } catch (e) { /* ignore */ }
    return {};
  }

  /* params = { server: "mac-ip:port", ambient: <same document as /api/state> } */
  function ingestPush(p) {
    if (p.server) {
      var parts = String(p.server).split(':');
      saveServer(parts[0], parts[1] || '8787');
    }
    if (p.ambient) {
      state.firstPoll = false; /* a push is live: show its message / run its command */
      applyRemoteState(p.ambient);
    }
    if (p.server) startPolling();
  }

  function useServer(server) {
    var parts = String(server).split(':');
    saveServer(parts[0], parts[1] || '8787');
    state.firstPoll = true;
    startPolling();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, false);
  } else {
    init();
  }
})();
