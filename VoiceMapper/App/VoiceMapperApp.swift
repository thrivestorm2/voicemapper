import SwiftUI
import SwiftData

@main
struct VoiceMapperApp: App {
    @State private var audio = AudioEngine()
    private let container: ModelContainer
    @State private var recorder: SessionRecorder
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = try! ModelContainer(for: PracticeSession.self, GridCellCount.self, Baseline.self)
        let audio = AudioEngine()
        self.container = container
        _audio = State(initialValue: audio)
        _recorder = State(initialValue: SessionRecorder(audio: audio, context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(audio)
                .task { recorder.run() }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { recorder.finish() }
        }
    }
}
