// Click dummy only: example data, hash routing, envelope budget computed in cents.
(() => {
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const C = v => Math.round(v * 100);
  const num = c => (c < 0 ? "−" : "") + (Math.abs(c) / 100).toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const eur = c => num(c) + " €";
  const signed = c => (c > 0 ? "+" : "") + eur(c);
  const esc = s => String(s).replace(/[&<>"]/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[ch]);
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const sum = (list, f) => list.reduce((s, x) => s + f(x), 0);
  const parse = s => {
    s = String(s).trim().replace(/\s|€/g, "").replace("−", "-");
    if (!s) return 0;
    s = s.includes(",") ? s.replace(/\./g, "").replace(",", ".") : /^-?\d+\.\d{1,2}$/.test(s) ? s : s.replace(/\./g, "");
    const v = Number(s);
    return Number.isFinite(v) ? C(v) : NaN;
  };
  const isDesktop = () => matchMedia("(min-width: 992px)").matches;
  const icon = (id, cls = "app-icon app-icon-sm") => `<svg class="${cls}" aria-hidden="true"><use href="#${id}"/></svg>`;

  // ------------------------------------------------------------ months (index 0 = Juni 2026, imported from YNAB)
  const MONTHS = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];
  const CUR = 4, LAST = 18, IMPORTED = 0, TODAY = "2026-10-08";
  const ym = i => { const t = 5 + i; return [2026 + Math.floor(t / 12), ((t % 12) + 12) % 12]; };
  const mLabel = i => { const [y, m] = ym(i); return `${MONTHS[m]} ${y}`; };
  const mName = i => MONTHS[ym(i)[1]];
  const mShort = i => MONTHS[ym(i)[1]].slice(0, 3);
  const mKey = i => { const [y, m] = ym(i); return `${y}-${String(m + 1).padStart(2, "0")}`; };
  const keyIdx = k => { const [y, m] = k.split("-").map(Number); return (y - 2026) * 12 + m - 6; };
  const dIdx = d => keyIdx(d.slice(0, 7));
  const dShort = d => `${d.slice(8, 10)}.${d.slice(5, 7)}.`;
  const dLong = d => `${d.slice(8, 10)}.${d.slice(5, 7)}.${d.slice(0, 4)}`;
  const lastDay = i => { const [y, m] = ym(i); return new Date(y, m + 1, 0).getDate(); };
  const ago = d => { const n = Math.round((new Date(TODAY) - new Date(d)) / 864e5); return n <= 0 ? "heute" : n === 1 ? "gestern" : `vor ${n} Tagen`; };

  // ------------------------------------------------------------ data
  // Arrays run from Juni 2026: a = assigned, h = activity before October, s = available entering Juni.
  const rep = (v, n = 5) => Array(n).fill(v);
  const monthly = (amount, mode = "setaside") => ({ amount, cadence: "month", mode });
  const yearly = (amount, due, mode = "refill") => ({ amount, cadence: "year", due, mode });
  const groups = [
    { id: "fix", name: "Fixkosten", cats: [
      { id: "miete", e: "🏠", name: "Miete", a: rep(1050), h: rep(-1050, 4), target: monthly(1050) },
      { id: "strom", e: "⚡", name: "Strom & Gas", a: rep(128), h: rep(-128, 4), target: monthly(128) },
      { id: "internet", e: "📶", name: "Internet & Mobilfunk", a: rep(54.98), h: rep(-54.98, 4) },
      { id: "versich", e: "🛡️", name: "Versicherungen", a: rep(86.4), h: rep(-86.4, 4) },
      { id: "rundfunk", e: "📻", name: "Rundfunkbeitrag", s: 18.36, a: rep(18.36), h: [0, 0, -55.08, 0], target: monthly(18.36) },
      { id: "oepnv", e: "🚆", name: "Deutschlandticket", a: rep(63), h: rep(-63, 4) },
    ] },
    { id: "alltag", name: "🛒 Alltag", cats: [
      { id: "lebensm", e: "🛒", name: "Lebensmittel", s: 52.4, a: rep(650), h: [-662.4, -662.4, -618.75, -641.2], target: monthly(700) },
      { id: "drog", e: "🧴", name: "Drogerie", s: 6.8, a: rep(45), h: [-41.8, -38.9, -52.1, -44.8], target: monthly(45) },
      { id: "resto", e: "🍝", name: "Restaurants & Café", s: 18.6, a: rep(120), h: [-113.6, -104.5, -131.2, -167.4] },
      { id: "kleidung", e: "👕", name: "Kleidung", s: 119.9, a: rep(60), h: [-59.9, 0, -89.95, -24.99], target: monthly(60) },
      { id: "gesund", e: "💊", name: "Gesundheit & Apotheke", s: 33.2, a: rep(30), h: [-18.2, -12.49, 0, -27.8] },
      { id: "haushalt", e: "🧽", name: "Haushalt & Baumarkt", s: 14.6, a: rep(50), h: [-34.6, -34.2, -71.85, -18.4], target: monthly(50) },
      { id: "tanken", e: "⛽", name: "Tanken", s: 21.3, a: rep(110), h: [-111.3, -96.4, -121.1, -104.85], target: monthly(120, "refill") },
    ] },
    { id: "ruecklagen", name: "🐷 Rücklagen", cats: [
      { id: "urlaub", e: "🏖️", name: "Urlaub", s: 1050, a: [400, 200, 200, 200, 200, 200], h: [0, 0, -1186.4, 0], target: yearly(3000, "2027-07-10") },
      { id: "kfzrep", e: "🔧", name: "Kfz-Reparaturen", s: 430, a: rep(50), h: [0, 0, 0, -312.8], target: monthly(50) },
      { id: "kfzvers", e: "🚗", name: "Kfz-Versicherung", s: 168, a: rep(42, 6), h: [0, 0, 0, 0], target: yearly(504, "2027-01-15") },
      { id: "geschenke", e: "🎁", name: "Geschenke & Weihnachten", s: 48.5, a: [40, 40, 40, 40, 40, 150], h: [-28.5, -35, 0, -62.9], target: yearly(450, "2026-12-24") },
      { id: "fahrrad", e: "🚲", name: "Fahrrad", s: 115, a: rep(25), h: [0, 0, -38.9, 0] },
      { id: "notgroschen", e: "🛟", name: "Notgroschen", s: 4600, a: rep(200), h: [0, 0, 0, 0], target: monthly(200) },
    ] },
    { id: "freizeit", name: "🎉 Freizeit", cats: [
      { id: "hobby", e: "🧗", name: "Hobbys", s: 22.6, a: rep(50), h: [-52.6, -42, -18.5, -64.9] },
      { id: "abos", e: "📺", name: "Abos & Streaming", a: rep(32.97), h: rep(-32.97, 4), target: monthly(32.97, "refill") },
      { id: "buecher", e: "📚", name: "Bücher & Zeitschriften", s: 4.99, a: rep(25), h: [-14.99, -19.99, -12, -34.9] },
    ] },
  ];
  const prepCat = c => {
    c.start = C(c.s || 0);
    c.assigned = Array.from({ length: LAST + 1 }, (_, i) => C((c.a || [])[i] || 0));
    c.hist = (c.h || []).map(C);
    if (c.target) c.target = { ...c.target, amount: C(c.target.amount) };
  };
  groups.forEach(g => g.cats.forEach(prepCat));
  const UNCAT = { id: "uncat", e: "⚠️", name: "Nicht kategorisiert" };
  prepCat(UNCAT);
  const cats = () => groups.flatMap(g => g.cats);
  const cat = id => (id === "uncat" ? UNCAT : cats().find(c => c.id === id));
  const groupOf = id => groups.find(g => g.cats.some(c => c.id === id));
  const plain = s => s.replace(/^\p{Extended_Pictographic}️?\s*/u, "");
  const catName = c => `<span class="app-catname"><span class="app-emoji" aria-hidden="true">${c.e}</span><span class="app-label">${esc(c.name)}</span></span>`;
  const catText = c => `${c.e} ${c.name}`;

  // "Zu verteilen" before October: Juni starts with the YNAB opening amount and Mai's overspending.
  const OPENING = C(150), OVER_BEFORE = C(-126.4);
  const incomeHist = { "Arbeitgeber Muster GmbH": [3240, 3240, 3240, 3240], "Finanzamt Musterstadt": [0, 0, 248.7, 0], "Nordbank Direkt": [0, 0, 0, 11.8] };

  const accounts = [
    { id: "giro", e: "💶", name: "Girokonto", kind: "Girokonto", type: "budget", base: C(2184.37), link: "Verbunden", rec: "2026-10-01", bank: { src: "aus deiner Verbindung, vor 2 Stunden", diff: 0 } },
    { id: "giro2", e: "🏦", name: "Girokonto Nordbank", kind: "Girokonto", type: "budget", base: 0, link: "Datei-Import (QFX)", rec: "2026-09-07", bank: { src: "aus Datei-Import vom 07.10.", diff: C(0.42) } },
    { id: "geteilt", e: "👫", name: "Geteilt", kind: "Geteilt", type: "budget", base: C(-35.6), link: "Zipfelkasse-API", rec: "2026-09-26", note: "Zipfelkasse bucht gemeinsame Ausgaben über die API, zuletzt heute 07:55.", bank: { src: "Saldo laut Zipfelkasse, heute 07:55", diff: 0 } },
    { id: "depot", e: "📈", name: "Depot", kind: "Tracking", type: "tracking", base: C(48213.4), link: "zipfelfolio", note: "Wert aus zipfelfolio, zuletzt 08.10. Kein Bankabruf." },
  ];
  const acc = id => accounts.find(a => a.id === id);
  const accText = a => `${a.e} ${a.name}`;

  let seq = 100;
  const T = (acc, date, payee, cat, amount, status = "c", more = {}) => ({ id: "t" + seq++, acc, date, payee, cat, amount: C(amount), status, memo: "", ...more });
  const zk = share => ({ memo: `Zipfelkasse · bezahlt von Jana, dein Anteil ${share}` });
  const imp = more => ({ approved: false, imported: true, ...more });
  const txs = [
    T("giro", "2026-10-01", "Arbeitgeber Muster GmbH", "rta", 3240, "c", { memo: "Gehalt Oktober" }),
    T("giro", "2026-10-01", "Hausverwaltung Beispiel", "miete", -1050, "c", { memo: "Miete Oktober" }),
    T("giro", "2026-10-01", "Stadtwerke Musterstadt", "strom", -128),
    T("giro", "2026-10-01", "Versicherungsverein Muster", "versich", -86.4),
    T("giro", "2026-10-01", "Verkehrsverbund Muster", "oepnv", -63),
    T("giro", "2026-10-02", "Frischmarkt", "lebensm", -87.43),
    T("giro", "2026-10-02", "StreamFlix", "abos", -13.99),
    T("giro", "2026-10-02", "Girokonto Nordbank", null, -200, "c", { transfer: "giro2", memo: "Rücklagen Oktober" }),
    T("giro", "2026-10-03", "Drogerie Sauber", "drog", -48.75, "u", { id: "t-manual", memo: "Shampoo, Zahnpasta" }),
    T("giro", "2026-10-03", "Pizzeria Da Mario", "resto", -38.5),
    T("giro", "2026-10-04", "Tankstelle Nord", "tanken", -68.2),
    T("giro", "2026-10-06", "Apotheke am Markt", "gesund", -8.97),
    T("giro", "2026-10-06", "Klangwerk Musik", "abos", -10.99),
    T("giro", "2026-10-06", "Seifenladen", "drog", -17.95),
    T("giro", "2026-10-06", "Baumarkt Hammer & Co", "haushalt", -29.99, "u", { memo: "Dübel, Silikon" }),
    T("giro", "2026-10-07", "Kletterhalle Musterstadt", "hobby", -14.5, "u"),
    T("giro", "2026-10-06", "Netzfunk Mobil", "internet", -54.98, "c", imp()),
    T("giro", "2026-10-07", "Frischmarkt", "lebensm", -41.06, "c", imp()),
    T("giro", "2026-10-07", "Drogerie Sauber", "drog", -48.75, "c", imp({ matchOf: "t-manual" })),
    T("giro", "2026-10-08", "Lastschrift Muster Abo GmbH", null, -9.99, "c", imp({ memo: "Mandat MA-4471" })),
    T("giro", "2026-09-30", "Frischmarkt", "lebensm", -63.12, "c", { hist: true }),
    T("giro", "2026-09-30", "Geteilt", null, -96.2, "c", { hist: true, transfer: "geteilt", memo: "Ausgleich September (Zipfelkasse)" }),
    T("giro", "2026-09-29", "Café Kranich", "resto", -12.4, "c", { hist: true }),
    T("giro", "2026-09-27", "Pizzeria Da Mario", "resto", -46.8, "r", { hist: true, memo: "Geburtstag Jana" }),
    T("giro", "2026-09-26", "Online-Buchhandlung", "buecher", -16.9, "r", { hist: true }),
    T("giro", "2026-09-22", "Werkstatt Schrauber", "kfzrep", -312.8, "r", { hist: true, memo: "Inspektion" }),
    T("giro", "2026-09-01", "Girokonto Nordbank", null, -200, "r", { hist: true, transfer: "giro2", memo: "Rücklagen September" }),
    T("giro2", "2026-10-02", "Girokonto", null, 200, "c", { transfer: "giro", memo: "Rücklagen Oktober" }),
    T("giro2", "2026-10-05", "Fahrradladen Speiche", "fahrrad", -89, "c", { memo: "Neue Bremsen" }),
    T("giro2", "2026-09-01", "Girokonto", null, 200, "r", { hist: true, transfer: "giro", memo: "Rücklagen September" }),
    T("giro2", "2026-09-01", "Nordbank Direkt", "rta", 11.8, "r", { hist: true, memo: "Zinsen August" }),
    T("geteilt", "2026-10-02", "Frischmarkt", "lebensm", -42.15, "c", zk("50 % von 84,30 €")),
    T("geteilt", "2026-10-05", "Wochenmarkt", "lebensm", -23.5, "c", zk("50 % von 47,00 €")),
    T("geteilt", "2026-10-06", "Café Kranich", "resto", -7.8, "c", zk("50 % von 15,60 €")),
    T("geteilt", "2026-10-07", "Kino Lichtspiel", "hobby", -12.5, "c", zk("50 % von 25,00 €")),
    T("geteilt", "2026-09-30", "Girokonto", null, 96.2, "c", { hist: true, transfer: "giro", memo: "Ausgleich September (Zipfelkasse)" }),
    ...[["08", 412.18, "Kursänderung"], ["07", -186.55, "Kursänderung"], ["06", 95.2, "Kursänderung"], ["02", 196.86, "Ausschüttung"], ["01", 1125, "Sparplan-Kauf"]]
      .map(([d, v, memo]) => T("depot", `2026-10-${d}`, "Wertänderung", null, v, "c", { hist: true, memo: `${memo} · aus zipfelfolio` })),
  ];
  const txById = id => txs.find(t => t.id === id);
  const counted = t => !t.hist && !t.matchOf && acc(t.acc).type === "budget";
  const parts = t => (t.splits ? t.splits.map(s => [s.cat, s.amount]) : t.transfer ? [] : [[t.cat || "uncat", t.amount]]);

  // ------------------------------------------------------------ budget model
  // Yearly targets spread what is still missing over the months up to the due month. "Set aside another" counts what
  // was assigned since the cycle started, "refill up to" counts what is available.
  const snoozed = (c, m) => !!c.target?.snooze?.includes(m);
  function targetFor(c, m, carry, assigned) {
    const t = c.target;
    if (!t) return { req: 0, under: 0, progress: null };
    if (snoozed(c, m)) return { req: 0, under: 0, progress: null, snoozed: true };
    let req, have = carry;
    if (t.cadence === "month") req = t.mode === "refill" ? Math.max(0, t.amount - carry) : t.amount;
    else {
      let due = dIdx(t.due);
      while (due < m) due += 12;
      if (t.mode === "setaside") {
        const from = due - 11;
        have = (from <= 0 ? c.start : 0) + sum(c.assigned.slice(Math.max(0, from), m), v => v);
      }
      req = Math.max(0, Math.ceil((t.amount - have) / (due - m + 1)));
    }
    const under = Math.max(0, req - assigned);
    const progress = t.cadence === "year" ? clamp((have + assigned) / t.amount, 0, 1) : req ? (req - under) / req : 1;
    return { req, under, progress };
  }

  function model() {
    const act = {}, src = {};
    const months = () => Array(LAST + 1).fill(0);
    Object.entries(incomeHist).forEach(([p, list]) => (src[p] = months().map((_, i) => C(list[i] || 0))));
    txs.filter(counted).forEach(t => {
      const m = dIdx(t.date);
      if (m < 0 || m > LAST) return;
      parts(t).forEach(([c, v]) => { if (c === "rta") (src[t.payee] ||= months())[m] += v; else act[c + "|" + m] = (act[c + "|" + m] || 0) + v; });
    });
    const income = months().map((_, m) => sum(Object.values(src), l => l[m]));
    const M = { cats: {}, months: [], income: src };
    [...cats(), UNCAT].forEach(c => {
      const rows = [];
      for (let m = 0; m <= LAST; m++) {
        const carry = m === 0 ? c.start : Math.max(0, rows[m - 1].avail);
        const assigned = c.assigned[m], activity = (c.hist[m] || 0) + (act[c.id + "|" + m] || 0);
        rows.push({ carry, assigned, activity, avail: carry + assigned + activity, ...targetFor(c, m, carry, assigned) });
      }
      M.cats[c.id] = rows;
    });
    for (let m = 0; m <= LAST; m++) {
      const s = { income: income[m], carry: 0, assigned: 0, activity: 0, avail: 0, under: 0, req: 0, over: 0, overN: 0 };
      Object.values(M.cats).forEach(r => {
        const x = r[m];
        s.carry += x.carry; s.assigned += x.assigned; s.activity += x.activity; s.avail += x.avail; s.under += x.under; s.req += x.req;
        if (x.avail < 0) { s.over += x.avail; s.overN++; }
      });
      s.prevRta = m === 0 ? OPENING : M.months[m - 1].rta;
      s.prevOver = m === 0 ? OVER_BEFORE : M.months[m - 1].over;
      s.rta = s.prevRta + s.prevOver + s.income - s.assigned;
      M.months.push(s);
    }
    for (let m = LAST, fut = 0, free = Infinity, at = LAST; m >= 0; m--) {
      const s = M.months[m];
      s.future = fut; fut += s.assigned;
      if (s.rta <= free) { free = s.rta; at = m; }
      s.free = free; s.freeAt = at;
      s.show = s.rta - s.future;
      // past months are closed: their card shows Zu verteilen as it stood at the month's end
      s.closed = m < CUR;
      s.disp = s.closed ? s.rta : s.show;
    }
    return M;
  }

  const balance = a => a.base + sum(txs.filter(t => t.acc === a.id && !t.hist && !t.matchOf), t => t.amount);
  const cleared = a => balance(a) - sum(txs.filter(t => t.acc === a.id && !t.hist && !t.matchOf && t.status === "u"), t => t.amount);
  const budgetCash = () => sum(accounts.filter(a => a.type === "budget"), balance);
  {
    // The Nordbank opening balance is whatever makes accounts and budget agree.
    const s = model().months[CUR];
    acc("giro2").base = s.rta + s.avail + s.future - budgetCash();
  }
  const checkBooks = M => { const s = M.months[CUR]; console.assert(budgetCash() === s.rta + s.avail + s.future, "Konten und Budget passen nicht zusammen"); };

  // ------------------------------------------------------------ assigning (never borrows from later months)
  const NO_MONEY = "Nicht genug zu verteilen – Abakus leiht nicht aus dem nächsten Monat.";
  function tryAssign(c, m, v) {
    const old = c.assigned[m];
    if (v === old) return true;
    const before = model().months.map(s => s.rta);
    c.assigned[m] = v;
    if (v < old) return true;
    const after = model().months.map(s => s.rta);
    for (let k = m; k <= LAST; k++) if (after[k] < 0 && after[k] < before[k]) { c.assigned[m] = old; return false; }
    return true;
  }

  // undo / redo by snapshots
  const undoStack = [], redoStack = [];
  const snap = () => JSON.stringify({ c: cats().map(c => [c.id, c.assigned, c.target]), t: txs, r: accounts.map(a => a.rec) });
  const restore = s => {
    const d = JSON.parse(s);
    d.c.forEach(([id, a, t]) => { const c = cat(id); if (c) { c.assigned = a; c.target = t; } });
    txs.splice(0, txs.length, ...d.t);
    accounts.forEach((a, i) => (a.rec = d.r[i]));
  };
  const commit = () => { undoStack.push(snap()); redoStack.length = 0; };
  const undoRedo = (from, to) => { if (!from.length) return; to.push(snap()); restore(from.pop()); renderAll(); };

  // ------------------------------------------------------------ state, routing
  const state = { m: CUR, n: 1, focus: null, insp: false, sel: null, sheet: null, pushed: false, calcOpen: new Set(), incomeKeys: [], running: false, filter: "all", editTarget: false, screen: null, acc: null, regFilter: "all", search: "", picked: new Set(), collapsed: new Set(), M: null };
  const screens = $$("[data-screen]");
  const parseHash = () => { const [s, q] = location.hash.slice(1).split("?"); return { screen: s || "budget", q: new URLSearchParams(q || "") }; };
  const go = (screen, params = {}) => {
    const q = new URLSearchParams(Object.entries(params).filter(([, v]) => v != null)).toString();
    history.replaceState(null, "", "#" + screen + (q ? "?" + q : ""));
    route();
  };
  const budgetParams = () => ({ m: mKey(state.m), kat: state.sel });

  function route() {
    const { screen, q } = parseHash();
    const target = screens.find(s => s.dataset.screen === screen) || screens[0];
    const id = target.dataset.screen, changed = state.screen !== id;
    screens.forEach(s => (s.hidden = s !== target));
    state.screen = id;
    if (id === "budget") {
      const had = state.sel;
      state.m = q.has("m") ? clamp(keyIdx(q.get("m")), 0, LAST) : CUR;
      state.sel = q.get("kat") && cat(q.get("kat")) ? q.get("kat") : null;
      if (!state.sel) state.pushed = false;
      layout(true);
      if (state.sel && !state.insp) openPanel();
      // back from a category: the sheet closes with it
      else if (had && !state.sel && panel.classList.contains("show")) bootstrap.Offcanvas.getInstance(panel)?.hide();
    } else {
      if (panel.classList.contains("show")) bootstrap.Offcanvas.getInstance(panel)?.hide();
      paint();
    }
    if (id === "konten") {
      const k = q.get("konto");
      if (k !== state.acc) { state.picked.clear(); state.regFilter = "all"; }
      state.acc = k && (k === "alle" || acc(k)) ? k : null;
      renderAccounts();
    }
    if (changed) window.scrollTo({ top: 0 });
    navActive();
  }
  const navActive = () => $$("[data-nav] .nav-link").forEach(a => {
    const href = a.getAttribute("href");
    const on = href === "#" + state.screen || (href.startsWith("#konten") && state.screen === "konten" && (href === "#konten" || state.acc === "alle"));
    a.classList.toggle("active", on);
    if (on) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
  });
  addEventListener("hashchange", route);

  // Months and inspector from the available width: the inspector comes before a third month (about 1280 px: 1 month
  // and inspector, 1600: 2, 1920: 3; below that 1 or 2 months only). A month is as wide as its widest content.
  const INSP_W = 312;
  let MONTH_W = 300, COLS = [96, 84, 108];
  const catW = () => Math.round(clamp(innerWidth * 0.24, 256, 384));
  function measure() {
    const M = model(), vals = [];
    Object.values(M.cats).forEach(rows => rows.forEach(r => vals.push(r.assigned, r.activity)));
    M.months.forEach(s => vals.push(s.assigned, s.activity, s.avail));
    groups.forEach(g => M.months.forEach((_, m) => ["assigned", "activity", "avail"].forEach(k => vals.push(sum(g.cats, c => M.cats[c.id][m][k])))));
    const longest = list => list.reduce((a, b) => (b.length > a.length ? b : a), "");
    const big = longest(vals.map(num)), pill = longest(Object.values(M.cats).flatMap(rows => rows.map(r => eur(r.avail))));
    const box = document.createElement("div");
    box.style.cssText = "position:absolute;left:-9999px;top:0;visibility:hidden";
    box.innerHTML = `<table class="app-budget"><tbody><tr><td><b data-w="n">${big}</b> <span class="badge rounded-pill app-pill" data-w="p">${icon("i-okc")}${pill}</span></td></tr></tbody></table>` +
      ["Zugewiesen", "Aktivität", "Verfügbar"].map(l => `<span class="app-colh d-inline-block" data-w="l">${l}</span>`).join("");
    document.body.append(box);
    const w = k => Math.max(...$$(`[data-w="${k}"]`, box).map(e => Math.ceil(e.getBoundingClientRect().width)));
    const n = w("n"), p = w("p"), l = w("l");
    box.remove();
    COLS = [Math.max(n + 12, l) + 12 + 10, Math.max(n, l) + 12, Math.max(p, n, l) + 12];
    MONTH_W = sum(COLS, v => v) + 4;
  }
  function sizeCols() {
    const t = $("[data-budget-table]"), cols = $$("col[data-col]", t);
    if (!cols.length || !t.parentElement.clientWidth) return;
    const cw = catW(), per = (t.parentElement.clientWidth - cw) / state.n, k = Math.max(1, per / MONTH_W);
    $("col", t).style.width = cw + "px";
    cols.forEach(c => (c.style.width = (COLS[+c.dataset.col] * k).toFixed(1) + "px"));
  }
  function layout(force) {
    const W = $('[data-screen="budget"]').clientWidth, cw = catW();
    document.documentElement.style.setProperty("--cat-w", cw + "px");
    let n = 1, insp = false;
    if (isDesktop() && W) {
      const room = W - cw;
      insp = room - INSP_W >= MONTH_W;
      n = clamp(Math.floor((room - (insp ? INSP_W : 0)) / MONTH_W), 1, insp ? 3 : 2);
    }
    if (force || n !== state.n || insp !== state.insp) {
      state.n = n; state.insp = insp;
      if (state.screen === "budget") renderBudget();
    } else sizeCols();
  }
  new ResizeObserver(() => layout(false)).observe($('[data-screen="budget"]'));
  const visibleMonths = () => { const start = clamp(state.m, 0, LAST - state.n + 1); return Array.from({ length: state.n }, (_, i) => start + i); };
  const focusMonth = () => { const v = visibleMonths(); return v.includes(state.focus) ? state.focus : v.includes(CUR) ? CUR : v[0]; };

  // ------------------------------------------------------------ budget rendering
  const FILTERS = {
    all: () => true, over: (c, r) => r.avail < 0, under: (c, r) => r.under > 0,
    overfunded: (c, r) => !!c.target && r.under === 0 && r.assigned > r.req, money: (c, r) => r.avail > 0, paused: (c, r) => !!r.snoozed,
  };
  const zero = v => (v === 0 ? "app-zero" : "");

  function renderBudget() {
    const months = visibleMonths(), f = focusMonth(), M = (state.M = model());
    $("[data-month-title]").textContent = mLabel(f);
    const shown = groups.map(g => ({ g, cats: g.cats.filter(c => FILTERS[state.filter](c, M.cats[c.id][f])) })).filter(x => state.filter === "all" || x.cats.length);
    const uncat = months.some(m => M.cats.uncat[m].activity !== 0) && FILTERS[state.filter](UNCAT, M.cats.uncat[f]);
    const income = state.filter === "all" ? Object.keys(M.income) : [];
    state.incomeKeys = income;

    const colh = (m, k, label) => `<th class="app-num${k === "assigned" ? " app-ms" : ""}"><span class="app-colh">${label}<b data-msum="${m}|${k}"></b></span></th>`;
    const line2 = (c, tag = "div") => `<${tag} class="app-line2" data-line2="${c.id}"><${tag} class="progress app-target" data-bar="${c.id}"></${tag}><span class="app-tstat" data-tstat="${c.id}"></span></${tag}>`;
    let h = `<colgroup><col>${months.map(() => '<col data-col="0"><col data-col="1"><col data-col="2">').join("")}</colgroup>
      <thead><tr><th class="app-cat"></th>${months.map(m => `<th colspan="3" class="app-ms">${monthCard(m, m === f)}</th>`).join("")}</tr>
      <tr><th class="app-cat"><span class="app-colh">Kategorie</span></th>${months.map(m => colh(m, "assigned", "Zugewiesen") + colh(m, "activity", "Aktivität") + colh(m, "avail", "Verfügbar")).join("")}</tr></thead><tbody>`;
    const row = c => `<tr data-row="${c.id}"${state.sel === c.id ? ' class="is-sel"' : ""}>
        <td class="app-cat"><div class="d-flex align-items-center gap-2"><input class="form-check-input mt-0 flex-shrink-0" type="checkbox" data-pick-cat="${c.id}"${state.sel === c.id ? " checked" : ""} aria-label="${esc(c.name)} auswählen">
          <div class="flex-grow-1" style="min-width:0"><button type="button" class="app-catbtn" data-open-cat="${c.id}">${catName(c)}</button>${line2(c)}</div></div></td>${months.map(m => `
        <td class="app-ms app-num">${c.id === "uncat" ? "" : `<input class="form-control form-control-sm app-assign" inputmode="decimal" autocomplete="off" data-assign="${c.id}|${m}" aria-label="${esc(c.name)}, zugewiesen im ${mLabel(m)}">`}</td>
        <td class="app-num" data-act="${c.id}|${m}"></td>
        <td class="app-num">${m === f ? `<button type="button" class="badge rounded-pill app-pill border-0" data-avail="${c.id}|${m}"></button>` : `<button type="button" class="app-q" data-avail="${c.id}|${m}"></button>`}</td>`).join("")}</tr>`;
    const grpRow = (id, name, cells) => `<tr class="app-grp"><th class="app-cat"><button type="button" class="app-catbtn d-flex align-items-center gap-1" data-group-toggle="${id}" aria-expanded="${!state.collapsed.has(id)}">${icon("i-down")}<span class="app-label">${esc(name)}</span></button></th>${months.map(cells).join("")}</tr>`;
    if (uncat) h += row(UNCAT);
    shown.forEach(({ g, cats: list }) => {
      h += grpRow(g.id, g.name, m => `<td class="app-ms app-num" data-gsum="${g.id}|${m}|assigned"></td><td class="app-num" data-gsum="${g.id}|${m}|activity"></td><td class="app-num" data-gsum="${g.id}|${m}|avail"></td>`);
      if (!state.collapsed.has(g.id)) list.forEach(c => (h += row(c)));
    });
    if (income.length) {
      h += grpRow("income", "💰 Einnahmen", m => `<td class="app-ms"></td><td class="app-num" data-isum="${m}"></td><td></td>`);
      if (!state.collapsed.has("income")) income.forEach((p, i) => (h += `<tr class="app-inc"><td class="app-cat"><span class="app-catname ps-4"><span class="app-label">${esc(p)}</span></span></td>${months.map(m => `<td class="app-ms"></td><td class="app-num" data-inc="${i}|${m}"></td><td></td>`).join("")}</tr>`));
    }
    if (!shown.length && !uncat) h += `<tr><td class="app-cat"></td><td colspan="${months.length * 3}" class="text-center text-body-secondary py-4">${state.filter === "paused" ? `Keine pausierten Ziele im ${mName(f)}.` : "Keine Kategorien in diesem Filter."}</td></tr>`;
    $("[data-budget-table]").innerHTML = h + "</tbody>";

    const span = clamp(Math.floor((($('[data-screen="budget"]').clientWidth - (state.insp ? INSP_W : 0)) - catW() - 90) / 42), 5, 12);
    const from = clamp(months[0] - Math.floor((span - months.length) / 2), 0, Math.max(0, LAST - span + 1)), vis = new Set(months);
    let strip = `<button type="button" data-month-step="-1" aria-label="Früher">${icon("i-back")}</button>`;
    for (let m = from; m <= Math.min(LAST, from + span - 1); m++) {
      if (m === from || ym(m)[1] === 0) strip += `<span class="app-year">${ym(m)[0]}</span>`;
      strip += `<button type="button" class="${m === f ? "is-focus" : vis.has(m) ? "is-sel" : ""}${m === CUR ? " is-cur" : ""}" data-goto-month="${m}"${m === CUR ? ' aria-current="date"' : ""}>${mShort(m)}</button>`;
    }
    $("[data-month-strip]").innerHTML = strip + `<button type="button" data-month-step="1" aria-label="Später">${icon("i-chevron")}</button>`;

    const prow = c => `<button type="button" class="list-group-item list-group-item-action app-prow" data-open-cat="${c.id}">
        <span class="app-crow"><span class="flex-grow-1" style="min-width:0">${catName(c)}</span><span class="badge rounded-pill app-pill" data-avail="${c.id}|${f}"></span></span>${line2(c, "span")}</button>`;
    const pgroup = (id, name, sumAttr, body) => `<div class="card mb-3"><button type="button" class="card-header app-catbtn d-flex align-items-center gap-2" data-group-toggle="${id}" aria-expanded="${!state.collapsed.has(id)}">${icon("i-down")}<span class="fw-semibold text-truncate">${esc(name)}</span><span class="ms-auto small tabular-nums text-body-secondary text-nowrap app-gsum" ${sumAttr}></span></button>${state.collapsed.has(id) ? "" : `<div class="list-group list-group-flush">${body}</div>`}</div>`;
    let l = uncat ? `<div class="list-group mb-3">${prow(UNCAT)}</div>` : "";
    shown.forEach(({ g, cats: list }) => (l += pgroup(g.id, g.name, `data-gsum="${g.id}|${f}|avail"`, list.map(prow).join(""))));
    if (income.length) l += pgroup("income", "💰 Einnahmen", `data-isum="${f}"`, income.map((p, i) => `<div class="list-group-item d-flex align-items-center gap-3"><span class="flex-grow-1 text-truncate">${esc(p)}</span><span class="tabular-nums text-nowrap" data-inc="${i}|${f}"></span></div>`).join(""));
    $("[data-budget-list]").innerHTML = l || '<p class="text-center text-body-secondary py-4">Keine Kategorien in diesem Filter.</p>';
    $("[data-rta-phone]").innerHTML = rtaPhone(f);
    $$("[data-group-toggle] svg").forEach(s => (s.style.transform = state.collapsed.has(s.parentElement.dataset.groupToggle) ? "rotate(-90deg)" : ""));

    $("[data-inspector]").classList.toggle("d-none", !state.insp);
    if (state.insp && $("#panel").classList.contains("show")) bootstrap.Offcanvas.getInstance($("#panel"))?.hide();
    sizeCols();
    paint();
  }

  const menuItems = m => `
    <li><button class="dropdown-item" type="button" data-auto="under|${m}">Unterfinanzierte füllen</button></li>
    <li><button class="dropdown-item" type="button" data-auto="last|${m}">Wie letzten Monat</button></li>
    <li><button class="dropdown-item" type="button" data-auto="spent|${m}">Ausgaben letzten Monat</button></li>
    <li><button class="dropdown-item" type="button" data-auto="avg|${m}">Durchschnitt (3 Monate)</button></li>
    <li><button class="dropdown-item" type="button" data-auto="reset|${m}">Verfügbar zurücksetzen</button></li>
    <li><hr class="dropdown-divider"></li>
    <li><button class="dropdown-item" type="button" data-auto="pick|${m}">In eine Kategorie …</button></li>`;
  // The focus month gets the full YNAB 4 card, the others a slim one with the calculation behind a toggle.
  const calcToggle = (m, open) => `<button type="button" class="app-calc-toggle d-inline-flex align-items-center gap-1" data-calc-toggle="${m}" aria-expanded="${open}">${icon(open ? "i-down" : "i-chevron")}So rechnet sich „Zu verteilen“</button>`;
  const monthCard = (m, full) => {
    const open = full || state.calcOpen.has(m);
    return `
    <div class="card app-mcard${full ? " is-focus" : ""}" data-focus-month="${m}">
      <div class="card-body p-2 d-flex flex-column gap-1">
        <div class="d-flex align-items-center gap-2">
          <span class="app-mname">${mName(m)}</span><span class="text-body-secondary">${ym(m)[0]}</span>
          ${m === CUR ? '<span class="badge text-bg-warning">aktuell</span>' : ""}${m === IMPORTED ? '<span class="badge text-bg-secondary">aus YNAB</span>' : ""}
          <div class="dropdown ms-auto"><button class="btn btn-sm btn-link text-reset p-0" type="button" data-bs-toggle="dropdown" aria-expanded="false" aria-label="Monatsmenü ${mName(m)}">${icon("i-dots")}</button>
            <ul class="dropdown-menu dropdown-menu-end">${menuItems(m)}<li><hr class="dropdown-divider"></li><li><button class="dropdown-item" type="button" data-summary="${m}">Monatsübersicht</button></li></ul></div>
        </div>
        ${full ? "" : calcToggle(m, open)}
        <div class="app-calc" data-calc="${m}"${open ? "" : " hidden"}></div>
        <div class="d-flex align-items-end gap-2 mt-auto pt-1">
          <div class="me-auto" style="min-width:0"><div class="app-rta-big" data-rta="${m}"></div><div class="fw-semibold" data-rta-label="${m}"></div></div>
          <div data-rta-act="${m}"></div>
        </div>
      </div>
    </div>`;
  };
  const rtaPhone = m => `
    <div class="d-flex align-items-center gap-2 mt-2">
      <div class="me-auto" style="min-width:0"><div class="app-rta-big" data-rta="${m}"></div><div class="small fw-semibold" data-rta-label="${m}"></div></div>
      <div data-rta-act="${m}"></div>
    </div>
    ${calcToggle(m, state.calcOpen.has(m))}
    <div class="app-calc mt-1" data-calc="${m}"${state.calcOpen.has(m) ? "" : " hidden"}></div>`;

  const tone = (c, r) => r.avail < 0 ? ["text-bg-danger", ""] : r.under > 0 ? ["text-bg-warning", "i-half"] : r.avail > 0 ? ["text-bg-success", c.target && !r.snoozed ? "i-okc" : ""] : ["bg-body-secondary text-body-secondary", ""];
  function targetStatus(c, r, m) {
    const budget = r.carry + r.assigned, spent = -r.activity;
    if (r.avail < 0) return { text: `Überzogen. ${eur(spent)} von ${eur(budget)}`, bars: [[100, "bg-danger"]] };
    if (!c.target) return null;
    if (r.snoozed) return { text: `Pausiert im ${mName(m)}`, bars: [] };
    if (r.under > 0) return { text: c.target.cadence === "month" ? `Noch ${eur(r.under)} nötig bis zum ${lastDay(m)}.` : `Noch ${eur(r.under)} diesen Monat nötig`, bars: [[Math.round(r.progress * 100), "bg-warning"]] };
    if (spent > 0 && r.avail === 0) return { text: "Ganz ausgegeben", bars: [[100, "bg-success progress-bar-striped"]] };
    if (spent > 0) { const p = Math.round((spent / budget) * 100); return { text: `Finanziert. ${eur(spent)} von ${eur(budget)} ausgegeben`, bars: [[p, "bg-success progress-bar-striped opacity-50"], [100 - p, "bg-success"]] }; }
    return { text: c.target.cadence === "year" ? "Im Plan" : "Finanziert", bars: [[100, "bg-success"]] };
  }
  const rtaState = s => s.disp < 0 ? ["text-danger", "Zu viel verteilt"] : s.closed ? ["text-body-secondary", "Nicht verteilt am Monatsende"]
    : s.disp > 0 ? ["text-success", "Zu verteilen"] : ["", "Alles verteilt ✓"];
  // How much more can go into month m without borrowing, and which month sets the limit
  const capText = m => {
    const s = state.M.months[m], free = Math.max(0, s.free), k = s.freeAt;
    if (!free) return `Nichts mehr frei, sonst wird ${k === m ? "„Zu verteilen“" : mName(k)} negativ.`;
    return k === m ? `max. +${eur(free)} (Zu verteilen im ${mName(m)})` : `max. +${eur(free)}, damit ${mName(k)} nicht negativ wird`;
  };

  function paintMonths(M, root = document) {
    $$("[data-calc]", root).forEach(el => {
      const m = +el.dataset.calc, s = M.months[m], p = m - 1;
      const ln = (v, label, cls = "") => `<div class="${cls}"><span>${v}</span><span>${label}</span></div>`;
      // the first line is the previous card's number, plus what that card held back for this month and later
      const before = p >= 0 ? M.months[p].disp : s.prevRta, held = s.prevRta - before;
      el.innerHTML = ln(num(before), `Nicht verteilt im ${mShort(p)}`, before < 0 ? "text-danger" : "") +
        (held ? ln("+" + num(held), `im ${mShort(p)} für ${mShort(m)}${s.future ? " ff." : ""} reserviert`) : "") +
        ln(num(s.prevOver), `Überzogen im ${mShort(p)}`, s.prevOver < 0 ? "text-danger" : "") +
        ln("+" + num(s.income), `Einnahmen im ${mShort(m)}`) + ln(num(-s.assigned), `Zugewiesen im ${mShort(m)}`) +
        (s.closed ? "" : ln(num(-s.future), s.future ? `für ${mShort(m + 1)}${M.months[m + 1]?.future ? " ff." : ""} reserviert` : "In künftigen Monaten zugewiesen"));
    });
    $$("[data-rta]", root).forEach(el => { const s = M.months[el.dataset.rta]; el.textContent = (el.closest(".app-mcard") ? "= " : "") + eur(s.disp); el.className = "app-rta-big " + rtaState(s)[0]; });
    $$("[data-rta-label]", root).forEach(el => {
      const s = M.months[el.dataset.rtaLabel];
      el.innerHTML = esc(rtaState(s)[1]) + (s.closed ? ' <span class="fw-normal text-body-secondary">· abgeschlossen</span>' : "");
    });
    $$("[data-rta-act]", root).forEach(el => {
      const m = el.dataset.rtaAct, v = M.months[m].closed ? 0 : M.months[m].show;
      el.innerHTML = v > 0 ? `<div class="dropdown"><button class="btn btn-sm btn-success dropdown-toggle" type="button" data-bs-toggle="dropdown" aria-expanded="false">Verteilen</button><ul class="dropdown-menu dropdown-menu-end">${menuItems(m)}</ul></div>`
        : v < 0 ? `<button type="button" class="btn btn-sm btn-danger" data-cover-rta="${m}">Aus Kategorien decken</button>` : "";
    });
  }

  function paint() {
    const M = (state.M = model());
    checkBooks(M);
    const f = focusMonth();
    $$("[data-assign]").forEach(i => { const [c, m] = i.dataset.assign.split("|"), v = M.cats[c][m].assigned; if (i !== document.activeElement) { i.value = num(v); i.classList.remove("is-invalid"); } i.classList.toggle("app-zero", v === 0); });
    $$("[data-act]").forEach(el => { const [c, m] = el.dataset.act.split("|"), v = M.cats[c][m].activity; el.textContent = num(v); el.className = "app-num " + (zero(v) || "text-body-secondary"); });
    $$("[data-avail]").forEach(el => {
      const [c, m] = el.dataset.avail.split("|"), r = M.cats[c][m];
      if (el.classList.contains("app-q")) {
        el.className = "app-q " + (r.avail < 0 ? "app-neg" : zero(r.avail));
        el.innerHTML = (r.under > 0 ? '<span class="app-udot"></span>' : "") + num(r.avail);
      } else {
        const [cls, ic] = tone(cat(c), r);
        el.className = `badge rounded-pill app-pill border-0 ${cls}`;
        el.innerHTML = (ic ? icon(ic) : "") + eur(r.avail);
      }
      el.title = r.avail < 0 ? "Überzogen – klicken zum Decken" : r.under > 0 ? `Ziel: noch ${eur(r.under)} nötig` : "Geld verschieben";
    });
    $$("[data-line2]").forEach(el => {
      const c = el.dataset.line2, r = M.cats[c][f], st = targetStatus(cat(c), r, f), bar = $("[data-bar]", el), ts = $("[data-tstat]", el);
      el.hidden = !st;
      bar.hidden = !st?.bars.length;
      bar.innerHTML = st ? st.bars.map(([w, cls]) => `<div class="progress-bar ${cls}" style="width:${w}%"></div>`).join("") : "";
      ts.textContent = st ? st.text : ""; ts.title = ts.textContent;
      ts.classList.toggle("is-over", r.avail < 0);
    });
    $$("[data-gsum]").forEach(el => { const [g, m, k] = el.dataset.gsum.split("|"), v = sum(groups.find(x => x.id === g).cats, c => M.cats[c.id][m][k]); el.textContent = num(v); el.classList.toggle("app-zero", v === 0); el.classList.toggle("app-neg", v < 0 && k === "avail"); });
    $$("[data-msum]").forEach(el => { const [m, k] = el.dataset.msum.split("|"); el.textContent = num(M.months[m][k]); });
    $$("[data-inc]").forEach(el => { const [i, m] = el.dataset.inc.split("|"), v = M.income[state.incomeKeys[i]][m]; el.textContent = el.closest("[data-budget-list]") ? eur(v) : num(v); el.classList.toggle("app-zero", v === 0); });
    $$("[data-isum]").forEach(el => { const m = +el.dataset.isum; el.textContent = num(M.months[m].income); });
    paintMonths(M);

    const count = key => [...cats(), UNCAT].filter(c => (c !== UNCAT || M.cats.uncat[f].activity) && FILTERS[key](c, M.cats[c.id][f])).length;
    const chip = (key, label, extra = "") => `<button type="button" class="btn btn-sm btn-pill ${state.filter === key ? "btn-primary" : extra || "btn-light"}" data-filter="${key}" aria-pressed="${state.filter === key}">${label}</button>`;
    const ov = count("over"), un = count("under"), pa = count("paused");
    $("[data-chips]").innerHTML = chip("all", "Alle") + chip("over", `${ov ? icon("i-alert") + " " : ""}${ov} überzogen`, ov ? "btn-outline-danger" : "") +
      chip("under", `Unterfinanziert${un ? " · " + un : ""}`) + chip("overfunded", "Überfinanziert") + chip("money", "Geld verfügbar") + chip("paused", `Pausiert${pa ? " · " + pa : ""}`);

    const hints = [];
    const neg = M.months.findIndex((x, k) => k > f && x.rta < 0);
    if (!state.insp && neg > 0) hints.push(`<div class="alert alert-danger d-flex flex-wrap align-items-center gap-2 py-2 small mb-0"><span class="me-auto"><strong>Zu verteilen im ${mName(neg)} ist ${eur(M.months[neg].rta)}.</strong> Überzug im ${mName(neg - 1)} verringert das Geld für ${mName(neg)}.</span><button type="button" class="btn btn-sm btn-danger" data-cover-month="${neg - 1}">Überzug decken</button><button type="button" class="btn btn-sm btn-outline-danger" data-goto-month="${neg}">Zum ${mName(neg)}</button></div>`);
    if (visibleMonths().includes(IMPORTED)) hints.push('<div class="alert alert-secondary py-2 small mb-0">Juni 2026 ist aus YNAB übernommen. Dort war durch den Überzug aus dem Mai mehr verteilt als vorhanden; Abakus selbst lässt das nur durch Überzug zu, nie durch Zuweisen.</div>');
    $("[data-budget-hint]").innerHTML = hints.join("");

    const open = txs.filter(t => t.approved === false).length;
    $$("[data-unapproved-badge]").forEach(b => { b.textContent = open; b.hidden = !open; });
    $$("[data-undo]").forEach(b => (b.disabled = !undoStack.length));
    $$("[data-redo]").forEach(b => (b.disabled = !redoStack.length));
    const ai = document.activeElement;
    if (ai?.matches("[data-assign]") && !ai.classList.contains("is-invalid")) showCap(ai, capText(+ai.dataset.assign.split("|")[1]));
    renderSide();
    renderPanel();
  }

  // the assign limit as a small note under the focused input
  const cap = document.createElement("div");
  cap.className = "app-cap"; cap.hidden = true; cap.setAttribute("role", "status");
  document.body.append(cap);
  function showCap(i, text, bad = false) {
    cap.textContent = text; cap.classList.toggle("text-danger", bad); cap.hidden = false;
    const r = i.getBoundingClientRect();
    cap.style.left = clamp(r.right - cap.offsetWidth, 8, innerWidth - cap.offsetWidth - 8) + "px";
    cap.style.top = r.bottom + 4 + "px";
  }
  document.addEventListener("focusout", e => { if (e.target.matches("[data-assign]")) cap.hidden = true; });
  addEventListener("scroll", () => (cap.hidden = true), { passive: true });

  // ------------------------------------------------------------ inspector / overlay panel
  const panel = $("#panel");
  const panelBody = () => (state.insp ? $("[data-inspector]") : $("[data-panel-body]"));
  function renderPanel() {
    if (state.screen !== "budget" && !panel.classList.contains("show")) return;
    if (!state.insp && !panel.classList.contains("show") && !panel.classList.contains("showing")) return;
    const el = panelBody();
    if (el.contains(document.activeElement) && document.activeElement.matches("input, select, textarea")) return;
    const m = focusMonth(), c = state.sel && cat(state.sel);
    if (c && state.sheet === "cover" && !state.insp) {
      $("#panelTitle").textContent = `Überzug decken · ${catText(c)}`;
      const r = state.M.cats[c.id][m];
      el.innerHTML = r.avail < 0 ? `${coverForm(c, m, -r.avail, true)}<button type="button" class="btn btn-sm btn-link px-0 mt-3" data-sheet-details>Details und Ziel</button>`
        : `<p class="small">${esc(catText(c))} ist gedeckt.</p><button type="button" class="btn btn-sm btn-primary" data-sheet-details>Details und Ziel</button>`;
      return;
    }
    $("#panelTitle").textContent = c ? catText(c) : `Zusammenfassung ${mName(m)}`;
    el.innerHTML = c ? catDetail(c, m) : monthSummary(m);
    paintMonths(state.M, el);
  }
  const openPanel = () => {
    if (!state.insp) {
      panel.classList.toggle("offcanvas-end", isDesktop());
      panel.classList.toggle("offcanvas-bottom", !isDesktop());
      bootstrap.Offcanvas.getOrCreateInstance(panel).show();
    }
    renderPanel();
  };
  panel.addEventListener("hidden.bs.offcanvas", () => {
    state.sheet = null;
    if (state.insp || !state.sel) return;
    state.sel = null; state.editTarget = false;
    if (state.pushed) { state.pushed = false; history.back(); } else if (state.screen === "budget") go("budget", budgetParams());
  });

  const line = (k, v, cls = "") => `<div class="d-flex justify-content-between gap-3 ${cls}"><span>${k}</span><span class="tabular-nums text-nowrap">${v}</span></div>`;
  function monthSummary(m) {
    const M = state.M, s = M.months[m], p = m > 0 ? M.months[m - 1] : null;
    const neg = M.months.findIndex((x, k) => k > m && x.rta < 0);
    const overs = [...cats(), UNCAT].filter(c => M.cats[c.id][m].avail < 0);
    const auto = (k, label, v) => `<button type="button" class="list-group-item list-group-item-action d-flex justify-content-between gap-2" data-auto="${k}|${m}"><span>${label}</span><span class="tabular-nums text-nowrap">${eur(v)}</span></button>`;
    const avg = sum(cats(), c => Math.round(sum([1, 2, 3], d => (m - d >= 0 ? c.assigned[m - d] : 0)) / 3));
    const futureList = M.months.map((x, k) => [k, x.assigned]).filter(([k, v]) => k > m && v > 0);
    return `
      ${state.insp ? `<h2 class="h5 mb-3">${mLabel(m)}</h2>` : ""}
      <div class="card mb-3"><div class="card-header fw-semibold">Zusammenfassung</div><div class="card-body small d-flex flex-column gap-1">
        ${line("Übrig aus Vormonat", eur(s.carry))}${line(`Zugewiesen im ${mName(m)}`, eur(s.assigned))}${line("Aktivität", eur(s.activity))}${line("Verfügbar", eur(s.avail), "fw-bold border-top pt-1")}
        <div class="mt-2 fw-semibold">Monatsbedarf</div>${line(`Ziele im ${mName(m)}`, eur(s.req))}${s.under ? line("Davon noch offen", eur(s.under), "text-warning-emphasis fw-semibold") : ""}
      </div></div>
      ${overs.length ? `<div class="card mb-3 border-danger"><div class="card-header fw-semibold text-danger d-flex align-items-center gap-2">${icon("i-alert")}${overs.length} überzogen</div><div class="list-group list-group-flush">${overs.map(c => `
        <div class="list-group-item d-flex align-items-center gap-2 small"><span class="flex-grow-1" style="min-width:0">${catName(c)}</span><span class="badge rounded-pill app-pill text-bg-danger">${eur(M.cats[c.id][m].avail)}</span><button type="button" class="btn btn-sm btn-outline-danger" data-cover="${c.id}|${m}">Decken</button></div>`).join("")}</div></div>` : ""}
      <div class="card mb-3"><div class="card-header fw-semibold d-flex align-items-center gap-2">${icon("i-bolt")}Auto-Verteilen</div><div class="list-group list-group-flush small">
        ${auto("under", "Unterfinanzierte", s.under)}${auto("last", "Wie letzten Monat", p ? p.assigned : 0)}${auto("spent", "Ausgaben letzten Monat", p ? -p.activity : 0)}${auto("avg", "Durchschnitt (3 Monate)", avg)}${auto("reset", "Verfügbar zurücksetzen", sum(cats(), c => Math.max(0, M.cats[c.id][m].avail)))}
      </div></div>
      <div class="card mb-3"><div class="card-header fw-semibold d-flex justify-content-between gap-2"><span>${neg > 0 ? icon("i-alert") + " " : ""}In künftigen Monaten zugewiesen</span><span class="tabular-nums text-nowrap">${eur(s.future)}</span></div><div class="card-body small">
        ${neg > 0 ? `<div class="alert alert-danger text-center py-2 mb-2"><strong>Zu verteilen im ${mName(neg)} ist ${eur(M.months[neg].rta)}</strong></div>
          <p class="text-body-secondary text-center">Überzug im ${mName(neg - 1)} verringert das Geld, das im ${mName(neg)} zu verteilen ist.</p>
          <div class="d-grid gap-2 mb-2"><button type="button" class="btn btn-sm btn-primary" data-cover-month="${neg - 1}">Überzug decken</button><button type="button" class="btn btn-sm btn-light" data-goto-month="${neg}">Zum ${mName(neg)}</button></div>` : ""}
        ${futureList.length ? futureList.map(([k, v]) => line(mLabel(k), eur(v))).join("") : '<span class="text-body-secondary">Nichts im Voraus verteilt.</span>'}
      </div></div>`;
  }

  const ring = (p, cls) => { const r = 40, c = 2 * Math.PI * r; return `<svg class="app-ring" viewBox="0 0 100 100" role="img" aria-label="${Math.round(p * 100)} Prozent"><circle cx="50" cy="50" r="${r}" fill="none" stroke="var(--felt-border-color)" stroke-width="10"/><circle cx="50" cy="50" r="${r}" fill="none" stroke="var(--felt-${cls})" stroke-width="10" stroke-linecap="round" stroke-dasharray="${(c * p).toFixed(1)} ${c.toFixed(1)}" transform="rotate(-90 50 50)"/><text x="50" y="57" text-anchor="middle" font-size="20" font-weight="700" fill="currentColor">${Math.round(p * 100)} %</text></svg>`; };
  const targetHead = t => t.cadence === "month"
    ? [t.mode === "refill" ? `Jeden Monat auffüllen bis ${eur(t.amount)}` : `Jeden Monat weitere ${eur(t.amount)} zurücklegen`, "Bis zum Monatsende"]
    : [`${eur(t.amount)} bis ${dLong(t.due)} ansparen`, `Jedes Jahr · ${t.mode === "refill" ? "auffüllen bis" : "weitere zurücklegen"}, verteilt auf die Monate bis dahin`];
  const targetText = t => (t ? targetHead(t)[0] : "Kein Ziel");
  const coverForm = (c, m, need, inline) => {
    const M = state.M, opts = cats().filter(x => x.id !== c.id && M.cats[x.id][m].avail > 0).sort((a, b) => M.cats[b.id][m].avail - M.cats[a.id][m].avail);
    const free = Math.max(0, M.months[m].free);
    return `<form class="d-flex flex-column gap-2" data-cover-form="${c.id}|${m}">
      <label class="small" for="cv-${c.id}">Decke <strong class="text-nowrap">${eur(need)}</strong> aus:</label>
      <select class="form-select form-select-sm" id="cv-${c.id}" name="from">${free > 0 ? `<option value="rta">📥 Zu verteilen (${eur(free)})</option>` : ""}${opts.map(x => `<option value="${x.id}">${esc(catText(x))} (${eur(M.cats[x.id][m].avail)})</option>`).join("")}</select>
      <div class="d-flex justify-content-end gap-2">${inline ? "" : '<button type="button" class="btn btn-sm" data-pop-close>Abbrechen</button>'}<button type="submit" class="btn btn-sm btn-primary">Decken</button></div></form>`;
  };
  const catOnlyOpts = (sel, skip) => groups.map(g => `<optgroup label="${esc(g.name)}">${g.cats.filter(x => x.id !== skip).map(x => `<option value="${x.id}"${x.id === sel ? " selected" : ""}>${esc(catText(x))}</option>`).join("")}</optgroup>`).join("");
  // move money between this category and another one (or "Zu verteilen"), YNAB style
  const moveForm = (c, m, key, inline) => {
    const r = state.M.cats[c.id][m], give = r.avail > 0;
    return `<form class="d-flex flex-column gap-2" data-move-form="${c.id}|${m}">
      <div class="input-group input-group-sm"><input class="form-control text-end tabular-nums" name="amount" inputmode="decimal" aria-label="Betrag" value="${num(give ? r.avail : r.under || Math.max(0, -r.avail))}"><span class="input-group-text">€</span></div>
      <div class="btn-group btn-group-sm w-100" role="group" aria-label="Richtung">
        <input type="radio" class="btn-check" name="dir" id="${key}-to" value="to"${give ? " checked" : ""}><label class="btn btn-outline-secondary" for="${key}-to">Abgeben an</label>
        <input type="radio" class="btn-check" name="dir" id="${key}-from" value="from"${give ? "" : " checked"}><label class="btn btn-outline-secondary" for="${key}-from">Holen aus</label>
      </div>
      <select class="form-select form-select-sm" name="other" aria-label="Andere Kategorie"><option value="rta">📥 Zu verteilen</option>${catOnlyOpts(null, c.id)}</select>
      <div class="d-flex justify-content-end gap-2">${inline ? "" : '<button type="button" class="btn btn-sm" data-pop-close>Abbrechen</button>'}<button type="submit" class="btn btn-sm btn-primary">Verschieben</button></div></form>`;
  };

  function catDetail(c, m) {
    const M = state.M, r = M.cats[c.id][m], p = m > 0 ? M.cats[c.id][m - 1] : null, t = c.target, [cls, ic] = tone(c, r);
    const back = state.insp ? `<button type="button" class="btn btn-sm btn-link px-0 mb-2 text-decoration-none" data-close-cat>${icon("i-back")} Monatsübersicht</button>` : "";
    if (c.id === "uncat") return `${back}<p class="small">Buchungen ohne Kategorie zählen als Überzug. Ordne sie im Konto einer Kategorie zu.</p><a class="btn btn-sm btn-primary" href="#konten?konto=alle">Zu den Buchungen</a>`;
    let h = `${back}${state.insp ? `<div class="d-flex align-items-center gap-2 mb-1"><h2 class="h5 mb-0 me-auto">${esc(catText(c))}</h2><button type="button" class="btn btn-sm btn-light" data-rename aria-label="Umbenennen">${icon("i-pencil")}</button></div>` : ""}
      <div class="small text-body-secondary mb-2">${mLabel(m)}${m === CUR ? " · aktueller Monat" : ""}</div>
      <div class="card mb-3"><div class="card-header d-flex align-items-center justify-content-between"><span class="fw-semibold">Verfügbarer Betrag</span><span class="badge rounded-pill app-pill ${cls}">${ic ? icon(ic) : ""}${eur(r.avail)}</span></div>
        <div class="card-body small d-flex flex-column gap-1">
          ${line("Übrig aus Vormonat", eur(r.carry))}${p && p.avail < 0 ? line(`Überzug ${mName(m - 1)} ging an „Zu verteilen“`, eur(p.avail), "text-danger") : ""}
          ${line("Diesen Monat zugewiesen", signed(r.assigned))}${line("Ausgaben", signed(r.activity))}
          <label class="form-label mt-2 mb-1 fw-semibold" for="cd-assign">Zugewiesen im ${mName(m)}</label>
          <div class="input-group input-group-sm has-validation"><input class="form-control text-end tabular-nums" id="cd-assign" inputmode="decimal" autocomplete="off" value="${num(r.assigned)}" data-detail-assign aria-describedby="cd-hint"><span class="input-group-text">€</span></div>
          <div class="form-text mt-0" id="cd-hint" data-detail-hint>${capText(m)}</div>
          <div class="d-grid gap-1 mt-1">
            <button type="button" class="btn btn-sm btn-outline-secondary d-flex justify-content-between gap-2" data-set="${p ? p.assigned : 0}"${p ? "" : " disabled"}><span>Wie Vormonat</span><span class="tabular-nums">${eur(p ? p.assigned : 0)}</span></button>
            <button type="button" class="btn btn-sm btn-outline-secondary d-flex justify-content-between gap-2" data-set="${p ? -p.activity : 0}"${p ? "" : " disabled"}><span>Ausgaben Vormonat</span><span class="tabular-nums">${eur(p ? -p.activity : 0)}</span></button>
          </div>
        </div></div>`;
    if (r.avail < 0) h += `<div class="card mb-3 border-danger"><div class="card-header fw-semibold text-danger">Überzug decken</div><div class="card-body">${m < CUR ? `<p class="small text-body-secondary">Im ${mName(m)} überzogen; am 1. ${mName(m + 1)} von „Zu verteilen“ abgezogen.</p>` : ""}${coverForm(c, m, -r.avail, true)}</div></div>`;
    const snooze = t ? `<button type="button" class="btn btn-sm btn-outline-secondary" data-snooze="${m}">${r.snoozed ? "Fortsetzen" : "Pausieren"}</button>` : "";
    h += `<div class="card mb-3"><div class="card-header fw-semibold d-flex align-items-center gap-2">${icon("i-target")}Ziel${r.snoozed ? '<span class="badge text-bg-secondary ms-auto">pausiert</span>' : ""}</div><div class="card-body small">`;
    if (t && !state.editTarget && r.snoozed) {
      h += `<div class="fw-semibold">${targetHead(t)[0]}</div><div class="text-body-secondary mb-2">${targetHead(t)[1]}</div>
        <div class="alert alert-secondary text-center py-2">Im ${mName(m)} pausiert: das Ziel zählt diesen Monat nicht als unterfinanziert.</div>
        <div class="d-flex gap-2">${snooze}<button type="button" class="btn btn-sm btn-light flex-grow-1" data-edit-target>Ziel bearbeiten</button></div>`;
    } else if (t && !state.editTarget) {
      const [head, sub] = targetHead(t), pct = t.cadence === "year" ? r.progress : r.req ? (r.req - r.under) / r.req : 1;
      h += `<div class="fw-semibold">${head}</div><div class="text-body-secondary mb-2">${sub}</div>
        <div class="text-center mb-2">${ring(pct, r.under > 0 ? "warning" : "success")}</div>
        ${r.under > 0 ? `<div class="alert alert-warning text-center py-2"><div>Weise noch <strong class="text-nowrap">${eur(r.under)}</strong> zu, um dein Ziel zu erreichen</div><button type="button" class="btn btn-sm btn-warning w-100 mt-2" data-set="${r.assigned + r.under}">Zuweisen</button></div>`
          : `<div class="alert alert-success text-center py-2">${t.cadence === "year" ? `Im Plan, ${eur(r.req)} diesen Monat` : "Ziel für diesen Monat erreicht"}</div>`}
        ${line("Diesen Monat zuzuweisen", eur(r.req))}${line("Bisher zugewiesen", eur(r.assigned))}
        <div class="d-flex gap-2 mt-2">${snooze}<button type="button" class="btn btn-sm btn-light flex-grow-1" data-edit-target>Ziel bearbeiten</button></div>`;
    } else if (!t && !state.editTarget) {
      h += `<p class="text-body-secondary">Kein Ziel. Ein Ziel sagt dir, wie viel diese Kategorie jeden Monat braucht.</p><button type="button" class="btn btn-sm btn-primary w-100" data-edit-target>Ziel festlegen</button>`;
    } else {
      const v = t || { amount: 0, cadence: "month", mode: "setaside", due: "" };
      h += `<form class="d-flex flex-column gap-2" data-target-form>
        <div class="fw-semibold">Für Ausgaben benötigt</div>
        <label class="form-label mb-0" for="tg-amount">Ich brauche</label>
        <div class="input-group input-group-sm"><input class="form-control text-end tabular-nums" id="tg-amount" name="amount" inputmode="decimal" value="${v.amount ? num(v.amount) : ""}" required><span class="input-group-text">€</span></div>
        <div class="btn-group btn-group-sm w-100" role="group" aria-label="Rhythmus">
          <input type="radio" class="btn-check" name="cadence" id="tg-m" value="month"${v.cadence === "month" ? " checked" : ""}><label class="btn btn-outline-secondary" for="tg-m">Jeden Monat</label>
          <input type="radio" class="btn-check" name="cadence" id="tg-y" value="year"${v.cadence === "year" ? " checked" : ""}><label class="btn btn-outline-secondary" for="tg-y">Jedes Jahr (bis Datum)</label>
        </div>
        <div data-tg-due${v.cadence === "year" ? "" : " hidden"}><label class="form-label mb-1" for="tg-due">Fällig am</label><input type="date" class="form-control form-control-sm" id="tg-due" name="due" min="2026-10-09" value="${v.due || ""}"></div>
        <label class="form-label mb-0" for="tg-mode">Nächsten Monat möchte ich:</label>
        <select class="form-select form-select-sm" id="tg-mode" name="mode"><option value="setaside"${v.mode === "setaside" ? " selected" : ""}>Weitere zurücklegen</option><option value="refill"${v.mode === "refill" ? " selected" : ""}>Auffüllen bis</option></select>
        <div class="form-text mt-0" data-tg-preview></div>
        <div class="d-flex flex-wrap gap-2 mt-1"><button type="submit" class="btn btn-sm btn-primary">Speichern</button>${t ? `${snooze}<button type="button" class="btn btn-sm btn-outline-danger" data-delete-target>Löschen</button>` : ""}<button type="button" class="btn btn-sm ms-auto" data-cancel-target>Abbrechen</button></div>
      </form>`;
    }
    h += `</div></div>
      <details class="card"><summary class="card-header fw-semibold d-flex align-items-center gap-2" style="cursor:pointer">${icon("i-swap")}Geld verschieben</summary>
        <div class="card-body small">${moveForm(c, m, "mvd", true)}</div></details>`;
    return h;
  }
  // what a target editor draft asks for this month, so a yearly date target shows its monthly amount right away
  function targetPreview(f) {
    const el = $("[data-tg-preview]", f), amount = parse(f.amount.value), c = cat(state.sel), m = focusMonth();
    if (!el || !c) return;
    if (!(amount > 0) || (f.cadence.value === "year" && !f.due.value)) return (el.textContent = "");
    const r = state.M.cats[c.id][m], t = { amount, cadence: f.cadence.value, mode: f.mode.value, due: f.due.value };
    const req = targetFor({ ...c, target: t }, m, r.carry, r.assigned).req;
    el.textContent = `Im ${mName(m)} zuzuweisen: ${eur(req)}` + (t.cadence === "year" ? ` (bis ${dLong(t.due)})` : "");
  }

  // ------------------------------------------------------------ popovers (move money, cover overspending, reconcile)
  const pop = $("[data-pop]");
  let popAnchor = null;
  function openPop(anchor, html) {
    pop.innerHTML = `<div class="card-body">${html}</div>`;
    pop.hidden = false;
    popAnchor = anchor;
    const r = anchor.getBoundingClientRect(), w = pop.offsetWidth, h = pop.offsetHeight;
    pop.style.left = clamp(r.right - w, 8, innerWidth - w - 8) + "px";
    pop.style.top = (r.bottom + h + 8 > innerHeight ? Math.max(8, r.top - h - 6) : r.bottom + 6) + "px";
    $("select, input:not([type=radio]), button.btn-primary", pop)?.focus();
  }
  const closePop = () => { pop.hidden = true; popAnchor = null; };
  document.addEventListener("click", e => { if (!pop.hidden && !pop.contains(e.target) && !popAnchor?.contains(e.target)) closePop(); }, true);
  document.addEventListener("keydown", e => { if (e.key === "Escape" && !pop.hidden) closePop(); });
  const openCover = (c, m, anchor) => {
    if (c.id === "uncat") return openPop(anchor, '<div class="fw-semibold mb-1">Nicht kategorisiert</div><p class="small">Ordne die Buchungen einer Kategorie zu, dann ist der Überzug weg.</p><a class="btn btn-sm btn-primary" href="#konten?konto=alle">Zu den Buchungen</a>');
    openPop(anchor, `<div class="fw-semibold mb-2">Überzug decken · ${esc(catText(c))}</div>${coverForm(c, m, -state.M.cats[c.id][m].avail)}`);
  };
  function openMove(c, m, anchor) {
    if (c.id === "uncat") return openCover(c, m, anchor);
    const r = state.M.cats[c.id][m], over = r.avail < 0, [cls, ic] = tone(c, r);
    openPop(anchor, `<div class="d-flex align-items-center gap-2 mb-2"><span class="fw-semibold me-auto text-truncate">${esc(catText(c))}</span><span class="badge rounded-pill app-pill ${cls}">${ic ? icon(ic) : ""}${eur(r.avail)}</span></div>
      <div class="small text-body-secondary mb-2">${mLabel(m)}</div>
      ${over ? `<div class="btn-group btn-group-sm w-100 mb-2" role="group" aria-label="Aktion"><input type="radio" class="btn-check" name="pm" id="pm-cover" value="cover" checked data-pm><label class="btn btn-outline-secondary" for="pm-cover">Decken</label><input type="radio" class="btn-check" name="pm" id="pm-move" value="move" data-pm><label class="btn btn-outline-secondary" for="pm-move">Verschieben</label></div>` : ""}
      ${over ? `<div data-pm-pane="cover">${coverForm(c, m, -r.avail)}</div>` : ""}
      <div data-pm-pane="move"${over ? " hidden" : ""}>${moveForm(c, m, "mvp")}</div>
      <button type="button" class="btn btn-sm btn-link px-0 mt-2 text-decoration-none" data-open-cat="${c.id}">Details und Ziel ${icon("i-chevron")}</button>`);
  }
  function openPick(m, anchor) {
    const M = state.M, first = cats().find(x => M.cats[x.id][m].under > 0) || cats()[0], free = Math.max(0, M.months[m].free);
    openPop(anchor, `<div class="fw-semibold mb-2">In eine Kategorie verteilen · ${mName(m)}</div>
      <form class="d-flex flex-column gap-2" data-pick-form="${m}">
        <select class="form-select form-select-sm" name="cat" aria-label="Kategorie" data-pick-cat-select>${catOnlyOpts(first.id)}</select>
        <div class="input-group input-group-sm"><input class="form-control text-end tabular-nums" name="amount" inputmode="decimal" aria-label="Betrag" value="${num(Math.min(free, M.cats[first.id][m].under || free))}"><span class="input-group-text">€</span></div>
        <div class="form-text mt-0">${capText(m)}</div>
        <div class="d-flex justify-content-end gap-2"><button type="button" class="btn btn-sm" data-pop-close>Abbrechen</button><button type="submit" class="btn btn-sm btn-primary">Zuweisen</button></div>
      </form>`);
  }

  // ------------------------------------------------------------ budget interactions
  let pending = null;
  document.addEventListener("focusin", e => {
    if (e.target.matches("[data-assign], [data-detail-assign]")) pending = snap();
    if (e.target.matches("[data-assign]")) showCap(e.target, capText(+e.target.dataset.assign.split("|")[1]));
  });
  document.addEventListener("input", e => {
    const i = e.target.closest("[data-assign]");
    if (i) {
      const v = parse(i.value), [c, m] = i.dataset.assign.split("|");
      if (Number.isNaN(v)) return;
      const before = pending;
      if (tryAssign(cat(c), +m, v)) {
        if (before) { undoStack.push(before); redoStack.length = 0; pending = null; }
        i.classList.remove("is-invalid");
        paint();
      } else {
        i.classList.add("is-invalid");
        showCap(i, `${NO_MONEY} ${capText(+m)}`, true);
      }
    }
    const tf = e.target.closest("[data-target-form]");
    if (tf) targetPreview(tf);
  });
  document.addEventListener("change", e => {
    const i = e.target.closest("[data-assign]");
    if (i) { const [c, m] = i.dataset.assign.split("|"); i.value = num(cat(c).assigned[m]); i.classList.remove("is-invalid"); paint(); }
    const d = e.target.closest("[data-detail-assign]");
    if (d) {
      const v = parse(d.value), c = cat(state.sel), m = focusMonth();
      if (Number.isNaN(v)) return;
      const before = pending;
      if (tryAssign(c, m, v)) { if (before) { undoStack.push(before); redoStack.length = 0; } pending = null; d.blur(); paint(); }
      else { d.classList.add("is-invalid"); $("[data-detail-hint]").className = "form-text mt-0 text-danger"; $("[data-detail-hint]").textContent = `${NO_MONEY} ${capText(m)}`; }
    }
    if (e.target.matches('[data-target-form] [name="cadence"]')) $("[data-tg-due]").hidden = e.target.value !== "year";
    const tf = e.target.closest("[data-target-form]");
    if (tf) targetPreview(tf);
    if (e.target.matches("[data-pm]")) $$("[data-pm-pane]", pop).forEach(p => (p.hidden = p.dataset.pmPane !== e.target.value));
    if (e.target.matches("[data-pick-cat-select]")) {
      const m = +e.target.form.dataset.pickForm, r = state.M.cats[e.target.value][m], free = Math.max(0, state.M.months[m].free);
      e.target.form.amount.value = num(Math.min(free, r.under || free));
    }
  });
  document.addEventListener("keydown", e => {
    const i = e.target.closest("[data-assign]");
    if (i && e.key === "Enter") {
      e.preventDefault();
      const m = i.dataset.assign.split("|")[1], all = $$(`[data-assign$="|${m}"]`), next = all[all.indexOf(i) + 1];
      (next || i).focus(); next?.select();
    }
    if (e.target.matches("[data-detail-assign]") && e.key === "Enter") { e.preventDefault(); e.target.dispatchEvent(new Event("change", { bubbles: true })); }
  });

  // On phones the sheet is a history entry, so "back" closes it.
  function selectCat(id, sheet = null) {
    const push = !state.insp && !panel.classList.contains("show") && !state.pushed;
    state.sel = id; state.editTarget = false; state.sheet = sheet;
    const url = "#budget?" + new URLSearchParams(Object.entries(budgetParams()).filter(([, v]) => v != null));
    if (push) { history.pushState(null, "", url); state.pushed = true; } else history.replaceState(null, "", url);
    $$("[data-row]").forEach(tr => { tr.classList.toggle("is-sel", tr.dataset.row === id); const cb = $("[data-pick-cat]", tr); if (cb) cb.checked = tr.dataset.row === id; });
    closePop();
    openPanel();
  }
  const setFocus = m => { if (m === focusMonth()) return; state.focus = m; renderBudget(); };
  const undoable = (before, msg) => { undoStack.push(before); redoStack.length = 0; closePop(); paint(); if (state.sheet === "cover") bootstrap.Offcanvas.getInstance(panel)?.hide(); return toast(msg); };

  function autoAssign(kind, m, anchor) {
    const M = state.M;
    if (kind === "pick") return openPick(m, anchor);
    const target = c => {
      const r = M.cats[c.id][m], p = m > 0 ? M.cats[c.id][m - 1] : null;
      return { under: r.assigned + r.under, last: p ? p.assigned : r.assigned, spent: p ? -p.activity : r.assigned, avg: Math.round(sum([1, 2, 3], d => (m - d >= 0 ? c.assigned[m - d] : 0)) / 3), reset: r.assigned - Math.max(0, r.avail) }[kind];
    };
    const before = snap();
    let missed = 0;
    cats().forEach(c => {
      const v = target(c);
      if (tryAssign(c, m, v)) return;
      missed++;
      if (kind !== "under") return;
      const room = Math.max(0, model().months[m].free);
      if (room > 0) tryAssign(c, m, c.assigned[m] + Math.min(room, v - c.assigned[m]));
    });
    if (missed && kind !== "under") { restore(before); paint(); return toast(NO_MONEY, "danger"); }
    undoStack.push(before); redoStack.length = 0;
    paint();
    toast(missed ? `Nur teilweise gefüllt. ${NO_MONEY}` : "Verteilt.", missed ? "warning" : "success");
  }

  document.addEventListener("click", e => {
    const t = e.target;
    const tog = t.closest("[data-group-toggle]");
    if (tog) { const g = tog.dataset.groupToggle; state.collapsed.has(g) ? state.collapsed.delete(g) : state.collapsed.add(g); return renderBudget(); }
    const ct = t.closest("[data-calc-toggle]");
    if (ct) {
      const m = +ct.dataset.calcToggle, open = !state.calcOpen.has(m);
      open ? state.calcOpen.add(m) : state.calcOpen.delete(m);
      $$(`[data-calc-toggle="${m}"]`).forEach(b => { b.setAttribute("aria-expanded", open); $("use", b).setAttribute("href", open ? "#i-down" : "#i-chevron"); b.nextElementSibling.hidden = !open; });
      return;
    }
    const av = t.closest("[data-avail]");
    if (av && state.screen === "budget" && !pop.contains(av)) {
      const [c, m] = av.dataset.avail.split("|"), over = state.M.cats[c][m].avail < 0;
      if (av.closest("[data-budget-list]")) { if (over && c !== "uncat") { e.stopPropagation(); return selectCat(c, "cover"); } }
      else return openMove(cat(c), +m, av);
    }
    if (t.closest("[data-sheet-details]")) { state.sheet = null; return renderPanel(); }
    const oc = t.closest("[data-open-cat]");
    if (oc) return selectCat(oc.dataset.openCat);
    const pk = t.closest("[data-pick-cat]");
    if (pk) { if (pk.checked) return selectCat(pk.dataset.pickCat); state.sel = null; return go("budget", budgetParams()); }
    if (t.closest("[data-close-cat]")) { state.sel = null; state.editTarget = false; return go("budget", budgetParams()); }
    const au = t.closest("[data-auto]");
    if (au) { const [k, m] = au.dataset.auto.split("|"); return autoAssign(k, +m, au.closest(".dropdown")?.querySelector("[data-bs-toggle]") || au); }
    const fm = t.closest("[data-focus-month]");
    if (fm && !t.closest("button, a, .dropdown-menu")) return setFocus(+fm.dataset.focusMonth);
    const fl = t.closest("[data-filter]");
    if (fl) { state.filter = fl.dataset.filter; return renderBudget(); }
    const cv = t.closest("[data-cover]");
    if (cv) { const [c, m] = cv.dataset.cover.split("|"); return openCover(cat(c), +m, cv); }
    const cm = t.closest("[data-cover-month]");
    if (cm) { const m = +cm.dataset.coverMonth, c = [...cats(), UNCAT].find(x => state.M.cats[x.id][m].avail < 0); return c ? openCover(c, m, cm) : toast("Kein Überzug in diesem Monat."); }
    const cr = t.closest("[data-cover-rta]");
    if (cr) {
      const m = +cr.dataset.coverRta, need = -state.M.months[m].show, src = cats().filter(x => state.M.cats[x.id][m].avail > 0).sort((a, b) => state.M.cats[b.id][m].avail - state.M.cats[a.id][m].avail);
      return openPop(cr, `<div class="fw-semibold mb-2">Zu viel verteilt im ${mName(m)}</div><form class="d-flex flex-column gap-2" data-unassign-form="${m}"><label class="small" for="ua-from">Nimm <strong class="text-nowrap">${eur(need)}</strong> zurück aus:</label><select class="form-select form-select-sm" id="ua-from" name="from">${src.map(x => `<option value="${x.id}">${esc(catText(x))} (${eur(state.M.cats[x.id][m].avail)})</option>`).join("")}</select><div class="d-flex justify-content-end gap-2"><button type="button" class="btn btn-sm" data-pop-close>Abbrechen</button><button type="submit" class="btn btn-sm btn-primary">OK</button></div></form>`);
    }
    if (t.closest("[data-pop-close]")) return closePop();
    const st = t.closest("[data-month-step]");
    if (st) {
      const d = +st.dataset.monthStep;
      state.focus = clamp(focusMonth() + d, 0, LAST);
      state.m = clamp(visibleMonths()[0] + d, 0, LAST - (isDesktop() ? state.n - 1 : 0));
      return go("budget", budgetParams());
    }
    if (t.closest("[data-month-today]")) { state.m = state.focus = CUR; return go("budget", budgetParams()); }
    const gm = t.closest("[data-goto-month]");
    if (gm) {
      const m = +gm.dataset.gotoMonth;
      state.focus = m; closePop();
      if (!visibleMonths().includes(m)) state.m = m;
      return go("budget", budgetParams());
    }
    const sm = t.closest("[data-summary]");
    if (sm) { state.focus = +sm.dataset.summary; if (!visibleMonths().includes(state.focus)) state.m = state.focus; state.sel = null; go("budget", budgetParams()); return openPanel(); }
    const set = t.closest("[data-set]");
    if (set) { const before = snap(); if (!tryAssign(cat(state.sel), focusMonth(), +set.dataset.set)) return toast(NO_MONEY, "danger"); undoStack.push(before); redoStack.length = 0; return paint(); }
    const sz = t.closest("[data-snooze]");
    if (sz) {
      commit();
      const tg = cat(state.sel).target, m = +sz.dataset.snooze, on = !tg.snooze?.includes(m);
      tg.snooze = on ? [...(tg.snooze || []), m] : tg.snooze.filter(x => x !== m);
      state.editTarget = false; paint();
      return toast(on ? `Ziel im ${mName(m)} pausiert.` : "Ziel läuft wieder.");
    }
    if (t.closest("[data-edit-target]")) { state.editTarget = true; renderPanel(); const f = $("[data-target-form]"); if (f) targetPreview(f); return; }
    if (t.closest("[data-cancel-target]")) { state.editTarget = false; return renderPanel(); }
    if (t.closest("[data-delete-target]")) { commit(); cat(state.sel).target = null; state.editTarget = false; renderCatAdmin(); paint(); return toast("Ziel gelöscht."); }
    if (t.closest("[data-rename]")) return toast("Umbenennen und Emoji ändern (im Klickdummy nicht umgesetzt).");
    if (t.closest("[data-undo]")) return undoRedo(undoStack, redoStack);
    if (t.closest("[data-redo]")) return undoRedo(redoStack, undoStack);
    const msg = t.closest("[data-toast-msg]");
    if (msg) return toast(msg.dataset.toastMsg);
  });

  document.addEventListener("submit", e => {
    const f = e.target;
    if (f.matches("[data-cover-form]")) {
      e.preventDefault();
      const [id, ms] = f.dataset.coverForm.split("|"), m = +ms, c = cat(id), need = -state.M.cats[id][m].avail, from = f.from.value;
      if (!from) return toast("Keine Kategorie mit Geld verfügbar.", "danger");
      const before = snap();
      if (from === "rta") {
        const v = Math.min(need, Math.max(0, state.M.months[m].free));
        if (!tryAssign(c, m, c.assigned[m] + v)) return toast(NO_MONEY, "danger");
        return undoable(before, `${eur(v)} aus „Zu verteilen“ gedeckt.`);
      }
      const src = cat(from), v = Math.min(need, state.M.cats[from][m].avail);
      src.assigned[m] -= v; c.assigned[m] += v;
      return undoable(before, `${eur(v)} aus ${catText(src)} gedeckt.`);
    }
    if (f.matches("[data-unassign-form]")) {
      e.preventDefault();
      const m = +f.dataset.unassignForm, src = cat(f.from.value), v = Math.min(-state.M.months[m].show, state.M.cats[src.id][m].avail);
      commit(); src.assigned[m] -= v; closePop(); paint();
      return toast(`${eur(v)} aus ${catText(src)} zurück nach „Zu verteilen“.`);
    }
    if (f.matches("[data-target-form]")) {
      e.preventDefault();
      const amount = parse(f.amount.value), cadence = f.cadence.value, due = f.due.value;
      if (!(amount > 0)) return toast("Bitte einen Betrag angeben.", "danger");
      if (cadence === "year" && !due) return toast("Bitte ein Fälligkeitsdatum angeben.", "danger");
      commit();
      const old = cat(state.sel).target;
      cat(state.sel).target = { amount, cadence, mode: f.mode.value, ...(cadence === "year" ? { due } : {}), ...(old?.snooze ? { snooze: old.snooze } : {}) };
      state.editTarget = false;
      document.activeElement?.blur();
      renderCatAdmin(); paint();
      return toast("Ziel gespeichert.");
    }
    if (f.matches("[data-move-form]")) {
      e.preventDefault();
      const [id, ms] = f.dataset.moveForm.split("|"), m = +ms, other = f.other.value, v = parse(f.amount.value);
      const [from, to] = f.dir.value === "to" ? [id, other] : [other, id];
      if (!(v > 0)) return toast("Bitte einen Betrag angeben.", "danger");
      const before = snap();
      if (from === "rta") { if (!tryAssign(cat(to), m, cat(to).assigned[m] + v)) return toast(`${NO_MONEY} ${capText(m)}`, "danger"); }
      else { cat(from).assigned[m] -= v; if (to !== "rta") cat(to).assigned[m] += v; }
      document.activeElement?.blur();
      const name = x => (x === "rta" ? "„Zu verteilen“" : catText(cat(x)));
      return undoable(before, `${eur(v)} von ${name(from)} nach ${name(to)} verschoben.`);
    }
    if (f.matches("[data-pick-form]")) {
      e.preventDefault();
      const m = +f.dataset.pickForm, c = cat(f.cat.value), v = parse(f.amount.value);
      if (!(v > 0)) return toast("Bitte einen Betrag angeben.", "danger");
      const before = snap();
      if (!tryAssign(c, m, c.assigned[m] + v)) return toast(`${NO_MONEY} ${capText(m)}`, "danger");
      return undoable(before, `${eur(v)} an ${catText(c)} verteilt.`);
    }
  });

  // ------------------------------------------------------------ sidebar, accounts and register
  function renderSide() {
    const item = a => {
      const b = balance(a), on = state.screen === "konten" && state.acc === a.id, n = txs.filter(t => t.acc === a.id && t.approved === false).length;
      return `<a class="nav-link app-acc${on ? " active" : ""}" href="#konten?konto=${a.id}"${on ? ' aria-current="page"' : ""}><span class="me-auto" title="${esc(a.name)}">${esc(accText(a))}</span>${n ? `<span class="badge rounded-pill text-bg-primary">${n}</span>` : ""}<span class="app-bal${b < 0 ? " text-danger" : ""}">${num(b)}</span></a>`;
    };
    const grp = (type, label) => { const list = accounts.filter(a => a.type === type); return `<div class="d-flex justify-content-between gap-2 app-side-h mt-2 mb-1"><span>${label}</span><span class="tabular-nums">${num(sum(list, balance))}</span></div><nav class="nav flex-column">${list.map(item).join("")}</nav>`; };
    $("[data-side-accounts]").innerHTML = grp("budget", "Budget") + grp("tracking", "Tracking");
  }

  const regAccounts = () => (state.acc === "alle" ? accounts : [acc(state.acc || "giro")]);
  const groupedCat = c => `${esc(plain(groupOf(c.id).name))}: ${c.e} ${esc(c.name)}`;
  const catCell = t => {
    if (t.transfer) return "";
    if (t.splits) return `<span class="text-body-secondary">Aufgeteilt (${t.splits.length})</span>`;
    if (t.cat === "rta") return "Einnahme: Zu verteilen";
    if (acc(t.acc).type === "tracking") return "";
    // unapproved rows keep the category editable inline, prefilled from the payee
    if (t.approved === false || !t.cat) return `<select class="form-select form-select-sm${t.cat ? "" : " border-warning text-warning-emphasis"}" style="max-width:15rem" data-categorize="${t.id}" aria-label="Kategorie">${t.cat ? "" : '<option value="">Kategorie wählen</option>'}${catOnlyOpts(t.cat)}</select>`;
    return groupedCat(cat(t.cat));
  };
  const clearCell = t => acc(t.acc).type === "tracking" ? '<span class="app-clear is-cleared" title="Von zipfelfolio gemeldet">C</span>'
    : t.status === "r" ? `<span class="app-clear is-reconciled" title="Abgeschlossen">${icon("i-lock")}</span>`
    : `<button type="button" class="app-clear${t.status === "c" ? " is-cleared" : ""}" data-toggle-clear="${t.id}" aria-label="${t.status === "c" ? "Abgeglichen" : "Nicht abgeglichen"}, umschalten">C</button>`;
  const FLAGS = [null, ["Rot", "tomato"], ["Orange", "pumpkin"], ["Gelb", "mustard"], ["Grün", "moss"], ["Blau", "denim"], ["Lila", "plum"]];
  const flagCell = t => { const f = FLAGS[t.flag || 0]; return `<button type="button" class="app-flag${f ? " is-set" : ""}" data-flag="${t.id}"${f ? ` style="color:var(--felt-${f[1]})"` : ""} aria-label="Markierung: ${f ? f[0] : "keine"}, ändern" title="Markierung">${icon("i-flag")}</button>`; };
  const matchBar = t => { const m = t.matchOf && txById(t.matchOf); return m ? `<span class="d-inline-flex align-items-center gap-1 text-info-emphasis small">${icon("i-link")} passt zu manueller Buchung vom ${dShort(m.date)}</span> <button type="button" class="btn btn-sm btn-primary py-0" data-merge="${t.id}">Zuordnen</button> <button type="button" class="btn btn-sm btn-outline-secondary py-0" data-approve="${t.id}">Trennen</button>` : ""; };
  // Depot and Geteilt are fed by zipfelfolio and Zipfelkasse, not by hand or file
  const FEEDS = { depot: "Wert kommt aus zipfelfolio", geteilt: "Buchungen kommen aus Zipfelkasse" };
  const equation = (cl, wb) => {
    const part = (op, v, label, cls = "") => `<div class="d-flex align-items-baseline gap-2"><span class="fs-5 text-body-secondary${op ? "" : " invisible d-sm-none"}" aria-hidden="true">${op || "+"}</span><div><div class="fs-5 fw-semibold tabular-nums text-nowrap ${cls}">${eur(v)}</div><div class="small text-body-secondary">${label}</div></div></div>`;
    return `<div class="d-flex flex-column flex-sm-row flex-wrap gap-1 gap-sm-3">${part("", cl, "Abgeglichen", cl < 0 ? "text-danger" : "text-success")}${part("+", wb - cl, "Nicht abgeglichen")}${part("=", wb, "Arbeitssaldo", wb < 0 ? "text-danger" : "text-success")}</div>`;
  };

  function renderAccounts() {
    const showReg = isDesktop() || !!state.acc;
    $("[data-acc-pane]").hidden = showReg;
    $("[data-reg-pane]").hidden = !showReg;
    $("[data-acc-list]").innerHTML = [["budget", "Budget"], ["tracking", "Tracking"]].map(([type, label]) => {
      const list = accounts.filter(a => a.type === type);
      return `<div class="d-flex justify-content-between small text-uppercase fw-bold text-body-secondary mb-2"><span>${label}</span><span class="tabular-nums">${eur(sum(list, balance))}</span></div>
        <div class="list-group mb-4">${list.map(a => { const n = txs.filter(t => t.acc === a.id && t.approved === false).length; return `<a href="#konten?konto=${a.id}" class="list-group-item list-group-item-action d-flex align-items-center gap-3">
          <span class="me-auto" style="min-width:0"><span class="d-block fw-semibold text-truncate">${esc(accText(a))}${n ? ` <span class="badge rounded-pill text-bg-primary">${n}</span>` : ""}</span><span class="small text-body-secondary">${esc(a.link)}</span></span>
          <span class="fw-bold tabular-nums text-nowrap ${balance(a) < 0 ? "text-danger" : ""}">${eur(balance(a))}</span></a>`; }).join("")}</div>`;
    }).join("") + `<div class="d-flex justify-content-between small text-uppercase fw-bold mb-3"><span>Gesamt</span><span class="tabular-nums">${eur(sum(accounts, balance))}</span></div><a href="#konten?konto=alle" class="btn btn-light w-100">Alle Konten</a>`;
    renderSide();
    if (!showReg) return;

    const list = regAccounts(), all = state.acc === "alle", a = list[0], track = !all && a.type === "tracking", feed = !all && FEEDS[a.id];
    const scope = txs.filter(t => list.some(x => x.id === t.acc));
    const fresh = scope.filter(t => t.approved === false);
    if (!fresh.length && state.regFilter === "new") state.regFilter = "all";
    $("[data-reg-banner]").innerHTML = fresh.length ? `<div class="alert alert-primary d-flex flex-wrap align-items-center gap-2 py-2 mb-3">${icon("i-info")}<span class="me-auto">${fresh.length} neue Buchungen zu bestätigen oder zu kategorisieren</span><button type="button" class="btn btn-sm btn-primary" data-reg-filter="new">Ansehen</button><button type="button" class="btn btn-sm btn-outline-primary" data-approve-all>Alle bestätigen</button></div>` : "";
    $("[data-reg-title]").textContent = all ? "Alle Konten" : accText(a);
    $("[data-reg-meta]").innerHTML = all ? "<span>Budget- und Tracking-Konten</span>"
      : `<span>${esc(a.kind)}</span><span class="d-inline-flex align-items-center gap-1">${icon(a.type === "tracking" ? "i-trend" : a.id === "giro" ? "i-check" : a.id === "geteilt" ? "i-users" : "i-file")}${esc(a.link)}</span>${a.rec ? `<span class="d-inline-flex align-items-center gap-1">${icon("i-lock")}Abgeglichen ${ago(a.rec)}</span>` : ""}${a.note ? `<span>${esc(a.note)}</span>` : ""}`;
    $("[data-reconcile-open]").hidden = all || track;
    $("[data-reg-edit]").hidden = all;
    $("[data-reg-legend]").hidden = track;
    $("[data-book-account]").hidden = !!feed;
    $("[data-file-import]").hidden = !!feed;
    $("[data-feed-hint]").hidden = !feed;
    $("[data-feed-hint]").innerHTML = feed ? `${icon("i-info")}${feed}, keine Buchungen von Hand oder per Datei` : "";
    const bud = list.filter(x => x.type === "budget"), trk = list.filter(x => x.type === "tracking"), cl = sum(bud, cleared), wb = sum(bud, balance);
    const plainVal = (v, label) => `<div><div class="fs-5 fw-semibold tabular-nums text-nowrap">${eur(v)}</div><div class="small text-body-secondary">${label}</div></div>`;
    $("[data-reg-balances]").innerHTML = track ? plainVal(balance(a), "Wert laut zipfelfolio")
      : all ? `<div><div class="small fw-semibold text-uppercase text-body-secondary mb-1">Budgetkonten</div>${equation(cl, wb)}</div><div class="vr d-none d-sm-block"></div>${plainVal(sum(trk, balance), "Tracking")}<div class="vr d-none d-sm-block"></div>${plainVal(wb + sum(trk, balance), "Gesamt")}`
      : equation(cl, wb);
    $("[data-reg-view-label]").textContent = { all: "Ansicht", new: "Ansicht: zu bestätigen", open: "Ansicht: nicht abgeglichen" }[state.regFilter];
    const runBtn = $("[data-reg-running]");
    runBtn.hidden = all;
    $("svg", runBtn).style.visibility = state.running ? "visible" : "hidden";

    const picked = [...state.picked].filter(txById);
    $("[data-reg-bulk]").innerHTML = picked.length ? `<div class="alert alert-secondary d-flex flex-wrap align-items-center gap-2 py-2 small"><strong class="me-2">${picked.length} ausgewählt</strong>
      <button type="button" class="btn btn-sm btn-primary" data-bulk-approve>Bestätigen</button>
      <select class="form-select form-select-sm" style="max-width:15rem" data-bulk-cat aria-label="Kategorisieren"><option value="">Kategorisieren …</option>${catOnlyOpts()}</select>
      <button type="button" class="btn btn-sm btn-link ms-auto" data-bulk-clear>Auswahl aufheben</button></div>` : "";

    const q = state.search.toLowerCase();
    const rows = scope.filter(t => state.regFilter === "all" || (state.regFilter === "new" ? t.approved === false : t.status === "u"))
      .filter(t => !q || [t.payee, t.memo, t.cat && t.cat !== "rta" ? cat(t.cat).name : "Zu verteilen"].join(" ").toLowerCase().includes(q))
      .sort((x, y) => y.date.localeCompare(x.date) || (y.approved === false) - (x.approved === false));
    // running balance after each row, newest first; only for one account and the full list
    const run = !all && state.running && state.regFilter === "all" && !q, after = {};
    if (run) { let b = balance(a); rows.forEach(t => { if (t.matchOf) return; after[t.id] = b; b -= t.amount; }); }
    const amt = (v, side) => ((side === "out" ? v < 0 : v > 0) ? num(Math.abs(v)) : "");
    const payee = t => (t.transfer ? `↔ ${esc(accText(acc(t.transfer)))}` : esc(t.payee));
    $("[data-reg-head]").innerHTML = `<tr><th style="width:2rem"><input class="form-check-input" type="checkbox" data-pick-all aria-label="Alle auswählen"${picked.length && picked.length === rows.length ? " checked" : ""}></th><th style="width:1.75rem"><span class="visually-hidden">Markierung</span>${icon("i-flag")}</th><th>Datum</th>${all ? "<th>Konto</th>" : ""}<th>Empfänger</th><th>Kategorie</th><th>Memo</th><th class="text-end">Ausgang</th><th class="text-end">Eingang</th>${run ? '<th class="text-end">Saldo</th>' : ""}<th style="width:2rem" class="text-center"><span class="visually-hidden">Abgeglichen</span>C</th><th style="width:2.75rem"><span class="visually-hidden">Bestätigen</span></th></tr>`;
    const cols = 11 + (all ? 1 : 0) + (run ? 1 : 0) - 1;
    $("[data-reg-table]").innerHTML = rows.map(t => `
      <tr class="${t.approved === false ? "app-unapproved" : ""}${state.picked.has(t.id) ? " table-active" : ""}">
        <td><input class="form-check-input" type="checkbox" data-pick-tx="${t.id}"${state.picked.has(t.id) ? " checked" : ""} aria-label="Buchung auswählen"></td>
        <td>${flagCell(t)}</td>
        <td>${dLong(t.date)}</td>${all ? `<td class="text-truncate" style="max-width:9rem">${esc(accText(acc(t.acc)))}</td>` : ""}
        <td class="text-truncate app-payee" style="max-width:14rem">${payee(t)}</td><td class="text-truncate" style="max-width:16rem">${catCell(t)}</td>
        <td class="small text-body-secondary text-truncate" style="max-width:14rem">${esc(t.memo)}</td>
        <td class="text-end tabular-nums">${amt(t.amount, "out")}</td><td class="text-end tabular-nums">${amt(t.amount, "in")}</td>${run ? `<td class="text-end tabular-nums text-body-secondary">${t.id in after ? num(after[t.id]) : ""}</td>` : ""}<td class="text-center">${clearCell(t)}</td>
        <td class="text-end">${t.approved === false && !t.matchOf ? `<button type="button" class="btn btn-sm btn-primary py-0 px-2" data-approve="${t.id}" title="Bestätigen" aria-label="${esc(t.payee)} bestätigen">${icon("i-check")}</button>` : ""}</td>
      </tr>${t.matchOf ? `<tr class="app-actrow"><td colspan="2"></td><td colspan="${cols - 2}">${matchBar(t)}</td></tr>` : ""}`).join("") ||
      `<tr><td colspan="${cols}" class="text-center text-body-secondary py-4">Keine Buchungen in dieser Ansicht.</td></tr>`;
    const uncategorized = t => !t.cat && !t.transfer && !t.splits && acc(t.acc).type === "budget";
    $("[data-reg-list]").innerHTML = rows.map(t => `
      <div class="list-group-item d-flex gap-2 align-items-start${t.approved === false ? " app-unapproved-item" : ""}">
        <span class="pt-1">${t.approved === false ? `<span class="app-dot">${icon("i-info")}</span>` : clearCell(t)}</span>
        <div class="flex-grow-1" style="min-width:0">
          <div class="text-truncate ${t.approved === false ? "fw-bold" : "fw-semibold"}">${payee(t)}</div>
          <div class="small text-body-secondary text-truncate">${dShort(t.date)}${all ? " · " + esc(acc(t.acc).name) : ""}${uncategorized(t) || t.transfer || (t.approved === false && t.cat !== "rta") ? "" : " · " + catCell(t)}</div>
          ${uncategorized(t) || (t.approved === false && t.cat && t.cat !== "rta") ? `<div class="mt-1">${catCell(t)}</div>` : ""}
          ${t.memo ? `<div class="small text-body-secondary text-truncate">${esc(t.memo)}</div>` : ""}
          ${t.approved === false ? `<div class="d-flex flex-wrap align-items-center gap-1 mt-1">${t.matchOf ? matchBar(t) : `<button type="button" class="btn btn-sm btn-primary py-0" data-approve="${t.id}">Bestätigen</button>`}</div>` : ""}
        </div>
        <div class="tabular-nums text-nowrap ${t.approved === false ? "fw-bold" : "fw-semibold"} ${t.amount > 0 ? "text-success" : ""}">${signed(t.amount)}</div>
      </div>`).join("") || '<div class="list-group-item text-center text-body-secondary py-4">Keine Buchungen in dieser Ansicht.</div>';
  }

  $("[data-reg-search]").addEventListener("input", e => { state.search = e.target.value; renderAccounts(); });
  const refresh = () => { paint(); if (state.screen === "konten") renderAccounts(); };
  const renderAll = () => { if (state.screen === "budget") renderBudget(); else paint(); if (state.screen === "konten") renderAccounts(); renderCatAdmin(); };
  const merge = x => { const m = txById(x.matchOf); m.status = "c"; m.imported = true; txs.splice(txs.indexOf(x), 1); state.picked.delete(x.id); };
  const approve = x => (x.matchOf ? merge(x) : (x.approved = true));
  document.addEventListener("click", e => {
    const t = e.target;
    const rf = t.closest("[data-reg-filter]");
    if (rf) { state.regFilter = rf.dataset.regFilter; return renderAccounts(); }
    const cl = t.closest("[data-toggle-clear]");
    if (cl) { commit(); const x = txById(cl.dataset.toggleClear); x.status = x.status === "c" ? "u" : "c"; return refresh(); }
    const ap = t.closest("[data-approve]");
    if (ap) { commit(); const x = txById(ap.dataset.approve), split = !!x.matchOf; x.approved = true; delete x.matchOf; refresh(); return toast(split ? "Getrennt und als eigene Buchung bestätigt." : "Bestätigt."); }
    const mg = t.closest("[data-merge]");
    if (mg) { commit(); merge(txById(mg.dataset.merge)); refresh(); return toast("Mit der manuellen Buchung zusammengeführt."); }
    if (t.closest("[data-approve-all]")) {
      // match proposals stay open: merging or splitting them is a decision of its own
      commit();
      const open = txs.filter(x => x.approved === false && regAccounts().some(a => a.id === x.acc)), props = open.filter(x => x.matchOf);
      open.filter(x => !x.matchOf).forEach(approve);
      state.regFilter = props.length ? "new" : "all"; refresh();
      return toast(`${open.length - props.length} bestätigt.${props.length ? ` ${props.length} Zuordnungsvorschlag bleibt offen: Zuordnen oder Trennen.` : ""}`, props.length ? "warning" : "success");
    }
    const fg = t.closest("[data-flag]");
    if (fg) { commit(); const x = txById(fg.dataset.flag); x.flag = ((x.flag || 0) + 1) % FLAGS.length; return renderAccounts(); }
    if (t.closest("[data-reg-running]")) { state.running = !state.running; return renderAccounts(); }
    const pt = t.closest("[data-pick-tx]");
    if (pt) { pt.checked ? state.picked.add(pt.dataset.pickTx) : state.picked.delete(pt.dataset.pickTx); return renderAccounts(); }
    const pa = t.closest("[data-pick-all]");
    if (pa) { $$("[data-pick-tx]").forEach(x => (pa.checked ? state.picked.add(x.dataset.pickTx) : state.picked.delete(x.dataset.pickTx))); return renderAccounts(); }
    if (t.closest("[data-bulk-approve]")) { commit(); [...state.picked].map(txById).filter(Boolean).forEach(approve); state.picked.clear(); refresh(); return toast("Bestätigt."); }
    if (t.closest("[data-bulk-clear]")) { state.picked.clear(); return renderAccounts(); }
    if (t.closest("[data-reg-edit]")) return toast("Konto bearbeiten: Name, Emoji, Bankverbindung (im Klickdummy nicht umgesetzt).");
    const ro = t.closest("[data-reconcile-open]");
    if (ro) { rcManual = null; return openReconcile(ro); }
  });
  document.addEventListener("change", e => {
    const s = e.target.closest("[data-categorize]");
    if (s && s.value) { commit(); txById(s.dataset.categorize).cat = s.value; refresh(); return toast(`Kategorie: ${catText(cat(s.value))}.`); }
    const b = e.target.closest("[data-bulk-cat]");
    if (b && b.value) { commit(); [...state.picked].map(txById).filter(x => x && !x.transfer && acc(x.acc).type === "budget").forEach(x => (x.cat = b.value)); refresh(); return toast("Kategorisiert."); }
  });

  // reconcile popover
  let rcManual = null;
  function openReconcile(anchor) {
    const a = acc(state.acc || "giro"), cb = cleared(a), bank = rcManual ?? cb + a.bank.diff, d = bank - cb;
    const block = (v, label, sub) => `<div><div class="fs-4 fw-bold tabular-nums">${eur(v)}</div><div class="small fw-semibold">${label}</div>${sub ? `<div class="small text-body-secondary">${sub}</div>` : ""}</div>`;
    openPop(anchor, `<div class="d-flex flex-column gap-2">
      ${block(bank, "Letzter Banksaldo", rcManual != null ? "von dir eingegeben" : esc(a.bank.src))}
      <div class="${d ? "text-danger" : "text-success"}">${icon(d ? "i-alert" : "i-okc", "app-icon")}</div>
      ${block(cb, "Abgeglichener Saldo in Abakus")}</div>
      ${d === 0 ? '<p class="small mt-3"><strong>Dein Konto sieht gut aus!</strong> Der abgeglichene Saldo stimmt mit dem letzten Banksaldo überein.</p><button type="button" class="btn btn-primary w-100" data-rc-ok>Passt!</button>'
        : `<p class="small mt-3 text-danger">Differenz: <strong class="tabular-nums">${signed(d)}</strong>. Fehlt eine Buchung oder ist eine nicht abgeglichen?</p><button type="button" class="btn btn-primary w-100" data-rc-adjust="${d}">Ausgleichsbuchung anlegen und abschließen</button><button type="button" class="btn btn-light w-100 mt-2" data-pop-close>Erst prüfen</button>`}
      <form class="mt-2" data-rc-form><label class="form-label small mb-1" for="rc-bank">Aktuellen Saldo eingeben</label><div class="input-group input-group-sm"><input class="form-control text-end tabular-nums" id="rc-bank" inputmode="decimal" placeholder="${num(bank)}"><button class="btn btn-outline-secondary" type="submit">Prüfen</button></div></form>`);
  }
  const lockCleared = a => { let n = 0; txs.forEach(t => { if (t.acc === a.id && t.status === "c" && !t.matchOf && t.approved !== false) { t.status = "r"; n++; } }); a.rec = TODAY; return n; };
  document.addEventListener("click", e => {
    if (e.target.closest("[data-rc-ok]")) { commit(); const n = lockCleared(acc(state.acc || "giro")); closePop(); refresh(); toast(`Abgeglichen, ${n} Buchungen abgeschlossen.`); }
    const adj = e.target.closest("[data-rc-adjust]");
    if (adj) {
      commit();
      const a = acc(state.acc || "giro"), d = +adj.dataset.rcAdjust;
      txs.push({ ...T(a.id, TODAY, "Ausgleichsbuchung", "rta", 0, "c", { memo: "Abgleich mit Bank" }), amount: d });
      const n = lockCleared(a);
      closePop(); refresh();
      toast(`Ausgleich ${signed(d)} gebucht, ${n} Buchungen abgeschlossen.`);
    }
  });
  document.addEventListener("submit", e => {
    if (!e.target.matches("[data-rc-form]")) return;
    e.preventDefault();
    const v = parse($("#rc-bank").value);
    if (Number.isNaN(v) || !$("#rc-bank").value.trim()) return;
    rcManual = v;
    openReconcile($("[data-reconcile-open]"));
  });

  // ------------------------------------------------------------ booking form
  const bk = $("[data-booking-form]"), bkModal = $("#bookingModal");
  const catOptions = (withRta = true) => (withRta ? '<option value="rta">📥 Zu verteilen (Einnahme)</option>' : "") + catOnlyOpts();
  const budgetAccs = () => accounts.filter(a => a.type === "budget");
  let bookAcc = null;
  $("[data-book-account]").addEventListener("click", () => { bookAcc = acc(state.acc || "")?.type === "budget" ? state.acc : "giro"; bootstrap.Modal.getOrCreateInstance(bkModal).show(); });
  const kind = () => $('input[name="bk-kind"]:checked').value;
  const splitRow = () => `<div class="d-flex gap-2" data-split-row><select class="form-select form-select-sm" aria-label="Kategorie">${catOptions(false)}</select><div class="input-group input-group-sm" style="max-width:9rem"><input class="form-control text-end tabular-nums" inputmode="decimal" placeholder="0,00" aria-label="Betrag"><span class="input-group-text">€</span></div><button type="button" class="btn btn-sm btn-outline-secondary" data-split-remove aria-label="Teil entfernen">×</button></div>`;
  const restSplit = () => {
    const r = (parse($("[data-bk-amount]").value) || 0) - sum($$("[data-split-row] input", bk), i => parse(i.value) || 0);
    $("[data-bk-rest]").innerHTML = r === 0 ? '<span class="text-success">Aufteilung stimmt</span>' : `Noch aufzuteilen: <strong class="${r < 0 ? "text-danger" : ""}">${eur(r)}</strong>`;
    return r;
  };
  const bkLayout = () => {
    const k = kind(), split = $("[data-bk-split]").checked && k !== "transfer";
    $$("[data-bk-only]", bk).forEach(el => {
      const w = el.dataset.bkOnly;
      el.hidden = w === "payee" ? k === "transfer" : w === "transfer" ? k !== "transfer" : w === "single" ? k === "transfer" || split : !split;
    });
    $("[data-bk-account-label]").textContent = k === "transfer" ? "Von Konto" : "Konto";
    restSplit();
  };
  bkModal.addEventListener("show.bs.modal", () => {
    bk.reset();
    const def = bookAcc || (acc(state.acc || "")?.type === "budget" ? state.acc : "giro");
    $("[data-bk-account]").innerHTML = budgetAccs().map(a => `<option value="${a.id}"${a.id === def ? " selected" : ""}>${esc(accText(a))}</option>`).join("");
    $("[data-bk-to]").innerHTML = budgetAccs().map(a => `<option value="${a.id}">${esc(accText(a))}</option>`).join("");
    $("[data-bk-to]").value = "giro2";
    $("[data-bk-cat]").innerHTML = catOptions();
    $("[data-bk-cat]").value = "lebensm";
    $("[data-bk-cat-hint]").textContent = "";
    $("[data-payees]").innerHTML = [...new Set(txs.filter(t => t.payee !== "Wertänderung" && !t.transfer).map(t => t.payee))].sort().map(p => `<option value="${esc(p)}"></option>`).join("");
    $("[data-bk-splits]").innerHTML = splitRow() + splitRow();
    bookAcc = null;
    bkLayout();
  });
  bkModal.addEventListener("shown.bs.modal", () => $("[data-bk-amount]").focus());
  bk.addEventListener("change", e => { if (e.target.matches('[name="bk-kind"], [data-bk-split]')) bkLayout(); if (e.target.matches('[name="bk-kind"]') && kind() === "in") $("[data-bk-cat]").value = "rta"; });
  bk.addEventListener("input", e => {
    if (e.target.matches("[data-bk-payee]")) {
      const p = e.target.value.trim().toLowerCase(), last = txs.filter(t => t.payee.toLowerCase() === p && t.cat).sort((a, b) => b.date.localeCompare(a.date))[0];
      if (last) {
        $("[data-bk-cat]").value = last.cat;
        $("[data-bk-cat-hint]").textContent = `Vorschlag aus der letzten Buchung bei ${last.payee} (${dShort(last.date)}, ${eur(Math.abs(last.amount))})`;
        $(last.amount > 0 ? "#bk-in" : "#bk-out").checked = true;
      } else $("[data-bk-cat-hint]").textContent = "";
    }
    restSplit();
  });
  bk.addEventListener("click", e => {
    if (e.target.closest("[data-bk-addsplit]")) { $("[data-bk-splits]").insertAdjacentHTML("beforeend", splitRow()); restSplit(); }
    const rm = e.target.closest("[data-split-remove]");
    if (rm && $$("[data-split-row]", bk).length > 2) { rm.closest("[data-split-row]").remove(); restSplit(); }
  });
  bk.addEventListener("submit", e => {
    e.preventDefault();
    const k = kind(), v = parse($("[data-bk-amount]").value), from = $("[data-bk-account]").value, date = $("[data-bk-date]").value || TODAY;
    const memo = $("[data-bk-memo]").value.trim(), payee = $("[data-bk-payee]").value.trim();
    if (!(v > 0)) return toast("Bitte einen Betrag angeben.", "danger");
    if (k === "transfer" && $("[data-bk-to]").value === from) return toast("Zwei verschiedene Konten wählen.", "danger");
    if (k !== "transfer" && $("[data-bk-split]").checked && restSplit() !== 0) return toast("Die Teile ergeben nicht den Gesamtbetrag.", "danger");
    commit();
    if (k === "transfer") {
      const to = $("[data-bk-to]").value;
      txs.push({ ...T(from, date, acc(to).name, null, 0, "u", { transfer: to, memo }), amount: -v }, { ...T(to, date, acc(from).name, null, 0, "u", { transfer: from, memo }), amount: v });
    } else {
      const sign = k === "out" ? -1 : 1, tx = { ...T(from, date, payee || "Ohne Empfänger", null, 0, "u", { memo }), amount: sign * v };
      if ($("[data-bk-split]").checked) tx.splits = $$("[data-split-row]", bk).map(r => ({ cat: $("select", r).value, amount: sign * (parse($("input", r).value) || 0) })).filter(s => s.amount);
      else tx.cat = $("[data-bk-cat]").value;
      txs.push(tx);
    }
    bootstrap.Modal.getInstance(bkModal).hide();
    refresh();
    toast(k === "transfer" ? `Umbuchung über ${eur(v)} angelegt.` : `Gebucht: ${payee || "Buchung"} ${signed(k === "out" ? -v : v)}`);
  });

  // ------------------------------------------------------------ import & sync
  const fetches = { mb: 2 };
  document.addEventListener("click", e => {
    const f = e.target.closest("[data-fetch]");
    if (f) {
      const k = f.dataset.fetch;
      fetches[k]++;
      $(`[data-fetch-count="${k}"]`).textContent = fetches[k] >= 4 ? "4 von 4 Abrufen heute, wieder ab 00:00" : `${fetches[k]} von 4 Abrufen heute`;
      f.disabled = fetches[k] >= 4;
      $("[data-sync-log]").insertAdjacentHTML("afterbegin", `<li class="list-group-item d-flex justify-content-between"><span>08.10. ${new Date().toTimeString().slice(0, 5)} · Musterbank</span><span class="text-body-secondary">0 neu</span></li>`);
      return toast("Abgerufen, keine neuen Buchungen.");
    }
    const r = e.target.closest("[data-renew]");
    if (r) {
      const card = r.closest(".card"), b = $(".card-header .badge", card);
      b.className = "badge text-bg-success"; b.textContent = "Freigabe gültig";
      $(".card-body", card).textContent = "Freigabe erneuert am 08.10.2026, gültig bis 06.04.2027 (180 Tage).";
      r.remove();
      return toast("Freigabe erneuert (im Echtbetrieb: Weiterleitung zur Bank).");
    }
  });
  const impRows = [
    ["07.10.", "Lastschrift Stadtwerke", -42, "new"], ["05.10.", "Fahrradladen Speiche", -89, "dup"], ["03.10.", "Bäckerei Korn", -6.4, "match"],
    ["02.10.", "Umbuchung Girokonto", 200, "dup"], ["30.09.", "Stadtbibliothek", -12, "new"], ["28.09.", "Paketshop Muster", -4.99, "new"],
    ["24.09.", "Kino Lichtspiel", -21, "match"], ["19.09.", "Frischmarkt", -58.37, "new"], ["15.09.", "Krankenkasse Muster", 34.9, "new"], ["12.09.", "Nordbank Direkt", -3.5, "dup"],
  ];
  const impBadge = { new: '<span class="badge text-bg-success">neu</span>', dup: '<span class="badge text-bg-secondary">vorhanden (FITID)</span>', match: '<span class="badge text-bg-info">zugeordnet</span>' };
  const showImport = () => {
    $("[data-imp-rows]").innerHTML = impRows.map(([d, p, v, s]) => `<tr${s === "dup" ? ' class="text-body-secondary"' : ""}><td>${d}</td><td>${esc(p)}${s === "match" ? `<div class="small text-info-emphasis">passt zu manueller Buchung vom ${p.startsWith("Bäckerei") ? "03.10." : "23.09."}</div>` : ""}</td><td class="text-end ${v > 0 ? "text-success" : ""}">${signed(C(v))}</td><td>${impBadge[s]}</td></tr>`).join("") +
      '<tr><td colspan="4" class="small text-body-secondary text-center">… und 20 weitere</td></tr>';
    // the file's ledger balance is what reconciling the account offers later
    const a = acc("giro2");
    $("[data-imp-bank]").textContent = eur(cleared(a) + a.bank.diff);
    $("[data-imp-preview]").hidden = false;
  };
  $("[data-imp-sample]").addEventListener("click", showImport);
  $("[data-imp-file]").addEventListener("change", showImport);
  $("[data-imp-cancel]").addEventListener("click", () => { $("[data-imp-preview]").hidden = true; $("[data-imp-file]").value = ""; });
  $("[data-imp-go]").addEventListener("click", () => { $("[data-imp-preview]").hidden = true; $("[data-imp-file]").value = ""; toast("23 Buchungen importiert, zur Bestätigung im Girokonto Nordbank. Banksaldo aus der Datei gemerkt."); });

  // ------------------------------------------------------------ settings
  function renderCatAdmin() {
    $("[data-cat-admin]").innerHTML = groups.map(g => `
      <div class="list-group-item d-flex align-items-center gap-2 bg-body-tertiary fw-semibold">${icon("i-grip", "app-icon app-icon-sm text-body-secondary")}<span class="me-auto text-truncate">${esc(g.name)}</span><button type="button" class="btn btn-sm btn-link" data-add-cat="${g.id}">+ Kategorie</button></div>
      ${g.cats.map(c => `<div class="list-group-item d-flex align-items-center gap-2">${icon("i-grip", "app-icon app-icon-sm text-body-secondary")}
        <span class="flex-grow-1" style="min-width:0">${catName(c)}<span class="d-block small text-body-secondary text-truncate">${esc(targetText(c.target))}</span></span>
        <a class="btn btn-sm btn-outline-secondary" href="#budget?m=${mKey(CUR)}&kat=${c.id}">Bearbeiten</a></div>`).join("")}`).join("");
  }
  document.addEventListener("click", e => {
    const ac = e.target.closest("[data-add-cat]");
    if (ac) {
      const c = { id: "neu" + seq++, e: "✨", name: "Neue Kategorie" };
      prepCat(c); groups.find(g => g.id === ac.dataset.addCat).cats.push(c);
      renderCatAdmin(); return toast("Kategorie angelegt.");
    }
    if (e.target.closest("[data-add-group]")) {
      groups.push({ id: "g" + seq++, name: "📦 Neue Gruppe", cats: [] });
      renderCatAdmin(); if (state.screen === "budget") renderBudget(); return toast("Gruppe angelegt.");
    }
    const rm = e.target.closest("[data-remove]");
    if (rm) { const li = rm.closest("li"); toast(`${$(".fw-semibold", li).textContent} ${rm.textContent === "Widerrufen" ? "widerrufen" : "entfernt"}.`); return li.remove(); }
    const cp = e.target.closest("[data-copy]");
    if (cp) { navigator.clipboard?.writeText($("input", cp.parentElement).value).catch(() => {}); return toast("Kopiert."); }
    if (e.target.closest("[data-add-passkey]")) {
      $("[data-passkeys]").insertAdjacentHTML("beforeend", '<li class="list-group-item d-flex align-items-center gap-3"><span class="me-auto"><span class="d-block fw-semibold">Neues Gerät</span><span class="small text-body-secondary">gerade eben angelegt</span></span><button type="button" class="btn btn-sm btn-outline-danger" data-remove>Entfernen</button></li>');
      return toast("Passkey hinzugefügt (im Echtbetrieb fragt der Browser nach).");
    }
    if (e.target.closest("[data-mcp-new]")) { $("[data-mcp-url]").value = "https://abakus.example/mcp/" + Math.random().toString(16).slice(2, 8) + "…" + Math.random().toString(16).slice(2, 6); return toast("Neue URL erzeugt, die alte gilt nicht mehr."); }
  });
  $("[data-mcp-toggle]").addEventListener("change", e => {
    $$("input, button", $("[data-mcp-body]")).forEach(el => (el.disabled = !e.target.checked));
    e.target.nextElementSibling.textContent = e.target.checked ? "aktiv" : "aus";
  });
  $("[data-token-form]").addEventListener("submit", e => {
    e.preventDefault();
    const [name, scope] = [$("input", e.target).value, $("select", e.target).value];
    $("[data-tokens]").insertAdjacentHTML("beforeend", `<li class="list-group-item d-flex align-items-center gap-3"><span class="me-auto"><span class="d-block fw-semibold">${esc(name)}</span><span class="small text-body-secondary">${scope} · erstellt 08.10.2026 · nie benutzt</span></span><button type="button" class="btn btn-sm btn-outline-danger" data-remove>Widerrufen</button></li>`);
    $("[data-token-new]").hidden = false;
    e.target.reset();
  });

  // ------------------------------------------------------------ toast, theme
  function toast(text, tone = "success") {
    const el = $("#toast");
    el.className = `toast text-bg-${tone}`;
    $("[data-toast-text]").textContent = text;
    bootstrap.Toast.getOrCreateInstance(el, { delay: 3000 }).show();
  }

  const root = document.documentElement;
  const store = (k, v) => { try { localStorage.setItem(k, v); } catch {} };
  $(`#theme-${root.dataset.bsTheme || "auto"}`).checked = true;
  $$('input[name="theme"]').forEach(i => i.addEventListener("change", () => {
    if (i.value === "auto") delete root.dataset.bsTheme; else root.dataset.bsTheme = i.value;
    store("theme", i.value);
  }));

  renderCatAdmin();
  measure();
  route();
  document.fonts?.ready.then(() => { measure(); layout(true); });
})();
