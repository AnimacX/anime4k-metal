import Anime4KMetal
import CoreVideo
import CryptoKit
import XCTest

final class ResourceReuseTests: XCTestCase {
    func testOutputsRemainStableAcrossReuseAndReset() throws {
        let first = try input(seed: 17), second = try input(seed: 31)
        let firstInputHash = hash(first)
        for preset in Anime4KPreset.allCases {
            let engine = try Anime4KInterpolator(configuration: .init(preset: preset, maxOutputWidth: 128, maxOutputHeight: 96))
            let held = try engine.enhance(pixelBuffer: first)
            XCTAssertEqual(CVPixelBufferGetWidth(held), 128)
            let expected = hash(held)
            let changed = try engine.enhance(pixelBuffer: second)
            XCTAssertNotEqual(expected, hash(changed))
            XCTAssertEqual(expected, hash(held), "后续处理不能覆盖已交付的输出")
            XCTAssertEqual(expected, hash(try engine.enhance(pixelBuffer: first)))
            engine.reset()
            XCTAssertEqual(expected, hash(try engine.enhance(pixelBuffer: first)))
            XCTAssertEqual(firstInputHash, hash(first))
        }
    }

    private func input(seed: Int) throws -> CVPixelBuffer {
        var value: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        XCTAssertEqual(CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &value), kCVReturnSuccess)
        let buffer = try XCTUnwrap(value)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        for y in 0..<48 {
            let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self)
            for x in 0..<256 { row[x] = UInt8((x * seed + y * 13) % 256) }
        }
        return buffer
    }

    private func hash(_ buffer: CVPixelBuffer) -> String {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        var digest = SHA256()
        let base = CVPixelBufferGetBaseAddress(buffer)!
        for y in 0..<CVPixelBufferGetHeight(buffer) {
            digest.update(data: Data(bytes: base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)), count: CVPixelBufferGetWidth(buffer) * 4))
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
