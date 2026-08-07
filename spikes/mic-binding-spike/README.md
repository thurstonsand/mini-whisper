# Microphone binding spike

Disposable CoreAudio/AVAudioEngine CLI for ticket 31's microphone picker. It proves whether a fresh, unprepared `AVAudioEngine` can bind its input audio unit to an explicit CoreAudio device before the input format or tap is touched.

```sh
mkdir -p .build
swiftc \
  -framework AudioToolbox \
  -framework AVFoundation \
  -framework CoreAudio \
  spikes/mic-binding-spike/MicBindingSpike.swift \
  -o .build/mic-binding-spike

.build/mic-binding-spike '<device UID substring>'
.build/mic-binding-spike default-arm '<device UID substring>'
.build/mic-binding-spike auhal '<device UID substring>'
.build/mic-binding-spike engine-variants '<device UID substring>'
```

The ordinary invocation captures the system-default baseline for two seconds, then captures the uniquely matched explicit device for two seconds. It reports both input-node bus formats and fails on a `CurrentDevice` readback mismatch, an invalid or dishonest format, or zero nonempty buffers. The other modes are controlled investigation arms: a temporary global-default capture with signal-backed restoration, direct AUHAL capture, and two managed-engine ordering variants.

## MOTIV Mix Virtual finding

Binding the idle MOTIV Mix Virtual device succeeded (`CurrentDevice` read back the requested ID), but its audio IO proc initially delivered no callbacks. This is consistent with its loopback topology: CoreAudio reports its input source as `MOTIV Mix Virtual Output`, and the Shure driver can remain loaded while the MOTIV Mix app and anything driving that output are absent. A later repeat delivered 20 silent callbacks and showed the managed graph's distinction clearly: the input bus reflected the two-channel device, while the output bus and tap were mono. Zero callbacks or silent buffers in that state are virtual-device behavior, not evidence that explicit binding failed. Do not add capture timeout machinery to compensate for an idle loopback; the app's whole-utterance silence handling owns an empty recording.

## Private aggregate finding

Realizing an AVAudioEngine graph can create an in-process `CADefaultDeviceAggregate-*` bridge which is then reflected back through `kAudioHardwarePropertyDevices`. The observed bridge declared `kAudioDevicePropertyIsHidden = 0`, aggregate transport (`'grup'`), and `kAudioAggregateDeviceIsPrivateKey = 1` in its composition. MiniWhisper filters both hidden devices and private aggregates by those declarations; user-created Audio MIDI Setup aggregates declare private `0` and remain selectable.

## Continuity microphone finding

A cold explicit managed-engine bind to Thurston's iPhone read back the requested device and exposed sane 48 kHz/mono input and output formats, but delivered no callbacks. Temporarily making the iPhone the system default woke the Continuity route: an unbound engine then delivered 20 nonempty buffers, and the saved built-in default was restored and read back as device 101. A direct AUHAL arm subsequently delivered 188 callbacks and 96,256 frames with no render errors, but it followed that global-default mutation and did not independently establish a wake mechanism.

A later controlled probe established that the limitation belongs to the HAL backend rather than a timing race. Apple's [Continuity Camera sample](https://github.com/apple/sample-code/tree/main/ContinuityCam) discovers `.microphone` and `.external` AVCapture devices and swaps `AVCaptureDeviceInput` in `Camera.swift` without changing the system default; the local probe reproduced that sanctioned app-local route:

| Probe | Result |
| --- | --- |
| Cold explicit AVAudioEngine HAL bind | Device readback succeeded; zero callbacks |
| AVCaptureSession on the same iPhone | 281 sample buffers; high-level Continuity handshake succeeded |
| Explicit AVAudioEngine bind after AVCaptureSession | Zero callbacks |
| Explicit AVAudioEngine bind during a running AVCaptureSession | Zero callbacks |
| Temporary system-default mutation with an unbound engine | Nonempty buffers; pass |

Neither preparing earlier nor choosing the input bus format changes the outcome. Continuity capture is unreachable through MiniWhisper's current app-local HAL/AVAudioEngine binding, but it is not an OS impossibility: AVCaptureSession is Apple's documented app-local backend and captured 281 buffers while HAL stayed silent before, after, and during that session. MiniWhisper excludes both wired and wireless Continuity transport types from explicit enumeration and resolution until it gains that backend. A Continuity microphone remains usable through **System Default** when macOS selects it, while a previously persisted explicit Continuity UID is preserved and truthfully falls back to the current default.

Cold ordinary-USB behavior was confirmed on a desktop setup: an explicit bind to a cold Shure MV7 (USB, non-default) delivered full nonempty buffers with real signal under both orderings, closing the open route — the failure is specific to Continuity, not explicit binding. A SteelSeries Arctis Nova Elite dongle clocked buffers with a 0.0 peak while its headset was off: the same idle-device class as the MOTIV loopback — binding works, the device has nothing to say, and the silence gate absorbs the empty result.

The terminal process needs microphone access. If macOS asks, grant the terminal rather than the disposable executable; do not add this spike to the app target.
