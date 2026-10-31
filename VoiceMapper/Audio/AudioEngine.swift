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

    struct Microphone: Identifiable, Hashable {
        let id: String  // AVAudioSessionPortDescription.uid
        let name: String
        let isBluetooth: Bool
    }

    /// Mixer level above which the volume slider shows a safe-listening warning.
    static let safeVolumeCap: Float = 0.6
    /// Longest delay offered for delayed-feedback drills.
    static let maxDelayMs: Double = 500

    private(set) var micPermission: MicPermission = .undetermined
    private(set) var isHearingYourself = false
    private(set) var headphonesConnected = false
    private(set) var microphones: [Microphone] = []
    private(set) var activeMicrophoneName: String?
    /// Mic-to-ear delay iOS reports for the current route (hardware + buffers),
    /// excluding the delay slider. Nil when hear-yourself is off.
    private(set) var deviceLatencyMs: Double?
    private(set) var lastError: String?

    var volume: Float {
        didSet {
            monitorMixer?.outputVolume = volume
            UserDefaults.standard.set(volume, forKey: Keys.volume)
        }
    }

    var delayMs: Double {
        didSet {
            delay?.delayTime = delayMs / 1000
            UserDefaults.standard.set(delayMs, forKey: Keys.delayMs)
        }
    }

    /// The user's chosen mic, or nil for automatic (the iPhone mic).
    var selectedMicrophoneID: String? {
        didSet {
            UserDefaults.standard.set(selectedMicrophoneID, forKey: Keys.microphone)
            // The switch is asynchronous; routeChanged() rebuilds the engine
            // once iOS reports the new mic.
            applyPreferredInput()
            refreshRoute()
        }
    }

    var isAboveSafeVolume: Bool { volume > Self.safeVolumeCap }

    // Rebuilt on every start: after a hardware change (e.g. switching to a
    // Bluetooth mic, which changes the sample rate) a reused engine can keep
    // stale formats and go silent.
    private var engine: AVAudioEngine?
    private var delay: AVAudioUnitDelay?
    private var monitorMixer: AVAudioMixerNode?
    /// The input and output ports the running engine was built for.
    private var engineRoute: String?
    private let session = AVAudioSession.sharedInstance()

    private enum Keys {
        static let volume = "hearYourself.volume"
        static let delayMs = "hearYourself.delayMs"
        static let microphone = "audio.microphoneID"
    }

    init() {
        let defaults = UserDefaults.standard
        volume = defaults.object(forKey: Keys.volume) as? Float ?? 0.4
        delayMs = defaults.object(forKey: Keys.delayMs) as? Double ?? 0
        selectedMicrophoneID = defaults.string(forKey: Keys.microphone)

        micPermission = Self.currentPermission()
        // Setting the category without activating doesn't affect other audio,
        // and lets availableInputs list every mic for the picker.
        try? configureSession()
        refreshRoute()
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
        do {
            // Check the route only after the session is configured and active;
            // before that iOS may not report Bluetooth headphones.
            try configureSession()
            try session.setActive(true)
            refreshRoute()
            guard headphonesConnected else {
                stop()
                lastError = "Connect headphones to hear yourself."
                return
            }
            try start()
            isHearingYourself = true
        } catch {
            stop()
            lastError = "Couldn't start audio: \(error.localizedDescription)"
        }
    }

    private func configureSession() throws {
        // .measurement turns off voice processing (AGC, noise suppression) so
        // later analysis sees the raw voice. A2DP gives high-quality Bluetooth
        // output; HFP is allowed only so a Bluetooth mic can be chosen in the
        // picker — applyPreferredInput() keeps it off otherwise.
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.allowBluetoothA2DP, .allowBluetoothHFP])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.005)
        applyPreferredInput()
    }

    private func start() throws {
        engine?.stop()
        try session.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioEngineError.noMicrophone
        }

        // Pure delay: no feedback, fully wet, no extra filtering.
        let delay = AVAudioUnitDelay()
        delay.feedback = 0
        delay.wetDryMix = 100
        delay.lowPassCutoff = 18_000
        delay.delayTime = delayMs / 1000
        let monitorMixer = AVAudioMixerNode()
        monitorMixer.outputVolume = volume

        engine.attach(delay)
        engine.attach(monitorMixer)
        engine.connect(input, to: delay, format: format)
        engine.connect(delay, to: monitorMixer, format: format)
        // The main mixer converts to the output's rate, which can differ from
        // the input's (e.g. Bluetooth mic in, wired or A2DP out).
        engine.connect(monitorMixer, to: engine.mainMixerNode, format: format)

        engine.prepare()
        try engine.start()
        self.engine = engine
        self.delay = delay
        self.monitorMixer = monitorMixer
        engineRoute = Self.routeKey(session.currentRoute)
        updateLatency()
    }

    private func updateLatency() {
        guard engine != nil else {
            deviceLatencyMs = nil
            return
        }
        // One IO buffer on the way in, one on the way out.
        let seconds = session.inputLatency + session.outputLatency + 2 * session.ioBufferDuration
        deviceLatencyMs = seconds * 1000
    }

    private func restart() {
        do {
            try start()
        } catch {
            stop()
            lastError = "Audio stopped after a device change. Turn hear-yourself on again."
        }
    }

    private func stop() {
        engine?.stop()
        engine = nil
        delay = nil
        monitorMixer = nil
        engineRoute = nil
        isHearingYourself = false
        deviceLatencyMs = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Microphone

    /// Routes input to the chosen mic, or in automatic mode to the iPhone mic:
    /// full quality and no extra latency (headset and USB mics can add both).
    private func applyPreferredInput() {
        let inputs = session.availableInputs ?? []
        let chosen = inputs.first { $0.uid == selectedMicrophoneID }
            ?? inputs.first { $0.portType == .builtInMic }
        if let chosen, session.preferredInput?.uid != chosen.uid {
            try? session.setPreferredInput(chosen)
        }
    }

    private func refreshRoute() {
        let route = session.currentRoute
        headphonesConnected = Self.outputIsHeadphones(route)
        activeMicrophoneName = route.inputs.first?.portName
        microphones = (session.availableInputs ?? []).map {
            Microphone(id: $0.uid, name: $0.portName, isBluetooth: Self.bluetoothPorts.contains($0.portType))
        }
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
        // route); rebuild it if hear-yourself should still be on.
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
            let changed = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let engine = self.engine, changed == ObjectIdentifier(engine) else { return }
                self.engineConfigurationChanged()
            }
        }
    }

    private func routeChanged() {
        // A chosen mic that reconnects should take over again.
        applyPreferredInput()
        refreshRoute()
        guard isHearingYourself else { return }
        if !headphonesConnected {
            stop()
            lastError = "Headphones disconnected, so hear-yourself was turned off."
        } else if Self.routeKey(session.currentRoute) != engineRoute {
            // A different mic or output: the engine's formats are now stale.
            restart()
        } else {
            updateLatency()
        }
    }

    private func engineConfigurationChanged() {
        guard isHearingYourself, headphonesConnected else { return }
        restart()
    }

    private static func routeKey(_ route: AVAudioSessionRouteDescription) -> String {
        (route.inputs + route.outputs).map(\.uid).joined(separator: "|")
    }

    private static let bluetoothPorts: Set<AVAudioSession.Port> = [.bluetoothHFP, .bluetoothLE, .bluetoothA2DP]

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
