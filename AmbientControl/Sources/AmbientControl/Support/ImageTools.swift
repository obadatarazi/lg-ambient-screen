import AppKit
import CoreImage
import QuickLookThumbnailing

enum ImageTools {
    private static let context = CIContext()

    /// Makes a TV-sized wallpaper (cover-cropped to 1920x1080) and a small blurred
    /// "glass" copy for the widgets, matching how the built-in wallpapers are prepared.
    static func makeWallpaper(from source: URL, wallOut: URL, glassOut: URL) throws {
        guard let input = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let wall = cover(input, width: 1920, height: 1080)
        let small = cover(input, width: 384, height: 216)
        let glass = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 9)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.25,
                kCIInputBrightnessKey: -0.05
            ])
            .cropped(to: small.extent)

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        try context.writeJPEGRepresentation(of: wall, to: wallOut, colorSpace: space,
                                            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.86])
        try context.writeJPEGRepresentation(of: glass, to: glassOut, colorSpace: space,
                                            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85])
    }

    private static func cover(_ image: CIImage, width: CGFloat, height: CGFloat) -> CIImage {
        let e = image.extent
        let scale = max(width / e.width, height / e.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let s = scaled.extent
        let crop = CGRect(x: s.midX - width / 2, y: s.midY - height / 2, width: width, height: height)
        return scaled.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    }

    /// Thumbnail for images and videos via QuickLook.
    static func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req).nsImage
    }
}
