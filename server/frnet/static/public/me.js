"use strict";
const $ = s => document.querySelector(s);
let data = null;
function row(cells, tag = "td") { const tr = document.createElement("tr"); cells.forEach(c => { const t = document.createElement(tag); t.textContent = c; tr.append(t); }); return tr; }
async function load() {
  const res = await fetch("/me/api/data", { credentials: "same-origin" });
  if (!res.ok) return;
  data = await res.json();
  $("#signin").hidden = true; $("#data").hidden = false;
  const box = $("#summary"); box.replaceChildren();
  const p = document.createElement("p");
  p.textContent = data.characters.length
    ? `${data.characters.length} WoW: Forever character(s) on your Battle.net account. Installs linked: ${data.linkedInstalls}. Group sessions you shared: ${data.sessionsYouShared}.`
    : "Battle.net lists no WoW: Forever characters for your account yet, so there is nothing we can tie to you.";
  box.append(p);
  if (data.characters.length) {
    const t = document.createElement("table");
    t.append(row(["Character", "Layers on", "Public profile", "Seen in shared sessions", "Excluded"], "th"));
    data.characters.forEach(c => {
      const layers = c.participant ? ["backup", "profile", "community", "recommend"].filter(k => c.participant["c_" + k]).join(", ") || "none" : "not a participant";
      t.append(row([`${c.name || "?"} (${c.realm || "?"})`, layers, c.publicProfile ? JSON.stringify(c.publicProfile) : "-", String(c.seenInCommunitySessions), c.optedOut ? "yes" : "no"]));
    });
    box.append(t);
  }
  const note = document.createElement("p"); note.className = "muted"; note.textContent = data.note; box.append(note);
}
$("#download").addEventListener("click", () => {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = "forever-relationships-my-data.json"; a.click();
});
$("#delete").addEventListener("click", async () => {
  if (!confirm("Delete everything Forever Relationships holds about your characters and keep them excluded from now on?")) return;
  const res = await fetch("/me/api/delete", { method: "POST", credentials: "same-origin" });
  const out = await res.json();
  $("#msg").textContent = res.ok ? `Done. ${out.excludedCharacters} character(s) deleted and excluded.` : out.error;
  if (res.ok) load();
});
$("#logout").addEventListener("click", async () => { await fetch("/me/api/logout", { method: "POST", credentials: "same-origin" }); location.reload(); });
load();
