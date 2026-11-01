// Skill table: press skills, read the listing size, copy one install command.
(function () {
  "use strict";
  const CAP = 8000;
  const $ = id => document.getElementById(id);
  const selected = new Set();
  const size = new Map();
  const groups = [];
  let total = 0;
  let over = false;
  let noteTimer = 0;

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text) e.textContent = text;
    return e;
  }
  const shortName = n => n.replace(/^nimony-/, "").replace(/^nim-/, "").replace(/-build-debugging$/, "-build");
  function symbol(n) {
    const w = shortName(n).split("-");
    const s = w.length > 1 ? w[0][0] + w[1][0] : w[0].slice(0, 2);
    return s[0].toUpperCase() + s.slice(1).toLowerCase();
  }
  const fmt = n => n.toLocaleString("en-US");
  const command = () => "nyx install " + [...selected].sort().join(" ");

  function build(data) {
    const rows = $("skill-rows");
    for (const { group, skills } of data) {
      const row = el("section", "skill-row");
      const head = el("div");
      const count = el("p", "skill-row__count");
      head.append(el("h2", "", group), count);
      const tiles = el("div", "tiles");
      skills.forEach((s, i) => {
        size.set(s.name, s.chars + s.name.length);
        const t = el("button", "tile" + (i >= 4 ? " tile--right" : ""));
        t.type = "button";
        t.dataset.name = s.name;
        t.setAttribute("aria-pressed", "false");
        t.setAttribute("aria-label", s.name + ". " + s.blurb);
        const tip = el("span", "tip");
        tip.append(el("b", "", s.name), document.createTextNode(s.blurb));
        t.append(el("span", "tile__no", String(++total)), el("span", "tile__sym", symbol(s.name)),
                 el("span", "tile__name", shortName(s.name)), tip);
        tiles.append(t);
      });
      row.append(head, tiles);
      rows.append(row);
      groups.push({ count, names: skills.map(s => s.name) });
    }
    rows.addEventListener("click", e => {
      const t = e.target.closest(".tile");
      if (!t) return;
      const name = t.dataset.name;
      const on = !selected.has(name);
      if (on) selected.add(name); else selected.delete(name);
      t.setAttribute("aria-pressed", String(on));
      render();
    });
  }

  function showNote(text) {
    $("note").textContent = text;
    $("note").hidden = !text;
    $("note-default").hidden = !!text;
  }
  // The standing note: the over-limit warning, or the install links.
  function restNote() {
    showNote(over ? "Over the limit: your agent's skill listing may cut descriptions." : "");
  }
  function say(text) {
    showNote(text);
    clearTimeout(noteTimer);
    noteTimer = setTimeout(() => { noteTimer = 0; restNote(); }, 5000);
  }

  function render() {
    for (const g of groups) {
      g.count.textContent = g.names.filter(n => selected.has(n)).length + " of " + g.names.length;
    }
    let chars = 0;
    for (const n of selected) chars += size.get(n);
    over = chars > CAP;
    $("count").textContent = selected.size + " of " + total + " selected";
    $("chars").textContent = fmt(chars) + " of " + fmt(CAP) + " characters";
    $("meter").classList.toggle("is-over", over);
    $("meter").firstElementChild.style.width = Math.min(100, chars / CAP * 100) + "%";
    if (!noteTimer) restNote();
    const box = $("command");
    box.classList.toggle("is-empty", selected.size === 0);
    box.textContent = selected.size ? command() : "Press a skill to build your command";
    $("copy").disabled = selected.size === 0;
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(command());
      say("Copied. Run it in your repository root.");
    } catch (_) {
      const range = document.createRange();
      range.selectNodeContents($("command"));
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
      say("Copy was blocked. The command is selected: copy it by hand.");
    }
  }

  $("copy").addEventListener("click", copy);
  render();
  fetch("skills.json")
    .then(r => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(data => { build(data); render(); })
    .catch(() => { $("skill-rows").append(el("p", "", "The skill list did not load. Reload the page to try again.")); });
})();
