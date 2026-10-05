import AVFoundation

public struct InputDevice: Codable, Sendable {
    public let id: String
    public let name: String
    public let isDefault: Bool
}

public enum Devices {
    static func all() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    public static func list() -> [InputDevice] {
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        return all().map { InputDevice(id: $0.uniqueID, name: $0.localizedName, isDefault: $0.uniqueID == defaultID) }
    }

    /// Resolves a device by exact unique ID, then by case-insensitive name substring.
    /// `nil` or an empty query means the system default input.
    public static func resolve(_ query: String?) throws -> AVCaptureDevice {
        guard let query, !query.isEmpty, query != "default" else {
            guard let device = AVCaptureDevice.default(for: .audio) else { throw RecorderError.noInputDevice }
            return device
        }
        let devices = all()
        if let device = devices.first(where: { $0.uniqueID == query }) { return device }
        let matches = devices.filter { $0.localizedName.localizedCaseInsensitiveContains(query) }
        guard matches.count == 1, let device = matches.first else { throw RecorderError.deviceNotFound(query) }
        return device
    }

    public static func requestAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
        default:
            break
        }
        throw RecorderError.microphoneAccessDenied
    }
}
