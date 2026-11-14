// Skill Table: pick a language, select skills, read the listing size, copy one install command.
(function () {
  "use strict";

  const CAP = 8000; // listing budget in characters
  const RANKS = [[10, "Large Set"], [6, "Broad Set"], [3, "Focused Set"], [1, "Light Set"], [0, "Nothing Selected"]];
  const COLORS = ["blue", "yellow", "green", "red", "purple"]; // Adwaita accents, by group index, so a row keeps its color in both views
  const LANGS = {
    nim: "Nim 2 skills for Claude Code, Codex, Cursor and more",
    nimony: "Nimony skills for Claude Code, Codex, Cursor and more",
  };

  let groups = [];
  let lang = "nim";
  let shown = []; // [row element, skill names] for the current view
  const sel = new Set(); // kept across views; only the shown part counts
  const sizes = {}; // name -> listing characters
  let toastTimer = 0;

  const $ = id => document.getElementById(id);
  const fmt = n => n.toLocaleString("en-US");
  const short = n => n.replace(/^(nim(ony)?-)?(compiler-)?/, "").replace(/-build-debugging$/, "-build");
  const titleCase = s => s[0].toUpperCase() + s.slice(1).toLowerCase();
  const chosen = () => shown.flatMap(([, names]) => names.filter(n => sel.has(n))).sort();
  const command = (picked = chosen()) => "nyx install " + picked.join(" ");
  const fromHash = () => location.hash.slice(1);

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text) e.textContent = text;
    return e;
  }

  // Initials, or the first two letters when the row has already used those initials.
  function symbol(name, used) {
    const w = short(name).split("-");
    const initials = w.length > 1 ? titleCase(w[0][0] + w[1][0]) : "";
    const s = initials && !used.has(initials) ? initials : titleCase(w[0].slice(0, 2));
    used.add(s);
    return s;
  }

  function tile(s, no, used) {
    const t = el("button", "tile");
    t.type = "button";
    t.dataset.name = s.name;
    t.setAttribute("aria-label", s.name + ". " + s.blurb);
    t.append(el("span", "no", String(no)), el("span", "sym", symbol(s.name, used)), el("span", "nm", short(s.name)), el("span", "tip", s.blurb));
    return t;
  }

  // Rebuild the rows for the current language, leaving out empty groups.
  function build() {
    shown = [];
    let no = 0;
    const rows = groups.flatMap(({ group, skills }, i) => {
      const list = skills.filter(s => s.langs.includes(lang));
      if (!list.length) return [];
      const row = el("section", "row " + COLORS[i % COLORS.length]), head = el("div", "rhead"), tiles = el("div", "tiles"), used = new Set();
      head.append(el("h2", "rname", group), el("div", "rprog"));
      tiles.append(...list.map(s => tile(s, ++no, used)));
      row.append(head, tiles);
      shown.push([row, list.map(s => s.name)]);
      return [row];
    });
    $("rows").replaceChildren(...rows);
  }

  function render() {
    let total = 0;
    for (const [row, names] of shown) {
      const k = names.filter(n => sel.has(n)).length;
      total += names.length;
      row.classList.toggle("done", k === names.length);
      row.querySelector(".rprog").textContent = `${k}/${names.length}`;
      for (const t of row.querySelectorAll(".tile")) {
        const on = sel.has(t.dataset.name);
        t.classList.toggle("on", on);
        t.setAttribute("aria-pressed", on);
      }
    }
    const picked = chosen();
    const count = picked.length;
    const chars = picked.reduce((s, n) => s + sizes[n], 0);
    const full = chars > CAP;
    $("rank").textContent = full ? "Context Full" : RANKS.find(r => count >= r[0])[1];
    $("count").textContent = `${count} of ${total}`;
    $("chars").textContent = `${fmt(chars)} / ${fmt(CAP)} context`;
    $("stat").classList.toggle("full", full);
    $("meter").style.width = Math.min(100, chars / CAP * 100) + "%";
    const cmd = $("cmd");
    cmd.classList.toggle("empty", !count);
    cmd.textContent = count ? command(picked) : "Select skills to build the install command";
    cmd.title = count ? cmd.textContent : "";
    $("copy").disabled = !count;
  }

  function setLang(next) {
    lang = Object.hasOwn(LANGS, next) ? next : "nim";
    $("lang").setAttribute("aria-checked", lang === "nimony");
    $("sub").textContent = LANGS[lang];
    if (!groups.length) return; // not loaded: keep the load message in place
    build();
    render();
  }

  // The switch flips between Nim and Nimony. Nim is the default view, so it drops the hash; Nimony deep-links as #nimony.
  $("lang").addEventListener("click", () => {
    const next = lang === "nim" ? "nimony" : "nim";
    history.replaceState(null, "", next === "nim" ? location.pathname + location.search : "#" + next);
    setLang(next);
  });
  window.addEventListener("hashchange", () => setLang(fromHash()));

  $("rows").addEventListener("click", e => {
    const t = e.target.closest(".tile");
    if (!t) return;
    const name = t.dataset.name;
    if (sel.has(name)) sel.delete(name); else sel.add(name);
    render();
  });

  // A toast: the live region announces the text, and it fades out on its own.
  function toast(text) {
    const t = $("toast");
    t.textContent = text;
    t.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove("show"), 2000);
  }

  $("copy").addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(command());
      toast("Command Copied");
    } catch {
      toast("Clipboard Access Blocked");
    }
  });

  render();
  fetch("skills.json")
    .then(r => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(data => {
      groups = data;
      for (const { skills } of groups) for (const s of skills) sizes[s.name] = s.chars + s.name.length;
      setLang(fromHash());
    })
    .catch(() => { $("rows").append(el("p", "status", "The skills didn’t load. Reload the page to try again.")); });
})();
