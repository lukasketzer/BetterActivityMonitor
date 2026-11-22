import Darwin
import Foundation
var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
var size = 0; sysctl(&mib, 4, nil, &size, nil, 0); size += size/8
var buf = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
sysctl(&mib, 4, &buf, &size, nil, 0)
let pids = buf.prefix(size / MemoryLayout<kinfo_proc>.stride).map { $0.kp_proc.p_pid }
func t(_ name: String, _ body: () -> Int) { let s = DispatchTime.now().uptimeNanoseconds; var ok = 0; for _ in 0..<10 { ok = body() }; print(name, String(format: "%.2f ms/pass", Double(DispatchTime.now().uptimeNanoseconds - s)/1e7), "ok=\(ok)/\(pids.count)") }
t("rusage v6") { var n = 0; for p in pids { var u = rusage_info_v6(); let r = withUnsafeMutablePointer(to: &u) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(p, RUSAGE_INFO_V6, $0) } }; if r == 0 { n += 1 } }; return n }
t("taskinfo ") { var n = 0; for p in pids { var ti = proc_taskinfo(); if proc_pidinfo(p, PROC_PIDTASKINFO, 0, &ti, Int32(MemoryLayout<proc_taskinfo>.size)) > 0 { n += 1 } }; return n }
t("bsdshortinfo") { var n = 0; for p in pids { var bi = proc_bsdshortinfo(); if proc_pidinfo(p, PROC_PIDT_SHORTBSDINFO, 0, &bi, Int32(MemoryLayout<proc_bsdshortinfo>.size)) > 0 { n += 1 } }; return n }
t("sysctl all") { var s = size; return sysctl(&mib, 4, &buf, &s, nil, 0) == 0 ? 1 : 0 }
