Profiling scripts used for this report. They work in `/tmp/bamprof` (runs/, apps/<build>.app, scripts/ with the
compiled `visible` and `procbench` helpers), and expect the app copies to compare in `/tmp/bamprof/apps`.

- `measure.sh <label> <app> <seconds> [open args]`: fresh launch, 12 s warm-up, CPU % over the window, footprint,
  idle wakeups, whether the window was on screen; `TRACE=<s>` also records a Time Profiler trace and converts it.
- `suite.sh`, `repeat.sh`, `repeat-menubar.sh`: scenario sets; `when-awake*.sh` wait for an unlocked screen first.
- `growth.sh`: footprint and CPU every 15 s over a long run.
- `tp2json.py` and `hotpath.py`: turn `xctrace export` XML into call trees and print hot paths.
- `report_data.py <out-dir>`: builds `data.json` and `traces/` for `index.html`.

Raw `.trace` bundles are not kept here: they record the shell's environment variables.
