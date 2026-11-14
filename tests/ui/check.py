#!/usr/bin/env python3
"""Browser checks for the Skill Table (docs/). Enforces the rules in docs/DESIGN.md.

Needs Playwright with Chromium:
  python3 -m venv .venv && .venv/bin/pip install playwright && .venv/bin/python -m playwright install chromium
Run from anywhere:
  .venv/bin/python tests/ui/check.py [--shots DIR] [--docs DIR]
Exits 1 and lists the failures if any rule breaks. --shots also saves screenshots of every
size, scheme and state for a visual pass.
"""
import argparse, functools, http.server, os, sys, threading
from playwright.sync_api import sync_playwright

DOCS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs")
SIZES = [("phone", 360, 740, False), ("touch", 412, 915, True), ("tablet", 768, 1024, False),
         ("mindesk", 1024, 600, False), ("desktop", 1440, 900, False)]
PICKS = ("nim-style-guide", "nim-api-design", "nim-testing", "nim-performance", "nim-c-bindings")

# Names wider or taller than their box: the tile layout allows two lines.
CLIPPED = """[...document.querySelectorAll('.tile')].filter(t => { const n = t.querySelector('.nm');
  return n.scrollHeight > n.clientHeight + 1 || n.scrollWidth > n.clientWidth + 1; }).map(t => t.dataset.name)"""
OVERFLOW = "document.scrollingElement.scrollWidth > innerWidth"

# Text contrast, compositing every translucent background layer through a canvas.
CONTRAST = r"""() => {
  const cv = document.createElement('canvas'); cv.width = cv.height = 1;
  const cx = cv.getContext('2d', { willReadFrequently: true });
  const over = cs => { cx.fillStyle = '#fff'; cx.fillRect(0, 0, 1, 1);
    for (const c of cs) { cx.fillStyle = c; cx.fillRect(0, 0, 1, 1); } return [...cx.getImageData(0, 0, 1, 1).data].slice(0, 3); };
  const lum = rgb => rgb.map(v => (v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
    .reduce((s, v, i) => s + v * [0.2126, 0.7152, 0.0722][i], 0);
  const layers = e => { const out = []; for (; e; e = e.parentElement) out.unshift(getComputedStyle(e).backgroundColor); return out; };
  const out = [];
  const add = (sel, label) => { const e = document.querySelector(sel); if (!e) return;
    const bg = layers(e), a = lum(over(bg)), b = lum(over([...bg, getComputedStyle(e).color]));
    out.push([label, (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)]); };
  add('#sub', 'subtitle'); add('.rprog', 'row progress'); add('.tile:not(.on) .no', 'tile number');
  add('.tile:not(.on) .nm', 'tile name'); add('.tile:not(.on) .sym', 'tile symbol');
  for (const c of ['blue', 'yellow', 'green', 'red', 'purple'])
    for (const p of ['sym', 'nm', 'no']) add(`.${c} .tile.on .${p}`, `${c} selected .${p}`);
  add('#count', 'dock count'); add('#chars', 'dock chars'); add('#rank', 'dock rank'); add('.note', 'note');
  add('.note a', 'note link'); add('#cmd', 'command'); add('#copy', 'Copy button'); add('.switch', 'switch label');
  return out;
}"""


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def serve(docs):
    handler = functools.partial(Quiet, directory=docs)
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{srv.server_port}/"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", help="directory for screenshots")
    ap.add_argument("--docs", default=DOCS, help="site directory to test (default: docs/)")
    args = ap.parse_args()
    if args.shots:
        os.makedirs(args.shots, exist_ok=True)
    fails = []
    srv, url = serve(args.docs)
    try:
        with sync_playwright() as p:
            b = p.chromium.launch()
            for name, w, h, touch in SIZES:
                for scheme in ("light", "dark"):
                    flows(b, url, name, w, h, touch, scheme, args.shots, fails)
            layout(b, url, fails)
            contrast(b, url, fails)
            b.close()
    finally:
        srv.shutdown()
    print("\n".join(fails) or "all checks passed")
    sys.exit(1 if fails else 0)


def flows(b, url, name, w, h, touch, scheme, shots, fails):
    """Selection, tip, focus, copy and toast, the switch and hash, over budget, touch targets."""
    ctx = b.new_context(viewport={"width": w, "height": h}, color_scheme=scheme, has_touch=touch, is_mobile=touch)
    ctx.grant_permissions(["clipboard-read", "clipboard-write"])
    pg = ctx.new_page()
    tag = f"{name}-{scheme}"
    pg.on("console", lambda m: m.type in ("error", "warning") and fails.append(f"{tag}: console {m.type}: {m.text}"))
    pg.on("pageerror", lambda e: fails.append(f"{tag}: page error: {e}"))
    tap = pg.tap if touch else pg.click

    def shot(state):
        if pg.evaluate(OVERFLOW):
            fails.append(f"{tag} {state}: horizontal overflow")
        if shots:
            pg.screenshot(path=os.path.join(shots, f"{tag}-{state}.png"))

    pg.goto(url); pg.wait_for_selector(".tile")
    shot("1-empty")
    for n in PICKS:
        tap(f'.tile[data-name="{n}"]')
    if not touch:
        pg.hover('.tile[data-name="nim-fuzzing"]')
    pg.wait_for_timeout(300)
    shot("2-selected-tip")

    pg.mouse.move(0, 0)
    pg.focus('.tile[data-name="nim-testing"]'); pg.keyboard.press("Tab"); pg.keyboard.press("Shift+Tab")
    pg.wait_for_timeout(300)
    if pg.evaluate("getComputedStyle(document.activeElement).outlineStyle") != "solid":
        fails.append(f"{tag}: no focus ring on a selected tile")
    shot("3-focus-selected")

    tap("#copy"); pg.wait_for_timeout(350)
    toast = pg.evaluate("document.getElementById('toast').className")
    clip = pg.evaluate("navigator.clipboard.readText()")
    if "show" not in toast or not clip.startswith("nyx install nim-api-design"):
        fails.append(f"{tag}: copy or toast failed ({toast!r}, {clip!r})")
    shot("4-toast")

    tap("#lang"); pg.wait_for_timeout(300)
    if not pg.url.endswith("#nimony"):
        fails.append(f"{tag}: switch did not set #nimony")
    pg.mouse.move(0, 0); pg.evaluate("document.activeElement.blur()")
    shot("5-nimony")
    pg.evaluate("document.querySelectorAll('.tile:not(.on)').forEach(t => t.click())")
    pg.wait_for_timeout(300)
    if not pg.evaluate("document.getElementById('stat').classList.contains('full')"):
        fails.append(f"{tag}: over-budget state missing")
    shot("6-over-budget")

    pg.goto(url + "#nimony"); pg.reload(); pg.wait_for_selector(".tile")
    if pg.evaluate("document.getElementById('lang').getAttribute('aria-checked')") != "true":
        fails.append(f"{tag}: #nimony deep link did not turn the switch on")

    if touch:
        for sel in ("#copy", "#cmd", ".tile"):
            bb = pg.locator(sel).first.bounding_box()
            if bb["height"] < 44 or bb["width"] < 44:
                fails.append(f"{tag}: {sel} is {bb['width']:.0f}x{bb['height']:.0f}, under 44px")
        r = pg.locator(".track").bounding_box()
        pg.touchscreen.tap(r["x"] + r["width"] / 2, r["y"] + r["height"] / 2 + 20); pg.wait_for_timeout(300)
        if pg.evaluate("document.getElementById('lang').getAttribute('aria-checked')") != "false":
            fails.append(f"{tag}: a tap 20px below the switch missed its 44px hit area")
    ctx.close()


def layout(b, url, fails):
    """1024x600 fits without scrolling; tips stay above the dock; names fit in two lines; no overflow."""
    pg = b.new_context(viewport={"width": 1024, "height": 600}).new_page()
    pg.goto(url); pg.wait_for_selector(".tile")
    sh, ch = pg.evaluate("(() => { const m = document.querySelector('main'); return [m.scrollHeight, m.clientHeight]; })()")
    if sh > ch:
        fails.append(f"1024x600: the Nim view scrolls ({sh} > {ch})")
    pg.hover('.tile[data-name="wine-windows-build-debugging"]'); pg.wait_for_timeout(300)
    tip, dock = pg.evaluate("[document.querySelector('.tile:hover .tip').getBoundingClientRect().bottom,"
                            " document.querySelector('.dock').getBoundingClientRect().top]")
    if tip > dock:
        fails.append("1024x600: a last-row tip covers the bottom bar")
    for w in [*range(320, 1500, 7), 360, 412, 550, 768, 860, 1023, 1024, 1440]:
        for hash_ in ("", "#nimony"):
            pg.set_viewport_size({"width": w, "height": 800})
            pg.goto(url + hash_); pg.reload(); pg.wait_for_selector(".tile")
            clipped = pg.evaluate(CLIPPED)
            if clipped:
                fails.append(f"{w}px{hash_}: clipped names {clipped}")
            if pg.evaluate(OVERFLOW):
                fails.append(f"{w}px{hash_}: horizontal overflow")


def contrast(b, url, fails):
    """Every text pair at least 4.5:1, light and dark, normal and high contrast, in range and over budget."""
    for scheme in ("light", "dark"):
        for more in ("no-preference", "more"):
            pg = b.new_context(viewport={"width": 1024, "height": 2400}, color_scheme=scheme, contrast=more).new_page()
            pg.goto(url + "#nimony"); pg.wait_for_selector(".tile")
            pg.evaluate("document.querySelectorAll('.row').forEach(r => r.querySelector('.tile').click())")
            pg.mouse.move(0, 0)
            for state in ("in range", "over budget"):
                if state == "over budget":
                    pg.evaluate("document.querySelectorAll('.tile:not(.on)').forEach(t => t.click())")
                pg.wait_for_timeout(400)  # past the 200ms transitions
                for label, ratio in pg.evaluate(CONTRAST):
                    if ratio < 4.5:
                        fails.append(f"contrast {scheme}/{more}/{state}: {label} {ratio:.2f}:1")


if __name__ == "__main__":
    main()
