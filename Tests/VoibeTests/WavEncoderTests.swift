#if canImport(XCTest)
import XCTest
@testable import Voibe

final class WavEncoderTests: XCTestCase {
    func testEncodesValidWavHeader() {
        let samples: [Int16] = [0, 1, -1, 32767, -32768]
        let pcmData = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)

        let wavData = WavEncoder.encodePCM(pcmData)

        XCTAssertEqual(String(data: wavData[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(readUInt32LE(wavData, 4), UInt32(36 + pcmData.count))
        XCTAssertEqual(String(data: wavData[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wavData[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(readUInt32LE(wavData, 16), 16)
        XCTAssertEqual(readUInt16LE(wavData, 20), 1)
        XCTAssertEqual(readUInt16LE(wavData, 22), 1)
        XCTAssertEqual(readUInt32LE(wavData, 24), 16000)
        XCTAssertEqual(readUInt32LE(wavData, 28), 16000 * 2)
        XCTAssertEqual(readUInt16LE(wavData, 32), 2)
        XCTAssertEqual(readUInt16LE(wavData, 34), 16)
        XCTAssertEqual(String(data: wavData[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(readUInt32LE(wavData, 40), UInt32(pcmData.count))
        XCTAssertEqual(wavData.count, 44 + pcmData.count)
    }

    func testEncodesCustomFormatFields() {
        let samples: [Int16] = [1, 2, 3, 4]
        let pcmData = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)

        let wavData = WavEncoder.encodePCM(pcmData, sampleRate: 44100, channels: 2, bitsPerSample: 16)

        XCTAssertEqual(readUInt16LE(wavData, 22), 2)
        XCTAssertEqual(readUInt32LE(wavData, 24), 44100)
        XCTAssertEqual(readUInt32LE(wavData, 28), 44100 * 2 * 2)
        XCTAssertEqual(readUInt16LE(wavData, 32), 4)
        XCTAssertEqual(readUInt16LE(wavData, 34), 16)
    }
}

private func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
    let bytes = data[offset..<(offset + 2)]
    return bytes.enumerated().reduce(UInt16(0)) { result, item in
        result | (UInt16(item.element) << (8 * item.offset))
    }
}

private func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
    let bytes = data[offset..<(offset + 4)]
    return bytes.enumerated().reduce(UInt32(0)) { result, item in
        result | (UInt32(item.element) << (8 * item.offset))
    }
}
#endif
