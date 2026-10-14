/*
 * JEVANS.CLOUD — public access television for an audience of whoever shows up.
 *
 * Everything you'd want to change lives in CONFIG. The rest is a tiny
 * 40x24 character-screen renderer: channels are lists of colored text rows
 * plus chunky block graphics drawn on a 2x3 grid per character cell.
 */
(() => {
  'use strict';

  // Assembled at runtime so the address never appears whole in the source,
  // which is what spam harvesters scan for.
  const EMAIL = ['evansjack36', 'gmail.com'].join('@');

  const CONFIG = {
    // Where Jellyfin will live once it's set up. The status light polls
    // <url>/System/Info/Public, which Jellyfin serves without a login.
    jellyfin: {
      url: 'https://media.jevans.cloud',
    },

    // Each row either opens `url` or, with `copy`, copies that text to the
    // clipboard. Up to 8 entries. Keep names <= 10 characters and handles
    // <= 22 so they fit the 40-column screen.
    socials: [
      { name: 'GITHUB',    handle: '@scjevans',             url: 'https://github.com/scjevans' },
      { name: 'INSTAGRAM', handle: '@jevans2206',           url: 'https://www.instagram.com/jevans2206/' },
      { name: 'YOUTUBE',   handle: '@realjevans',           url: 'https://www.youtube.com/@realjevans' },
      { name: 'STEAM',     handle: 'scjevans',              url: 'https://steamcommunity.com/id/scjevans/' },
      { name: 'DISCORD',   handle: '.jevans',               copy: '.jevans' },
      { name: 'EMAIL',     handle: EMAIL,                   copy: EMAIL },
    ],

    // How often to re-check the media server, in seconds.
    pollEvery: 60,
  };

  /* ------------------------------------------------------------------ */
  /* Grid + text primitives                                              */
  /* ------------------------------------------------------------------ */

  const COLS = 40;
  const ROWS = 24;
  const ASPECT = 1.22; // cell height / cell width
  const MAX_ASPECT = 2.4; // rows may stretch this far; past it VT323 starts to squash
  const GLYPH = 1.02;  // font-size / row height

  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  const s = (text, fg = 'w', bg = null, o = {}) => ({ text: String(text), fg, bg, ...o });
  const row = (segs, o = {}) => ({ segs: [].concat(segs), ...o });
  const pad = (str, n) => (str.length >= n ? str.slice(0, n) : str + ' '.repeat(n - str.length));
  const padL = (str, n) => (str.length >= n ? str.slice(0, n) : ' '.repeat(n - str.length) + str);
  const two = (n) => String(n).padStart(2, '0');

  // Text in a black box, centered: how on-screen captions and cards look.
  const boxed = (text, fg = 'w', o = {}) => {
    const t = ' ' + text + ' ';
    return row([s(' '.repeat(Math.max(0, Math.floor((COLS - t.length) / 2)))), s(t, fg, 'k', o.hot ? { hot: true } : {})], o);
  };

  // "Label ........... 03" with the channel number as the hover target.
  const leader = (label, ch, fg = 'w') => {
    const left = ' ' + label + ' ';
    const num = ' ' + two(ch) + ' ';
    return row([s(left, fg), s('.'.repeat(COLS - left.length - num.length), 'b'), s(num, 'y', null, { hot: true })], { ch });
  };

  // Double-height title band.
  const title = (rows, text, fg, bg) => {
    rows[1] = row(s(' ' + text, fg, bg), { dh: true, bg });
  };

  const band = (rows, from, to, bg) => {
    for (let r = from; r <= to; r++) rows[r] = rows[r] || row([], { bg });
  };

  const host = (url) => {
    try { return new URL(url).host.toUpperCase(); } catch { return url.toUpperCase(); }
  };

  /* ------------------------------------------------------------------ */
  /* Block graphics                                                      */
  /* ------------------------------------------------------------------ */

  // A bitmap is an array of strings; each char is a color letter or '.'.
  // Every character cell holds 2x3 of these blocks.
  const blocks = (bitmap) => {
    const h = bitmap.length;
    const w = Math.max(...bitmap.map((l) => l.length));
    const cols = Math.ceil(w / 2);
    const rows = Math.ceil(h / 3);
    let out = '';
    bitmap.forEach((line, y) => {
      // merge horizontal runs so contiguous blocks don't seam
      let x = 0;
      while (x < line.length) {
        const ch = line[x];
        if (ch === '.' || ch === ' ') { x++; continue; }
        let end = x + 1;
        while (end < line.length && line[end] === ch) end++;
        out += `<rect class="m${ch}" x="${x}" y="${y}" width="${end - x + 0.04}" height="1.04"/>`;
        x = end;
      }
    });
    return { cols, rows, svg: `<svg class="gfx" viewBox="0 0 ${cols * 2} ${rows * 3}" preserveAspectRatio="none" shape-rendering="crispEdges" aria-hidden="true">${out}</svg>` };
  };

  const FONT = {
    J: ['#####', '...#.', '...#.', '...#.', '...#.', '#..#.', '.##..'],
    E: ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
    V: ['#...#', '#...#', '#...#', '#...#', '.#.#.', '.#.#.', '..#..'],
    A: ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    N: ['#...#', '#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#'],
    S: ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
  };

  // Big blocky lettering with a drop shadow, built from the 5x7 font above.
  const bigText = (str, { scale = 2, gap = 2, fg = 'y', shadow = 'r' } = {}) => {
    const step = 5 * scale + gap;
    const W = str.length * step - gap + 1;
    const H = 7 * scale + 1;
    const g = Array.from({ length: H }, () => Array(W).fill('.'));
    const plot = (ox, oy, c) => [...str].forEach((ch, i) => {
      FONT[ch].forEach((line, y) => [...line].forEach((p, x) => {
        if (p !== '#') return;
        for (let sy = 0; sy < scale; sy++) for (let sx = 0; sx < scale; sx++) {
          g[oy + y * scale + sy][ox + i * step + x * scale + sx] = c;
        }
      }));
    });
    if (shadow) plot(1, 1, shadow);
    plot(0, 0, fg);
    return g.map((r) => r.join(''));
  };

  const LOGO = blocks(bigText('JEVANS'));

  const BELL = [
    '....mmmmmm....',
    '..mmmmmmmmmm..',
    '.mmmmmmmmmmmm.',
    'mmm..mmmm..mmm',
    'mmm..mmmm..mmm',
    'mmmmmmmmmmmmmm',
    'mmmmmmmmmmmmmm',
    'mm.mm.mm.mm.mm',
  ];
  const TENT_A = [
    '..c..c..c..c..', '..c..c..c..c..', '...c..c..c..c.', '...c..c..c..c.',
    '..c..c..c..c..', '..c..c..c..c..', '.c..c..c..c...', '.c..c..c..c...',
    '..c..c..c..c..',
  ];
  const TENT_B = [
    '..c..c..c..c..', '..c..c..c..c..', '.c..c..c..c...', '.c..c..c..c...',
    '..c..c..c..c..', '..c..c..c..c..', '...c..c..c..c.', '...c..c..c..c.',
    '..c..c..c..c..',
  ];
  const BLANK = '..............';
  const JELLY = [
    blocks([BLANK, BLANK, ...BELL, ...TENT_A, BLANK]),
    blocks([BLANK, ...BELL, ...TENT_B, BLANK, BLANK]),
  ];

  /* ------------------------------------------------------------------ */
  /* Live state                                                          */
  /* ------------------------------------------------------------------ */

  const HOME = 2;
  const SURF = [2, 3, 4, 5, 99]; // what channel up/down cycles through

  const state = {
    ch: HOME,
    buffer: '',     // digits typed so far
    cc: false,      // closed captions
    ccLine: 0,
    copied: null,   // text most recently copied, for the COPIED flash
    status: { state: CONFIG.jellyfin.url ? 'checking' : 'unset' },
  };

  const statusLabel = () => {
    switch (state.status.state) {
      case 'online':   return s(' ON AIR ', 'k', 'g');
      case 'offline':  return s(' OFF AIR ', 'w', 'r');
      case 'checking': return s(' TUNING ', 'k', 'y', { flash: true });
      default:         return s(' NO SIGNAL ', 'k', 'w');
    }
  };

  /* ------------------------------------------------------------------ */
  /* Channels                                                            */
  /* ------------------------------------------------------------------ */

  const chGuide = () => {
    const rows = {};
    band(rows, 1, 7, 'b');
    rows[8] = row([s(' PUBLIC ACCESS TELEVISION', 'c'), s(padL('EST 2026 ', 14), 'b')]);
    rows[10] = row(s(' MOSTLY MOVIES. SOME LINKS.', 'y'), { dh: true });
    rows[13] = row(s(' A home media server, and the places'));
    rows[14] = row(s(' you can find me online.'));
    rows[16] = row([s(pad(' CHANNEL GUIDE', 37), 'k', 'c'), s('CH ', 'k', 'c')], { bg: 'c' });
    rows[17] = leader('Media server', 3);
    rows[18] = leader('Socials & contact', 4);
    rows[19] = leader('About this channel', 5);
    rows[20] = leader('Color bars', 99);
    const brief = { online: 'Tune in', offline: 'Back soon', checking: 'Searching' }[state.status.state] || '';
    rows[22] = row([s(' MEDIA SERVER ', 'c'), statusLabel(), s(' ' + brief + ' '), s('03', 'y', null, { hot: true })], { ch: 3 });
    return { section: 'y', rows, gfx: [{ r: 2, c: 2, art: LOGO }] };
  };

  const chMedia = () => {
    const rows = {};
    const st = state.status;
    const url = CONFIG.jellyfin.url;
    band(rows, 1, 2, 'r');
    title(rows, 'MEDIA SERVER', 'w', 'r');

    rows[4] = row([s(pad('', 10)), s('STATUS  ', 'c'), statusLabel()]);
    if (st.state === 'online') {
      rows[5] = row([s(pad('', 10)), s('NAME    ', 'c'), s((st.name || 'Jellyfin').slice(0, 22))]);
      rows[6] = row([s(pad('', 10)), s('VERSION ', 'c'), s((st.version || '?').slice(0, 22))]);
    } else {
      const [a, b] = {
        offline: ['Not broadcasting yet.', 'Check back soon.'],
        checking: ['Looking for a signal...', ''],
      }[st.state] || ['No server configured.', ''];
      rows[5] = row([s(pad('', 10)), s(a)]);
      rows[6] = row([s(pad('', 10)), s(b, 'b')]);
    }
    rows[8] = row([s(pad('', 10)), s('ADDRESS', 'c')]);
    rows[9] = row([s(pad('', 10)), s(host(url).slice(0, 30), 'y')]);

    rows[12] = row([s(pad('  >> OPEN JELLYFIN', 34), 'k', 'y'), s('WATCH ', 'k', 'y')], { href: url, bg: 'y', cls: 'btn' });
    rows[14] = row(state.copied === url
      ? s('  COPIED TO CLIPBOARD', 'g')
      : [s('  COPY SERVER ADDRESS ', 'w'), s('.'.repeat(13), 'b'), s(' >> ', 'y', null, { hot: true })],
    { copy: url });

    rows[16] = row(s(' GET THE APP', 'c'));
    rows[17] = row(s(' Android, iPhone, Apple TV, Fire TV,'));
    rows[18] = row(s(' Roku, desktop and the web. Paste the'));
    rows[19] = row(s(' address above when the app asks.'));
    rows[21] = row([s(' JELLYFIN.ORG/DOWNLOADS ', 'w'), s('.'.repeat(12), 'b'), s(' >> ', 'y', null, { hot: true })],
      { href: 'https://jellyfin.org/downloads/' });
    rows[23] = row(s(' No account yet? Ask me for an invite.', 'm'));

    return { section: 'r', rows, gfx: [{ r: 4, c: 1, frames: JELLY, every: 650 }] };
  };

  const chLinks = () => {
    const rows = {};
    band(rows, 1, 3, 'g');
    title(rows, 'ELSEWHERE', 'k', 'g');
    rows[3] = row(s(padL('LINKS & SOCIALS ', COLS), 'k', 'g'), { bg: 'g' });
    rows[5] = row([s(pad(' SERVICE', 12), 'w'), s(pad('HANDLE', 24), 'w')], { bg: 'b' });

    const list = CONFIG.socials.slice(0, 8);
    list.forEach((x, i) => {
      const live = !!(x.url || x.copy);
      const copied = x.copy && state.copied === x.copy;
      const end = copied ? s(' COPIED', 'g') : s(x.copy ? 'COPY ' : ' >> ', live ? 'y' : 'b', null, { hot: live });
      const segs = [
        s(' ' + pad(x.name, 11), live ? 'y' : 'c'),
        s(pad(x.handle, copied ? 21 : 23), 'w'),
        live ? end : s(' -- ', 'b'),
      ];
      rows[7 + i * 2] = row(segs, x.url ? { href: x.url } : x.copy ? { copy: x.copy } : {});
    });

    if (!list.some((x) => x.url || x.copy)) {
      rows[Math.min(7 + list.length * 2, 22)] = row(s(' Links are being wired up. Stand by.', 'g'));
    }
    return { section: 'g', rows };
  };

  const chAbout = () => {
    const rows = {};
    band(rows, 1, 2, 'c');
    title(rows, 'ABOUT THIS CHANNEL', 'k', 'c');
    rows[4] = row(s(' A public access channel for whoever'));
    rows[5] = row(s(' happens to tune in. Built like an 80s'));
    rows[6] = row(s(' cable info channel: forty columns,'));
    rows[7] = row(s(' eight colors, not one photograph.'));

    rows[9] = row(s(' HOW TO WATCH', 'y'));
    rows[10] = row([s(' > ', 'g'), s('Punch in a channel number')]);
    rows[11] = row([s(' > ', 'g'), s('Colored keys jump between channels')]);
    rows[12] = row([s(' > ', 'g'), s('Arrow keys surf up and down')]);
    rows[13] = row([s(' > ', 'g'), s('Press '), s('C', 'y'), s(' for closed captions')]);

    rows[15] = row(s(' TODAY\'S QUESTION', 'm'));
    rows[16] = row(s(' What does a home server do all day?'));
    rows[17] = row(s(' Turn on captions for the answer.', 'b'));
    return { section: 'c', rows };
  };

  // SMPTE-style color bars, near enough with eight colors.
  const chBars = () => {
    const rows = {};
    const W = [6, 6, 6, 6, 5, 6, 5];
    const bars = (colors) => row(colors.map((c, i) => s(' '.repeat(W[i]), 'w', c)));
    for (let r = 1; r <= 13; r++) rows[r] = bars(['w', 'y', 'c', 'g', 'm', 'r', 'b']);
    for (let r = 14; r <= 15; r++) rows[r] = bars(['b', 'k', 'm', 'k', 'c', 'k', 'w']);
    for (let r = 16; r <= 19; r++) {
      rows[r] = row([s(' '.repeat(7), 'w', 'b'), s(' '.repeat(7), 'w', 'w'), s(' '.repeat(7), 'w', 'm'), s(' '.repeat(19), 'w', 'k')]);
    }
    rows[21] = boxed('JEVANS.CLOUD  CH 99');
    rows[22] = row([s(pad('', 11)), statusLabel(), s(' MEDIA SERVER', 'w')]);
    rows[23] = boxed('Back to the guide on 02', 'b', { ch: HOME });
    return { section: 'w', rows };
  };

  const chNoSignal = (n) => {
    const rows = {};
    rows[9] = row([s(pad('', 14)), s(' NO SIGNAL ', 'w', 'k')], { dh: true });
    rows[13] = boxed(`Nothing on channel ${two(n)}`);
    rows[16] = boxed('Guide on 02 >>', 'y', { ch: HOME });
    return { section: 'm', rows };
  };

  const CHANNELS = { 2: chGuide, 3: chMedia, 4: chLinks, 5: chAbout, 99: chBars };

  // Closed captions, rotated every few seconds while CC is on.
  const CAPTIONS = {
    2: [['[UPBEAT SYNTH MUSIC]'], ['>> YOU\'RE WATCHING', 'JEVANS PUBLIC ACCESS.'], ['>> STAY TUNED FOR', 'THE MEDIA SERVER ON 3.']],
    3: [['[HARD DRIVES WHIRRING]'], ['>> IT\'S STILL BUFFERING.', 'GIVE IT A SECOND.'], ['[FAN NOISE INTENSIFIES]']],
    4: [['[KEYBOARD CLACKING]'], ['>> LIKE AND SUBSCRIBE,', 'OR DON\'T. NO PRESSURE.']],
    5: [['>> WHAT DOES A HOME SERVER', 'DO ALL DAY?'], ['>> TRANSCODES.', 'MOSTLY TRANSCODES.']],
    99: [['[STEADY 1000 HZ TONE]']],
    none: [['[STATIC]']],
  };

  /* ------------------------------------------------------------------ */
  /* Rendering                                                           */
  /* ------------------------------------------------------------------ */

  const grid = document.getElementById('grid');
  const screen = document.getElementById('screen');
  let header = null;
  let ccEls = [];
  let pageTimers = [];

  const isLink = (o) => o.ch || o.href || o.copy;

  const linkAttrs = (el, o) => {
    if (o.ch) {
      el.href = '#' + o.ch;
    } else if (o.href) {
      el.href = o.href;
      if (!o.href.startsWith('mailto:')) { el.target = '_blank'; el.rel = 'noopener'; }
    } else if (o.copy) {
      el.href = '#';
      el.dataset.copy = o.copy;
      el.setAttribute('role', 'button');
      el.setAttribute('aria-label', 'Copy ' + o.copy);
    }
  };

  const segEl = (g, rowBg, inLink) => {
    const link = !inLink && isLink(g);
    const el = document.createElement(link ? 'a' : 'span');
    let cls = 'f' + g.fg;
    const bg = g.bg || rowBg;
    if (bg) cls += ' b' + bg;
    if (g.flash && !reduced) cls += ' flash';
    if (g.hot) cls += ' hot';
    el.className = cls;
    el.textContent = g.text;
    if (link) linkAttrs(el, g);
    return el;
  };

  const rowEl = (r, line) => {
    const link = isLink(r);
    const el = document.createElement(link ? 'a' : 'div');
    el.className = 'row' + (r.dh ? ' dh' : '') + (r.cls ? ' ' + r.cls : '');
    el.style.gridRow = `${line + 1} / span ${r.dh ? 2 : 1}`;
    if (link) linkAttrs(el, r);
    let used = 0;
    for (const g of r.segs) {
      if (used >= COLS) break;
      const room = COLS - used;
      const seg = g.text.length > room ? { ...g, text: g.text.slice(0, room) } : g;
      el.append(segEl(seg, r.bg, link));
      used += seg.text.length;
    }
    if (used < COLS) el.append(segEl(s(' '.repeat(COLS - used), 'w'), r.bg, true));
    return el;
  };

  const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  const drawHeader = () => {
    const d = new Date();
    const label = state.buffer ? 'CH' + (state.buffer + '-').slice(0, 2) : 'CH' + two(state.ch);
    const left = [s(' ' + label + ' ', 'w'), s('JEVANS', 'y')];
    const h = d.getHours() % 12 || 12;
    const date = `${DAYS[d.getDay()]} ${MONTHS[d.getMonth()]} ${d.getDate()}`;
    const time = `${h}:${two(d.getMinutes())}:${two(d.getSeconds())} ${d.getHours() < 12 ? 'AM' : 'PM'} `;
    const used = left.reduce((n, g) => n + g.text.length, 0);
    const gap = COLS - used - date.length - 1 - time.length;
    const el = rowEl(row([...left, s(' '.repeat(Math.max(1, gap))), s(date, 'w'), s(' ' + time, 'y')]), 0);
    el.setAttribute('aria-hidden', 'true');
    if (header) header.replaceWith(el); else grid.append(el);
    header = el;
  };

  const drawCC = () => {
    ccEls.forEach((e) => e.remove());
    ccEls = [];
    if (!state.cc) return;
    const list = CAPTIONS[state.ch] || CAPTIONS.none;
    const lines = list[state.ccLine % list.length];
    lines.forEach((t, i) => {
      const el = rowEl(boxed(t), ROWS - lines.length + i);
      el.classList.add('cc');
      el.setAttribute('aria-hidden', 'true');
      grid.append(el);
      ccEls.push(el);
    });
  };

  const render = () => {
    pageTimers.forEach(clearInterval);
    pageTimers = [];

    const make = CHANNELS[state.ch];
    const page = make ? make() : chNoSignal(state.ch);

    grid.replaceChildren();
    header = null;
    ccEls = [];
    drawHeader();

    // skip rows hidden under a double-height row above them
    const taken = new Set();
    for (let r = 1; r < ROWS; r++) {
      const def = page.rows[r];
      if (!def || taken.has(r)) continue;
      if (def.dh) taken.add(r + 1);
      grid.append(rowEl(def, r));
    }

    for (const g of page.gfx || []) {
      const art = g.art || g.frames[0];
      const holder = document.createElement('div');
      holder.style.gridColumn = `${g.c + 1} / span ${art.cols}`;
      holder.style.gridRow = `${g.r + 1} / span ${art.rows}`;
      holder.style.pointerEvents = 'none';
      holder.innerHTML = art.svg;
      grid.append(holder);
      if (g.frames && !reduced) {
        let f = 0;
        pageTimers.push(setInterval(() => {
          f = (f + 1) % g.frames.length;
          holder.innerHTML = g.frames[f].svg;
        }, g.every || 600));
      }
    }

    document.body.dataset.section = page.section || 'y';

    snow.classList.toggle('idle', !make);
    if (!make) startSnow();
    drawCC();
  };

  /* ------------------------------------------------------------------ */
  /* Static + on-screen display                                          */
  /* ------------------------------------------------------------------ */

  const snow = document.createElement('canvas');
  snow.className = 'snow';
  snow.width = 120;
  snow.height = 90;
  snow.setAttribute('aria-hidden', 'true');
  screen.append(snow);
  const sctx = snow.getContext('2d');
  const noise = sctx.createImageData(snow.width, snow.height);

  const drawSnow = () => {
    const d = noise.data;
    for (let i = 0; i < d.length; i += 4) {
      const v = (Math.random() * 255) | 0;
      d[i] = d[i + 1] = d[i + 2] = v;
      d[i + 3] = 255;
    }
    sctx.putImageData(noise, 0, 0);
  };

  let snowLoop = null;
  const snowTick = () => {
    drawSnow();
    const live = !reduced && (snow.classList.contains('burst') || snow.classList.contains('idle'));
    snowLoop = live ? setTimeout(snowTick, 70) : null;
  };
  const startSnow = () => { if (!snowLoop) snowTick(); };

  let burstTimer = null;
  const burst = () => {
    if (reduced) return;
    snow.classList.add('burst');
    startSnow();
    clearTimeout(burstTimer);
    burstTimer = setTimeout(() => snow.classList.remove('burst'), 180);
  };

  const osd = document.createElement('div');
  osd.className = 'osd';
  osd.setAttribute('aria-hidden', 'true');
  screen.append(osd);
  let osdTimer = null;
  const showOSD = (text, hold = false) => {
    osd.textContent = text;
    osd.classList.add('show');
    clearTimeout(osdTimer);
    if (!hold) osdTimer = setTimeout(() => osd.classList.remove('show'), 2200);
  };

  /* ------------------------------------------------------------------ */
  /* Tuning                                                              */
  /* ------------------------------------------------------------------ */

  let digitTimer = null;

  const tune = (n, quiet = false) => {
    n = Number(n);
    if (!Number.isInteger(n) || n < 1 || n > 99) n = HOME;
    clearTimeout(digitTimer);
    state.buffer = '';
    state.copied = null;
    state.ccLine = 0;
    state.ch = n;
    if (!quiet) burst();
    render();
    showOSD('CH ' + two(n));
  };

  const navigate = (n) => {
    if (location.hash === '#' + n) tune(n);
    else location.hash = String(n);
  };

  // Like a real set: two digits tune at once, one digit tunes after a pause.
  const pushDigit = (d) => {
    clearTimeout(digitTimer);
    state.buffer += d;
    const commit = () => {
      const n = Number(state.buffer);
      state.buffer = '';
      navigate(n || HOME);
    };
    if (state.buffer.length >= 2) return commit();
    drawHeader();
    showOSD('CH ' + state.buffer + '-', true);
    digitTimer = setTimeout(commit, 1400);
  };

  const surf = (dir) => {
    const i = SURF.indexOf(state.ch);
    let next;
    if (i >= 0) next = SURF[(i + dir + SURF.length) % SURF.length];
    else if (dir > 0) next = SURF.find((c) => c > state.ch) ?? SURF[0];
    else next = [...SURF].reverse().find((c) => c < state.ch) ?? SURF[SURF.length - 1];
    navigate(next);
  };

  const fromHash = () => {
    const n = parseInt(location.hash.slice(1), 10);
    return Number.isInteger(n) && n >= 1 && n <= 99 ? n : HOME;
  };

  window.addEventListener('hashchange', () => tune(fromHash()));

  const ccButton = document.querySelector('[data-cc]');
  const toggleCC = () => {
    state.cc = !state.cc;
    ccButton.setAttribute('aria-pressed', String(state.cc));
    drawCC();
  };

  setInterval(() => {
    if (!state.cc) return;
    state.ccLine++;
    drawCC();
  }, 3200);

  const copyText = async (text) => {
    try {
      await navigator.clipboard.writeText(text);
      const ch = state.ch;
      state.copied = text;
      render();
      setTimeout(() => {
        if (state.copied !== text) return;
        state.copied = null;
        if (state.ch === ch) render();
      }, 2200);
    } catch {
      window.prompt('Copy this:', text);
    }
  };

  grid.addEventListener('click', (e) => {
    const a = e.target.closest('[data-copy]');
    if (!a) return;
    e.preventDefault();
    copyText(a.dataset.copy);
  });

  // light up the matching remote button when a key is pressed
  const press = (sel) => {
    const b = document.querySelector(sel);
    if (!b) return;
    b.classList.add('down');
    setTimeout(() => b.classList.remove('down'), 120);
  };

  document.addEventListener('keydown', (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const k = e.key;
    if (/^[0-9]$/.test(k)) {
      e.preventDefault();
      press(`[data-digit="${k}"]`);
      pushDigit(k);
    } else if (k === 'c' || k === 'C') {
      press('[data-cc]');
      toggleCC();
    } else if (k === 'Escape' && state.buffer) {
      clearTimeout(digitTimer);
      state.buffer = '';
      osd.classList.remove('show');
      drawHeader();
    } else if (k === 'ArrowUp' || k === 'ArrowRight' || k === 'PageUp') {
      e.preventDefault();
      press('[data-surf="1"]');
      surf(1);
    } else if (k === 'ArrowDown' || k === 'ArrowLeft' || k === 'PageDown') {
      e.preventDefault();
      press('[data-surf="-1"]');
      surf(-1);
    }
  });

  document.querySelector('.remote').addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    if (b.dataset.digit) pushDigit(b.dataset.digit);
    else if (b.dataset.ch) navigate(Number(b.dataset.ch));
    else if (b.dataset.surf) surf(Number(b.dataset.surf));
    else if ('cc' in b.dataset) toggleCC();
  });

  /* ------------------------------------------------------------------ */
  /* Sizing: whole-pixel rows, glyphs stretched to fill the cells        */
  /* ------------------------------------------------------------------ */

  const rootStyle = document.documentElement.style;
  let advance = 0.5; // glyph advance / font-size, measured once the font loads

  // Measure real laid-out text with the screen's own font stack rather than a
  // canvas: iOS Safari measures canvas text with a fallback font, which made
  // every row render ~20% too narrow there.
  const ruler = document.createElement('span');
  ruler.setAttribute('aria-hidden', 'true');
  ruler.textContent = '0'.repeat(40);
  ruler.style.cssText = 'position:absolute;left:-9999px;top:0;visibility:hidden;white-space:pre;' +
    'font-family:"VT323",ui-monospace,monospace;font-size:100px;letter-spacing:0';
  document.body.append(ruler);

  const measure = () => {
    advance = ruler.getBoundingClientRect().width / 4000 || 0.5;
  };

  const fit = () => {
    const remote = document.querySelector('.remote');
    const short = innerHeight < 560; // e.g. a phone held sideways
    const padX = short ? 24 : 32;
    const padY = short ? 24 : 48;    // body padding, top + bottom
    const gap = short ? 24 : 48;     // between set and remote when side by side

    // Stand the remote up beside the set whenever that leaves room for a
    // bigger screen than stacking it underneath would.
    const fitCw = (w, h) => Math.min(w / (COLS + 2), h / ((ROWS + 1) * ASPECT));
    const wide = innerWidth >= 640 &&
      fitCw(innerWidth - padX * 2 - 172 - gap, innerHeight - padY) >
      fitCw(innerWidth - 32, innerHeight - 64 - 80);
    document.body.classList.toggle('wide', wide);

    // Phones get a thinner border and fractional columns: every pixel counts
    // at 40 characters across. Row heights stay whole so bands never seam.
    const narrow = innerWidth < 760 && !wide;
    const padc = narrow ? 0.5 : 1;
    const availW = wide
      ? innerWidth - padX * 2 - remote.offsetWidth - gap
      : innerWidth - (narrow ? 24 : 32);
    const availH = wide
      ? innerHeight - padY
      : innerHeight - remote.offsetHeight - (narrow ? 40 : 56) - 24;
    const byW = availW / (COLS + padc * 2);
    const byH = availH / ((ROWS + 1) * ASPECT);
    const cw = narrow ? Math.floor(byW * 100) / 100 : Math.max(6, Math.floor(Math.min(byW, byH)));

    // Tall screens (phones, portrait tablets) have height to spare once the
    // width is used up. Spend it on taller rows instead of empty space; VT323
    // is a tall font anyway, so text gets bigger and less stretched.
    const aspect = wide ? ASPECT : Math.min(MAX_ASPECT, Math.max(ASPECT, availH / ((ROWS + 1) * cw)));
    const rh = Math.floor(cw * aspect);
    const fs = rh * GLYPH;
    rootStyle.setProperty('--cw', cw + 'px');
    rootStyle.setProperty('--padc', padc);
    rootStyle.setProperty('--row', rh + 'px');
    rootStyle.setProperty('--fs', fs.toFixed(2) + 'px');
    rootStyle.setProperty('--sx', (cw / (fs * advance)).toFixed(4));
    rootStyle.setProperty('--nudge', Math.round(rh * 0.04) + 'px');
  };

  addEventListener('resize', fit);
  // If the font arrives late or swaps in after a fallback (in-app browsers
  // like Discord's do this), the ruler changes width: measure again.
  const remeasure = () => {
    const before = advance;
    measure();
    if (Math.abs(advance - before) > 1e-4) fit();
  };
  if (window.ResizeObserver) new ResizeObserver(remeasure).observe(ruler);
  if (document.fonts) {
    document.fonts.addEventListener('loadingdone', remeasure);
    document.fonts.ready.then(remeasure);
  }
  addEventListener('load', remeasure);

  /* ------------------------------------------------------------------ */
  /* Media server status                                                 */
  /* ------------------------------------------------------------------ */

  const timeout = (ms) => {
    if (AbortSignal.timeout) return AbortSignal.timeout(ms);
    const c = new AbortController();
    setTimeout(() => c.abort(), ms);
    return c.signal;
  };

  const probe = async () => {
    const base = CONFIG.jellyfin.url.replace(/\/+$/, '');
    try {
      const r = await fetch(base + '/System/Info/Public', { signal: timeout(6000), cache: 'no-store' });
      if (!r.ok) return { state: 'online' };
      const j = await r.json();
      return { state: 'online', name: j.ServerName, version: j.Version };
    } catch {
      // A CORS refusal still means something answered. An opaque request
      // tells us whether the host is reachable at all.
      try {
        await fetch(base + '/web/', { mode: 'no-cors', signal: timeout(6000), cache: 'no-store' });
        return { state: 'online' };
      } catch {
        return { state: 'offline' };
      }
    }
  };

  const poll = async () => {
    if (!CONFIG.jellyfin.url) return;
    const next = await probe();
    const changed = JSON.stringify(next) !== JSON.stringify(state.status);
    state.status = next;
    if (changed && [2, 3, 99].includes(state.ch)) render();
  };

  /* ------------------------------------------------------------------ */
  /* Switch on                                                           */
  /* ------------------------------------------------------------------ */

  const start = () => {
    measure();
    fit();
    tune(fromHash(), true);
    if (!reduced) {
      screen.classList.add('boot');
      setTimeout(() => screen.classList.remove('boot'), 900);
    }
    setInterval(() => drawHeader(), 1000);
    poll();
    setInterval(poll, CONFIG.pollEvery * 1000);
  };

  (document.fonts ? document.fonts.load('20px VT323').catch(() => {}) : Promise.resolve()).then(start);
})();
