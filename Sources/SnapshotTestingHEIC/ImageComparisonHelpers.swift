#if os(iOS) || os(tvOS) || os(macOS)
import Foundation
import CoreGraphics

// MARK: - Image Context Constants

/// Color space for consistent image comparison across platforms
let imageContextColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

/// Bits per component for RGBA images
let imageContextBitsPerComponent = 8

/// Bytes per pixel for RGBA images (4 channels: R, G, B, A)
let imageContextBytesPerPixel = 4

/// Block size for optimized comparison (64KB chunks for better cache locality)
private let comparisonBlockSize = 65536

// MARK: - Pixel Comparison

/// Compares two byte arrays using optimized block comparison with early exit.
///
/// This implementation uses memcmp for block-level comparison which is highly optimized
/// by the system (often using SIMD instructions). When differences are found within a block,
/// it counts individual differing bytes only in that block.
///
/// - Parameters:
///   - oldBytes: Reference image bytes
///   - newBytes: New image bytes
///   - byteCount: Total number of bytes to compare
///   - precision: Required precision (0-1), where 1 means 100% match required
/// - Returns: Tuple containing (passed: Bool, actualPrecision: Float)
func comparePixelBytes(
    _ oldBytes: UnsafePointer<UInt8>,
    _ newBytes: UnsafePointer<UInt8>,
    byteCount: Int,
    precision: Float
) -> (passed: Bool, actualPrecision: Float) {
    let tolerance = max(Float.ulpOfOne, 1.0 / Float(byteCount))

    // Fast path: exact match required - use single memcmp
    if precision >= 1.0 {
        let isEqual = memcmp(oldBytes, newBytes, byteCount) == 0
        return (isEqual, isEqual ? 1.0 : 0.0)
    }

    let maxPassingDifferentByteCount = Int(floor(Float(byteCount) * (1 - precision + tolerance)))
    var differentByteCount = 0
    var offset = 0

    // Process in blocks for better cache performance
    while offset < byteCount {
        let remainingBytes = byteCount - offset
        let blockSize = min(comparisonBlockSize, remainingBytes)

        // Fast path: check if entire block is identical using memcmp (SIMD optimized)
        if memcmp(oldBytes + offset, newBytes + offset, blockSize) == 0 {
            offset += blockSize
            continue
        }

        // Block has differences - count them individually
        let blockEnd = offset + blockSize
        var index = offset
        while index < blockEnd {
            if oldBytes[index] != newBytes[index] {
                differentByteCount += 1

                // Early exit if failure is guaranteed even with tolerance
                if differentByteCount > maxPassingDifferentByteCount {
                    let actualPrecision = 1 - Float(differentByteCount) / Float(byteCount)
                    return (false, actualPrecision)
                }
            }
            index += 1
        }
        offset += blockSize
    }

    let actualPrecision = 1 - Float(differentByteCount) / Float(byteCount)
    let passed = actualPrecision + tolerance >= precision
    return (passed, actualPrecision)
}

// MARK: - CGContext Creation

/// Creates a CGContext for the given CGImage using consistent sRGB color space.
///
/// - Parameters:
///   - cgImage: The source CGImage to create context for
///   - data: Optional buffer to store pixel data. If nil, context allocates its own buffer.
/// - Returns: A CGContext configured for the image, or nil if creation fails
func createImageContext(for cgImage: CGImage, data: UnsafeMutableRawPointer? = nil) -> CGContext? {
    let bytesPerRow = cgImage.width * imageContextBytesPerPixel
    guard
        let colorSpace = imageContextColorSpace,
        let context = CGContext(
            data: data,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: imageContextBitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    return context
}
#endif
