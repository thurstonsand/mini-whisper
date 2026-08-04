---
name: release
description: Coordinates MiniWhisper releases across GitHub archives and the Homebrew tap casks. Use when preparing, tagging, publishing, or verifying a MiniWhisper release.
---

# Release

Use this skill when preparing or publishing a MiniWhisper release.

## Release model

- Release from `main`.
- Push `main` before creating a stable tag so nightly artifacts publish first.
- Assume the release starts from a stable committed state. Do not repeat verification the user already performed.
- Do not push the stable tag until the user explicitly approves stable publishing.
- Stable releases are `vX.Y.Z` tags; release notes come from the matching `RELEASE.md` section.
- Binary nightly releases are unique prereleases named `nightly-<version>-nightly-<run>-<sha>`, using the latest stable version as their base.
- Stable tags are immutable. Never force-push a stable release tag.

## Release channels

One workflow (`.github/workflows/release.yml`) fans out into two surfaces:

| Surface                 | Trigger                     | Result                                                                                          |
| ----------------------- | --------------------------- | ----------------------------------------------------------------------------------------------- |
| GitHub release archives | `vX.Y.Z` tag or `main` push | Signed/notarized/stapled arm64 `MiniWhisper_<version>_darwin_arm64.zip`                         |
| Homebrew tap casks      | Same run                    | `thurstonsand/homebrew-tap` `Casks/mini-whisper.rb` (stable) or `Casks/mini-whisper-nightly.rb` |

A tag builds the Release configuration into `MiniWhisper.app`; a `main` push builds the Nightly configuration into `MiniWhisper Nightly.app`. They are separate apps with separate bundle identifiers, TCC grants, and application support directories, so both casks can be installed at once.

## 1. Inspect release state

```sh
git status --short
git log --oneline --decorate -10
git tag --list 'v*' --sort=-version:refname | head -10
gh run list --branch main --limit 10
```

If the working tree has unrelated changes, leave them alone. If release-relevant changes are uncommitted, ask whether they belong in the release before proceeding.

Inspect changes since the latest stable tag:

```sh
LATEST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*')"
git diff --stat "${LATEST_TAG}..HEAD"
git log --oneline "${LATEST_TAG}..HEAD"
```

Summarize user-facing features and fixes, packaging or workflow changes, and the likely semver bump. Ask the user to confirm the target version unless they already specified it.

## 2. Local validation (optional)

An unsigned local archive proves the build shape without CI:

```sh
RELEASE_VERSION=X.Y.Z scripts/build-release-archive.sh
```

This produces an unsigned `dist/MiniWhisper_X.Y.Z_darwin_arm64.zip` plus a `.sha256` sidecar. Signing and notarization run only in CI.

## 3. Push main and verify the nightly

```sh
git push origin main
gh run list --workflow Release --branch main --limit 6
gh run watch <release-run-id> --exit-status
```

Find the published nightly prerelease:

```sh
gh release list --exclude-drafts --limit 10 | rg '^nightly-'
```

The workflow pushes the generated nightly cask to `thurstonsand/homebrew-tap`, which triggers that repo's separate `Casks` workflow. The release workflow does not wait for that downstream audit — find the run for the exact generated tap commit and watch it too:

```sh
tap_sha=$(gh api "repos/thurstonsand/homebrew-tap/commits?path=Casks/mini-whisper-nightly.rb&per_page=1" --jq '.[0].sha')
tap_run_id=$(gh run list -R thurstonsand/homebrew-tap --workflow Casks --commit "${tap_sha}" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch -R thurstonsand/homebrew-tap "${tap_run_id}" --exit-status
```

Do not report the nightly as published until both workflows pass.

If the release needs hand-testing, stop here and ask the user to test (`brew install thurstonsand/tap/mini-whisper-nightly`) before tagging.

## 4. Create and push the stable tag

After the user approves stable publishing:

```sh
VERSION=X.Y.Z
git tag -a "v${VERSION}" -m "v${VERSION}"
git push origin "v${VERSION}"
```

Do not force-push a stable tag. If the tag already exists, stop and inspect; do not overwrite it.

## 5. Watch stable publishing

```sh
gh run list --workflow Release --limit 10 --json databaseId,headBranch,headSha,status,conclusion,event
gh run watch <release-run-id> --exit-status
```

The run creates the GitHub release with the matching `RELEASE.md` section and updates `Casks/mini-whisper.rb` in the tap. Watch the downstream tap audit for the stable cask commit:

```sh
tap_sha=$(gh api "repos/thurstonsand/homebrew-tap/commits?path=Casks/mini-whisper.rb&per_page=1" --jq '.[0].sha')
tap_run_id=$(gh run list -R thurstonsand/homebrew-tap --workflow Casks --commit "${tap_sha}" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch -R thurstonsand/homebrew-tap "${tap_run_id}" --exit-status
```

Do not report the stable release as published until both workflows pass.

## 6. Verify the install

```sh
brew update
brew install thurstonsand/tap/mini-whisper
```

Confirm the installed app launches, passes Gatekeeper (`spctl -a -vv /Applications/MiniWhisper.app`), and reports the released version in the About panel. The nightly cask installs `/Applications/MiniWhisper Nightly.app` and is verified the same way.
