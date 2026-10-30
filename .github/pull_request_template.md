## What and why

<!-- What changes, and the problem it solves. -->

## Checks

- [ ] `swift test -c release --skip AppPerformanceTests` passes
- [ ] UI changes: `scripts/check-layout.sh` reports no layout issues
- [ ] Sampler or UI hot-path changes: `swift run -c release sysbench` / `scripts/measure-screens.sh` show no regression
- [ ] Screenshots attached for visible changes
