// Skill Table: select skills, read the listing size, copy one install command.
(function () {
  "use strict";
  const CAP = 8000;
  const SIZES = [[0, "Nothing selected"], [1, "Light set"], [3, "Focused set"], [6, "Broad set"], [10, "Large set"]];
  const sel = new Set();
  const sizes = {};
  const groupEls = [];
  const $ = id => document.getElementById(id);
  const fmt = n => n.toLocaleString("en-US");
  const short = n => n.replace(/^nimony-/, "").replace(/^nim-/, "").replace(/-build-debugging$/, "-build");
  const noteHTML = $("note").innerHTML;
  let copyTimer = 0;

  function cap(s) { return s[0].toUpperCase() + s.slice(1).toLowerCase(); }
  // Initials, or the first two letters when the row has already used those initials.
  function symbol(n, used) {
    const w = short(n).split("-");
    const initials = w.length > 1 ? cap(w[0][0] + w[1][0]) : "";
    const s = initials && !used.has(initials) ? initials : cap(w[0].slice(0, 2));
    used.add(s);
    return s;
  }
  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text) e.textContent = text;
    return e;
  }

  // The note under the command describes the active skill, or else gives the usage line.
  function showNote(tile) {
    if (tile) $("note").textContent = tile.dataset.blurb;
    else $("note").innerHTML = noteHTML;
  }

  function build(data) {
    const rows = $("rows");
    for (const { group, skills } of data) {
      const row = el("section", "row"), head = el("div", "rhead"), tiles = el("div", "tiles"), used = new Set();
      head.append(el("h2", "rname", group), el("div", "rprog"));
      for (const s of skills) {
        sizes[s.name] = s.chars + s.name.length;
        const t = el("button", "tile");
        t.type = "button";
        t.dataset.name = s.name;
        t.dataset.blurb = s.blurb;
        t.setAttribute("aria-label", s.name + ". " + s.blurb);
        t.append(el("span", "sym", symbol(s.name, used)), el("span", "nm", short(s.name)));
        tiles.append(t);
      }
      row.append(head, tiles);
      rows.append(row);
      groupEls.push([row, skills.map(s => s.name)]);
    }
    rows.addEventListener("click", e => {
      const t = e.target.closest(".tile");
      if (!t) return;
      const name = t.dataset.name;
      if (sel.has(name)) sel.delete(name); else sel.add(name);
      render();
    });
    rows.addEventListener("focusin", e => showNote(e.target.closest(".tile")));
    rows.addEventListener("focusout", () => showNote(null));
    // The gaps between tiles keep the current description, so it doesn't flicker.
    // Touch screens keep it too: a tap can report the pointer leaving straight away.
    const canHover = matchMedia("(hover: hover)").matches;
    document.addEventListener("mouseover", e => {
      const t = e.target.closest(".tile");
      if (t || (canHover && !e.target.closest(".tiles"))) showNote(t);
    });
  }

  function command() { return "nyx install " + [...sel].sort().join(" "); }
  function render() {
    document.querySelectorAll(".tile").forEach(t => {
      const on = sel.has(t.dataset.name);
      t.classList.toggle("on", on);
      t.setAttribute("aria-pressed", on);
    });
    for (const [row, names] of groupEls) {
      const k = names.filter(n => sel.has(n)).length;
      row.classList.toggle("done", k === names.length);
      row.querySelector(".rprog").textContent = `${k}/${names.length}`;
    }
    const count = sel.size;
    const chars = [...sel].reduce((s, n) => s + sizes[n], 0);
    const full = chars > CAP;
    $("rank").textContent = full ? "Context full" : [...SIZES].reverse().find(r => count >= r[0])[1];
    $("count").textContent = `${count} of ${Object.keys(sizes).length}`;
    $("chars").textContent = `${fmt(chars)} / ${fmt(CAP)} context`;
    $("stat").classList.toggle("full", full);
    $("meter").style.width = Math.min(100, chars / CAP * 100) + "%";
    const cmd = $("cmd");
    cmd.classList.toggle("empty", !count);
    cmd.textContent = count ? command() : "Select skills to build your install command";
    cmd.title = count ? command() : "";
    $("copy").disabled = !count;
  }

  $("copy").addEventListener("click", async () => {
    const copy = $("copy");
    showNote(null);
    try {
      await navigator.clipboard.writeText(command());
      copy.textContent = "Copied";
    } catch (_) {
      copy.textContent = "Blocked";
    }
    clearTimeout(copyTimer);
    copyTimer = setTimeout(() => { copy.textContent = "Copy"; }, 1500);
  });

  render();
  fetch("skills.json")
    .then(r => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(data => { build(data); render(); })
    .catch(() => { $("rows").append(el("p", "", "The skills didn't load. Reload the page to try again.")); });
})();
