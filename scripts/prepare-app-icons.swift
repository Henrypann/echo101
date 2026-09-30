// Build-format conversion only: original artwork is already fully opaque.
// Reject genuinely transparent input instead of silently changing the design.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else { fatalError("Pass AppIcon.appiconset directory") }
for name in ["default", "dark", "mono"] {
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("\(name).png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let rgba = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                               bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Invalid icon") }
    rgba.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = rgba.data!.assumingMemoryBound(to: UInt8.self)
    for i in stride(from: 3, to: image.width * image.height * 4, by: 4) {
        guard pixels[i] == 255 else { fatalError("Artwork has transparency; review source instead of flattening") }
    }
    guard let rgb = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                             bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot encode icon") }
    rgb.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    CGImageDestinationAddImage(destination, rgb.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save icon") }
}
print("Prepared 3 opaque icons without changing artwork composition.")
