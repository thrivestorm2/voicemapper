import SwiftUI
import SwiftData

@main
struct VoiceMapperApp: App {
    @State private var audio = AudioEngine()
    private let container: ModelContainer
    @State private var recorder: SessionRecorder
    @State private var strain: StrainGuard
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = try! ModelContainer(for: PracticeSession.self, GridCellCount.self, Baseline.self)
        let audio = AudioEngine()
        self.container = container
        _audio = State(initialValue: audio)
        let strain = StrainGuard()
        _strain = State(initialValue: strain)
        _recorder = State(initialValue: SessionRecorder(audio: audio, context: container.mainContext, strain: strain))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(audio)
                .environment(strain)
                .environment(recorder)
                .task { recorder.run() }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { recorder.finish() }
        }
    }
}
