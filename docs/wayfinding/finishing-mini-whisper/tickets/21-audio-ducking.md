---
status: open
type: grilling
blocked-by: [8]
---

# Audio ducking: quiet the machine while it listens

## Question

When a dictation is actively recording, other audio playing on the system (music, video, calls) bleeds into the microphone and degrades transcription. Should MiniWhisper duck actively playing audio for the duration of a recording, and by what mechanism? Candidates range from cooperative session hints to output-volume manipulation (Core Audio `kAudioDevicePropertyVolumeScalar` on the default output, restored on stop) to per-app approaches. What do other dictation apps do, what is reliably restorable when the app crashes mid-duck, and does ducking apply to hold, latch, or both?

## Notes

- Requested post-Phase-7 while daily-driving onboarding builds: playing audio during a dictation is a real, recurring scenario.
- Restore-on-stop must be crash-safe — a killed process must not leave the user's volume permanently lowered (same spirit as the delivery path's clipboard-restore discipline).
- macOS has no public per-app volume API; system-output ducking is the likely shape. AVAudioSession ducking is iOS-only.
- Interaction with sound cues: the app's own cues should presumably not be ducked.
