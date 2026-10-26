# VoiceMapper — approved plan

Guiding principle: whatever helps the user accomplish their voice goal safely.

## 1. Hear yourself through headphones (toggle)
- AVAudioEngine mic → mixer → output; `.playAndRecord`, ~5 ms IO buffer.
- Only enabled when headphones are connected (prevents speaker feedback).
- 1a. When enabled and the route is Bluetooth: banner "Wired headphones recommended: Bluetooth adds ~150–250 ms delay." Re-shown on route change; dismissible, not permanently hidden.
- 1b. Volume slider with safe-listening cap + warning; delay slider for delayed-feedback drills.

## 2. Pitch → note
- YIN or McLeod pitch detection, voicing gate; `midi = 69 + 12·log2(f/440)`.
- 2a. Note label only (e.g. G4) — no needle/cents — inside a table of all vocal ranges:
  note, Hz, classical voice type, rows colour-coded by typical speaking-voice gender perception
  (usually read male / ambiguous-androgynous / usually read female), from speaking-F0 research.
  Current row highlighted and auto-scrolled. Legend: resonance matters too. Colour-blind-safe with text labels.

## 3. Pitch & resonance
- Pitch: median, 10–90th percentile range, variability in semitones.
- Resonance: LPC formants F1–F3(/F4) → vocal tract length estimate, formant spacing → brightness score. Vowel-guided exercises improve reliability.

## 4. Pitch × resonance grid
- X: dark → bright resonance; Y: log pitch with note labels; typical male / female / androgynous zones.
- Live smoothed dot + trail; draggable target zone.
- 4a. Toggleable history overlay: session averages joined in time order.
- 4b. Heat map of time-in-cell (voiced time only), with Today / Week / Month / All time selector.

## 5. Research-backed measures (safety-focused)
- Vocal weight: H1–H2, spectral tilt, CPP (shown neutrally as lighter ↔ heavier).
- Health: HNR, jitter, shimmer vs the user's own baseline.
- Strain guard: rest alerts on declining health measures, sustained top-of-range pitch or loudness; daily practice cap; warm-up/cool-down prompts.
- Intonation: pitch movement across phrases.
- Sources: Hillenbrand & Clark 2009; Gelfer & Mikos 2005; Leung, Oates & Chan 2018; Hillenbrand et al. 1995. Validate against Praat.

## 6. App structure
- Tabs: Live (grid) · Range · Exercises · History · Settings.
- Goal setup: feminine / masculine / androgynous / custom zone; baseline recording centres the grid.
- Privacy: optional on-device recordings, delete-all, optional Face ID lock.
- Disclaimer: not a substitute for a speech-language pathologist; link to finding gender-affirming voice therapy.

## Risks
- Formants noisy at high F0 → vowel-guided exercises, median smoothing, confidence gates.
- Norms vary by person and language → present as typical ranges, not rules.
- Strain detection is heuristic, not diagnostic → state clearly, point to an SLP.
