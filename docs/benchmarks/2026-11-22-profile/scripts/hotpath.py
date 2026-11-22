import json, sys
d = json.load(open(sys.argv[1])); thr = sys.argv[2] if len(sys.argv) > 2 else "Main Thread"
minfrac = float(sys.argv[3]) if len(sys.argv) > 3 else 0.04
root = next(c for c in d["flame"]["c"] if c["n"] == thr)
T = root["v"]
def walk(n, depth, budget=400):
    kids = n.get("c", [])
    big = [k for k in kids if k["v"] >= T * minfrac]
    for k in big:
        name = k["n"]
        if len(big) > 1 or depth % 1 == 0:
            pass
        print(f"{'  '*min(depth,60)}{k['v']:7.0f} {k['v']/T*100:5.1f}%  {name[:130]}")
        walk(k, depth + (1 if len(big) > 1 else 0) if False else depth + 1)
walk(root, 0)
