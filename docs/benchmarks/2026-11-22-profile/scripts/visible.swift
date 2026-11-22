import CoreGraphics
import Foundation
// prints the window id of the pid's largest on-screen window, or nothing
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
  .compactMap { w -> (Int, Double)? in
    guard let b = w[kCGWindowBounds as String] as? [String: Double], let id = w[kCGWindowNumber as String] as? Int else { return nil }
    return (id, (b["Width"] ?? 0) * (b["Height"] ?? 0)) }
  .filter { $0.1 > 400_000 }
if let w = mine.max(by: { $0.1 < $1.1 }) { print(w.0) }
