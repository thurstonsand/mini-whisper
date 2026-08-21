---
status: open
type: grilling
blocked-by: [18]
---

# Cleanup endpoints: persist the listing, and maybe keep more than one

## Question

The model listing is in-memory only. `CleanupFeature.State.listing` starts at `.notLoaded` on every launch and `init` sets `modelChoice = .custom`, so a configured, working endpoint comes back from a restart displaying `Custom…` with a Model ID row under it — technically honest (nothing was chosen from a list that does not exist), and it reads as unconfigured. Load Models is a button the user presses again for information the app already had.

The minimum is that the list of models an endpoint offered survives a relaunch, and manual reload stays for the case where the endpoint gained a model worth trying. Beyond that:

- **Where the listing lives.** It is derived data — an endpoint's answer, not the user's choice. `settings.json` is the user's file and human-editable; a cache of forty model ids per endpoint may not belong in it. Its own file in the channel's application support directory, keyed by endpoint, is the alternative. Whichever it is, a listing must be attributed to the endpoint that produced it, or switching endpoints shows the wrong menu.
- **Freshness.** Persistence makes staleness possible: the pane can refetch quietly when it opens or when an endpoint becomes active, and fall back to what it remembers when the fetch fails. Decide whether the quiet refetch exists at all, or whether remembered-until-reloaded is the whole contract.
- **Profiles.** The endpoint surface is one slot: one address, one key, one model. Switching from Cerebras to Groq means finding credentials again for something the app already knew. Saved endpoints — name, address, model listing, chosen model, key — turn that into a picker. This is the part that earns the ticket.
- **Keys.** Today one Keychain item, `cleanupAPIKey`. Profiles need a per-profile account, deletion when a profile is deleted, and an answer for what happens to the existing single item on upgrade.
- **Relationship to [presets](39-recommended-cleanup-providers.md).** A preset is a factory endpoint; a profile is a user's. If they are the same type with different provenance, the two tickets are one surface and should be designed together — that is the first thing to settle.
- **What the pane becomes.** A picker over saved endpoints changes the Endpoint section's shape: what Save means when there are many, whether switching is immediate or needs confirmation, where Delete lives, and whether the cursor grammar gains a row kind.

Output: a decided endpoint surface — at minimum a persisted listing, at most a profile store folded into the presets design — and the storage location for data the user did not type.

## Scope addition (2026-08-20, user, post corpus round 2)

A profile owns more than credentials: it owns the **vocabulary strategy**. The corpus's dictionary three-way (four models, ten arms — [results](../assets/43-dictation-corpus/results/dictionary-three-way/)) showed that when an LLM cleanup runs, the recognition sidecar is strictly harmful — every model bites more traps on boosted input and recovers zero additional terms; the DICTIONARY block alone reaches 18/18 recall with 0 traps on gemini. So: **online profiles suppress the sidecar and stage vocabulary in the prompt**. The exception is the offline profile — s1-mini has no prompt surface and no dictionary, and the sidecar is its only vocabulary story; the hypothesis that sidecar+s1-mini shore up each other's weaknesses (boost supplies the terms, s1-mini the cleanup) is untested and worth one corpus run before this design lands. Suppression is decided per-profile, not globally — that is why it lives here and not as a standalone change.

The user's working profile taxonomy (2026-08-20, to be confirmed by round-3 measurements): (1) best speed-to-accuracy online — Parakeet + no sidecar + gpt-oss-120b on Cerebras, unless a hosted ASR beats Parakeet; (2) best accuracy — best-measured engine + no sidecar + gemini (or haiku if the speed trade is worth it); (3) best offline — Parakeet + sidecar + s1-mini. Each profile gets its own prompt tuning pass ([ticket 48](48-prompt-eval-automation.md)).

Round 3 answered the taxonomy from measurement ([results/profiles-recommendation.md](../assets/43-dictation-corpus/results/profiles-recommendation.md)): speed = Parakeet + DICTIONARY block + gpt-oss-120b (15/27 @ 420 ms; haiku at 17/27 @ 696 ms is the arguable swap); accuracy = Scribe v2 + keyterms+DICTIONARY + gemini direct (21/27 @ 2443 ms, Scribe+haiku 19/27 @ 1313 ms the value point); offline = Parakeet + sidecar + s1-mini, uncontested. Two design facts the grilling must carry: ASR-level vocabulary conditioning bites zero traps on whisper (+3 ms local) — the sidecar's failure mode is absent when the terms enter the decoder that reads the sentence — so where vocabulary lives is an engine property; and a hosted engine ships audio off-machine, a distinct consent from shipping transcripts, which the profile UI must say out loud. Crosses still unmeasured: sidecar+s1-mini, whisper-prompt+s1-mini (offline vocabulary at zero trap cost), Scribe keyterms stacked with the DICTIONARY block.
