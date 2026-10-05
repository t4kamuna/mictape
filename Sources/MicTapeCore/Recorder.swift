import AVFoundation
import Foundation

public struct RecordingFormat: Sendable {
    public var sampleRate: Double = 48_000
    public var channels: Int = 1
    public var bitRate: Int = 128_000
    /// How often the writer flushes a movie fragment. Anything recorded before
    /// the last fragment stays playable even if the process is killed.
    public var fragmentInterval: TimeInterval = 1

    public init() {}
}

public enum RecorderError: Error, CustomStringConvertible {
    case microphoneAccessDenied
    case deviceNotFound(String)
    case noInputDevice
    case cannotAddInput
    case cannotAddOutput
    case writerFailed(String)

    public var description: String {
        switch self {
        case .microphoneAccessDenied:
            return "Microphone access is denied. Allow it in System Settings > Privacy & Security > Microphone."
        case .deviceNotFound(let query):
            return "No input device matches \"\(query)\". Run `mictape devices` to list them."
        case .noInputDevice:
            return "No audio input device is available."
        case .cannotAddInput:
            return "Could not open the input device."
        case .cannotAddOutput:
            return "Could not attach the audio output."
        case .writerFailed(let message):
            return "Could not write the recording: \(message)"
        }
    }
}

/// Records one input device to an AAC .m4a file written as fragmented MP4.
public final class Recorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    public let url: URL
    public let device: AVCaptureDevice
    public let format: RecordingFormat

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "mictape.recorder")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private var stopping = false
    private var lastTime = CMTime.zero
    private var firstTime = CMTime.invalid

    public init(url: URL, device: AVCaptureDevice, format: RecordingFormat = RecordingFormat()) throws {
        self.url = url
        self.device = device
        self.format = format

        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        writer.movieFragmentInterval = CMTime(seconds: format.fragmentInterval, preferredTimescale: 600)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channels,
            AVEncoderBitRateKey: format.bitRate,
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderError.writerFailed("cannot add audio input") }
        writer.add(input)
        super.init()

        let deviceInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(deviceInput) else { throw RecorderError.cannotAddInput }
        session.addInput(deviceInput)
        // Ask the capture output for PCM that already matches the target layout,
        // so the encoder never has to resample or downmix.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw RecorderError.cannotAddOutput }
        session.addOutput(output)
    }

    public func start() {
        session.startRunning()
    }

    /// Seconds of audio written so far.
    public var duration: TimeInterval {
        queue.sync {
            guard firstTime.isValid else { return 0 }
            return CMTimeGetSeconds(CMTimeSubtract(lastTime, firstTime))
        }
    }

    /// Stops capture and finalizes the file.
    public func stop() async throws {
        session.stopRunning()
        let state: (Bool, AVAssetWriter.Status) = queue.sync {
            stopping = true
            return (started, writer.status)
        }
        guard state.0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !stopping else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: time)
            firstTime = time
            started = true
        }
        guard input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) {
            lastTime = CMTimeAdd(time, CMSampleBufferGetDuration(sampleBuffer))
        }
    }
}
