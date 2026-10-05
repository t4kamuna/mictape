import AVFoundation
import Foundation

public struct LevelReport: Codable, Sendable {
    public enum Verdict: String, Codable, Sendable {
        case ok, quiet, silent
    }

    /// RMS level over the whole file, in dBFS (same as ffmpeg volumedetect's mean_volume).
    public let meanDB: Double
    /// Peak sample level, in dBFS.
    public let maxDB: Double
    public let verdict: Verdict

    /// Below this the recording is effectively silent.
    public static let silentThreshold = -40.0
    /// Below this it is usable but quiet.
    public static let quietThreshold = -32.0

    public init(meanDB: Double, maxDB: Double) {
        self.meanDB = meanDB
        self.maxDB = maxDB
        if meanDB < Self.silentThreshold {
            verdict = .silent
        } else if meanDB < Self.quietThreshold {
            verdict = .quiet
        } else {
            verdict = .ok
        }
    }
}

public enum LevelCheck {
    public static func analyze(_ url: URL) throws -> LevelReport {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk: AVAudioFrameCount = 48_000
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else {
            throw RecorderError.writerFailed("cannot allocate analysis buffer")
        }
        var sumSquares = 0.0
        var peak: Float = 0
        var count = 0
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunk)
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channels = buffer.floatChannelData else { break }
            for ch in 0..<Int(buffer.format.channelCount) {
                let samples = channels[ch]
                for i in 0..<frames {
                    let s = samples[i]
                    sumSquares += Double(s * s)
                    peak = max(peak, abs(s))
                }
                count += frames
            }
        }
        return LevelReport(meanDB: decibels(count > 0 ? (sumSquares / Double(count)).squareRoot() : 0),
                           maxDB: decibels(Double(peak)))
    }

    static func decibels(_ amplitude: Double) -> Double {
        amplitude > 0 ? 20 * log10(amplitude) : -91
    }

    /// Length of an audio file in seconds.
    public static func duration(_ url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
