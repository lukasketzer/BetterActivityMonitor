#!/usr/bin/env python3
"""Converts an `xctrace export` time-profile table into a compact JSON profile:
call tree per thread (for flame graphs), top self/inclusive frames, and a per-100 ms timeline.
usage: tp2json.py tp.xml out.json [label]"""
import json
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

src, dst = sys.argv[1], sys.argv[2]
label = sys.argv[3] if len(sys.argv) > 3 else src

ids = {}  # id -> element-derived value

def resolve(el):
    ref = el.get("ref")
    if ref is not None:
        return ids[ref]
    return None

def frame_name(el):
    r = resolve(el)
    if r is not None:
        return r
    name = el.get("name") or el.get("addr") or "?"
    b = el.find("binary")
    binary = None
    if b is not None:
        binary = resolve(b) if b.get("ref") else b.get("name")
        if b.get("id"):
            ids[b.get("id")] = b.get("name")
    val = (name, binary or "?")
    ids[el.get("id")] = val
    return val

def backtrace(el):
    r = resolve(el)
    if r is not None:
        return r
    frames = tuple(frame_name(f) for f in el.findall("frame"))
    ids[el.get("id")] = frames
    return frames

def simple(el):
    r = resolve(el)
    if r is not None:
        return r
    val = el.get("fmt") or el.text
    if el.get("id"):
        ids[el.get("id")] = val
    # register nested ids (thread contains tid/process)
    for child in el.iter():
        if child is not el and child.get("id"):
            ids[child.get("id")] = child.get("fmt") or child.text
    return val

def thread_label(fmt):
    # "Main Thread (0xd9e26c) (BetterActivityMonitor, pid: 51465)" -> "Main Thread"; others keep the name
    base = fmt.split(" (0x")[0]
    return base

tree = {}  # thread -> nested dict {name: [weight, children]}
selfw = defaultdict(float)
inclw = defaultdict(float)
thread_tot = defaultdict(float)
timeline = defaultdict(lambda: defaultdict(float))
total = 0.0
start_ns = None
binaries_self = defaultdict(float)

for _, el in ET.iterparse(src, events=("end",)):
    if el.tag != "row":
        continue
    t = el.find("sample-time")
    if t.get("ref") is None:
        tns = int(t.text)
        ids[t.get("id") + "_raw"] = tns
    else:
        tns = ids.get(t.get("ref") + "_raw", 0)
    thr = thread_label(simple(el.find("thread")))
    state = el.find("thread-state")
    w_el = el.find("weight")
    wfmt = simple(w_el)
    # weight fmt like "1.00 ms"
    try:
        w = float(wfmt.split()[0]) * (1000 if "s" == wfmt.split()[1] else 1 if wfmt.split()[1] == "ms" else 0.001)
    except Exception:
        w = 1.0
    bt_el = el.find("tagged-backtrace")
    if bt_el is None:
        bt_el = el.find("backtrace")
    frames = backtrace(bt_el) if bt_el is not None else ()
    el.clear()
    total += w
    thread_tot[thr] += w
    if start_ns is None:
        start_ns = tns
    bucket = int((tns - start_ns) / 1e8) if tns else 0
    timeline[thr][bucket] += w
    stack = list(reversed(frames))  # root first
    if not stack:
        stack = [("<no backtrace>", "?")]
    node = tree.setdefault(thr, [0.0, {}])
    node[0] += w
    seen = set()
    for f in stack:
        key = f"{f[0]}  [{f[1]}]"
        if key not in seen:
            inclw[key] += w
            seen.add(key)
        child = node[1].setdefault(key, [0.0, {}])
        child[0] += w
        node = child
    leaf = stack[-1]
    selfw[f"{leaf[0]}  [{leaf[1]}]"] += w
    binaries_self[leaf[1]] += w

# sample-time ref fix: ids for sample-time store fmt; we stored raw text only via simple(); good enough.

def to_json(name, node, depth=0, min_w=0.0):
    w, kids = node
    out = {"n": name, "v": round(w, 2)}
    ch = [to_json(k, v, depth + 1, min_w) for k, v in sorted(kids.items(), key=lambda kv: -kv[1][0]) if v[0] >= min_w]
    if ch:
        out["c"] = ch
    return out

min_w = max(total * 0.0005, 1.0)
threads = sorted(thread_tot.items(), key=lambda kv: -kv[1])
result = {
    "label": label,
    "total_ms": round(total, 1),
    "duration_s": round(max((max(b.keys()) for b in timeline.values()), default=0) / 10 + 0.1, 1),
    "threads": [{"name": n, "ms": round(v, 1)} for n, v in threads],
    "self": [{"f": k, "ms": round(v, 1)} for k, v in sorted(selfw.items(), key=lambda kv: -kv[1])[:60]],
    "inclusive": [{"f": k, "ms": round(v, 1)} for k, v in sorted(inclw.items(), key=lambda kv: -kv[1])[:120]],
    "binaries": [{"b": k, "ms": round(v, 1)} for k, v in sorted(binaries_self.items(), key=lambda kv: -kv[1])[:25]],
    "timeline": {n: [round(timeline[n].get(i, 0), 1) for i in range(0, max(timeline[n].keys()) + 1)] for n, _ in threads[:6]},
    "flame": to_json("all threads", [total, {n: tree[n] for n, _ in threads}], min_w=min_w),
}
json.dump(result, open(dst, "w"), separators=(",", ":"))
print(f"{label}: {total:.0f} ms of samples over ~{result['duration_s']} s")
for n, v in threads[:8]:
    print(f"  thread {n:40s} {v:8.1f} ms")
print("  top self:")
for e in result["self"][:25]:
    print(f"    {e['ms']:8.1f}  {e['f'][:150]}")
