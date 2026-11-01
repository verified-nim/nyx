// Skill Table: press skills, read the listing size, copy one install command.
(function () {
  "use strict";
  const CAP = 8000;
  const SIZES = [[0, "Nothing selected"], [1, "Light set"], [3, "Focused set"], [6, "Broad set"], [10, "Large set"]];
  const sel = new Set();
  const info = {};
  const groupEls = [];
  const $ = id => document.getElementById(id);
  const fmt = n => n.toLocaleString("en-US");
  const short = n => n.replace(/^nimony-/, "").replace(/^nim-/, "").replace(/-build-debugging$/, "-build");
  let no = 0;
  let noteTimer = 0;

  function symbol(n) {
    const w = short(n).split("-");
    const s = w.length > 1 ? w[0][0] + w[1][0] : w[0].slice(0, 2);
    return s[0].toUpperCase() + s.slice(1).toLowerCase();
  }
  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text) e.textContent = text;
    return e;
  }

  function build(data) {
    const rows = $("rows");
    for (const { group, skills } of data) {
      const row = el("section", "row"), head = el("div", "rhead"), tiles = el("div", "tiles");
      head.append(el("div", "rname", group), el("div", "rprog"));
      skills.forEach((s, i) => {
        info[s.name] = s.chars + s.name.length;
        const t = el("button", "tile" + (i >= 4 ? " r" : ""));
        t.type = "button";
        t.dataset.name = s.name;
        t.setAttribute("aria-label", s.name + ". " + s.blurb);
        const tip = el("span", "tip");
        tip.append(el("b", "", s.name), document.createTextNode(s.blurb));
        t.append(el("span", "no", String(++no)), el("span", "sym", symbol(s.name)), el("span", "nm", short(s.name)), tip);
        tiles.append(t);
      });
      row.append(head, tiles);
      rows.append(row);
      groupEls.push([row, skills.map(s => s.name)]);
    }
    rows.addEventListener("click", e => {
      const t = e.target.closest(".tile");
      if (!t) return;
      const name = t.dataset.name, adding = !sel.has(name);
      if (adding) sel.add(name); else sel.delete(name);
      render();
      if (adding) { t.classList.remove("pop"); void t.offsetWidth; t.classList.add("pop"); }
    });
  }

  function command(full) {
    const names = [...sel].sort();
    if (full || names.length <= 2) return "nyx install " + names.join(" ");
    return `nyx install ${names[0]} ${names[1]} +${names.length - 2} more`;
  }
  function resetNote() {
    const n = $("note");
    n.className = "note";
    n.innerHTML = 'Needs <a href="https://github.com/verified-nim/nyx">nyx</a> and a <a href="https://verified-nim.github.io/get-access.html">subscription</a>. Installs for Claude Code, Codex, Cursor and more.';
  }
  function render() {
    document.querySelectorAll(".tile").forEach(t => {
      const on = sel.has(t.dataset.name);
      t.classList.toggle("on", on);
      t.setAttribute("aria-pressed", on);
    });
    for (const [row, names] of groupEls) {
      const k = names.filter(n => sel.has(n)).length, done = k === names.length;
      row.classList.toggle("done", done);
      row.querySelector(".rprog").textContent = done ? "Complete" : `${k} of ${names.length}`;
    }
    const count = sel.size;
    const chars = [...sel].reduce((s, n) => s + info[n], 0);
    const full = chars > CAP;
    $("rank").textContent = full ? "Context full" : [...SIZES].reverse().find(r => count >= r[0])[1];
    $("rank").classList.toggle("full", full);
    $("count").textContent = `${count} of ${no} selected`;
    $("chars").textContent = `${fmt(chars)} / ${fmt(CAP)} context`;
    $("meter").classList.toggle("full", full);
    $("meter").firstElementChild.style.width = Math.min(100, chars / CAP * 100) + "%";
    const cmd = $("cmd");
    if (!count) {
      cmd.className = "cmd empty";
      cmd.removeAttribute("title");
      cmd.textContent = "Press a skill to build your command";
      $("copy").disabled = true;
    } else {
      cmd.className = "cmd";
      cmd.title = command(true);
      cmd.replaceChildren(el("span", "", command(false)));
      $("copy").disabled = false;
    }
    if (!noteTimer) resetNote();
  }

  $("copy").addEventListener("click", async () => {
    const note = $("note");
    let msg = "Copied. Run it in your project root.";
    try { await navigator.clipboard.writeText(command(true)); }
    catch (_) { msg = "Copy blocked here. Hover the box to read the full command."; }
    note.className = "note ok";
    note.textContent = msg;
    clearTimeout(noteTimer);
    noteTimer = setTimeout(() => { noteTimer = 0; resetNote(); }, 3500);
  });

  render();
  fetch("skills.json")
    .then(r => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(data => { build(data); render(); })
    .catch(() => { $("rows").append(el("p", "", "The skill list did not load. Reload the page to try again.")); });
})();
