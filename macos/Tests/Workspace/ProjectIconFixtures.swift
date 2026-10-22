import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Temp-directory fixtures for the project icon engine tests. Everything is
/// built from scratch under a unique temp dir; no real project folder is read.
enum ProjectIconFixtures {
    static func makeRoot(_ label: String = "root") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-icon-tests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Real path (/private/var, not /var) so path comparisons are stable.
        let resolved = realpath(url.path, nil)!
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    /// A solid-colour PNG, `pixels` square.
    static func pngData(pixels: Int = 64) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let image = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// Writes a PNG at `relative` under `root`, creating parent dirs.
    @discardableResult
    static func writePNG(_ root: URL, _ relative: String, pixels: Int = 64) throws -> URL {
        try write(root, relative, data: pngData(pixels: pixels))
    }

    @discardableResult
    static func write(_ root: URL, _ relative: String, data: Data) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }

    /// An `AppIcon.appiconset` with the given (filename, "NxN", "2x") entries.
    static func writeAppIconSet(
        _ root: URL, under relative: String, entries: [(file: String, size: String, scale: String, pixels: Int)]
    ) throws {
        var images: [[String: String]] = []
        for e in entries {
            try writePNG(root, "\(relative)/\(e.file)", pixels: e.pixels)
            images.append(["filename": e.file, "size": e.size, "scale": e.scale, "idiom": "universal"])
        }
        let json = try JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1]])
        try write(root, "\(relative)/Contents.json", data: json)
    }
}
