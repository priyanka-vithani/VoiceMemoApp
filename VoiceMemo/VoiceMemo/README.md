# Voice Memo Learning App — Setup Notes

## Before you build

1. New Xcode project, iOS App template, SwiftUI, minimum deployment target
   set to iOS 26.0. This code will not compile below that, on purpose.
2. Drag all files from `Sources/` into the project.
3. Add these two keys to Info.plist, or the app will crash on first
   record attempt instead of showing a permission prompt:
   - `NSMicrophoneUsageDescription` — string explaining why you need the mic
   - `NSSpeechRecognitionUsageDescription` — string explaining transcription
4. Under Signing & Capabilities, confirm Background Modes is NOT
   silently required unless you're doing background recording. Skip it
   for the learning version.

## What's actually implemented

- Recording to disk (AVAudioEngine, .caf format)
- Live transcription with volatile + finalized results (SpeechAnalyzer)
- Model download check via AssetInventory
- Saving memo + transcript to a JSON index in Documents
- Basic list + record screens

## What's NOT implemented, and you should know that going in

- **Playback UI is not wired to a screen.** `PlaybackViewModel` exists
  but there's no view calling `play(memo:)`. Add a detail view.
- **Word-level highlighting during playback** needs you to store the
  `audioTimeRange` runs from the AttributedString, not just the plain
  string. Right now `RecordingViewModel` collapses the transcript to
  `String` when saving, which throws that timing data away. If you
  want the highlight-as-you-play feature from Voice Memos/Notes, you
  need to persist the AttributedString (or the runs) instead.
- **No waveform visualization.** Voice Memos shows a live waveform.
  Not covered here; that's audio buffer amplitude sampling and a
  custom Canvas/Shape, unrelated to SpeechAnalyzer.
- **No delete/rename/share UI**, only the repository methods exist.
- **No background recording, interruption handling (calls, Siri), or
  audio route change handling.** All three matter a lot in a real
  Voice Memos competitor and none are stubbed in here. This is
  the biggest gap between "learning demo" and "shippable app."
- **BufferConverter is unverified.** Flagged already above. Test it
  with real device audio before trusting it.

## If you later need a deployment target below iOS 26

Write a class conforming to `TranscriptionService` that wraps
`SFSpeechRecognizer` instead of `SpeechAnalyzer`. Nothing else in the
app changes, because `RecordingViewModel` only depends on the
protocol. That's the entire point of the abstraction, confirm it
actually pays off before you assume it will.
