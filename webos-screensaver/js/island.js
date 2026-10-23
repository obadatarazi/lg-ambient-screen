/* Dynamic Island for webOS 3.x (ES5).
   One black shape that morphs between four states, like the iPhone:
     hidden    — nothing on screen
     mini      — one-line status pill ("Brightness: High")
     compact   — live activity: icon on the left, countdown on the right
     expanded  — notification card: round colour icon, title, message
   Notifications queue up; a running timer stays in the compact pill between them. */
var Island = (function () {
  'use strict';

  var ICONS = {
    bell: '<path d="M6 16v-5a6 6 0 0 1 12 0v5l1.6 2.2H4.4z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
    message: '<path d="M4 5.5h16v10.5H9.5L5 20v-4H4z"/>',
    timer: '<circle cx="12" cy="13.5" r="7"/><path d="M12 13.5V9.5M10 2.8h4M17.8 7.2l1.4-1.4"/>',
    home: '<path d="M3.5 11.2L12 4.5l8.5 6.7V20h-5.6v-5.6H9.1V20H3.5z"/>',
    food: '<path d="M7 3v18M4.6 3v4.6a2.4 2.4 0 0 0 4.8 0V3M17 21V3c-2.6 1.6-3.4 5.4-3 9h3"/>',
    heart: '<path d="M12 20.2s-7.5-4.6-7.5-10.4A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 7.5 2.6c0 5.8-7.5 10.4-7.5 10.4z"/>',
    star: '<path d="M12 3.2l2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 17l-5.4 2.9 1.1-6.1-4.5-4.2 6.1-.8z"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.4v.2"/>',
    phone: '<path d="M5.5 3.5h3.6l1.8 4.7-2.3 1.5a11 11 0 0 0 5.7 5.7l1.5-2.3 4.7 1.8v3.6a2 2 0 0 1-2.1 2A16.5 16.5 0 0 1 3.5 5.6a2 2 0 0 1 2-2.1z"/>',
    car: '<path d="M4.5 16.5v-4.2l2.2-5.3h10.6l2.2 5.3v4.2zM4.5 12.3h15"/><circle cx="8" cy="16.6" r="1.6"/><circle cx="16" cy="16.6" r="1.6"/>',
    moon: '<path d="M19.5 14.6A8 8 0 1 1 9.4 4.5a6.5 6.5 0 0 0 10.1 10.1z"/>',
    gift: '<path d="M4.5 11h15v9h-15zM3.5 7.5h17V11h-17zM12 7.5V20M12 7.5c-1-3.4-5.2-3.6-5.2-1.4 0 1.6 5.2 1.4 5.2 1.4zm0 0c1-3.4 5.2-3.6 5.2-1.4 0 1.6-5.2 1.4-5.2 1.4z"/>',
    play: '<path d="M8 5.5v13l10.5-6.5z"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>'
  };

  var el = {};
  var queue = [];
  var showing = null;      /* notification currently expanded */
  var holdTimer = null;
  var miniTimer = null;
  var activity = null;     /* { id, title, end } running timer */
  var STORAGE = 'ambient_activity';

  function svg(name, cls) {
    return '<svg class="' + (cls || 'isl-svg') + '" viewBox="0 0 24 24">' + (ICONS[name] || ICONS.bell) + '</svg>';
  }

  function init() {
    el.root = document.getElementById('island');
    el.lead = document.getElementById('isl-lead');
    el.trail = document.getElementById('isl-trail');
    el.mini = document.getElementById('isl-mini');
    el.miniDot = document.getElementById('isl-mini-dot');
    el.icon = document.getElementById('isl-icon');
    el.title = document.getElementById('isl-title');
    el.text = document.getElementById('isl-text');
    el.side = document.getElementById('isl-side');
    el.lead.innerHTML = svg('timer');
    restoreActivity();
    setInterval(tick, 500);
    settle();
  }

  function setState(s) {
    el.root.className = 'island ' + s;
  }

  /* Where the island rests when nothing is being announced */
  function settle() {
    if (showing) return;
    if (queue.length) {
      next();
    } else if (activity) {
      renderTimer();
      setState('compact');
    } else {
      setState('hidden');
    }
  }

  /* ---- Notifications ---- */

  function notify(n) {
    queue.push({
      title: n.title || '',
      text: n.text || '',
      icon: ICONS[n.icon] ? n.icon : 'bell',
      color: /^#[0-9a-fA-F]{3,8}$/.test(n.color || '') ? n.color : '#0a84ff',
      seconds: Math.max(3, Math.min(30, n.seconds || 6))
    });
    if (!showing) next();
  }

  function next() {
    var n = queue.shift();
    if (!n) {
      settle();
      return;
    }
    showing = n;
    clearTimeout(miniTimer);
    el.icon.style.backgroundColor = n.color;
    el.icon.innerHTML = svg(n.icon);
    el.title.textContent = n.title || n.text;
    el.text.textContent = n.title ? n.text : '';
    el.text.style.display = n.title && n.text ? '' : 'none';
    el.side.textContent = 'now';
    setState('expanded');
    clearTimeout(holdTimer);
    holdTimer = setTimeout(function () {
      showing = null;
      /* collapse first, then show whatever is next */
      setState(activity ? 'compact' : 'hidden');
      if (activity) renderTimer();
      holdTimer = setTimeout(settle, queue.length ? 650 : 0);
    }, n.seconds * 1000);
  }

  /* ---- Mini status pill ---- */

  function status(text, ms, kind) {
    if (showing) return; /* never cover a notification */
    el.mini.textContent = text;
    el.miniDot.className = 'isl-mini-dot' + (kind ? ' ' + kind : '');
    setState('mini');
    clearTimeout(miniTimer);
    miniTimer = setTimeout(settle, ms || 2200);
  }

  /* ---- Live activity: timer ---- */

  function timer(a) {
    if (!a) {
      if (activity) {
        activity = null;
        save();
        settle();
      }
      return;
    }
    if (activity && activity.id === a.id) return;
    activity = { id: a.id, title: a.title || 'Timer', end: new Date().getTime() + a.durationSec * 1000 };
    save();
    renderTimer();
    if (!showing) setState('compact');
  }

  function tick() {
    if (!activity) return;
    var left = activity.end - new Date().getTime();
    if (left <= 0) {
      var title = activity.title;
      activity = null;
      save();
      notify({ title: title, text: 'Time’s up', icon: 'timer', color: '#ff9f0a', seconds: 12 });
      return;
    }
    renderTimer();
  }

  function renderTimer() {
    if (!activity) return;
    var s = Math.max(0, Math.ceil((activity.end - new Date().getTime()) / 1000));
    var h = Math.floor(s / 3600);
    var m = Math.floor((s % 3600) / 60);
    var sec = s % 60;
    el.trail.textContent = (h ? h + ':' + (m < 10 ? '0' : '') : '') + m + ':' + (sec < 10 ? '0' : '') + sec;
  }

  function save() {
    try {
      if (activity) localStorage.setItem(STORAGE, JSON.stringify(activity));
      else localStorage.removeItem(STORAGE);
    } catch (e) { /* ignore */ }
  }

  function restoreActivity() {
    try {
      var a = JSON.parse(localStorage.getItem(STORAGE) || 'null');
      if (a && a.end > new Date().getTime()) activity = a;
    } catch (e) { /* ignore */ }
  }

  function currentActivityId() {
    return activity ? activity.id : null;
  }

  return {
    init: init,
    notify: notify,
    status: status,
    timer: timer,
    activityId: currentActivityId,
    isBusy: function () { return !!showing; }
  };
})();
