import Foundation

struct WavEncoder {
    static func encodePCM(
        _ pcmData: Data,
        sampleRate: UInt32 = 16000,
        channels: UInt16 = 1,
        bitsPerSample: UInt16 = 16
    ) -> Data {
        var header = Data()

        header.append("RIFF".data(using: .ascii)!)
        let fileSize = 36 + pcmData.count
        header.append(UInt32(fileSize).littleEndian.data)
        header.append("WAVE".data(using: .ascii)!)

        header.append("fmt ".data(using: .ascii)!)
        header.append(UInt32(16).littleEndian.data)
        header.append(UInt16(1).littleEndian.data)
        header.append(UInt16(channels).littleEndian.data)
        header.append(UInt32(sampleRate).littleEndian.data)

        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        header.append(UInt32(byteRate).littleEndian.data)
        let blockAlign = UInt16(channels * (bitsPerSample / 8))
        header.append(UInt16(blockAlign).littleEndian.data)
        header.append(UInt16(bitsPerSample).littleEndian.data)

        header.append("data".data(using: .ascii)!)
        header.append(UInt32(pcmData.count).littleEndian.data)

        var wavData = Data()
        wavData.append(header)
        wavData.append(pcmData)
        return wavData
    }
}
