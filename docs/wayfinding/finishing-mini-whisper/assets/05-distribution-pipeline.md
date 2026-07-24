# Distribution pipeline research

## Recommendation

Ship stable releases from immutable `vX.Y.Z` tags as a Developer ID-signed, hardened-runtime `MiniWhisper.app` inside a ZIP. Build and export through Xcode, submit the first ZIP to Apple's notary service, staple the accepted ticket to the app, validate the staple, recreate the final ZIP, verify it, and only then publish it and calculate the cask checksum. A DMG adds signing and packaging work without improving this app's Homebrew installation.

Keep App Sandbox for the MVP unless the installed-product proof below disproves Apple's stated behavior. Apple DTS explicitly says a listen-only `CGEventTap` uses Input Monitoring and has worked in sandboxed apps since macOS 10.15, and that `CGEvent.post` uses the separate PostEvent privilege and is also sandbox-compatible. Use those two Core Graphics paths for right-Option observation and clipboard-plus-Command-V delivery. Do not use `NSEvent` global monitoring, full Accessibility APIs, or Apple Events for this vertical.

Publish stable tags only at first. Generate `Casks/mini-whisper.rb` after the GitHub release exists and commit it to `thurstonsand/homebrew-tap` with the existing deploy-key pattern. Do not add a moving nightly cask until daily driving demonstrates that its extra release and upgrade surface is worthwhile. Brew upgrade is the MVP update mechanism; an in-app updater remains a later product decision.

Aim for one universal `arm64` + `x86_64` app and ZIP if the delivered whisper XCFramework contains both macOS architectures. If it does not, make the first release intentionally Apple-silicon-only and constrain the cask accordingly. Never let the CI runner's architecture decide this accidentally.

## Current repository state

The app target currently has these release properties:

- bundle identifier `com.thurstonsand.MiniWhisper` and team `6JMB7W6NB4`;
- macOS 14 minimum and `LSUIElement=YES`;
- automatic signing, App Sandbox enabled, and hardened runtime enabled only for Release;
- sandbox entitlements for microphone input, outgoing network, user-selected read/write files, and Apple Events automation;
- generated `NSMicrophoneUsageDescription` and `NSAppleEventsUsageDescription` values in Xcode build settings;
- no whisper XCFramework in the empty project `Frameworks` group yet;
- development commands fixed to `platform=macOS,arch=arm64`, while Release has no explicit architecture policy.

The checked-in `MiniWhisper/Info.plist` is empty because Xcode merges generated values into the built plist. Release validation must inspect `MiniWhisper.app/Contents/Info.plist`, not infer the shipped values from that source file alone.

GhosttyKit already proves the account and repository mechanics. Its release workflow validates the six Apple secrets, imports the `.p12` with `apple-actions/import-codesign-certs@v7`, writes the App Store Connect `.p8` key, signs nested executables before the outer app with a timestamp and hardened runtime, archives with `ditto`, waits on `notarytool`, publishes GitHub assets, and updates the tap with a repository-scoped deploy key. MiniWhisper should reuse those mechanics, but not GhosttyKit's hand-assembled SwiftPM bundle or its omission of stapling and final Gatekeeper validation.

## Permissions, entitlements, and App Sandbox

### What each operation actually requires

| MiniWhisper operation               | API path                                                                                                                   | TCC surface shown to the user | Sandbox/signing requirement                                                                                                                                   | Usage-description key                                                            |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Capture speech                      | AVFoundation microphone capture                                                                                            | Microphone                    | `com.apple.security.device.audio-input` while sandboxed                                                                                                       | `NSMicrophoneUsageDescription` is required                                       |
| Observe right-Option globally       | listen-only `CGEventTap` plus `CGPreflightListenEventAccess` / `CGRequestListenEventAccess`                                | Input Monitoring              | Compatible with App Sandbox since macOS 10.15 according to Apple DTS; no special code-signing entitlement                                                     | Apple documents no Input Monitoring usage-description key for this API           |
| Synthesize Command-V                | pasteboard write plus `CGEvent.post`, preflighted/requested with `CGPreflightPostEventAccess` / `CGRequestPostEventAccess` | Accessibility                 | The underlying TCC service is PostEvent, not full Accessibility; Apple DTS says it is sandbox-compatible and limited to event posting; no special entitlement | Apple documents no PostEvent or Accessibility usage-description key for this API |
| Inspect or control another app's UI | Accessibility `AXUIElement` APIs                                                                                           | Accessibility                 | Full Accessibility is a distinct TCC service and is generally blocked by App Sandbox                                                                          | Apple documents no general Accessibility usage-description key                   |
| Send Apple Events to another app    | Apple Events APIs                                                                                                          | Automation                    | A sandboxed/hardened app needs the applicable Apple Events entitlement and target access                                                                      | `NSAppleEventsUsageDescription` is required                                      |

Apple's [protected-resources catalog](https://developer.apple.com/documentation/bundleresources/protected-resources) lists the supported usage-description keys. It does not contain `NSInputMonitoringUsageDescription` or `NSAccessibilityUsageDescription`. For the Core Graphics path, use the explicit request APIs rather than adding undocumented plist keys. `NSMicrophoneUsageDescription` is [required for microphone APIs](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription), and `NSAppleEventsUsageDescription` is [required only when sending Apple Events](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription).

The names in System Settings are misleading. Apple DTS distinguishes three TCC services: ListenEvent appears under Input Monitoring; PostEvent and full Accessibility both appear under Accessibility, but PostEvent grants only event posting. The corresponding test resets are `tccutil reset ListenEvent com.thurstonsand.MiniWhisper`, `tccutil reset PostEvent com.thurstonsand.MiniWhisper`, and `tccutil reset Accessibility com.thurstonsand.MiniWhisper`. They are not interchangeable.

### Recommended MVP entitlement set

Keep the release hardened runtime. Apple's notary service requires it, and Core Graphics listening/posting does not require a hardened-runtime exception.

Keep App Sandbox initially. Reduce its entitlements to the capabilities the shipped MVP actually invokes:

- keep `com.apple.security.app-sandbox`;
- keep `com.apple.security.device.audio-input`;
- keep user-selected file access only if the MVP asks the user to locate a model outside the app's container, and prefer read-only if it never modifies that file;
- remove `com.apple.security.automation.apple-events` and the generated `NSAppleEventsUsageDescription` if delivery is pasteboard plus `CGEvent.post`;
- remove `com.apple.security.network.client` for a wholly local MVP unless model download or the controlled-network cleanup feature is actually present.

The project capability build settings and `MiniWhisper.entitlements` must agree. Otherwise Xcode can regenerate an entitlement thought to have been removed.

Do not add a blanket Accessibility entitlement. If a later design selects `AXUIElement` to write directly into another app, that is a different mechanism with a real sandbox conflict. Developer ID distribution permits dropping App Sandbox, so the direct fallback is an unsandboxed, hardened-runtime app with the smallest remaining entitlements—not a temporary-exception maze. Likewise, retain Apple Events automation only if the transcript delivery implementation actually sends Apple Events.

### Required installed-product proof

Apple's guidance establishes the general model, but the exact MiniWhisper behavior is still a release gate. Before freezing the entitlement decision, test the signed, notarized, Homebrew-installed Release app on supported macOS versions with App Sandbox visibly present in `codesign -d --entitlements :-`:

1. With only Input Monitoring granted, a `.listenOnly` event tap must receive right-side `flagsChanged` events, distinguish right Option from left Option, survive app deactivation, and never suppress or rewrite the user's input.
2. With PostEvent denied, transcription must fail visibly at delivery rather than silently; requesting access must place MiniWhisper in System Settings > Privacy & Security > Accessibility.
3. With PostEvent granted, pasteboard-plus-Command-V must insert into representative native, Electron, browser, and terminal text fields while the app remains sandboxed.
4. Microphone access, event listening, and event posting must still work after quit/relaunch and after a cask upgrade.
5. Revoking each grant while MiniWhisper is running must transition to a recoverable denied state. Permission changes that macOS applies only after relaunch should produce explicit relaunch guidance.

If step 1 or 3 fails only when sandboxed after the implementation itself is proven unsandboxed, remove App Sandbox for Developer ID builds and record the failed OS/build matrix. Do not remove it based on old pre-macOS-10.15 reports. Conversely, do not claim sandbox compatibility from a Debug build launched by Xcode; TCC and code identity differ in the distributed artifact.

MiniWhisper does not need an active filtering tap for the fixed right-Option UX. A listen-only tap is sufficient and avoids conflating observation with event suppression. If a later design decides to consume or rewrite key events, treat that as a new permission proof rather than assuming the listen-only result covers it.

## Build and archive

### Release inputs

A stable tag must match `vMAJOR.MINOR.PATCH`. Resolve:

- `MARKETING_VERSION=MAJOR.MINOR.PATCH`, which becomes `CFBundleShortVersionString`;
- `CURRENT_PROJECT_VERSION` from a monotonically increasing GitHub run/build number, which becomes `CFBundleVersion`;
- artifact name `MiniWhisper-MAJOR.MINOR.PATCH.zip`;
- immutable release URL under the matching GitHub tag.

The workflow should reject malformed tags and verify the built plist contains those exact values. Do not commit per-release project-file version edits; pass the values to `xcodebuild`.

Run normal CI before release packaging. Then, on a pinned macOS/Xcode runner, import the Developer ID Application certificate and archive the app through Xcode:

```text
xcodebuild archive
  -project MiniWhisper.xcodeproj
  -scheme MiniWhisper
  -configuration Release
  -destination "generic/platform=macOS"
  -archivePath <path>/MiniWhisper.xcarchive
  MARKETING_VERSION=<tag version>
  CURRENT_PROJECT_VERSION=<monotonic build>
  <explicit ARCHS policy>
```

Export the archive with `xcodebuild -exportArchive` and an explicit `ExportOptions.plist` using Developer ID distribution, team `6JMB7W6NB4`, the imported Developer ID Application certificate, and the intended signing style. The export step should produce `MiniWhisper.app`; it should not upload or notarize implicitly because the following pipeline needs deterministic control over submission, stapling, verification, and final packaging.

This Xcode-native path is preferable to copying GhosttyKit's assembly script. Xcode understands app archives, generated Info.plist values, Swift runtime content, embedded frameworks, and nested signing. Keep the `.xcarchive` and dSYM as short-lived workflow artifacts for diagnosis; publish only the install ZIP and optional checksum sidecar unless crash-symbol handling later needs a private retention policy.

### Architecture policy

Prefer a universal app. Set and verify `ARCHS="arm64 x86_64"` and `ONLY_ACTIVE_ARCH=NO` only after the whisper binary supplies compatible macOS slices and all code compiles for both. The release must run `lipo -archs` or `file` on the main executable and every embedded dynamic binary and compare the result to the declared artifact architecture.

If whisper initially supplies only arm64, explicitly archive `ARCHS=arm64`, name and document the artifact as Apple-silicon-only, and add an arm64 requirement to the cask. Do not publish a cask that Homebrew can install on Intel and leave Gatekeeper or dyld to explain the mistake. Moving from arm64-only to universal can retain the same cask token and URL pattern.

## XCFramework handling and inside-out signing

An XCFramework is a build-time container of platform and architecture variants, not a runtime artifact. `whisper.xcframework` itself must not appear anywhere inside the final app. Xcode must select the matching macOS variant during link/embed.

Handle the selected product according to its Mach-O type:

- For a static whisper library, link its object code into the app executable. Do not copy the `.a`, a static `.framework` binary, headers, or the XCFramework container into `Contents/Frameworks`. There is no nested whisper binary to sign.
- For a dynamic framework or dylib, embed the selected runtime product under `MiniWhisper.app/Contents/Frameworks`, ensure its install name resolves through `@rpath`, and sign it before the outer app. Xcode's Embed & Sign/export machinery should do this.
- If a static framework carries resources, let modern Xcode perform its supported embedding behavior and inspect the exported bundle; do not invent a manual copy phase.

Apple's code-signing model is inside-out: all nested code must already be signed correctly before the outer signature records it. Prefer Xcode's export signing. If an explicit signing fallback is required, enumerate actual nested code, sign the deepest frameworks/dylibs/helpers first with the Developer ID Application identity, `--timestamp`, and `--options runtime`, then sign `MiniWhisper.app` last with only its app entitlements. Never use `codesign --deep` to repair or create signatures, and never apply the app's microphone/sandbox entitlements indiscriminately to libraries.

Before notarization, fail if any nested executable is unsigned or ad hoc signed. Inspect the exported app with `find`, `file`, `lipo -archs`, `otool -L`, `codesign -dv`, and `codesign -d --entitlements :-`. Also fail if a `.xcframework`, `.a`, development provisioning artifact, `get-task-allow=true`, or unexpected executable appears in the app.

## Packaging, notarization, stapling, and verification

Use this order. The order is part of the product; rearranging it produces a different artifact.

1. Verify the exported app's structure, versions, architectures, entitlements, Developer ID identity, secure timestamp, and nested signatures.
2. Create a submission ZIP with `/usr/bin/ditto -c -k --sequesterRsrc --keepParent MiniWhisper.app <submission.zip>`.
3. Submit that ZIP with `xcrun notarytool submit ... --wait` using the App Store Connect API key.
4. Require status `Accepted`. On any rejection or timeout, retrieve and retain `xcrun notarytool log <submission-id>` and publish nothing.
5. Run `xcrun stapler staple MiniWhisper.app`, then `xcrun stapler validate MiniWhisper.app`.
6. Recreate `MiniWhisper-MAJOR.MINOR.PATCH.zip` from the now-stapled app. Apple accepts ZIPs for notarization but cannot staple a ZIP; its official workflow says to staple each contained item and then create a new ZIP.
7. Extract the final ZIP to a clean directory and verify the extracted copy, not the working copy.
8. Calculate SHA-256 from the final ZIP. A checksum calculated before stapling is necessarily wrong for the published artifact.

Mandatory local checks on the extracted app are:

```text
codesign --verify --deep --strict --verbose=2 MiniWhisper.app
xcrun stapler validate MiniWhisper.app
syspolicy_check distribution MiniWhisper.app
spctl --assess --type execute --verbose=4 MiniWhisper.app
```

`syspolicy_check distribution` is Apple's preferred quick check on macOS 14 and later. Keep `spctl` as a supplementary signal and compatibility check; Apple DTS now calls it less accurate. Neither replaces a quarantined first-install test.

Stapling is mandatory here, not merely prudent. Apple's notary service also publishes the ticket online, but attaching it lets Gatekeeper validate the app when the controlled work environment cannot reach Apple's service. The final ZIP must contain the stapled app.

Do not publish a DMG for MVP. A ZIP is accepted by the notary service, preserves the app bundle when created with `ditto`, and is directly consumed by a Homebrew cask's `app "MiniWhisper.app"` stanza. A DMG becomes justified only for a designed drag-to-Applications experience or other presentation need outside Homebrew.

## GitHub release workflow and versioning

The release graph should be:

```text
vX.Y.Z tag
  -> CI
  -> resolve and validate version/build metadata
  -> archive and Developer ID export on macOS
  -> inspect and verify signatures
  -> ZIP submission, notarization, staple, final ZIP, final verification
  -> immutable GitHub release and checksum
  -> generate and push stable cask update
  -> tap CI audit/install/verify
```

Only `v*` tags should trigger MVP publication. Require an existing tag, make the GitHub release title/version match it, and never replace an asset for an already published stable tag. Use GitHub's built-in token with `contents: write` to create the release; no separate GitHub release token is required.

Do not copy GhosttyKit's push-to-main nightlies yet. If dogfooding later needs them, add a separate `mini-whisper@nightly` cask with unique immutable nightly release tags and checksums. Never make a stable cask URL point at a mutable asset.

## Homebrew cask and tap automation

Generate `Casks/mini-whisper.rb` only after the final GitHub asset exists. The cask should declare:

- token `mini-whisper`;
- stable version `X.Y.Z` and the SHA-256 of the final stapled ZIP;
- immutable GitHub release URL;
- `name "MiniWhisper"`, an accurate one-line description, and the repository homepage;
- `depends_on macos: :sonoma` for the app's macOS 14 deployment target;
- an architecture restriction only if the release is not universal;
- `app "MiniWhisper.app"`;
- no `auto_updates` stanza, because Homebrew is the updater;
- a stable-release livecheck or an explicit generated-release skip, following the tap's chosen policy;
- concise caveats for first launch and the three possible permission surfaces: Microphone, Input Monitoring, and Accessibility/PostEvent.

No installer script or postflight logic is needed. Homebrew's declarative `app` artifact moves the bundle to `/Applications`.

Follow GhosttyKit's tap update pattern: check out `thurstonsand/homebrew-tap` over SSH using the deploy key, render the cask deterministically, run `ruby -c`, commit only `Casks/mini-whisper.rb`, and push. Add workflow concurrency so two releases cannot race the tap branch. If the generated cask is already identical, exit without an empty commit.

Extend the tap's `Casks` CI rather than creating a disconnected validation path. It currently audits, installs, and runs only `wt`. The MiniWhisper path should:

1. run `brew audit --strict --online --cask thurstonsand/tap/mini-whisper`;
2. run `brew install --cask thurstonsand/tap/mini-whisper` on a compatible macOS runner;
3. verify `/Applications/MiniWhisper.app` has the expected bundle ID, version, architectures, Developer ID signature, stapled ticket, and Gatekeeper/distribution acceptance;
4. avoid launching permission-gated behavior in unattended CI; microphone and TCC behavior belongs in the fresh-machine validation matrix.

A tap CI failure after publication must block declaring the release complete. Because the GitHub asset is already immutable, fix the pipeline/cask and republish a new patch tag if the artifact itself is defective.

## Required repository secrets

Repository secrets are scoped. Their existence in GhosttyKit does not make them available to MiniWhisper unless they were configured at organization level. Inventory or copy these into the MiniWhisper repository:

| Secret                                    | Purpose                                                                      |
| ----------------------------------------- | ---------------------------------------------------------------------------- |
| `APPLE_CODESIGN_IDENTITY`                 | Exact `Developer ID Application: … (TEAMID)` identity                        |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64`   | Base64 `.p12` containing the certificate and private key                     |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the `.p12`                                                      |
| `APPLE_NOTARY_KEY`                        | Contents of the App Store Connect API `.p8` key                              |
| `APPLE_NOTARY_KEY_ID`                     | App Store Connect API key identifier                                         |
| `APPLE_NOTARY_ISSUER_ID`                  | App Store Connect issuer identifier                                          |
| `HOMEBREW_TAP_PRIVATE_KEY`                | Private half of the write-enabled deploy key for `thurstonsand/homebrew-tap` |

The existing tap deploy key can be reused if its public key already has write access and the matching private key is installed as the MiniWhisper repository secret. Do not copy GhosttyKit's unrelated mirror or package-registry secrets. Team ID `6JMB7W6NB4`, bundle ID, and release certificate name are configuration; only the exact identity is currently carried as a secret to match the proven workflow.

Validate all required secrets before an expensive build. Write the `.p8` to a runner-temporary file with mode `0600`, import the `.p12` into an ephemeral keychain through the proven Apple action, and rely on runner teardown for cleanup. Do not print certificate material, key contents, or passwords.

## First-install and upgrade validation

Command-line verification catches malformed artifacts. It does not prove the user's first run. Apple recommends a fresh machine, a download path that applies quarantine, and a restored VM snapshot between tests because Gatekeeper caches results.

### First stable release

Use a clean macOS 14-or-later VM that has never seen the bundle ID:

1. Install through the actual tap with `brew tap thurstonsand/tap` and `brew install --cask thurstonsand/tap/mini-whisper`; confirm the app lands at `/Applications/MiniWhisper.app`.
2. Launch it normally and confirm Gatekeeper accepts it without bypass instructions, the menu-bar item appears, and no Dock icon appears.
3. Exercise the right-Option path. Confirm the Input Monitoring request and denied-state guidance, grant it, relaunch if requested, and prove side-specific hold/release plus latch behavior in more than one frontmost app.
4. Exercise microphone capture. Confirm the usage string is accurate, denial is visible, and granting enables recording.
5. Exercise transcript delivery. Confirm the PostEvent request appears under Accessibility, denial preserves the transcript or reports failure, and granting enables pasteboard-plus-Command-V.
6. Repeat with the VM disconnected from the network after obtaining the quarantined final ZIP. The stapled app must still pass Gatekeeper and launch. This is the explicit offline-work-environment proof.
7. Inspect the installed app again; Homebrew must not alter its signature or staple.

Homebrew's downloader and quarantine behavior can change, so also perform Apple's canonical test at least once: download the published ZIP through Safari in a fresh VM, disconnect networking, unpack with Finder/Archive Utility, move the app to Applications, and launch it. `curl`, `scp`, `tar`, and `unzip` are not substitutes because they may not apply or propagate quarantine.

### Upgrade proof

Once two versions exist, validate the exact user journey:

1. Install version N and grant Microphone, ListenEvent, and PostEvent.
2. Record the installed app's bundle identifier, Team ID, designated requirement, entitlements, and TCC-visible behavior.
3. Publish the version N+1 cask update and run `brew upgrade --cask mini-whisper`.
4. Confirm the app was replaced cleanly, reports version N+1, and retains the same bundle identifier, Team ID, designated requirement shape, sandbox decision, and application path.
5. Quit and relaunch, then prove listening, recording, and delivery without repeat permission prompts.
6. Repeat signature, staple, `syspolicy_check`, and `spctl` checks on the upgraded installed app.

Stable TCC identity is a release invariant. Preserve `com.thurstonsand.MiniWhisper`, team `6JMB7W6NB4`, the Developer ID identity lineage, and the `/Applications/MiniWhisper.app` bundle shape. An upgrade that unexpectedly prompts for all permissions is a release failure even if the binary runs.

## Decisions still owned by the MVP design

This research supports the following recommendations, but the later grilling/spec ticket should record the product decisions:

- use listen-only `CGEventTap` and `CGEvent.post`, retaining App Sandbox after the signed installed-product proof;
- use clipboard-plus-Command-V rather than Apple Events or full Accessibility UI control;
- ship a universal app if whisper has both macOS slices, otherwise an explicitly arm64-only MVP;
- staple every stable app and prove offline Gatekeeper acceptance;
- publish stable tags and a stable cask only; defer nightly and in-app updates.

The engine/model decision must also determine whether user-selected file and network-client entitlements remain. Entitlements should follow implemented behavior, not anticipated features.

## Sources

### Apple

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — Developer ID, hardened runtime, secure timestamps, notarization tickets, and automation.
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) — accepted ZIP format, `notarytool`, stapling, and mandatory re-ZIP after stapling an app.
- [TN2206: macOS Code Signing In Depth](https://developer.apple.com/library/archive/technotes/tn2206/_index.html) — inside-out signing, standard nested-code locations, strict verification, and Gatekeeper checks.
- [Testing a Notarised Product](https://developer.apple.com/forums/thread/130560) — fresh quarantined VM testing, offline testing, `syspolicy_check`, and limitations of `spctl`.
- [Resolving Trusted Execution Problems](https://developer.apple.com/forums/thread/706442) — quarantine propagation and distribution diagnostics.
- [How to properly realize global hotkeys on macOS](https://developer.apple.com/forums/thread/735223) — Apple DTS statement that `CGEventTap` listening uses Input Monitoring and is sandbox-compatible from macOS 10.15.
- [Accessibility permission in sandboxed app](https://developer.apple.com/forums/thread/707680) — Apple DTS listen-only tap example and Input Monitoring distinction.
- [Accessibility Permission In Sandbox For Keyboard](https://developer.apple.com/forums/thread/789896) — Apple DTS statement that `CGEvent.post` uses sandbox-compatible PostEvent permission and appears under Accessibility.
- [AXIsProcessTrusted returns wrong value](https://developer.apple.com/forums/thread/727984) — ListenEvent, PostEvent, and full Accessibility distinction and reset names.
- [CGEvent tap creation](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29) — passive-listener versus active-filter API contract.
- [TN2435: Embedding Frameworks In An App](https://developer.apple.com/library/archive/technotes/tn2435/_index.html) and [Creating a static framework](https://developer.apple.com/documentation/xcode/creating-a-static-framework) — dynamic embedding and static-library handling.
- [Protected resources](https://developer.apple.com/documentation/bundleresources/protected-resources), [`NSMicrophoneUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription), and [`NSAppleEventsUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription) — documented plist privacy keys.

Apple Developer Forums are not API reference, but the cited answers are from Apple Developer Technical Support and directly address sandbox/TCC behavior omitted from the terse Core Graphics reference. The installed-product matrix above remains the proof requirement.

### Local proven machinery

- `/Users/thurstonsand/Develop/ghosttykit/.github/workflows/release.yml`
- `/Users/thurstonsand/Develop/ghosttykit/scripts/build-release-archive.sh`
- `/Users/thurstonsand/Develop/ghosttykit/docs/release.md`
- `/Users/thurstonsand/Develop/ghosttykit/docs/tcc-macos.md`
- `/Users/thurstonsand/Develop/homebrew-tap/Casks/wt.rb`
- `/Users/thurstonsand/Develop/homebrew-tap/.github/workflows/casks.yml`
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
