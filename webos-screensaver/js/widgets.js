/* Widget board for webOS 3.x (ES5).
   Places widgets where the Mac's layout editor put them and renders the data widgets
   (weather, world clock, events, now playing, prayer times, countdown, notes) plus the
   weather effects over the wallpaper. Live data comes from the Mac as `live`. */
var Widgets = (function () {
  'use strict';

  var IDS = {
    calendar: 'w-calendar', quote: 'quote-block', clock: 'w-clock', weather: 'w-weather', world: 'w-world',
    events: 'w-events', music: 'w-music', prayer: 'w-prayer', countdown: 'w-countdown', notes: 'w-notes'
  };
  var SCALES = [0.75, 1, 1.35];
  /* The original row: date, quote, clock centered near the bottom */
  var DEFAULT_BOARD = [
    { kind: 'calendar', x: 0.135, y: 0.673, size: 1 },
    { kind: 'quote', x: 0.28, y: 0.673, size: 1 },
    { kind: 'clock', x: 0.735, y: 0.673, size: 1 }
  ];
  var STORAGE_LIVE = 'ambient_live';
  var DAYS_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  var PRAYERS = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

  var el = {};
  var nodes = {};
  var on = {};
  var live = {};
  var cfg = { use24h: true, worldCity: 'London', countdowns: [], notes: { title: 'Notes', items: [] }, effects: true };
  var resolveUrl = function (u) { return u; };
  var lastMinute = -1;
  var fxKey = '';
  var artUrl = null;

  function $(id) { return document.getElementById(id); }
  function pad2(n) { return (n < 10 ? '0' : '') + n; }
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function fmtTime(h, m) {
    if (cfg.use24h) return pad2(h) + ':' + pad2(m);
    return (h % 12 === 0 ? 12 : h % 12) + ':' + pad2(m) + (h < 12 ? ' AM' : ' PM');
  }
  function fmtDate(d) { return fmtTime(d.getHours(), d.getMinutes()); }
  function nowSec() { return Math.floor(new Date().getTime() / 1000); }
  function midnight(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); }

  /* ---- Board ---- */

  function setScale(node, s) {
    node.style.webkitTransform = 'scale(' + s + ')';
    node.style.transform = 'scale(' + s + ')';
  }

  function applyBoard(board) {
    var list = board && board.length !== undefined ? board : DEFAULT_BOARD;
    var i, b, node, k, s;
    on = {};
    for (i = 0; i < list.length; i++) {
      b = list[i];
      node = nodes[b.kind];
      if (!node) continue;
      on[b.kind] = true;
      s = SCALES[b.size] || 1;
      node._scale = s;
      node.style.left = (b.x * 100) + '%';
      node.style.top = (b.y * 100) + '%';
      setScale(node, s);
    }
    for (k in nodes) {
      if (nodes.hasOwnProperty(k)) nodes[k].classList[on[k] ? 'remove' : 'add']('off');
    }
  }

  /* ---- Weather ---- */

  function category(code) {
    if (code === 0) return 'clear';
    if (code <= 2) return 'partly';
    if (code === 3) return 'cloudy';
    if (code === 45 || code === 48) return 'fog';
    if (code >= 51 && code <= 57) return 'drizzle';
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return 'rain';
    if ((code >= 71 && code <= 77) || code === 85 || code === 86) return 'snow';
    if (code >= 95) return 'thunder';
    return 'cloudy';
  }

  function describe(code, phase) {
    var c = category(code);
    if (c === 'clear') return { night: 'Clear', sunrise: 'Sunrise', sunset: 'Sunset' }[phase] || 'Sunny';
    if (code === 1) return phase === 'night' ? 'Mostly Clear' : 'Mostly Sunny';
    if (code === 65 || code === 82) return 'Heavy Rain';
    if (code === 80 || code === 81) return 'Showers';
    return { partly: 'Partly Cloudy', cloudy: 'Cloudy', fog: 'Fog', drizzle: 'Drizzle', rain: 'Rain',
      snow: 'Snow', thunder: 'Thunderstorm' }[c];
  }

  /* day / night / sunrise / sunset, from today's sunrise and sunset (±45 min around them) */
  function phase(w, now) {
    if (!w || !w.sunrise) {
      var h = new Date().getHours();
      return h >= 6 && h < 19 ? 'day' : 'night';
    }
    var d = Math.floor((now - w.sunrise + 43200) / 86400);
    var sr = w.sunrise + d * 86400;
    var ss = w.sunset + d * 86400;
    if (Math.abs(now - sr) < 2700) return 'sunrise';
    if (Math.abs(now - ss) < 2700) return 'sunset';
    return now > sr && now < ss ? 'day' : 'night';
  }

  /* Icons on a 64×64 grid */
  function sun(cx, cy, r) {
    var s = '<circle cx="' + cx + '" cy="' + cy + '" r="' + r + '" fill="#ffd60a"/>';
    var i, a, x1, y1, x2, y2;
    for (i = 0; i < 8; i++) {
      a = i * Math.PI / 4;
      x1 = cx + Math.cos(a) * (r + 4); y1 = cy + Math.sin(a) * (r + 4);
      x2 = cx + Math.cos(a) * (r + 9); y2 = cy + Math.sin(a) * (r + 9);
      s += '<line x1="' + x1.toFixed(1) + '" y1="' + y1.toFixed(1) + '" x2="' + x2.toFixed(1) + '" y2="' + y2.toFixed(1) +
        '" stroke="#ffd60a" stroke-width="3.5" stroke-linecap="round"/>';
    }
    return s;
  }
  function moon(cx, cy, r) {
    var ax = cx + r * 0.5, ay = cy - r * 0.866, bx = cx + r * 0.866, by = cy + r * 0.5;
    return '<path d="M' + ax.toFixed(1) + ' ' + ay.toFixed(1) + 'A' + r + ' ' + r + ' 0 1 0 ' + bx.toFixed(1) + ' ' + by.toFixed(1) +
      'A' + (r * 0.78).toFixed(1) + ' ' + (r * 0.78).toFixed(1) + ' 0 0 1 ' + ax.toFixed(1) + ' ' + ay.toFixed(1) + 'Z" fill="#f5f0c8"/>';
  }
  function cloud(dx, dy, s, fill) {
    return '<g transform="translate(' + dx + ' ' + dy + ') scale(' + s + ')"><path d="M18 50h28a11 11 0 0 0 1.5-21.9 15 15 0 0 0-28.9-3.6A12.5 12.5 0 0 0 18 50z" fill="' +
      (fill || '#fff') + '"/></g>';
  }
  function horizon(rising) {
    var s = '<path d="M17 44a15 15 0 0 1 30 0z" fill="#ff9f0a"/>';
    s += '<path d="M32 22v-6M18 30l-4-4M46 30l4-4" stroke="#ff9f0a" stroke-width="3.5" stroke-linecap="round"/>';
    s += '<line x1="6" y1="45" x2="58" y2="45" stroke="#fff" stroke-width="3" stroke-linecap="round"/>';
    s += rising
      ? '<path d="M32 61v-10M27 55l5-5 5 5" stroke="#fff" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
      : '<path d="M32 50v10M27 56l5 5 5-5" stroke="#fff" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/>';
    return s;
  }
  function drops(n, color) {
    var s = '', i, x;
    for (i = 0; i < n; i++) {
      x = 22 + i * (n === 2 ? 14 : 10);
      s += '<line x1="' + x + '" y1="48" x2="' + (x - 3) + '" y2="58" stroke="' + color + '" stroke-width="3.5" stroke-linecap="round"/>';
    }
    return s;
  }

  function icon(code, ph) {
    var c = category(code);
    var day = ph !== 'night';
    var s = '';
    if (c === 'clear') {
      if (ph === 'sunrise' || ph === 'sunset') s = horizon(ph === 'sunrise');
      else s = day ? sun(32, 32, 12) : moon(32, 32, 19);
    } else if (c === 'partly') {
      s = (day ? sun(23, 23, 9) : moon(22, 19, 13)) + cloud(12, 10, 0.8);
    } else if (c === 'cloudy') {
      s = cloud(-4, -8, 0.75, '#c7c7cc') + cloud(4, 2, 0.95);
    } else if (c === 'fog') {
      s = cloud(0, -10, 1, '#e5e5ea') + '<path d="M12 50h40M16 58h32" stroke="#c7c7cc" stroke-width="3.5" stroke-linecap="round"/>';
    } else {
      s = cloud(0, -10, 1, c === 'thunder' ? '#d1d1d6' : '#fff');
      if (c === 'drizzle') s += drops(2, '#64d2ff');
      else if (c === 'rain') s += drops(3, '#64d2ff');
      else if (c === 'snow') {
        s += '<circle cx="22" cy="51" r="3" fill="#fff"/><circle cx="34" cy="56" r="3" fill="#fff"/><circle cx="44" cy="50" r="3" fill="#fff"/>';
      } else if (c === 'thunder') {
        s += '<path d="M35 40l-10 13h8l-4 10 13-15h-8l4-8z" fill="#ffd60a"/>';
      }
    }
    return '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' + s + '</svg>';
  }

  function renderWeather(now) {
    var w = live.weather;
    var node = nodes.weather;
    if (!w) {
      el.wxCity.textContent = 'Weather';
      el.wxTemp.innerHTML = '--&deg;';
      el.wxIcon.innerHTML = '';
      el.wxDesc.textContent = '';
      el.wxHilo.textContent = 'Set your city in the Mac app';
      el.wxDays.innerHTML = '';
      el.wxSun.textContent = '';
      return;
    }
    var ph = phase(w, now);
    var c = category(w.code);
    node.classList[ph === 'night' ? 'add' : 'remove']('wx-night');
    node.classList[ph === 'sunrise' || ph === 'sunset' ? 'add' : 'remove']('wx-dusk');
    node.classList[ph === 'day' && c !== 'clear' && c !== 'partly' ? 'add' : 'remove']('wx-gray');
    el.wxCity.textContent = w.city;
    el.wxTemp.innerHTML = w.temp + '&deg;';
    el.wxIcon.innerHTML = icon(w.code, ph);
    el.wxDesc.textContent = describe(w.code, ph);
    el.wxHilo.innerHTML = 'H:' + w.hi + '&deg; L:' + w.lo + '&deg;';
    var h = '', i, d;
    for (i = 0; i < (w.days || []).length; i++) {
      d = w.days[i];
      h += '<div class="wx-day"><div>' + esc(d.d) + '</div><div class="ic">' + icon(d.code, 'day') + '</div><div>' +
        d.hi + '&deg;</div><div class="lo">' + d.lo + '&deg;</div></div>';
    }
    el.wxDays.innerHTML = h;
    el.wxSun.innerHTML = '&uarr; ' + fmtDate(new Date(w.sunrise * 1000)) + ' &nbsp; &darr; ' + fmtDate(new Date(w.sunset * 1000));
  }

  /* ---- Weather effects over the wallpaper ---- */

  function rnd(a, b) { return a + Math.random() * (b - a); }
  function anim(dur, delay) {
    return '-webkit-animation-duration:' + dur.toFixed(2) + 's;-webkit-animation-delay:-' + delay.toFixed(2) + 's;';
  }

  function renderFx(now) {
    var w = live.weather;
    var c = w ? category(w.code) : '';
    var ph = w ? phase(w, now) : '';
    var key = cfg.effects && w ? c + '|' + ph : '';
    if (key === fxKey) return;
    fxKey = key;
    var h = '', i, n, d;
    if (key) {
      if (ph === 'sunrise' || ph === 'sunset') h += '<div class="fx-glow ' + ph + '"></div>';
      else if (ph === 'day' && (c === 'clear' || c === 'partly')) h += '<div class="fx-glow day"></div>';
      if (ph === 'night' && (c === 'clear' || c === 'partly')) {
        for (i = 0; i < 36; i++) {
          h += '<i class="fx-star" style="left:' + rnd(0, 100).toFixed(1) + '%;top:' + rnd(0, 55).toFixed(1) + '%;' + anim(rnd(2.5, 6), rnd(0, 6)) + '"></i>';
        }
      }
      n = c === 'partly' ? 2 : (c === 'clear' ? 0 : 4);
      for (i = 0; i < n; i++) {
        d = rnd(110, 200);
        h += '<i class="fx-cloud" style="top:' + rnd(-4, 40).toFixed(1) + '%;' + anim(d, rnd(0, d)) + '"></i>';
      }
      if (c === 'fog') h += '<div class="fx-fog"></div>';
      if (c === 'rain' || c === 'drizzle' || c === 'thunder') {
        n = c === 'drizzle' ? 16 : 34;
        for (i = 0; i < n; i++) {
          d = c === 'drizzle' ? rnd(1.3, 1.8) : rnd(0.7, 1.05);
          h += '<i class="fx-drop" style="left:' + rnd(0, 106).toFixed(1) + '%;' + anim(d, rnd(0, d)) + '"></i>';
        }
      }
      if (c === 'thunder') h += '<div class="fx-flash"></div>';
      if (c === 'snow') {
        for (i = 0; i < 28; i++) {
          d = rnd(7, 13);
          h += '<i class="fx-flake" style="left:' + rnd(0, 100).toFixed(1) + '%;' + anim(d, rnd(0, d)) + '"></i>';
        }
      }
    }
    el.fx.innerHTML = h;
  }

  /* ---- World clock ---- */

  function renderWorld() {
    var off = live.worldOffsetSec;
    el.wcCity.textContent = cfg.worldCity;
    if (typeof off !== 'number') {
      el.wcTime.textContent = '--:--';
      el.wcDiff.textContent = '';
      return;
    }
    var now = new Date();
    var there = new Date(now.getTime() + off * 1000);
    el.wcTime.textContent = cfg.use24h
      ? pad2(there.getUTCHours()) + ':' + pad2(there.getUTCMinutes())
      : (there.getUTCHours() % 12 === 0 ? 12 : there.getUTCHours() % 12) + ':' + pad2(there.getUTCMinutes());
    var localOff = -now.getTimezoneOffset() * 60;
    var diff = (off - localOff) / 3600;
    var dayThere = Date.UTC(there.getUTCFullYear(), there.getUTCMonth(), there.getUTCDate());
    var dayHere = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
    var day = dayThere > dayHere ? 'Tomorrow' : (dayThere < dayHere ? 'Yesterday' : 'Today');
    var hrs = diff === 0 ? 'same time' : (diff > 0 ? '+' : '−') + Math.abs(diff) + (Math.abs(diff) === 1 ? ' hr' : ' hrs');
    el.wcDiff.textContent = day + ', ' + hrs + (cfg.use24h ? '' : (there.getUTCHours() < 12 ? ' · AM' : ' · PM'));
  }

  /* ---- Calendar events ---- */

  function eventWhen(e, now) {
    var s = new Date(e.start * 1000);
    var today = midnight(new Date());
    var day = midnight(s) <= today ? '' : (midnight(s) - today < 2 * 86400000 && midnight(s) - today >= 86400000 ? 'Tomorrow' : DAYS_SHORT[s.getDay()]);
    if (e.allDay) return (day ? day + ' · ' : '') + 'All day';
    if (e.start <= now) return 'Now · until ' + fmtDate(new Date(e.end * 1000));
    return (day ? day + ' ' : '') + fmtDate(s) + ' – ' + fmtDate(new Date(e.end * 1000));
  }

  function renderEvents(now) {
    var list = live.events;
    var h = '', i, e, shown = 0;
    if (!list) {
      el.evList.innerHTML = '<div class="ev-empty">Allow Calendar access in the Mac app</div>';
      return;
    }
    for (i = 0; i < list.length && shown < 3; i++) {
      e = list[i];
      if (e.end <= now) continue;
      shown++;
      h += '<div class="ev"><i style="background:' + esc(e.color || '#ff6b61') + '"></i><div><div class="ev-t">' + esc(e.title) +
        '</div><div class="ev-s">' + esc(eventWhen(e, now)) + '</div></div></div>';
    }
    el.evList.innerHTML = h || '<div class="ev-empty">No more events today</div>';
  }

  /* ---- Now Playing ---- */

  function mmss(s) {
    s = Math.max(0, Math.floor(s));
    return Math.floor(s / 60) + ':' + pad2(s % 60);
  }

  function renderMusic(now) {
    var m = live.music;
    if (!m) {
      nodes.music.classList.add('paused');
      el.muLabel.textContent = 'Now Playing';
      el.muTitle.textContent = 'Not Playing';
      el.muArtist.textContent = '';
      el.muPos.textContent = '';
      el.muDur.textContent = '';
      setBar(el.muBar, 0);
      setArt('');
      return;
    }
    nodes.music.classList[m.playing ? 'remove' : 'add']('paused');
    el.muLabel.textContent = m.playing ? 'Now Playing' : 'Paused';
    el.muTitle.textContent = m.title;
    el.muArtist.textContent = m.artist;
    var pos = Math.min(m.duration || 0, m.position + (m.playing ? now - m.at : 0));
    el.muPos.textContent = mmss(pos);
    el.muDur.textContent = m.duration ? '-' + mmss(m.duration - pos) : '';
    setBar(el.muBar, m.duration ? pos / m.duration : 0);
    setArt(m.art ? resolveUrl(m.art) : '');
  }

  function setArt(url) {
    if (url === artUrl) return;
    artUrl = url;
    el.muArt.style.backgroundImage = url ? 'url(' + url + ')' : '';
    el.muArt.innerHTML = url ? '' : '<svg viewBox="0 0 64 64"><path d="M26 44V18l22-5v26" stroke="#fff" stroke-opacity=".5" stroke-width="4" fill="none" stroke-linejoin="round"/>' +
      '<circle cx="20" cy="44" r="7" fill="#fff" fill-opacity=".5"/><circle cx="42" cy="39" r="7" fill="#fff" fill-opacity=".5"/></svg>';
  }

  function setBar(node, f) {
    node.style.webkitTransform = 'scaleX(' + f + ')';
    node.style.transform = 'scaleX(' + f + ')';
  }

  /* ---- Prayer times ---- */

  function renderPrayer() {
    var list = live.prayer;
    if (!list || !list.length) {
      el.prNext.textContent = 'Prayer Times';
      el.prIn.textContent = '';
      el.prList.innerHTML = '<div class="ev-empty">Set your city in the Mac app</div>';
      return;
    }
    var d = new Date();
    var nowMin = d.getHours() * 60 + d.getMinutes();
    var items = [], i, p, t, next = -1;
    for (i = 0; i < list.length; i++) {
      p = list[i];
      if (PRAYERS.indexOf(p.name) < 0) continue;
      t = parseInt(p.time.substr(0, 2), 10) * 60 + parseInt(p.time.substr(3, 2), 10);
      items.push({ name: p.name, min: t });
    }
    for (i = 0; i < items.length; i++) {
      if (items[i].min > nowMin) { next = i; break; }
    }
    var wrap = next < 0;
    if (wrap) next = 0;
    var left = items[next].min + (wrap ? 1440 : 0) - nowMin;
    el.prNext.textContent = items[next].name + ' ' + fmtTime(Math.floor(items[next].min / 60), items[next].min % 60);
    el.prIn.textContent = 'in ' + (left >= 60 ? Math.floor(left / 60) + 'h ' : '') + (left % 60) + 'm';
    var h = '';
    for (i = 0; i < items.length; i++) {
      h += '<div class="pr' + (i === next ? ' next' : '') + '"><div class="n">' + items[i].name + '</div><div class="t">' +
        fmtTime(Math.floor(items[i].min / 60), items[i].min % 60).replace(/ [AP]M$/, '') + '</div></div>';
    }
    el.prList.innerHTML = h;
  }

  /* ---- Countdown ---- */

  function renderCountdown() {
    var today = midnight(new Date());
    var best = null, bestDays = 0, i, c, parts, days;
    for (i = 0; i < cfg.countdowns.length; i++) {
      c = cfg.countdowns[i];
      parts = String(c.date).split('-');
      if (parts.length !== 3) continue;
      days = Math.round((new Date(+parts[0], +parts[1] - 1, +parts[2]).getTime() - today) / 86400000);
      if (days >= 0 && (best === null || days < bestDays)) { best = c; bestDays = days; }
    }
    if (!best) {
      el.cdTitle.textContent = 'Countdown';
      el.cdNum.className = 'cd-num';
      el.cdNum.innerHTML = '&ndash;';
      el.cdUnit.textContent = 'Add one in the Mac app';
      return;
    }
    el.cdTitle.textContent = best.title;
    el.cdNum.className = bestDays === 0 ? 'cd-num word' : 'cd-num';
    el.cdNum.textContent = bestDays === 0 ? 'Today' : bestDays;
    el.cdUnit.textContent = bestDays === 0 ? '' : (bestDays === 1 ? 'day to go' : 'days to go');
  }

  /* ---- Notes ---- */

  function renderNotes() {
    var items = [], i, h = '';
    for (i = 0; i < (cfg.notes.items || []).length; i++) {
      if (String(cfg.notes.items[i]).replace(/\s+/g, '')) items.push(cfg.notes.items[i]);
    }
    el.ntTitle.textContent = cfg.notes.title || 'Notes';
    for (i = 0; i < items.length && i < 4; i++) {
      h += '<div class="nt-item"><i></i>' + esc(items[i]) + '</div>';
    }
    if (items.length > 4) h += '<div class="nt-item">+' + (items.length - 4) + ' more</div>';
    el.ntList.innerHTML = h || '<div class="nt-item">Type notes in the Mac app</div>';
  }

  /* ---- Public ---- */

  function renderAll() {
    var now = nowSec();
    if (on.weather) renderWeather(now);
    if (on.world) renderWorld();
    if (on.events) renderEvents(now);
    if (on.music) renderMusic(now);
    if (on.prayer) renderPrayer();
    if (on.countdown) renderCountdown();
    if (on.notes) renderNotes();
    renderFx(now);
  }

  /* Every second from the main clock */
  function tick(date) {
    var now = Math.floor(date.getTime() / 1000);
    if (on.music) renderMusic(now);
    if (date.getMinutes() !== lastMinute) {
      lastMinute = date.getMinutes();
      renderAll();
    }
  }

  function setSettings(data) {
    cfg.use24h = data.use24h !== false;
    cfg.worldCity = (data.worldClock && data.worldClock.city) || 'London';
    cfg.countdowns = data.countdowns || [];
    cfg.notes = data.notes || { title: 'Notes', items: [] };
    cfg.effects = !data.weather || data.weather.effects !== false;
    applyBoard(data.board);
    fxKey = '-';
    renderAll();
  }

  function setLive(data) {
    var json = JSON.stringify(data || {});
    if (json === JSON.stringify(live)) return;
    live = data || {};
    try { localStorage.setItem(STORAGE_LIVE, json); } catch (e) { /* ignore */ }
    renderAll();
  }

  function init(resolver) {
    var k;
    resolveUrl = resolver;
    for (k in IDS) {
      if (IDS.hasOwnProperty(k)) nodes[k] = $(IDS[k]);
    }
    el.fx = $('fx');
    el.wxCity = $('wx-city'); el.wxTemp = $('wx-temp'); el.wxIcon = $('wx-icon'); el.wxDesc = $('wx-desc');
    el.wxHilo = $('wx-hilo'); el.wxDays = $('wx-days'); el.wxSun = $('wx-sun');
    el.wcCity = $('wc-city'); el.wcTime = $('wc-time'); el.wcDiff = $('wc-diff');
    el.evList = $('ev-list');
    el.muArt = $('mu-art'); el.muLabel = $('mu-label'); el.muTitle = $('mu-title'); el.muArtist = $('mu-artist');
    el.muBar = $('mu-bar'); el.muPos = $('mu-pos'); el.muDur = $('mu-dur');
    el.prNext = $('pr-next'); el.prIn = $('pr-in'); el.prList = $('pr-list');
    el.cdTitle = $('cd-title'); el.cdNum = $('cd-num'); el.cdUnit = $('cd-unit');
    el.ntTitle = $('nt-title'); el.ntList = $('nt-list');
    try { live = JSON.parse(localStorage.getItem(STORAGE_LIVE) || '{}') || {}; } catch (e) { live = {}; }
    applyBoard(null);
  }

  return {
    init: init,
    setSettings: setSettings,
    setLive: setLive,
    tick: tick
  };
})();
