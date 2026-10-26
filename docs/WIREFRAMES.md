# VoiceMapper — approved wireframes

## 1. Onboarding / goal setup
```
┌─────────────────────────┐
│  Welcome to VoiceMapper │
│  Everything stays on    │
│  your phone.            │
│  Your goal:             │
│  ( ) Feminine           │
│  ( ) Masculine          │
│  ( ) Androgynous        │
│  ( ) Custom zone        │
│  Record baseline (20s)  │
│      [ ● Record ]       │
│  ⓘ Not a substitute for │
│    a voice therapist    │
│        [ Continue ]     │
└─────────────────────────┘
```

## 2. Live — grid
```
┌─────────────────────────┐
│ ⚠ Wired headphones rec- │  ← only if Bluetooth +
│   ommended (BT delay) ✕ │    hear-yourself is on
│─────────────────────────│
│        G4   196 Hz      │  ← note label only
│ Pitch+                  │
│ ┌──────────┬──────────┐ │
│ │░ ░       │   ╭───╮  │ │
│ │  ░       │   │ ♀ ●  │ │  ● live dot + trail
│ │          │   ╰───╯  │ │  ▒ heat map
│ ├────andro─┼──────────┤ │  ◦─◦ history overlay
│ │ ╭───╮    │          │ │  ▭ your target zone
│ │ │ ♂ │  ◦─◦─◦        │ │
│ │ ╰───╯    │          │ │
│ └──────────┴──────────┘ │
│ Dark      Pitch-  Bright│
│ [🎧 Hear self] [History]│
│ [Heat map ▾ Today]      │
│ Weight: light ──●── heavy│
│ Health: ● good          │
├─────────────────────────┤
│ Live │Range│Exer│Hist│⚙ │
└─────────────────────────┘
```

## 3. Range table
```
┌─────────────────────────┐
│        G4   196 Hz      │
│─────────────────────────│
│ Note  Hz   Voice  Read  │
│ C5   523  Sop    ████ F │
│ A4   440  Sop    ████ F │
│ F4   349  Mezzo  ████ F │
│▶G3   196  Alto   ████ F◀│ ← current, highlighted
│ E3   165  Tenor  ▓▓▓▓ A │
│ C3   131  Bari   ░░░░ M │
│ G2    98  Bass   ░░░░ M │
│ E2    82  Bass   ░░░░ M │
│─────────────────────────│
│ ████ usually read F     │
│ ▓▓▓▓ ambiguous/andro    │
│ ░░░░ usually read M     │
│ ⓘ Resonance matters too │
└─────────────────────────┘
```

## 4. Hear-yourself sheet
```
┌─────────────────────────┐
│ Hear yourself    [ ON ] │
│ Route: AirPods (BT) ⚠   │
│ → Wired recommended     │
│ Volume  ───●──── (cap)  │
│ Delay   ●─────── 0 ms   │
└─────────────────────────┘
```

## 5. Exercises
```
┌─────────────────────────┐
│ Today: 8 / 30 min  ▓▓░░ │
│ ▸ Warm-up (required)    │
│ ▸ Pitch slides          │
│ ▸ Hold target pitch     │
│ ▸ Resonance: big→small  │
│   dog                   │
│ ▸ Vowel ladder (ee/ah)  │
│ ▸ Reading: Rainbow      │
│   Passage               │
│ ▸ Cool-down             │
└─────────────────────────┘
```

## 6. Exercise with strain alert
```
┌─────────────────────────┐
│ Hold target: A3 (220 Hz)│
│      ●──────── 6s/10s   │
│ ┌─────────────────────┐ │
│ │ 💧 Take a break     │ │
│ │ Signs of strain     │ │
│ │ detected. Rest 5    │ │
│ │ min, sip water.     │ │
│ │  [ Rest ] [Dismiss] │ │
│ └─────────────────────┘ │
└─────────────────────────┘
```

## 7. History
```
┌─────────────────────────┐
│ [Today|Week|Month|All]  │
│ ┌─────────────────────┐ │
│ │ heat map grid  ▒▒▓█ │ │
│ └─────────────────────┘ │
│ Median pitch (Hz)       │
│ 220┤        ╭──●        │
│ 160┤ ●──●──╯            │
│ Resonance score         │
│    ┤    ╭──╮╭──●        │
│ Sessions                │
│ Oct 26  14m  G3  bright │
│ Oct 25  20m  F#3 mid  ▸ │
└─────────────────────────┘
```

## 8. Settings
```
┌─────────────────────────┐
│ Goal: Feminine  ▸       │
│ Target zone: edit ▸     │
│ Re-record baseline ▸    │
│ Daily practice cap: 30m │
│ Strain alerts   [ ON ]  │
│ Save recordings [ OFF ] │
│ Face ID lock    [ OFF ] │
│ Colour-blind palette [ ]│
│ Delete all data  ▸      │
│ Research sources ▸      │
│ Find a voice therapist ▸│
└─────────────────────────┘
```
