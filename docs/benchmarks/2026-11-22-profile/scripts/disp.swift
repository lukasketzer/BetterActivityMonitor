import CoreGraphics
var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
CGGetOnlineDisplayList(8, &ids, &n)
for i in 0..<Int(n) { print(ids[i], "asleep:", CGDisplayIsAsleep(ids[i]) != 0, "active:", CGDisplayIsActive(ids[i]) != 0) }
