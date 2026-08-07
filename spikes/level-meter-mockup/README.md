# Settings level meter

The spike compared six live, unsmoothed microphone treatments in the Settings row: a thermometer, segmented LEDs, dancing bars, a variable microphone glyph, a scrolling waveform, and an arc gauge. Variant c, dancing bars, was chosen for its minimalism and its kinship with the recording pill's existing voice glyph.

The first implementation used a determinate `ProgressView`. The monitor delivered raw RMS levels promptly, but macOS animated the control's fill on its own slower schedule, which made the meter appear delayed. The Settings row now shares the pill's five-bar component and its exact ballistics: the same -60 dB normalization, center-weighted heights, 1.35 gain and clamp, and 80 ms linear tween. There is no additional smoothing.
