clear
cat <<'T'
╭─ claude ─────────────────────────────────────────────────────────────╮
> why does the pill flash Polishing for a keyless profile?

⏺ The flash comes from cleanupStarted firing before TranscriptPipeline.plan
  resolves. In AppFeature+Delivery.swift, cleanupEffect sends
  .cleanupStarted only inside requestStarting, so the bug is elsewhere:
  CleanupPlan.keyUnreadable returns before requestStarting runs.

  I traced it to FocusedFieldReader.captureBudget being 60ms — the
  context capture times out on cold Chromium processes, so dictation.capture
  stays nil and DeliveryTarget.isGUI flips. Proposed fix:

    - raise firstContactTimeout to 0.040 in FocusedFieldReader.swift
    - keep ChromiumAccessibility.prewarmFrontmostApp at recording start

  Run `mise run test:packages` to confirm. Want me to apply it?
╰──────────────────────────────────────────────────────────────────────╯
T
printf '> '
read -r line
