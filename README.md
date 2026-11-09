# VoiceMemoApp

An iOS voice memo app that records audio and shows a live transcript while you speak.

## Features

- Record audio from the microphone
- Live speech-to-text with partial and final results
- Save each memo with its audio file and transcript
- Memo list screen to see saved recordings

## Tech Used

- Swift and SwiftUI
- AVFoundation (AVAudioEngine) for recording
- Speech framework (SpeechAnalyzer) for live transcription
- MVVM architecture with protocol-based services
- JSON file storage in the Documents folder
- Silero VAD with ONNX Runtime (in progress)

## Requirements

- Xcode with the iOS 26 SDK
- iOS 26 or later (SpeechAnalyzer needs it)
- Microphone and speech recognition permissions

## How to Run

1. Clone the repo.
2. Open `VoiceMemo/VoiceMemo.xcodeproj` in Xcode.
3. Pick your team under Signing and Capabilities.
4. Run on a device or simulator with iOS 26.
5. Allow microphone and speech recognition access when asked.

## Project Structure

- `Models` has the Memo data model
- `Views` has the SwiftUI screens
- `ViewModels` has recording and playback logic
- `Services` has audio recording and transcription
- `Repository` has saving and loading memos
- `VAD` has the Silero voice activity detection code

## Status

Done:
- Recording, live transcription, saving and listing memos

In progress:
- Playback screen
- Voice activity detection (Silero VAD) connected to recording
- Delete, rename and share options
- Background recording and call interruption handling

## Notes

This is a personal learning project.
