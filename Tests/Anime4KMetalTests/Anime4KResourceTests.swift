import CoreVideo
import Metal
import XCTest
@testable import Anime4KMetal
@testable import Anime4KMetalCore

final class Anime4KResourceTests: XCTestCase {
    func testShaderCatalogLoadsModeAFastStages() throws {
        let program = try Anime4KShaderCatalog.program(for: .modeAFast)
        XCTAssertEqual(program.name, "Anime4K Mode A (Fast)")
        XCTAssertEqual(program.stages.map(\.name), [
            "Restore/Anime4K_Clamp_Highlights.glsl",
            "Restore/Anime4K_Restore_CNN_M.glsl",
            "Upscale/Anime4K_Upscale_CNN_x2_M.glsl",
            "Upscale/Anime4K_AutoDownscalePre_x2.glsl",
            "Upscale/Anime4K_AutoDownscalePre_x4.glsl",
            "Upscale/Anime4K_Upscale_CNN_x2_S.glsl",
        ])
        XCTAssertTrue(program.stages.allSatisfy { $0.glsl.contains("//!") })
    }

    func testEveryPresetLoadsAtLeastOneStage() throws {
        for preset in Anime4KPreset.allCases {
            let program = try Anime4KShaderCatalog.program(for: preset)
            XCTAssertFalse(program.stages.isEmpty, "Missing stages for \(preset.rawValue)")
            XCTAssertEqual(program.stages.count, program.stageFiles.count)
        }
    }

    func testMetalLibraryContainsConverterKernels() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal unavailable")
        }
        let library = try Anime4KMetalLibrary.makeDefaultLibrary(device: device)
        let requiredFunctions = [
            "YUV420BiPlanarToRGBA",
            "YUV420PlanarToRGBA",
            "YUV420P010BiPlanarToRGBA",
            "BGRA8ToRGBA",
            "ABCompareSplit",
            "DirectTransfer",
            "CenterResize",
        ]
        for name in requiredFunctions {
            XCTAssertNotNil(library.makeFunction(name: name), "Missing Metal function \(name)")
        }
    }

    func testOutputTexturePoolReusesTexturesAndCanBePurged() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal unavailable")
        }
        let engine = try Anime4KHostEngine(preferredDevice: device)
        let input = try makeBGRApixelBuffer(width: 32, height: 24)

        XCTAssertNotNil(engine.enhance(
            pixelBuffer: input,
            timestamp: 0,
            generation: 0,
            preset: .modeAFast,
            maxOutputWidth: 64,
            maxOutputHeight: 48
        ))
        let firstSnapshot = engine.debugSnapshot()
        XCTAssertGreaterThan(firstSnapshot.cachedOutputTextureCount, 0)
        XCTAssertGreaterThan(firstSnapshot.outputTextureAllocationCount, 0)

        XCTAssertNotNil(engine.enhance(
            pixelBuffer: input,
            timestamp: 1,
            generation: 0,
            preset: .modeAFast,
            maxOutputWidth: 64,
            maxOutputHeight: 48
        ))
        let secondSnapshot = engine.debugSnapshot()
        XCTAssertEqual(
            secondSnapshot.outputTextureAllocationCount,
            firstSnapshot.outputTextureAllocationCount,
            "same-size frames should reuse cached stage output textures"
        )

        engine.purgeOutputTextureCache()
        XCTAssertEqual(engine.debugSnapshot().cachedOutputTextureCount, 0)
    }

    func testPurgeResourcesAllowsSubsequentEnhancement() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal unavailable")
        }
        let engine = try Anime4KHostEngine(preferredDevice: device)
        let input = try makeBGRApixelBuffer(width: 32, height: 24)

        XCTAssertNotNil(engine.enhance(
            pixelBuffer: input,
            timestamp: 0,
            generation: 0,
            preset: .modeAFast,
            maxOutputWidth: 64,
            maxOutputHeight: 48
        ))
        engine.purgeResources()
        XCTAssertEqual(engine.debugSnapshot().cachedOutputTextureCount, 0)

        XCTAssertNotNil(engine.enhance(
            pixelBuffer: input,
            timestamp: 1,
            generation: 1,
            preset: .modeAFast,
            maxOutputWidth: 64,
            maxOutputHeight: 48
        ))
    }

    private func makeBGRApixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw Anime4KError.processingFailed("CVPixelBufferCreate failed: \(status)")
        }
        return buffer
    }
}
