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

    /// System (headphone) volume above which a safe-listening warning shows.
    static let safeVolumeCap: Float = 0.75
    static let defaultVoiceLevel: Float = 0.7
    /// Longest delay offered for delayed-feedback drills.
    static let maxDelayMs: Double = 500

    private(set) var micPermission: MicPermission = .undetermined
    private(set) var isHearingYourself = false
    /// Mic capture for pitch analysis is on (the Listen button). Hear-yourself
    /// also runs capture, so pitch updates in either case.
    private(set) var isListening = false
    /// Current smoothed pitch, or nil when silent or unvoiced.
    private(set) var pitch: PitchReading?
    /// Current smoothed resonance, or nil when there's no steady voiced sound.
    private(set) var resonance: ResonanceReading?
    /// ~1 s median of voice-quality measures (weight, health), nil when unvoiced.
    private(set) var quality: VoiceQuality?
    /// Background noise level (dBFS), nil when not capturing.
    private(set) var noiseFloor: Double?
    /// Background noise is loud enough to throw off the readings. Turns on
    /// after 1.5 s of noise and off after 3 s of quiet, so it doesn't flicker.
    private(set) var isNoisy = false

    /// A room louder than this is noisy whatever the voice level ...
    static let noisyFloor = -48.0
    /// ... and the voice should be at least this far above the room.
    static let minimumVoiceMargin = 18.0
    private(set) var headphonesConnected = false
    private(set) var microphones: [Microphone] = []
    private(set) var activeMicrophoneName: String?
    /// Name of the current output, e.g. "AirPods Pro" or "Headphones".
    private(set) var outputName: String?
    private(set) var outputIsBluetooth = false
    /// Set when the user closes the Bluetooth banner; cleared on every output
    /// change and each time hear-yourself turns on, so it is never hidden for good.
    private(set) var bluetoothBannerDismissed = false
    /// Mic-to-ear delay iOS reports for the current route (hardware + buffers),
    /// excluding the delay slider. Nil when hear-yourself is off.
    private(set) var deviceLatencyMs: Double?
    private(set) var lastError: String?
    /// iOS output volume (0–1): what the headphones' own buttons or Digital
    /// Crown change. Apps can't set it directly; the sheet embeds the system
    /// volume slider for that.
    private(set) var systemVolume: Float

    /// How loud your voice is in the mix. Remembered per mic, because mics
    /// pick up the voice at different levels.
    var voiceLevel: Float {
        didSet {
            applyMonitorVolume()
            if let voiceLevelMic {
                voiceLevels[voiceLevelMic] = voiceLevel
                UserDefaults.standard.set(voiceLevels, forKey: Keys.voiceLevels)
            }
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

    /// Only meaningful with headphones: without them iOS reports the
    /// speaker's (often stale) volume.
    var isAboveSafeVolume: Bool { headphonesConnected && systemVolume > Self.safeVolumeCap }

    /// "Wired headphones recommended" banner: Bluetooth output adds
    /// ~150–250 ms delay. See docs/PLAN.md §1a.
    var showsBluetoothBanner: Bool {
        isHearingYourself && outputIsBluetooth && !bluetoothBannerDismissed
    }

    func dismissBluetoothBanner() {
        bluetoothBannerDismissed = true
    }

    // Rebuilt on every start: after a hardware change (e.g. switching to a
    // Bluetooth mic, which changes the sample rate) a reused engine can keep
    // stale formats and go silent.
    private var engine: AVAudioEngine?
    private var delay: AVAudioUnitDelay?
    private var monitorMixer: AVAudioMixerNode?
    /// The input and output ports the running engine was built for.
    private var engineRoute: String?
    /// The mic whose voice level the slider currently edits.
    private var voiceLevelMic: String?
    private var voiceLevels: [String: Float]
    /// The outputs last seen, to notice output changes for the banner.
    private var outputUIDs: [String] = []
    private var volumeObservation: NSKeyValueObservation?
    private var noisySince: Date?
    private var quietSince: Date?
    private let session = AVAudioSession.sharedInstance()

    private enum Keys {
        static let voiceLevels = "hearYourself.voiceLevels"
        static let delayMs = "hearYourself.delayMs"
        static let microphone = "audio.microphoneID"
    }

    init() {
        let defaults = UserDefaults.standard
        voiceLevels = defaults.dictionary(forKey: Keys.voiceLevels) as? [String: Float] ?? [:]
        voiceLevel = Self.defaultVoiceLevel
        systemVolume = session.outputVolume
        delayMs = defaults.object(forKey: Keys.delayMs) as? Double ?? 0
        selectedMicrophoneID = defaults.string(forKey: Keys.microphone)

        micPermission = Self.currentPermission()
        // Setting the category without activating doesn't affect other audio,
        // and lets availableInputs list every mic for the picker.
        try? configureSession()
        refreshRoute()
        observeSession()
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { @Sendable [weak self] session, _ in
            let volume = session.outputVolume
            Task { @MainActor in self?.systemVolume = volume }
        }
    }

    // MARK: - Hear yourself

    /// Turns the hear-yourself path on or off. Only turns on with headphones
    /// connected, to prevent speaker feedback.
    func setHearYourself(_ on: Bool) async {
        lastError = nil
        guard on else {
            isHearingYourself = false
            deviceLatencyMs = nil
            applyMonitorVolume()
            stopIfIdle()
            return
        }
        guard await ensureRunning() else { return }
        guard headphonesConnected else {
            stopIfIdle()
            lastError = "Connect headphones to hear yourself."
            return
        }
        bluetoothBannerDismissed = false
        isHearingYourself = true
        applyMonitorVolume()
        updateLatency()
    }

    /// Turns mic capture for pitch analysis on or off, without hearing yourself.
    func setListening(_ on: Bool) async {
        lastError = nil
        guard on else {
            isListening = false
            stopIfIdle()
            return
        }
        guard await ensureRunning() else { return }
        isListening = true
    }

    /// Starts the engine if needed. False if it couldn't (error set).
    private func ensureRunning() async -> Bool {
        guard await requestMicPermission() else { return false }
        do {
            // Check the route only after the session is configured and active;
            // before that iOS may not report Bluetooth headphones.
            try configureSession()
            try session.setActive(true)
            refreshRoute()
            if engine == nil { try start() }
            return true
        } catch {
            stop()
            lastError = "Couldn't start audio: \(error.localizedDescription)"
            return false
        }
    }

    /// The monitor path is always wired up so pitch capture and hear-yourself
    /// share one engine; it is silent unless hear-yourself is on.
    private func applyMonitorVolume() {
        monitorMixer?.outputVolume = isHearingYourself ? voiceLevel : 0
    }

    private func stopIfIdle() {
        if !isHearingYourself && !isListening { stop() }
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
        loadVoiceLevel()  // before building the mixer
        systemVolume = session.outputVolume
        let monitorMixer = AVAudioMixerNode()
        monitorMixer.outputVolume = isHearingYourself ? voiceLevel : 0

        engine.attach(delay)
        engine.attach(monitorMixer)
        engine.connect(input, to: delay, format: format)
        engine.connect(delay, to: monitorMixer, format: format)
        // The main mixer converts to the output's rate, which can differ from
        // the input's (e.g. Bluetooth mic in, wired or A2DP out).
        engine.connect(monitorMixer, to: engine.mainMixerNode, format: format)

        // Analysis tap. The closures are @Sendable and run on the audio thread.
        let pitchTracker = PitchTracker(sampleRate: format.sampleRate) { [weak self] reading in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.pitch = reading }
            }
        }
        let resonanceTracker = ResonanceTracker(sampleRate: format.sampleRate) { [weak self] reading in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.resonance = reading }
            }
        }
        let qualityTracker = VoiceQualityTracker(sampleRate: format.sampleRate) { [weak self] reading in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.quality = reading }
            }
        }
        let noiseMeter = NoiseMeter(sampleRate: format.sampleRate) { [weak self] floor in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateNoise(floor: floor) }
            }
        }
        Self.installAnalysisTap(on: input, format: format, pitch: pitchTracker,
                                resonance: resonanceTracker, quality: qualityTracker, noise: noiseMeter)

        engine.prepare()
        try engine.start()
        self.engine = engine
        self.delay = delay
        self.monitorMixer = monitorMixer
        engineRoute = Self.routeKey(session.currentRoute)
        pitch = nil
        resonance = nil
        quality = nil
        resetNoise()
        updateLatency()
    }

    /// Nonisolated on purpose: a closure written in this @MainActor class would
    /// inherit main-actor isolation, and Swift 6 traps when AVAudioEngine calls
    /// it on the audio thread.
    private nonisolated static func installAnalysisTap(
        on input: AVAudioInputNode, format: AVAudioFormat,
        pitch: PitchTracker, resonance: ResonanceTracker, quality: VoiceQualityTracker,
        noise: NoiseMeter
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            pitch.process(samples)
            resonance.process(samples, pitch: pitch.currentFrequency)
            quality.process(samples, pitch: pitch.currentFrequency)
            noise.process(samples)
        }
    }

    // MARK: - Background noise

    private func updateNoise(floor: Double) {
        guard engine != nil else { return }
        noiseFloor = floor
        let noisyNow = floor > Self.noisyFloor
            || (quality.map { $0.level - floor < Self.minimumVoiceMargin } ?? false)
        let now = Date.now
        if noisyNow {
            quietSince = nil
            if noisySince == nil { noisySince = now }
            if !isNoisy, now.timeIntervalSince(noisySince!) >= 1.5 { isNoisy = true }
        } else {
            noisySince = nil
            if quietSince == nil { quietSince = now }
            if isNoisy, now.timeIntervalSince(quietSince!) >= 3 { isNoisy = false }
        }
    }

    private func resetNoise() {
        noiseFloor = nil
        isNoisy = false
        noisySince = nil
        quietSince = nil
    }

    private func updateLatency() {
        guard engine != nil, isHearingYourself else {
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
            lastError = "Audio stopped after a device change. Turn it on again."
        }
    }

    private func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        delay = nil
        monitorMixer = nil
        engineRoute = nil
        isHearingYourself = false
        isListening = false
        pitch = nil
        resonance = nil
        quality = nil
        resetNoise()
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

    /// Switches the voice-level slider to the active mic's saved level.
    private func loadVoiceLevel() {
        guard let mic = session.currentRoute.inputs.first?.uid, mic != voiceLevelMic else { return }
        voiceLevelMic = mic
        voiceLevel = voiceLevels[mic] ?? Self.defaultVoiceLevel
    }

    private func refreshRoute() {
        loadVoiceLevel()
        let route = session.currentRoute
        headphonesConnected = Self.outputIsHeadphones(route)
        systemVolume = session.outputVolume
        activeMicrophoneName = route.inputs.first?.portName
        let outputs = route.outputs.map(\.uid)
        if outputs != outputUIDs {
            outputUIDs = outputs
            bluetoothBannerDismissed = false
        }
        outputName = route.outputs.first?.portName
        outputIsBluetooth = route.outputs.contains { Self.bluetoothPorts.contains($0.portType) }
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
        guard engine != nil else { return }
        if isHearingYourself, !headphonesConnected {
            isHearingYourself = false
            applyMonitorVolume()
            lastError = "Headphones disconnected, so hear-yourself was turned off."
            if isListening { restart() } else { stop() }
        } else if Self.routeKey(session.currentRoute) != engineRoute {
            // A different mic or output: the engine's formats are now stale.
            restart()
        } else {
            updateLatency()
        }
    }

    private func engineConfigurationChanged() {
        guard engine != nil, !isHearingYourself || headphonesConnected else { return }
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
