# VoiceMapper — project guide for Claude

iOS voice-training app (SwiftUI, iOS 17+, Swift 6). Fully local: no network code, analytics, or third-party SDKs.
Guiding principle: help the user reach *their* voice goal safely — no "correct" voice, strain prevention built in.

Full approved plan: `docs/PLAN.md`. Approved screen wireframes: `docs/WIREFRAMES.md`.

## Working rules (Claude Pro budget, spread-out pace)
- One session = one row of the build table below. Stop at the session boundary.
- Read only the files the current session needs; don't re-scan the whole repo.
- Development happens on the user's Mac. Claude builds locally for the simulator and fixes errors before handing off:
  `xcodebuild -project VoiceMapper.xcodeproj -scheme VoiceMapper -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build`
  It can also launch the app and screenshot it with `xcrun simctl`. Device tests (mic, headphones, Bluetooth, Face ID) still need the user's iPhone.
- The iPhone gets builds through TestFlight (internal testing), not by cable — the user doesn't want Developer Mode on. To ship a build: bump `CURRENT_PROJECT_VERSION`, then `xcodebuild ... -configuration Release -destination 'generic/platform=iOS' -archivePath <path> -allowProvisioningUpdates archive`, then `xcodebuild -exportArchive` with an ExportOptions.plist (`method` app-store-connect, `destination` upload, `teamID` R6PF4UF778).
- Commit + push at the end of every session, then update the status column below.
- Use Sonnet for routine UI sessions; Opus for DSP sessions (S3, S5, S6, S10).

## Stack
SwiftUI · AVAudioEngine · Accelerate/vDSP · Swift Charts · SwiftData

## Xcode project notes
- Requires Xcode 16+. `VoiceMapper/` is a *synchronized folder*: any file added under it is compiled automatically. Do not edit `project.pbxproj` to add files.
- Info.plist is generated from build settings (`INFOPLIST_KEY_*`); microphone and Face ID usage strings are already set.
- Bundle ID `com.thrivestorm2.VoiceMapper`; signing is Automatic — the user picks their Team in Xcode.
- iPhone only, portrait only, iOS 17.0 minimum, Swift 6 language mode.

## Module layout
- `AudioEngine` — capture, hear-yourself output, route monitoring + Bluetooth banner
- `DSP/` — PitchDetector (YIN/MPM), FormantAnalyzer (LPC), SpectralMetrics (H1–H2, CPP, HNR, jitter, shimmer), VoicingDetector
- `Analysis/` — NoteMapper, ResonanceScorer, StrainGuard, SessionAggregator, HeatmapBinner
- `UI/` — GridView, RangeTableView, ExerciseViews, HistoryView, SettingsView, OnboardingView
- `Store/` — SwiftData models (sessions, grid-cell counts, baseline, goals)

## Build sessions
| # | Session | Scope | Device test | Status |
|---|---|---|---|---|
| S1 | Setup | Xcode project, app structure, tab bar with empty screens | App opens, tabs switch | done |
| S2 | Audio | Engine, mic permission, hear-yourself toggle, volume cap, delay slider | Hear yourself in headphones | done |
| S3 | Bluetooth | Route monitoring, "wired recommended" banner, headphones-only lock | Banner appears with AirPods | done |
| S4 | Pitch | Pitch detection + note label | Correct note when humming | done |
| S5 | Range table | Colour-coded range table, current note highlighted | Highlight follows voice | built, awaiting device test |
| S6 | Resonance | Formant analysis + resonance score | "ee" vs "oo" changes score | todo |
| S7 | Grid | Grid view, gender zones, live dot + trail | Dot moves as expected | todo |
| S8 | Storage | SwiftData sessions + baseline recording | Data survives restart | todo |
| S9 | History | History overlay, heat map, Today/Week/Month/All | Overlay + heat map correct | todo |
| S10 | Safety | Weight/health measures, strain alerts, daily cap | Alert fires in strain test | todo |
| S11 | Exercises | Exercise list, warm-up, cool-down, target-hold drill | Exercises completable | todo |
| S12 | Setup & settings | Onboarding, goal picker, settings, Face ID, delete all | Clean install end to end | todo |
| S13 | Polish | Praat accuracy check, accessibility, colour-blind palette, performance | Overall testing | todo |
| S14 | Buffer | Bug fixes | — | todo |
