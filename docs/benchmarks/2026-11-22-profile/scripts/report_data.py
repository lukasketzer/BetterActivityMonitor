#!/usr/bin/env python3
"""Builds data.json and traces/*.json for the report page from the runs in /tmp/bamprof/runs.
usage: report_data.py <out-dir>"""
import json, os, re, statistics, sys

out = sys.argv[1]
R = "/tmp/bamprof/runs"
os.makedirs(os.path.join(out, "traces"), exist_ok=True)


def summ(label):
    p = os.path.join(R, label, "summary.txt")
    if not os.path.exists(p):
        return None
    s = open(p).read()
    if "window=hidden" in s and "menubar" not in label:
        return None  # the window ended up covered, so the page was not drawn: not a window-visible measurement
    cpu = float(re.search(r"cpu=\s*([\d.]+)%", s).group(1))
    fp = re.search(r"footprint=([\d.]+) (MB|GB)", s)
    top = re.search(r"top=\[\s*\d+\s+([\d.]+)\s+(\d+)", s)
    return {"cpu": cpu, "footprint": float(fp.group(1)) * (1024 if fp.group(2) == "GB" else 1) if fp else None,
            "wakeups": int(top.group(2)) if top else None, "time": os.path.getmtime(p)}


# --- every run, with build and display state. Values of runs whose summary files were later overwritten are
# --- copied from the session log (marked "log").
B, F1, FIN = "Before", "After fixes 1-2", "Final"
ON, OFF = "on", "asleep"
logged = {
    "base-overview": {"cpu": 56.6, "footprint": 215, "wakeups": 494},
    "base-processes": {"cpu": 6.1, "footprint": 296, "wakeups": 66},
    "base-cpu": {"cpu": 4.8, "footprint": 299, "wakeups": 94},
    "base-memory": {"cpu": 3.9, "footprint": 225, "wakeups": 89},
    "base-system": {"cpu": 3.9, "footprint": 202, "wakeups": 58},
}
catalog = [
    ("base-overview", B, "Overview", ON, ""),
    ("base-processes", B, "Processes", ON, ""),
    ("base-cpu", B, "CPU", ON, ""),
    ("base-memory", B, "Memory", ON, ""),
    ("base-system", B, "System", ON, ""),
    ("base-menubar-only", B, "Menu bar only (window closed)", ON, ""),
    ("base-menubar-only-tp", B, "Menu bar only (window closed)", ON, "while tracing"),
    ("base-ov-norings", B, "Overview without rings", ON, "ablation"),
    ("base-ov-nopanels", B, "Overview, rings only", ON, "ablation"),
    ("base-ov-empty", B, "Overview, nothing shown", ON, "ablation"),
    ("base-ring-cpu", B, "Overview, CPU ring only", ON, "ablation"),
    ("base-ring-storage", B, "Overview, storage ring only", ON, "ablation"),
    ("base-ring-battery", B, "Overview, battery ring only", ON, "ablation"),
    ("fix1-overview", F1, "Overview", ON, ""),
    ("fix1-overview-tp", F1, "Overview", ON, "while tracing"),
    ("fix1-overview-again", F1, "Overview", ON, ""),
    ("fix1-overview-nomenubar", F1, "Overview, menu bar item off", ON, ""),
    ("fix1-menubar-only", F1, "Menu bar only (window closed)", ON, ""),
    ("fix1-menubar-tp", F1, "Menu bar only (window closed)", ON, "while tracing"),
    ("rep-base-menubar-1", B, "Menu bar only (window closed)", OFF, "interleaved pair 1"),
    ("rep-after-menubar-1", FIN, "Menu bar only (window closed)", OFF, "interleaved pair 1"),
    ("rep-after-menubar-2", FIN, "Menu bar only (window closed)", OFF, "interleaved pair 2"),
    ("rep-base-menubar-2", B, "Menu bar only (window closed)", OFF, "interleaved pair 2"),
    ("rep-base-menubar-3", B, "Menu bar only (window closed)", OFF, "interleaved pair 3"),
    ("rep-after-menubar-3", FIN, "Menu bar only (window closed)", OFF, "interleaved pair 3"),
    ("after-menubar-asleep-tp", FIN, "Menu bar only (window closed)", OFF, "while tracing"),
    ("final-overview", FIN, "Overview", ON, ""),
    ("final-overview-nomenubar", FIN, "Overview, menu bar item off", ON, ""),
    ("final-overview-2", FIN, "Overview", ON, ""),
    ("final-processes", FIN, "Processes", ON, ""),
    ("final-menubar", FIN, "Menu bar only (window closed)", ON, ""),
    ("final-overview-tp", FIN, "Overview", ON, "while tracing"),
    ("final-menubar-tp", FIN, "Menu bar only (window closed)", ON, "while tracing"),
    ("exp-overview-canvas", "Experiment", "Overview, charts drawn (Canvas)", ON, "same build as next row"),
    ("exp-overview-nocanvas", "Experiment", "Overview, Canvas drawing switched off", ON, "same build, flag set"),
    ("cmp-canvas-overview-1", FIN, "Overview", ON, "charts: Canvas, pair 1"),
    ("cmp-shapes-overview-1", "Final + shapes", "Overview", ON, "charts: shapes, pair 1"),
    ("cmp-canvas-overview-2", FIN, "Overview", ON, "charts: Canvas, pair 2"),
    ("cmp-shapes-overview-2", "Final + shapes", "Overview", ON, "charts: shapes, pair 2"),
    ("final2-overview-tp", "Final + shapes", "Overview", ON, "while tracing"),
]
runs = []
for label, build, scen, disp, note in catalog:
    s = logged.get(label) or summ(label)
    if not s:
        continue
    runs.append({"label": label, "build": build, "scenario": scen, "display": disp, "note": note,
                 "cpu": s["cpu"], "footprint": s["footprint"], "wakeups": s["wakeups"]})


def pick(build, scen, disp, note_ok=("", "interleaved pair 1", "interleaved pair 2", "interleaved pair 3")):
    vals = [r for r in runs if r["build"] == build and r["scenario"] == scen and r["display"] == disp and r["note"] in note_ok]
    return vals


def med(vals, key):
    v = [r[key] for r in vals if r[key] is not None]
    return statistics.median(v) if v else None


have_final_on = bool(pick(FIN, "Overview", ON))
after_build = FIN if have_final_on else F1

comparisons = []
FS = "Final + shapes"
for scen, disp, name in [("Overview", ON, "Overview, window in front"),
                         ("Processes", ON, "Processes, window in front"),
                         ("Menu bar only (window closed)", ON, "Menu bar only, display on"),
                         ("Menu bar only (window closed)", OFF, "Menu bar only, display asleep")]:
    b = pick(B, scen, disp)
    shapes = pick(FS, scen, disp, note_ok=("charts: shapes, pair 1", "charts: shapes, pair 2"))
    a = shapes or pick(FIN, scen, disp) or (pick(F1, scen, disp) if disp == ON else [])
    if not b or not a:
        continue
    ab = a[0]["build"]
    # Footprint only compares when the after build already draws charts with shapes, or the scenario has no charts.
    mem_ok = ab == FS or scen.startswith("Menu bar")
    comparisons.append({"name": name, "afterBuild": ab, "n": [len(b), len(a)], "memOk": mem_ok,
                        "before": {"cpu": med(b, "cpu"), "footprint": med(b, "footprint"), "wakeups": med(b, "wakeups")},
                        "after": {"cpu": med(a, "cpu"), "footprint": med(a, "footprint"), "wakeups": med(a, "wakeups")}})

ablation = [{"name": r["scenario"].replace("Overview, ", "").replace("Overview without rings", "without the rings"),
             "cpu": r["cpu"]} for r in runs if r["label"] in
            ("base-overview", "base-ov-nopanels", "base-ring-cpu", "base-ov-norings", "base-ring-storage", "base-ring-battery", "base-ov-empty")]
ablation.sort(key=lambda x: -x["cpu"])
for a in ablation:
    if a["name"] == "Overview":
        a["name"] = "everything (default)"


# --- traces
def prune(node, minv):
    kids = [prune(c, minv) for c in node.get("c", []) if c["v"] >= minv]
    o = {"n": node["n"], "v": node["v"]}
    if kids:
        o["c"] = kids
    return o


trace_specs = [
    ("on-base-overview-tp", "Before · Overview (display on)"),
    ("final2-overview-tp", "Final + shapes · Overview (display on)"),
    ("final-overview-tp", "Final · Overview (display on)"),
    ("fix1-overview-tp", "After fixes 1-2 · Overview (display on)"),
    ("base-menubar-only-tp", "Before · Menu bar only (display on)"),
    ("final-menubar-tp", "Final · Menu bar only (display on)"),
    ("fix1-menubar-tp", "After fixes 1-2 · Menu bar only (display on)"),
    ("after-menubar-asleep-tp", "Final · Menu bar only (display asleep)"),
    ("sysbench", "Sampler alone (sysbench, 60 ticks at 250 ms)"),
]
traces = []
for label, name in trace_specs:
    p = os.path.join(R, label, "tp.json")
    if not os.path.exists(p):
        continue
    d = json.load(open(p))
    d["flame"] = prune(d["flame"], max(d["total_ms"] * 0.0025, 2))
    d["label"], d["id"] = name, label
    d["inclusive"], d["self"] = d["inclusive"][:80], d["self"][:40]
    json.dump(d, open(os.path.join(out, "traces", label + ".json"), "w"), separators=(",", ":"))
    # Script twin, so the page also works opened straight from disk (file:// blocks fetch).
    with open(os.path.join(out, "traces", label + ".js"), "w") as f:
        f.write("(window.REPORT_TRACES = window.REPORT_TRACES || {})[" + json.dumps(label) + "] = ")
        json.dump(d, f, separators=(",", ":"))
        f.write(";\n")
    traces.append({"id": label, "name": name, "total_ms": d["total_ms"], "duration_s": d["duration_s"]})


# --- memory breakdown of menu-bar-only, interleaved pair 1
def cats(label):
    p = os.path.join(R, label, "footprint.txt")
    if not os.path.exists(p):
        return None
    total = None
    c = {"GPU buffers": 0.0, "Malloc heap": 0.0, "CG images": 0.0, "Everything else": 0.0}
    for line in open(p):
        m = re.search(r"Footprint: ([\d.]+) (MB|GB|KB)", line)
        if m and total is None:
            total = float(m.group(1)) * (1024 if m.group(2) == "GB" else 1 / 1024 if m.group(2) == "KB" else 1)
        m = re.match(r"\s*([\d.]+) (B|KB|MB|GB)\s+[\d.]+ (?:B|KB|MB|GB)\s+[\d.]+ (?:B|KB|MB|GB)\s+\d+\s+(.+)", line)
        if m:
            v = float(m.group(1)) * {"B": 1 / 1048576, "KB": 1 / 1024, "MB": 1, "GB": 1024}[m.group(2)]
            name = m.group(3).strip()
            if name == "TOTAL":
                continue
            key = ("GPU buffers" if "(graphics)" in name else "Malloc heap" if name.startswith("Malloc")
                   else "CG images" if name == "CG Image" else "Everything else")
            c[key] += v
    c = {k: round(v, 1) for k, v in c.items()}
    c["total"] = total
    return c


def shot(label):
    d = os.path.join(R, label)
    if not os.path.exists(os.path.join(d, "visible.txt")) or "no" in open(os.path.join(d, "visible.txt")).read():
        return None
    c = cats(label)
    return {"label": label, "footprint": c["total"], "gpu": c["GPU buffers"], "png": os.path.join(d, "window.png")}


shots = {k: shot(k) for k in ("shapes-overview", "shapes-memory", "shapes-network", "shapes-cpu", "canvas-overview")}
growth = [[int(t), float(c), float(f)] for t, c, f in (l.split() for l in open(os.path.join(R, "fix1-growth-processes", "growth.tsv")))]

c = {x["name"]: x for x in comparisons}
ov, mbo, mba = c.get("Overview, window in front"), c.get("Menu bar only, display on"), c.get("Menu bar only, display asleep")
pct = lambda v: f"{v:.1f} %"
fin_on = pick(FIN, "Overview", ON)
fin_nomb = pick(FIN, "Overview, menu bar item off", ON)
f1_on = pick(F1, "Overview", ON)
f1_nomb = pick(F1, "Overview, menu bar item off", ON)
mb_cost_before = med(f1_on, "cpu") - med(f1_nomb, "cpu")
mb_cost_after = (med(fin_on, "cpu") - med(fin_nomb, "cpu")) if fin_on and fin_nomb else None
after_label = {FS: "final build", FIN: "final build before the chart change", F1: "after fixes 1 and 2"}[ov["afterBuild"]]

headline = [
    {"what": "Overview page, window in front", "from": pct(ov["before"]["cpu"]), "to": pct(ov["after"]["cpu"]), "unit": "of a core",
     "note": f"{ov['before']['cpu'] / ov['after']['cpu']:.0f}× less CPU; idle wakeups {ov['before']['wakeups']}/s → {ov['after']['wakeups']}/s ({after_label})"},
    {"what": "Menu bar only, window closed", "from": pct(mbo["before"]["cpu"]), "to": pct(mbo["after"]["cpu"]), "unit": "of a core",
     "note": f"the state the app sits in all day; {mbo['before']['cpu'] / mbo['after']['cpu']:.0f}× less CPU"},
    {"what": "Memory, Overview window open", "from": f"{ov['before']['footprint']:.0f} MB", "to": f"{ov['after']['footprint']:.0f} MB", "unit": "footprint",
     "note": "GPU buffers behind the charts and the menu bar image are gone"},
    {"what": "Memory, menu bar only", "from": f"{mba['before']['footprint']:.0f} MB", "to": f"{mba['after']['footprint']:.0f} MB", "unit": "footprint",
     "note": f"{(1 - mba['after']['footprint'] / mba['before']['footprint']) * 100:.0f} % less; medians of 3 interleaved pairs"},
]

summary_note = (
    "Measurements were taken with the window in front and the displays on, except where marked <i>display asleep</i>: "
    "about an hour into the session the screen locked and the displays slept, which stops display-driven animation and "
    "makes CPU numbers from that time incomparable to display-on runs. Comparisons below only pair runs taken in the same "
    "display state. Absolute CPU time also drifts between runs on this machine (the scheduler places the app's threads on "
    "efficiency or performance cores), so pairs that matter were repeated."
    + ("" if have_final_on else " <b>The final build's display-on numbers are pending</b>: the Overview and menu-bar-only "
       "\"after\" figures for display on are from the build with fixes 1 and 2, which still used SwiftUI's menu bar item.")
)

so = shots.get("shapes-overview")
co = shots.get("canvas-overview")
cmp_c = [summ(f"cmp-canvas-overview-{i}") for i in (1, 2)]
cmp_s = [summ(f"cmp-shapes-overview-{i}") for i in (1, 2)]
cmp_c = [x for x in cmp_c if x]
cmp_s = [x for x in cmp_s if x]
if so and co:
    SHAPES_RESULT = (f"Overview with the window open: {co['footprint']:.0f} MB → {so['footprint']:.0f} MB, GPU buffers "
                     f"{co['gpu']:.0f} MB → {so['gpu']:.0f} MB.")
    if cmp_c and cmp_s:
        SHAPES_RESULT += (f" CPU {statistics.median(x['cpu'] for x in cmp_c):.1f} % with Canvas, "
                          f"{statistics.median(x['cpu'] for x in cmp_s):.1f} % with shapes.")
else:
    SHAPES_RESULT = ("Built and tested; the window-visible measurement and screenshots of the shape-drawn charts were still "
                     "pending when this report was written, because the screen was locked.")

findings = [
    {
        "sev": "crit", "sevLabel": "Critical", "title": "The Overview rings re-laid out the whole window at display refresh rate",
        "evidence": "Overview used over half a core with nothing else happening. The main-thread timeline is flat (no 1 s rhythm), "
                    "the app had about 490 idle wakeups per second, and almost every sample sits under <code>NSHostingView.layout</code> → "
                    "<code>NavigationStackLayout</code> → <code>ScrollView</code> → stack layouts. Turning the rings off brought the page to 3.8 %; "
                    "the CPU ring alone cost 28 % of a core (see the ablation chart).",
        "cause": "Each ring had <code>.animation(.smooth(duration: 0.6), value: fraction)</code> on a trimmed <code>Circle</code>. "
                 "Every sample starts a 0.6 s animation, and SwiftUI drives it by re-running the view graph and the whole window's "
                 "layout on every display frame (up to 120 Hz on the built-in display). With values changing every second, the window "
                 "was animating most of the time.",
        "fix": "<code>RingGauge</code> (new, <code>Components/RingGauge.swift</code>): an <code>NSViewRepresentable</code> backed by two "
               "<code>CAShapeLayer</code>s. A new value adds a <code>CABasicAnimation</code> on <code>strokeEnd</code>, which the render "
               "server interpolates outside the app. The look (track, round cap, start at 12 o'clock, 0.6 s ease-out) is unchanged. "
               "The battery ring on Battery & Energy uses it too.",
        "result": f"Overview: {pct(ov['before']['cpu'])} → {pct(ov['after']['cpu'])} of a core; idle wakeups {ov['before']['wakeups']}/s → {ov['after']['wakeups']}/s.",
        "traces": [["on-base-overview-tp", "Before · Overview", "NSHostingView.layout"], ["final2-overview-tp", "After · Overview", "NSHostingView.layout"]],
    },
    {
        "sev": "crit", "sevLabel": "Critical", "title": "A closed or hidden window kept rendering",
        "evidence": "With the window closed and only the menu bar item showing, the app still used 55 % of a core, and the trace is "
                    "the same Overview layout as with the window open. The 9-day-old installed instance, its window off screen, held a "
                    "full Processes table in memory: 736 text fields and about 11,000 Auto Layout objects.",
        "cause": "SwiftUI keeps a <code>Window</code> scene's view graph alive after the window closes and keeps updating it whenever the "
                 "observed store changes. Nothing told the pages they were not visible.",
        "fix": "<code>onWindowVisibilityChange</code> (new, <code>Components/WindowVisibility.swift</code>) watches the window's occlusion "
               "state and close notification. While the main window is not on screen (closed, minimized, on another Space, fully "
               "covered) the detail area shows an empty view and the sidebar stops reading live values; the page is rebuilt when the "
               "window comes back. Pages that start <code>nettop</code> or per-process GPU sampling stop those too, through their "
               "<code>onDisappear</code>.",
        "result": f"Menu bar only, display on: {pct(mbo['before']['cpu'])} → {pct(mbo['after']['cpu'])} of a core.",
        "traces": [["base-menubar-only-tp", "Before · Menu bar only", "NSHostingView.layout"], ["fix1-menubar-tp", "After fixes 1-2 · Menu bar only", "NSHostingView.layout"]],
    },
    {
        "sev": "crit", "sevLabel": "Critical", "title": "The 18-point menu bar image held over 100 MB of GPU buffers",
        "evidence": "<code>footprint</code> in menu-bar-only mode: 113-129 MB of \"owned unmapped (graphics)\" memory in 4 MB purgeable "
                    "chunks; the 9-day instance had 117 MB of it. Swapping the menu bar renderer for a fixed symbol image dropped the "
                    "whole app from 204 MB to 68 MB.",
        "cause": "<code>MenuBarRenderer</code> built a new SwiftUI <code>ImageRenderer</code> for every new value and read its "
                 "<code>nsImage</code>. That path rasterizes on the GPU and keeps a pool of Metal buffers.",
        "fix": "One reused <code>ImageRenderer</code>, drawn with <code>render(rasterizationScale:renderer:)</code> into a plain CPU bitmap "
               "<code>CGContext</code>. The SwiftUI glyph view stays the single source of truth (the settings preview uses it). "
               "<code>check-menubar.sh</code> reports no issues and the sheets look the same; item widths with symbols changed by 1-4 pt.",
        "result": f"Menu bar only footprint: {mba['before']['footprint']:.0f} MB → {mba['after']['footprint']:.0f} MB (medians of 3 interleaved pairs). One render: 0.47 ms → 0.13 ms.",
        "traces": [["base-menubar-only-tp", "Before · Menu bar only", "ImageRenderer"]],
    },
    {
        "sev": "warn", "sevLabel": "High", "title": "SwiftUI's MenuBarExtra pushed the status item image again on every redraw",
        "evidence": f"After fixes 1 and 2 the menu bar item was the largest remaining cost: Overview at {pct(med(f1_on, 'cpu'))} with it, "
                    f"{pct(med(f1_nomb, 'cpu'))} without. About 16 ms per tick sat under <code>-[NSStatusItem _updateReplicants]</code>, "
                    "6 ms of it in <code>MenuBarExtraController.observeValue</code> → <code>updateButton</code> → <code>setImage:</code>.",
        "cause": "AppKit redraws the status item's copy on each display (two here) when its image changes, and sets the button's "
                 "appearance for each copy. <code>MenuBarExtra</code> observes that through KVO, re-evaluates the label and sets the "
                 "image again. The 9-day instance had collected 31,776 <code>NSKeyValueDependency</code> objects.",
        "fix": "<code>StatusItemController</code> (new): a plain <code>NSStatusItem</code> whose image is set only when the renderer returns "
               "a different image, fed by <code>withObservationTracking</code>. The popover is an <code>NSPopover</code> with the same "
               "<code>MenuBarView</code>, built when it opens and released when it closes. Show/hide, Open Monitor, Settings and Quit "
               "work as before; the popover now has the standard popover arrow.",
        "result": (f"Menu bar item's CPU cost with the window open: {mb_cost_before:.1f} → {mb_cost_after:.1f} points."
                   if mb_cost_after is not None else
                   "The KVO round trip is gone from the trace. What remains is AppKit redrawing the item on each display "
                   "when the image changes (about 13 ms per tick, <code>NSControl drawRect:</code> drawing the template image), "
                   "which any status item with a value that changes every second pays."),
        "traces": [["fix1-menubar-tp", "After fixes 1-2 · Menu bar only", "MenuBarExtraController"], ["after-menubar-asleep-tp", "Final · Menu bar only", "NSStatusItem"]],
    },
    {
        "sev": "warn", "sevLabel": "High", "title": "Every history chart drew into a Canvas backed by about 130 MB of GPU buffers",
        "evidence": "With the window open, the final build still had 114-130 MB of \"owned unmapped (graphics)\" memory, with or without "
                    "the menu bar item. The same build on the Overview, one minute apart: 209 MB with its charts drawn, 66 MB with "
                    "Canvas drawing switched off by a test flag (GPU buffers 130 MB → 0). Pages with only the sidebar's small "
                    "sparklines (System) had none.",
        "cause": "<code>HistoryChart</code> drew with a SwiftUI <code>Canvas</code>. A Canvas of chart size rasterizes through an "
                 "in-process Metal buffer pool, which stays allocated while the window is open.",
        "fix": "<code>HistoryChart</code> and <code>Sparkline</code> draw the same marks with SwiftUI shapes (<code>Path</code> fills and "
               "strokes, <code>Text</code> labels), which Core Animation renders in the window server. Hover, tooltip, bar, line and "
               "area styles, stacking and mirrored series are unchanged.",
        "result": SHAPES_RESULT,
    },
    {
        "sev": "info", "sevLabel": "Medium", "title": "The process sampler is bound by kernel calls",
        "evidence": "<code>sysbench</code>: the process list takes 10-11 ms of a 12 ms tick, and its trace has 388 of 827 ms in "
                    "<code>__proc_info</code> and 113 ms in <code>__sysctl</code>, for about 1,000 processes with two calls each.",
        "cause": "Per process, <code>proc_pid_rusage</code> (CPU, memory, disk, energy) and <code>PROC_PIDTASKINFO</code> (threads, running "
                 "state). The process table buffer (about 700 KB) was also allocated, zeroed and sized with an extra call every tick.",
        "fix": "Task info is skipped for a process whose CPU time did not change since the last tick (it cannot have started threads or "
               "been running), and refreshed at least every 10 ticks. The <code>kinfo_proc</code> buffer is kept between ticks. A new "
               "test checks that idle processes keep their thread counts.",
        "result": "A small saving within run-to-run noise. The rest is kernel time that top and Activity Monitor pay too; it runs on a "
                  "low-priority thread, often on efficiency cores.",
        "traces": [["sysbench", "Sampler alone", "__proc_info"]],
    },
    {
        "sev": "info", "sevLabel": "Low", "title": "Per-process history copied every point every tick",
        "evidence": "<code>SystemStore.apply</code> rebuilt two dictionaries of about 1,000 60-point histories per tick.",
        "cause": "Reading a <code>History</code> out of the old dictionary and appending to it copied its array (copy on write): about "
                 "2,000 allocations and 3 MB copied per second, for a chart only the process inspector shows.",
        "fix": "The dictionaries are moved out of the store, appended to in place, pruned of exited processes when needed, and put back.",
        "result": "Same data without the per-tick copies.",
    },
]

sampler_html = (
    "<p>All sampling runs on one background task: about 12 ms of CPU per tick, 1 % of a core at the default 1 s refresh. Sensors "
    "and battery refresh only every few ticks. The process list is nearly all of it, and nearly all of that is kernel time answering "
    "<code>proc_pid_rusage</code>, <code>proc_pidinfo</code> and <code>sysctl(KERN_PROC_ALL)</code>. In a standalone benchmark the "
    "two per-process calls take 1.7 ms and 0.9 ms per 1,000 processes on a performance core; the sampler's thread often runs on "
    "efficiency cores, where the same calls take two to three times as long but cost less energy. Benchmark output, 40 ticks at "
    "250 ms (the machine was busier during the second run, so compare the shares rather than absolute times):</p>"
)

method_html = """
<ul class="plain">
  <li><b>Builds.</b> Release builds of the Xcode project with the desktop widgets, ad-hoc signed. "Before" is <code>main</code> at
  <code>9b7dce2</code>; "after fixes 1-2" adds the ring and window-visibility fixes; "final" is the full set of changes.</li>
  <li><b>CPU.</b> Cumulative CPU time from <code>ps</code> at the start and end of a 30 s window (20 s for interleaved pairs), after
  12 s of warm-up, as a percentage of one core. Idle wakeups per second from <code>top -stats idlew</code>.</li>
  <li><b>Display state.</b> CPU numbers only compare within one display state. With the displays asleep the window server stops
  driving animations, so the "before" build's main problem disappears.</li>
  <li><b>Memory.</b> Physical footprint from <code>footprint</code> (what Activity Monitor's Memory column shows), with
  <code>vmmap --summary</code>, <code>heap -s</code> and <code>leaks</code> for the breakdowns.</li>
  <li><b>Traces.</b> <code>xctrace record --template 'Time Profiler' --attach PID --time-limit 15s</code> (20 s for some), exported
  with <code>xctrace export</code> and folded into the call trees on this page. The raw <code>.trace</code> bundles are not
  published because they contain the recording shell's environment variables.</li>
  <li><b>Caveats.</b> One machine, two displays, normal background load, and the installed 0.4.0 build kept running alongside
  (measured separately, never counted). <code>nettop</code> runs started by the Network page are separate processes and not
  counted. Opening Settings from the popover needs a real click (macOS refuses to activate an app without one), so that path was
  only checked to create the window. <code>SamplerPerformanceTests.testPerTickCostStaysLow</code> fails on this machine before
  and after these changes (the process list takes 13-15 ms with about 1,050 processes against a 12 ms budget).</li>
</ul>
<pre>scripts/ in this folder
  measure.sh      launch a fresh instance on a screen, measure CPU, footprint and wakeups, optionally record a trace
  suite.sh        every screen, menu-bar-only and 100 ms refresh, for one build
  repeat.sh       interleaved before/after pairs
  growth.sh       footprint and CPU every 15 s for a long run
  tp2json.py      xctrace time-profile XML to call tree, self/inclusive tables and timeline
  hotpath.py      print the heaviest paths of a converted trace
  report_data.py  build data.json and traces/ for this page</pre>
"""

data = {
    "headline": headline, "summaryNote": summary_note, "findings": findings, "comparisons": comparisons,
    "ablation": ablation, "runs": runs, "traces": traces, "growth": growth,
    "menubarMemory": {"categories": ["GPU buffers", "Malloc heap", "CG images", "Everything else"],
                      "before": cats("rep-base-menubar-1"), "after": cats("rep-after-menubar-1")},
    "sysbench": {"before": open("/tmp/bamprof/sysbench-baseline.txt").read(), "after": open("/tmp/bamprof/sysbench-after.txt").read()},
    "heapDiff": json.load(open("/tmp/bamprof/heapdiff.json")),
    "shots": {k: ({kk: vv for kk, vv in v.items() if kk != "png"} if v else None) for k, v in shots.items()},
    "samplerHtml": sampler_html, "methodHtml": method_html, "finalOn": have_final_on,
}
json.dump(data, open(os.path.join(out, "data.json"), "w"), separators=(",", ":"))
with open(os.path.join(out, "data.js"), "w") as f:
    f.write("window.REPORT_DATA = ")
    json.dump(data, f, separators=(",", ":"))
    f.write(";\n")
print("runs", len(runs), "comparisons", [(x["name"], x["before"]["cpu"], x["after"]["cpu"], x["afterBuild"]) for x in comparisons])
print("traces", [t["id"] for t in traces], "finalOn", have_final_on)
print("menubar memory", data["menubarMemory"])
