import AppKit
import Foundation

let input = URL(fileURLWithPath: "ForgeIPA/Assets.xcassets/AppIcon.appiconset/icon.svg")
let output = URL(fileURLWithPath: "ForgeIPA/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
guard let image = NSImage(contentsOf: input) else {
    fatalError("Cannot load Forge IPA SVG icon")
}
var rect = CGRect(origin: .zero, size: NSSize(width: 1024, height: 1024))
guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
    fatalError("Cannot rasterize Forge IPA SVG icon")
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode Forge IPA icon as PNG")
}
try png.write(to: output, options: .atomic)
print("Generated AppIcon.png")
