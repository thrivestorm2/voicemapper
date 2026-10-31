import AVFoundation
import Observation

/// Owns the audio session and engine: mic capture and the hear-yourself path
/// (mic → delay → monitor mixer → output). See docs/PLAN.md §1.
@MainActor
@Observable
final class AudioEngine {
    enum MicPermission {
        case undetermined, granted, denied
    }

    /// Mixer level above which the volume slider shows a safe-listening warning.
    static let safeVolumeCap: Float = 0.6
    /// Longest delay offered for delayed-feedback drills.
    static let maxDelayMs: Double = 500

    private(set) var micPermission: MicPermission = .undetermined
    private(set) var isHearingYourself = false
    private(set) var headphonesConnected = false
    private(set) var lastError: String?

    var volume: Float {
        didSet {
            monitorMixer.outputVolume = volume
            UserDefaults.standard.set(volume, forKey: Keys.volume)
        }
    }

    var delayMs: Double {
        didSet {
            delay.delayTime = delayMs / 1000
            UserDefaults.standard.set(delayMs, forKey: Keys.delayMs)
        }
    }

    var isAboveSafeVolume: Bool { volume > Self.safeVolumeCap }

    private let engine = AVAudioEngine()
    private let delay = AVAudioUnitDelay()
    private let monitorMixer = AVAudioMixerNode()
    private let session = AVAudioSession.sharedInstance()

    private enum Keys {
        static let volume = "hearYourself.volume"
        static let delayMs = "hearYourself.delayMs"
    }

    init() {
        let defaults = UserDefaults.standard
        volume = defaults.object(forKey: Keys.volume) as? Float ?? 0.4
        delayMs = defaults.object(forKey: Keys.delayMs) as? Double ?? 0

        // Pure delay: no feedback, fully wet, no extra filtering.
        delay.feedback = 0
        delay.wetDryMix = 100
        delay.lowPassCutoff = 18_000
        delay.delayTime = delayMs / 1000
        monitorMixer.outputVolume = volume

        engine.attach(delay)
        engine.attach(monitorMixer)

        micPermission = Self.currentPermission()
        headphonesConnected = Self.outputIsHeadphones(session.currentRoute)
        observeSession()
    }

    // MARK: - Hear yourself

    /// Turns the hear-yourself path on or off. Only turns on with headphones
    /// connected, to prevent speaker feedback.
    func setHearYourself(_ on: Bool) async {
        lastError = nil
        guard on else {
            stop()
            return
        }
        guard await requestMicPermission() else { return }
        headphonesConnected = Self.outputIsHeadphones(session.currentRoute)
        guard headphonesConnected else {
            lastError = "Connect headphones to hear yourself."
            return
        }
        do {
            try start()
            isHearingYourself = true
        } catch {
            stop()
            lastError = "Couldn't start audio: \(error.localizedDescription)"
        }
    }

    private func start() throws {
        // .measurement turns off voice processing (AGC, noise suppression) so
        // later analysis sees the raw voice. A2DP keeps the built-in mic when
        // Bluetooth headphones are connected, instead of the low-quality HFP mic.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioEngineError.noMicrophone
        }

        engine.disconnectNodeOutput(input)
        engine.disconnectNodeOutput(delay)
        engine.disconnectNodeOutput(monitorMixer)
        engine.connect(input, to: delay, format: format)
        engine.connect(delay, to: monitorMixer, format: format)
        engine.connect(monitorMixer, to: engine.mainMixerNode, format: format)

        engine.prepare()
        try engine.start()
    }

    private func stop() {
        engine.stop()
        isHearingYourself = false
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Permission

    private func requestMicPermission() async -> Bool {
        if micPermission == .undetermined {
            let granted = await AVAudioApplication.requestRecordPermission()
            micPermission = granted ? .granted : .denied
        }
        return micPermission == .granted
    }

    private static func currentPermission() -> MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }

    // MARK: - Session events

    private func observeSession() {
        let center = NotificationCenter.default

        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeChanged() }
        }

        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init) == .began else { return }
            MainActor.assumeIsolated { self?.stop() }
        }

        // The engine stops itself when the hardware format changes (e.g. a new
        // route); restart it if hear-yourself should still be on.
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineConfigurationChanged() }
        }
    }

    private func routeChanged() {
        headphonesConnected = Self.outputIsHeadphones(session.currentRoute)
        if isHearingYourself && !headphonesConnected {
            stop()
            lastError = "Headphones disconnected, so hear-yourself was turned off."
        }
    }

    private func engineConfigurationChanged() {
        guard isHearingYourself, headphonesConnected else { return }
        do {
            try start()
        } catch {
            stop()
            lastError = "Audio stopped after a device change. Turn hear-yourself on again."
        }
    }

    private static func outputIsHeadphones(_ route: AVAudioSessionRouteDescription) -> Bool {
        // USB audio is included because USB-C wired headphones report as it.
        let headphonePorts: Set<AVAudioSession.Port> = [
            .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio,
        ]
        return route.outputs.contains { headphonePorts.contains($0.portType) }
    }
}

enum AudioEngineError: LocalizedError {
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "No microphone input is available."
        }
    }
}
