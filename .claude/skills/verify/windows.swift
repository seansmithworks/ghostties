// Lists on-screen windows owned by a pid: "<windowid> <width> <height>", largest first.
// Usage: swift windows.swift <pid>
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments.dropFirst().first ?? "") ?? -1
let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
var rows: [(Int, Int, Int)] = []
for w in info {
    guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
          let b = w[kCGWindowBounds as String] as? [String: Any],
          let id = w[kCGWindowNumber as String] as? Int,
          let wd = b["Width"] as? Double, let ht = b["Height"] as? Double else { continue }
    rows.append((id, Int(wd), Int(ht)))
}
for r in rows.sorted(by: { $0.1 * $0.2 > $1.1 * $1.2 }) { print("\(r.0) \(r.1) \(r.2)") }
