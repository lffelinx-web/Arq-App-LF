import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reading and writing `ImagenRGBA` as JPEG files.
enum ImagenesIO {
    /// Pixel size of an image file without decoding it.
    static func tamano(_ url: URL) -> SIMD2<Int>? {
        guard let origen = CGImageSourceCreateWithURL(url as CFURL, nil),
              let propiedades = CGImageSourceCopyPropertiesAtIndex(origen, 0, nil) as? [CFString: Any],
              let ancho = propiedades[kCGImagePropertyPixelWidth] as? Int,
              let alto = propiedades[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return SIMD2(ancho, alto)
    }

    static func leer(_ url: URL) -> ImagenRGBA? {
        guard let origen = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(origen, 0, nil) else { return nil }
        var imagen = ImagenRGBA(ancho: cg.width, alto: cg.height)
        let dibujado = imagen.pixeles.withUnsafeMutableBytes { buffer -> Bool in
            guard let contexto = CGContext(
                data: buffer.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            contexto.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        return dibujado ? imagen : nil
    }

    @discardableResult
    static func escribirJPEG(_ imagen: ImagenRGBA, en url: URL, calidad: Double = 0.88) -> Bool {
        var pixeles = imagen.pixeles
        let cg: CGImage? = pixeles.withUnsafeMutableBytes { buffer in
            guard let contexto = CGContext(
                data: buffer.baseAddress, width: imagen.ancho, height: imagen.alto, bitsPerComponent: 8, bytesPerRow: imagen.ancho * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            return contexto.makeImage()
        }
        guard let cg, let destino = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destino, cg, [kCGImageDestinationLossyCompressionQuality: calidad] as CFDictionary)
        return CGImageDestinationFinalize(destino)
    }
}
