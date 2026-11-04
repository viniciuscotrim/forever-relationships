// Trust Advisor Cockpit. Vanilla JS, no external code (strict CSP).
"use strict";

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const SVGNS = "http://www.w3.org/2000/svg";
const fmt = new Intl.NumberFormat();
const dayFmt = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" });
const dtFmt = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });
const COLORS = { s1: "var(--series-1)", s2: "var(--series-2)" };
const TRAITS = { finish: "Finishing", ready: "Arriving ready", loot: "Loot honesty", carry: "Carry delivered",
  generosity: "Small generosity", teach: "Higher-level partner", craft: "Crafting for others", help: "Stayed to help",
  hc: "Hardcore steadfastness", endorse: "Endorsements", pay: "Paying what's owed", attend: "Showing up" };

function el(tag, attrs = {}, ...children) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") n.className = v; else if (k === "text") n.textContent = v;
    else if (k.startsWith("on")) n.addEventListener(k.slice(2), v); else if (v !== undefined && v !== null) n.setAttribute(k, v);
  }
  for (const c of children.flat()) if (c != null) n.append(c.nodeType ? c : document.createTextNode(String(c)));
  return n;
}
function svg(tag, attrs = {}) {
  const n = document.createElementNS(SVGNS, tag);
  for (const [k, v] of Object.entries(attrs)) if (v !== undefined) n.setAttribute(k, v);
  return n;
}

// ------------------------------------------------------------------ API
async function api(method, path, body) {
  const res = await fetch("api/" + path, {
    method, credentials: "same-origin",
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = {};
  try { data = await res.json(); } catch (_) { /* empty */ }
  if (!res.ok) { const e = new Error(data.error || ("HTTP " + res.status)); e.status = res.status; throw e; }
  return data;
}

// ------------------------------------------------------------------ WebAuthn helpers
const b64u = {
  decode(s) { s = s.replace(/-/g, "+").replace(/_/g, "/"); while (s.length % 4) s += "="; return Uint8Array.from(atob(s), c => c.charCodeAt(0)).buffer; },
  encode(buf) { return btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); },
};
function credToJSON(c) {
  const r = c.response, out = { id: c.id, rawId: b64u.encode(c.rawId), type: c.type, response: { clientDataJSON: b64u.encode(r.clientDataJSON) } };
  if (r.attestationObject) out.response.attestationObject = b64u.encode(r.attestationObject);
  if (r.authenticatorData) {
    out.response.authenticatorData = b64u.encode(r.authenticatorData);
    out.response.signature = b64u.encode(r.signature);
    if (r.userHandle) out.response.userHandle = b64u.encode(r.userHandle);
  }
  return out;
}

// ------------------------------------------------------------------ auth screens
const msg = (t, ok) => { const m = $("#auth-msg"); m.textContent = t || ""; m.classList.toggle("ok", !!ok); };
let loginNonce = null;

async function startLogin() {
  msg("");
  try {
    const begin = await api("POST", "login/begin");
    loginNonce = begin.nonce;
    const pk = begin.publicKey;
    pk.challenge = b64u.decode(pk.challenge);
    const cred = await navigator.credentials.get({ publicKey: pk });
    await api("POST", "login/passkey", { nonce: loginNonce, credential: credToJSON(cred) });
    $("#btn-passkey").hidden = true;
    $("#form-code").hidden = false;
    $("#code").focus();
  } catch (e) { msg(e.name === "NotAllowedError" ? "Cancelled." : e.message); }
}
async function submitCode(ev) {
  ev.preventDefault();
  try {
    await api("POST", "login/code", { nonce: loginNonce, code: $("#code").value });
    $("#auth").hidden = true;
    startApp();
  } catch (e) {
    msg(e.message);
    if (e.status === 400 || e.status === 429) { $("#form-code").hidden = true; $("#btn-passkey").hidden = false; }
  }
}

let setupToken = null, setupNonce = null;
async function createPasskey() {
  msg("");
  try {
    const begin = await api("POST", "setup/begin", { setupToken });
    const pk = begin.publicKey;
    pk.challenge = b64u.decode(pk.challenge);
    pk.user.id = b64u.decode(pk.user.id);
    pk.excludeCredentials = (pk.excludeCredentials || []).map(c => ({ ...c, id: b64u.decode(c.id) }));
    const cred = await navigator.credentials.create({ publicKey: pk });
    const fin = await api("POST", "setup/finish", { nonce: begin.nonce, credential: credToJSON(cred), label: navigator.platform });
    $("#step-passkey").classList.add("dim");
    $("#btn-create").disabled = true;
    if (fin.done) { finishSetup(); return; }
    setupNonce = fin.nonce;
    $("#step-totp").classList.remove("dim");
    $("#totp-box").hidden = false;
    $("#otpauth").href = fin.otpauth;
    $("#totp-secret").textContent = fin.totpSecret.replace(/(.{4})/g, "$1 ").trim();
    msg("Passkey saved. Now add the verification code.", true);
  } catch (e) { msg(e.name === "NotAllowedError" ? "Cancelled." : e.message); }
}
async function confirmSetupCode(ev) {
  ev.preventDefault();
  try { await api("POST", "setup/totp", { nonce: setupNonce, code: $("#setup-code").value }); finishSetup(); }
  catch (e) { msg(e.message); }
}
function finishSetup() {
  history.replaceState(null, "", location.pathname);
  $("#auth-setup").hidden = true; $("#auth-login").hidden = false; $("#auth").classList.add("login");
  msg("");
}

// ------------------------------------------------------------------ tooltip
const tip = $("#tooltip");
function showTip(ev, text) { tip.textContent = text; tip.hidden = false; moveTip(ev); }
function moveTip(ev) {
  const w = tip.offsetWidth, x = Math.min(ev.clientX + 14, innerWidth - w - 8);
  tip.style.left = x + "px"; tip.style.top = (ev.clientY + 14) + "px";
}
function hideTip() { tip.hidden = true; }
function hover(node, text) {
  node.addEventListener("mouseenter", e => showTip(e, text));
  node.addEventListener("mousemove", moveTip);
  node.addEventListener("mouseleave", hideTip);
}

// ------------------------------------------------------------------ charts (SVG)
function empty(host, text = "No data yet") { host.replaceChildren(el("div", { class: "empty", text })); }

// Horizontal bar list: one series, sorted, value labels at bar end, hover tooltip.
const widthOf = host => Math.max(280, Math.round(host.clientWidth || 520));

function barList(host, rows, { total, max = 12 } = {}) {
  rows = (rows || []).filter(r => r.n > 0).slice(0, max);
  if (!rows.length) return empty(host);
  const sum = total ?? rows.reduce((a, r) => a + r.n, 0);
  const W = widthOf(host), labelW = Math.min(150, W * .32), valW = 78, rowH = 26, barH = 14, H = rows.length * rowH;
  const top = Math.max(...rows.map(r => r.n));
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, width: W, height: H, role: "img", "aria-label": rows.map(r => `${r.k}: ${r.n}`).join(", ") });
  rows.forEach((r, i) => {
    const y = i * rowH, w = Math.max(3, (W - labelW - valW) * r.n / top);
    const t = svg("text", { x: labelW - 8, y: y + rowH / 2 + 4, "text-anchor": "end", class: "cat" }); t.textContent = String(r.k).slice(0, 20); s.append(t);
    s.append(svg("rect", { x: labelW, y: y + (rowH - barH) / 2, width: w, height: barH, rx: 4, fill: COLORS.s1 }));
    const v = svg("text", { x: labelW + w + 6, y: y + rowH / 2 + 4, class: "val" });
    v.textContent = `${fmt.format(r.n)} · ${Math.round(100 * r.n / sum)}%`; s.append(v);
    const hit = svg("rect", { x: 0, y, width: W, height: rowH, class: "hit" });
    hover(hit, `${r.k}: ${fmt.format(r.n)} (${(100 * r.n / sum).toFixed(1)}%)`); s.append(hit);
  });
  host.replaceChildren(s);
}

// Vertical columns (histogram-like), one series.
function columns(host, rows, unit = "") {
  rows = rows || [];
  if (!rows.some(r => r.n > 0)) return empty(host);
  const W = widthOf(host), H = 180, pad = { l: 34, r: 6, t: 10, b: 26 };
  const iw = W - pad.l - pad.r, ih = H - pad.t - pad.b, top = Math.max(...rows.map(r => r.n));
  const bw = iw / rows.length, gap = Math.min(8, bw * .25);
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, width: W, height: H, role: "img", "aria-label": rows.map(r => `${r.k}: ${r.n}`).join(", ") });
  const g = svg("g", { class: "grid" });
  for (const f of [0, .5, 1]) {
    const y = pad.t + ih * (1 - f); g.append(svg("line", { x1: pad.l, x2: W - pad.r, y1: y, y2: y }));
    const t = svg("text", { x: pad.l - 6, y: y + 4, "text-anchor": "end", class: "lbl" }); t.textContent = fmt.format(Math.round(top * f)); s.append(t);
  }
  s.prepend(g);
  rows.forEach((r, i) => {
    const h = top ? ih * r.n / top : 0, x = pad.l + i * bw + gap / 2;
    if (h > 0) s.append(svg("path", { d: roundedTop(x, pad.t + ih - h, bw - gap, h, 4), fill: COLORS.s1 }));
    const t = svg("text", { x: x + (bw - gap) / 2, y: H - 8, "text-anchor": "middle", class: "lbl" }); t.textContent = r.k; s.append(t);
    const hit = svg("rect", { x: pad.l + i * bw, y: pad.t, width: bw, height: ih, class: "hit" });
    hover(hit, `${r.k}${unit}: ${fmt.format(r.n)}`); s.append(hit);
  });
  host.replaceChildren(s);
}
function roundedTop(x, y, w, h, r) {
  r = Math.min(r, w / 2, h);
  return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`;
}

// Time series: area + 2px line, crosshair tooltip. One series per chart (no legend).
function area(host, pts) {
  pts = pts || [];
  if (!pts.length) return empty(host);
  const W = widthOf(host), H = 170, pad = { l: 34, r: 8, t: 10, b: 24 };
  const iw = W - pad.l - pad.r, ih = H - pad.t - pad.b, top = Math.max(1, ...pts.map(p => p.n));
  const X = i => pad.l + iw * i / Math.max(1, pts.length - 1), Y = n => pad.t + ih * (1 - n / top);
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, width: W, height: H, role: "img", "aria-label": `Total ${fmt.format(pts.reduce((a, p) => a + p.n, 0))} over ${pts.length} days` });
  const g = svg("g", { class: "grid" });
  for (const f of [0, .5, 1]) {
    const y = pad.t + ih * (1 - f); g.append(svg("line", { x1: pad.l, x2: W - pad.r, y1: y, y2: y }));
    const t = svg("text", { x: pad.l - 6, y: y + 4, "text-anchor": "end", class: "lbl" }); t.textContent = fmt.format(Math.round(top * f)); s.append(t);
  }
  s.append(g);
  const line = pts.map((p, i) => `${i ? "L" : "M"}${X(i)},${Y(p.n)}`).join("");
  s.append(svg("path", { d: `${line}L${X(pts.length - 1)},${pad.t + ih}L${X(0)},${pad.t + ih}Z`, fill: COLORS.s1, opacity: .18 }));
  s.append(svg("path", { d: line, fill: "none", stroke: COLORS.s1, "stroke-width": 2, "stroke-linejoin": "round" }));
  for (const i of [0, Math.floor(pts.length / 2), pts.length - 1]) {
    const t = svg("text", { x: X(i), y: H - 6, "text-anchor": i === 0 ? "start" : i === pts.length - 1 ? "end" : "middle", class: "lbl" });
    t.textContent = dayFmt.format(new Date(pts[i].t * 1000)); s.append(t);
  }
  const cross = svg("line", { y1: pad.t, y2: pad.t + ih, stroke: "var(--text-muted)", "stroke-width": 1, visibility: "hidden" });
  const dot = svg("circle", { r: 4, fill: COLORS.s1, stroke: "var(--surface-1)", "stroke-width": 2, visibility: "hidden" });
  s.append(cross, dot);
  const hit = svg("rect", { x: pad.l, y: pad.t, width: iw, height: ih, class: "hit" });
  hit.addEventListener("mousemove", e => {
    const box = s.getBoundingClientRect(), vx = (e.clientX - box.left) * W / box.width;
    const i = Math.max(0, Math.min(pts.length - 1, Math.round((vx - pad.l) / iw * (pts.length - 1))));
    cross.setAttribute("x1", X(i)); cross.setAttribute("x2", X(i)); cross.setAttribute("visibility", "visible");
    dot.setAttribute("cx", X(i)); dot.setAttribute("cy", Y(pts[i].n)); dot.setAttribute("visibility", "visible");
    showTip(e, `${dayFmt.format(new Date(pts[i].t * 1000))}: ${fmt.format(pts[i].n)}`);
  });
  hit.addEventListener("mouseleave", () => { cross.setAttribute("visibility", "hidden"); dot.setAttribute("visibility", "hidden"); hideTip(); });
  s.append(hit);
  host.replaceChildren(s);
}

// Two-part stacked bars (verified / not verified) with legend + 2px gap.
function stacked2(host, rows, names) {
  rows = (rows || []).filter(r => r.a + r.b > 0);
  if (!rows.length) return empty(host);
  const W = widthOf(host), labelW = 170, valW = 90, rowH = 26, barH = 14, H = rows.length * rowH;
  const top = Math.max(...rows.map(r => r.a + r.b)), scale = (W - labelW - valW) / top;
  const legend = el("div", { class: "legend" },
    el("span", {}, el("i", { class: "sw1" }), names[0]), el("span", {}, el("i", { class: "sw2" }), names[1]));
  legend.querySelector(".sw1").style.background = COLORS.s1; legend.querySelector(".sw2").style.background = COLORS.s2;
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, width: W, height: H, role: "img", "aria-label": rows.map(r => `${r.k}: ${r.a} ${names[0]}, ${r.b} ${names[1]}`).join("; ") });
  rows.forEach((r, i) => {
    const y = i * rowH + (rowH - barH) / 2, wa = r.a * scale, wb = r.b * scale;
    const t = svg("text", { x: labelW - 8, y: i * rowH + rowH / 2 + 4, "text-anchor": "end", class: "cat" }); t.textContent = r.k; s.append(t);
    if (wa > 0) s.append(svg("rect", { x: labelW, y, width: Math.max(2, wa - (wb > 0 ? 2 : 0)), height: barH, rx: 4, fill: COLORS.s1 }));
    if (wb > 0) s.append(svg("rect", { x: labelW + wa, y, width: Math.max(2, wb), height: barH, rx: 4, fill: COLORS.s2 }));
    const v = svg("text", { x: labelW + wa + wb + 6, y: i * rowH + rowH / 2 + 4, class: "val" }); v.textContent = `${fmt.format(r.a)} / ${fmt.format(r.a + r.b)}`; s.append(v);
    const hit = svg("rect", { x: 0, y: i * rowH, width: W, height: rowH, class: "hit" });
    hover(hit, `${r.k}: ${fmt.format(r.a)} ${names[0]}, ${fmt.format(r.b)} ${names[1]}${r.extra ? " · " + r.extra : ""}`); s.append(hit);
  });
  host.replaceChildren(legend, s);
}

function kpis(host, items) {
  host.replaceChildren(...items.map(([label, value, accent]) =>
    el("div", { class: "kpi" + (accent ? " accent" : "") }, el("div", { class: "v", text: typeof value === "number" ? fmt.format(value) : value }), el("div", { class: "l", text: label }))));
}
function simpleTable(host, head, rows) {
  if (!rows.length) return empty(host);
  host.replaceChildren(el("table", { class: "table" }, el("thead", {}, el("tr", {}, head.map(h => el("th", { text: h })))),
    el("tbody", {}, rows.map(r => el("tr", {}, r.map((c, i) => el("td", { class: i && typeof c === "number" ? "num" : "", text: typeof c === "number" ? fmt.format(c) : c })))))));
}

// ------------------------------------------------------------------ views
let data = null, feedback = [], selectedFb = null;
const VIEWS = { cockpit: "Cockpit", demographics: "Demographics", network: "Network", feedback: "Feedback", disputes: "Disputes" };

function showView(v) {
  if (!VIEWS[v]) v = "cockpit";
  $("#view-title").textContent = VIEWS[v];
  $$("section[data-section]").forEach(s => s.hidden = s.dataset.section !== v);
  $$(".side a").forEach(a => a.classList.toggle("active", a.dataset.view === v));
  current = v;
  if (v === "feedback") loadFeedback();
  if (v === "disputes") loadDisputes();
  render();   // charts are drawn at the visible card's real width
}

let current = "cockpit";
function render() {
  if (!data) return;
  const k = data.kpis;
  $("#updated").textContent = "Live from the server · " + dtFmt.format(new Date(data.generatedAt * 1000));
  const banner = $("#demo-banner");
  banner.hidden = !data.demoRows;
  banner.textContent = data.demoRows ? `Demo data present (${fmt.format(data.demoRows)} demo participants/feedback). Remove it on the server with: python -m trustnet.demo clean` : "";
  $("#nav-fb").hidden = !k.feedbackNew; $("#nav-fb").textContent = k.feedbackNew;
  $("#nav-dsp").hidden = !k.openDisputes; $("#nav-dsp").textContent = k.openDisputes;
  kpis($("#kpis"), [
    ["Network participants", k.participants, true], ["Active last 24 h", k.active24h], ["Active last 7 days", k.active7d],
    ["Linked Battle.net accounts", k.linkedAccounts], ["New feedback", k.feedbackNew, true], ["Open disputes", k.openDisputes],
    ["Bugs reported", k.bugs], ["Ideas", k.ideas],
  ]);
  area($("#ch-new"), data.series.newParticipants);
  area($("#ch-reports"), data.series.reports);
  area($("#ch-feedback"), data.series.feedback);
  barList($("#ch-fb-status"), data.feedback.byStatus.map(r => ({ k: STATUS_LABEL[r.k] || r.k, n: r.n })));
  simpleTable($("#tbl-errors"), ["Error (from diagnostics)", "Reports"], data.feedback.topErrors.map(e => [e.k, e.n]));

  const d = data.demographics;
  barList($("#ch-faction"), d.faction);
  columns($("#ch-levels"), d.levels);
  barList($("#ch-region"), (d.region || []).map(r => ({ k: String(r.k).toUpperCase(), n: r.n })));
  barList($("#ch-race"), d.race);
  barList($("#ch-class"), d.class);
  barList($("#ch-realm"), d.realm);
  barList($("#ch-locale"), d.locale);

  kpis($("#net-kpis"), [
    ["Players observed", k.playersObserved], ["Witness reports", k.reports], ["Incidents", k.incidents],
    ["Verified incidents", k.verifiedIncidents, true], ["Verified negatives", k.verifiedNegatives],
    ["Verified characters", k.verifiedCharacters], ["Opted out (deleted)", k.optedOut], ["Guilds seen", d.guilds],
  ]);
  stacked2($("#ch-dims"), data.network.byDimension.map(r => ({ k: TRAITS[r.k] || r.k, a: r.verified, b: r.incidents - r.verified,
    extra: `${r.verifiedNegatives} of ${r.negatives} negatives verified` })), ["verified", "not verified"]);
  columns($("#ch-witness"), data.network.witnessHistogram.map(r => ({ k: String(r.k), n: r.n })), " witness(es)");
  simpleTable($("#tbl-protocol"), ["Parameter", "Value"], Object.entries(data.protocol).map(([a, b]) => [a, String(b)]));
}

async function loadOverview() {
  try { data = await api("GET", "overview"); render(); }
  catch (e) { if (e.status === 401) return toLogin(); console.error(e); }
}

// feedback
const STATUS_LABEL = { received: "New", planned: "Planned", fixed: "Fixed", done: "Done", wontfix: "Won't do", duplicate: "Duplicate" };
async function loadFeedback() {
  try { feedback = (await api("GET", "feedback")).feedback; drawFeedback(); }
  catch (e) { if (e.status === 401) toLogin(); }
}
function drawFeedback() {
  const st = $("#fb-status").value, kind = $("#fb-kind").value, q = $("#fb-search").value.toLowerCase();
  const rows = feedback.filter(f => (!st || f.status === st) && (!kind || f.kind === kind) && (!q || (f.text || "").toLowerCase().includes(q)));
  $("#fb-count").textContent = `${rows.length} of ${feedback.length}`;
  $("#tbl-fb tbody").replaceChildren(...rows.map(f => {
    const tr = el("tr", { class: selectedFb === f.id ? "sel" : "" },
      el("td", { text: dayFmt.format(new Date(f.received_at * 1000)) }),
      el("td", {}, el("span", { class: "tag " + f.kind, text: f.kind === "bug" ? "Bug" : "Idea" })),
      el("td", { text: (f.text || "(diagnostics only)").slice(0, 110) }),
      el("td", { text: f.version || "" }),
      el("td", { class: "status", text: (STATUS_LABEL[f.status] || f.status) + (f.reply ? " · replied" : "") }));
    tr.addEventListener("click", () => { selectedFb = f.id; drawFeedback(); showFeedback(f); });
    return tr;
  }));
}
function showFeedback(f) {
  const box = $("#fb-detail"); box.hidden = false; box.parentElement.classList.add("open");
  let diag = "";
  try {
    const d = JSON.parse(f.diag || "null");
    if (d) diag = [`Addon ${d.addon} · client ${d.build} · ${d.locale}`, `Companion ${d.companion}${d.companionVersion ? " " + d.companionVersion : ""} · network ${d.network ? "on" : "off"}`,
      `${d.players} players known · ${d.events} events`, ...(d.unavailable || []).map(u => "Unavailable: " + u), ...(d.errors || []).map(e => "Error: " + e)].join("\n");
  } catch (_) { diag = f.diag || ""; }
  const sel = el("select", { "aria-label": "Status" }, Object.entries(STATUS_LABEL).map(([v, l]) => el("option", { value: v, text: l })));
  sel.value = f.status;
  const reply = el("textarea", { placeholder: "Reply shown to the player in game (optional)", maxlength: "500" });
  reply.value = f.reply || "";
  const save = el("button", { class: "primary", text: "Save", onclick: async () => {
    save.disabled = true;
    try { await api("POST", "feedback/" + encodeURIComponent(f.id), { status: sel.value, reply: reply.value.trim() || null });
      f.status = sel.value; f.reply = reply.value.trim() || f.reply; drawFeedback(); loadOverview(); note.textContent = "Saved. The player sees it after their next companion sync."; }
    catch (e) { note.textContent = e.message; }
    save.disabled = false;
  } });
  const note = el("p", { class: "muted" });
  box.replaceChildren(
    el("h3", { text: (f.kind === "bug" ? "Bug" : "Idea") + " · " + dtFmt.format(new Date(f.received_at * 1000)) }),
    el("p", { text: f.text || "(no text, diagnostics only)" }),
    diag ? el("pre", { text: diag }) : null,
    el("label", { text: "Status" }), el("div", { class: "row" }, sel),
    el("label", { text: "Reply" }), reply,
    el("div", { class: "row" }, save), note,
    el("p", { class: "muted", text: "Id " + f.id }));
}

// disputes
async function loadDisputes() {
  try {
    const list = (await api("GET", "disputes")).disputes;
    $("#tbl-dsp tbody").replaceChildren(...(list.length ? list.map(d => {
      const actions = d.status === "open" ? el("td", {},
        el("button", { text: "Uphold (remove event)", onclick: () => decide(d.id, "upheld") }), " ",
        el("button", { text: "Reject (keep event)", onclick: () => decide(d.id, "rejected") })) : el("td", {});
      return el("tr", {}, el("td", { text: dayFmt.format(new Date(d.created_at * 1000)) }), el("td", { text: TRAITS[d.d] || d.d }),
        el("td", { text: d.reason || "" }), el("td", { text: d.status }), actions);
    }) : [el("tr", {}, el("td", { colspan: "5", class: "muted", text: "No disputes." }))]));
  } catch (e) { if (e.status === 401) toLogin(); }
}
async function decide(id, status) { await api("POST", "disputes/" + encodeURIComponent(id), { status }); loadDisputes(); loadOverview(); }

// ------------------------------------------------------------------ boot
let timer = null;
function toLogin() {
  clearInterval(timer);
  $("#app").hidden = true; $("#auth").hidden = false; $("#auth").classList.add("login");
  $("#auth-setup").hidden = true; $("#auth-login").hidden = false;
  $("#btn-passkey").hidden = false; $("#form-code").hidden = true;
}
function startApp() {
  $("#app").hidden = false;
  showView(location.hash.slice(1));
  loadOverview();
  clearInterval(timer);
  timer = setInterval(loadOverview, 60000);
}

$("#btn-passkey").addEventListener("click", startLogin);
$("#form-code").addEventListener("submit", submitCode);
$("#btn-create").addEventListener("click", createPasskey);
$("#form-setup-code").addEventListener("submit", confirmSetupCode);
$("#btn-refresh").addEventListener("click", () => { loadOverview(); if (!$('[data-section="feedback"]').hidden) loadFeedback(); });
$("#btn-logout").addEventListener("click", async () => { try { await api("POST", "logout"); } catch (_) { /* ignore */ } toLogin(); });
["#fb-status", "#fb-kind"].forEach(s => $(s).addEventListener("change", drawFeedback));
$("#fb-search").addEventListener("input", drawFeedback);
window.addEventListener("hashchange", () => { if (!$("#app").hidden) showView(location.hash.slice(1)); });
let resizeTimer = null;
window.addEventListener("resize", () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(render, 150); });

(async function boot() {
  const m = location.hash.match(/setup=([\w-]+)/);
  if (m) {
    setupToken = m[1];
    $("#auth").hidden = false; $("#auth").classList.remove("login"); $("#auth-login").hidden = true; $("#auth-setup").hidden = false;
    if (!window.PublicKeyCredential) msg("This browser doesn't support passkeys. Use Safari on your Mac.");
    return;
  }
  try {
    const st = await api("GET", "status");
    if (st.session) return startApp();
    toLogin();
    if (!st.enrolled) msg("Not enrolled yet.");
  } catch (e) { toLogin(); msg(e.message); }
})();
