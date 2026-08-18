# Native LLM endpoints: what they buy for cleanup

Research checked 2026-08-17. This is a recommendation for the later design session, not an endpoint decision. It evaluates a single, blocking text cleanup request: a few hundred bounded input tokens, a much smaller output, no tools, no conversation continuation, and raw fallback on timeout/error.[^ticket-18] The installed work artifact may use only controlled-network, OpenAI-compatible egress and the existing dependency allowlist, so a technically better direct integration is not deployable merely because its public API exists.[^map]

## Recommendation

Keep the OpenAI-compatible **Chat Completions over `URLSession`** contract as the shipped baseline. It is already the sanctioned network shape, it fits the one-turn completion exactly, and it adds no dependency. Do not add Responses, native Anthropic, an SDK, or subscription login to the cleanup scope now.

Design the client boundary so a future _explicitly approved_ provider kind can add one small native request/response adapter. The only native adapter worth considering after that approval is Anthropic Messages with a Console API key, and only if a real same-prompt, same-model, same-network benchmark beats the sanctioned gateway on final wall clock and tail latency. Do not infer that result from either vendor's API branding or streaming support: there is no primary-source A/B TTFT result for this workload.[^openai-migration][^anthropic-overview]

The practical evaluation order is:

1. Measure the sanctioned gateway first, using the existing bounded harness and target models. Its network path and queueing are what the user will feel.[^benchmark]
2. If corporate review admits direct Anthropic egress and a Console key, measure Messages against the gateway with identical prompt, `max_tokens`, model family, cold-ish first call, and repeated calls. Record first byte/first token when streaming and final-body wall clock/p95; the blocking delivery path needs the latter.
3. Only implement a native adapter after that test demonstrates a material win and dependency/auth approval exists. A one-request endpoint-specific adapter is smaller and more auditable than importing a general agent SDK.

## OpenAI: Responses versus Chat Completions

### No demonstrated latency win

OpenAI recommends Responses for new projects because it is a newer primitive with agentic tools, state, and other features; its stated “better performance” example is a 3% **SWE-bench intelligence** improvement for reasoning models, not TTFT or request wall clock.[^openai-migration] OpenAI's latency guide attributes latency chiefly to generated-token count and model processing, recommends smaller/faster models and shorter output, and does not present an endpoint comparison.[^openai-latency] Both endpoint references expose request-level `service_tier` controls, including fast/priority where the account and model support them.[^openai-chat][^openai-responses]

So the primary sources do **not** establish a Responses latency advantage for MiniWhisper's tiny, single-turn cleanup. A direct controlled A/B is the only evidence that could justify changing the user-visible blocking path. Responses can be preferable for a different product requirement, but its distinctive capabilities—tool loops, hosted tools, multimodal items, and persistent conversation state—are unused here.[^openai-migration]

### Shape delta

| Concern                    | Chat Completions (current contract)                                   | Responses                                                                                |
| -------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| URL                        | `POST /v1/chat/completions`                                           | `POST /v1/responses`                                                                     |
| Simple input               | `messages`: system/developer and user messages                        | top-level `instructions` plus `input` string, or typed input items                       |
| Output to extract          | `choices[0].message.content`                                          | text blocks inside typed `output` items; official SDKs provide `output_text` convenience |
| Output limit/config schema | chat parameters such as `max_completion_tokens` and `response_format` | Responses parameters such as `max_output_tokens` and `text.format`                       |
| State                      | caller resends its bounded messages                                   | caller may resend items, use `previous_response_id`, or use Conversations                |
| Storage                    | configured with `store`; do not rely on a default                     | configured with `store`; do not rely on a default                                        |

The mappings and output differences are OpenAI's own migration guidance; the exact available parameters remain model-dependent, so the cleanup adapter should use the smallest portable subset and assert a nonempty final text result.[^openai-migration][^openai-chat][^openai-responses] For this client, Responses would replace one small Codable body/decoder with another, but would not remove any meaningful work: prompt construction, timeouts, cancellation, error classification, and raw fallback still belong to MiniWhisper.

One additional compatibility concern: “OpenAI-compatible” does not promise `/v1/responses`. The provider benchmark intentionally uses the portable chat-completions subset because the gateway/provider menu contains compatibility differences.[^benchmark] Keep Chat Completions as the custom-endpoint protocol even if a future direct OpenAI choice exposes Responses separately.

## Anthropic: native Messages

### Wire shape and API-key authentication

Anthropic's first-party conversation endpoint is `POST https://api.anthropic.com/v1/messages`. A basic cleanup request requires `model`, `max_tokens`, and `messages`; `system` is a separate top-level field rather than a system message in the message array. Each message has a `user` or `assistant` role and string or typed-block `content`.[^anthropic-messages]

```json
{
  "model": "<approved Haiku-class model ID>",
  "max_tokens": 128,
  "system": "<cleanup rules>",
  "messages": [
    { "role": "user", "content": "<bounded transcript and field context>" }
  ]
}
```

The API-key request headers are `x-api-key`, `anthropic-version: 2023-06-01`, and `content-type: application/json`; the API returns a message object whose `content` is typed blocks, so this client must select and concatenate only text blocks, then honor `stop_reason` and usage/error fields.[^anthropic-overview][^anthropic-messages] API keys are provisioned in Claude Console; API billing and a Claude consumer subscription are separate products.[^anthropic-overview][^anthropic-legal]

Anthropic also supplies an OpenAI-SDK compatibility layer at `https://api.anthropic.com/v1/`, but says it is for testing/comparing capabilities rather than a long-term production solution. It documents semantic gaps including system/developer-message hoisting, unsupported prompt caching, and silently ignored fields.[^anthropic-openai-compat] That is an argument for native Messages if direct Anthropic ever becomes an approved production choice—not an argument to send MiniWhisper directly today.

### Would first-party be faster than the gateway?

Anthropic says its direct API gives direct access to latest models/features, while partner platforms can differ in feature timing and are selected partly for compliance and consolidated billing.[^anthropic-overview] It publishes no direct-versus-OpenAI-compatible-gateway TTFT or final-latency guarantee in the cited API material. A direct request may remove a translation/proxy hop, but the actual gateway may instead have a better controlled route, connection reuse, capacity tier, or proximity. Those are deployment facts, not API semantics.

Under the current project constraint, first-party Messages additionally requires unsanctioned direct egress and a new credential/billing arrangement. It cannot be treated as a latency optimization until those controls approve it and the required measurement wins. The current controlled gateway remains the appropriate Haiku-class route if it fronts Haiku; ask its operator which native model/region/priority path sits behind the compatible endpoint, then benchmark that path.[^map][^benchmark]

## Swift client choice

### What exists

There is no official Swift SDK from either vendor in the current official SDK lists. OpenAI lists official JavaScript, Python, C#, Java, Go, and Ruby SDKs, then lists Swift clients—including MacPaw/OpenAI—as **community** libraries that OpenAI does not verify for correctness or security.[^openai-sdks] Anthropic lists official Python, TypeScript, C#, Go, Java, PHP, and Ruby client SDKs; Swift is absent.[^anthropic-sdks]

| Candidate                                      | Evidence of health/function                                                                                                                                                                                                                                                                          | Allowlist assessment for this app                                                                                                                                                              |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`URLSession` + Codable (current direction)** | Apple framework already allowed; `TranscriptCleanup` currently declares no package dependencies.[^cleanup-package]                                                                                                                                                                                   | Strongest: no new vendor or transitive dependency, direct control over bounded request/response parsing, URLSession timeout/cancellation, and the corporate gateway shape.                     |
| **MacPaw/OpenAI**                              | OpenAI itself lists it as a Swift community library. Its repository describes OpenAI-compatible support and both Chat Completions and Responses; it is MIT-licensed and its releases show 43 releases, including a recent 0.5.1 with Responses work.[^openai-sdks][^macpaw-readme][^macpaw-releases] | The credible general OpenAI Swift choice if an exception is granted, but still third-party and unnecessary for one bounded request. It cannot make an unsupported gateway endpoint compatible. |
| **fumito-ito/AnthropicSwiftSDK**               | An Apache-2.0 community package with 22 tagged releases; its repository calls itself “yet another” Anthropic API client, rather than an Anthropic offering.[^anthropic-swift][^anthropic-swift-releases]                                                                                             | Plausible community prior art, but not a stronger allowlist case than a ~one-shape `URLSession` adapter. No official Swift SDK exists to justify the added supply-chain surface.               |
| **A multi-provider/agent SDK**                 | The vendor SDK pages focus on general Messages/Responses clients and agent tooling, which manage tools, streaming, retries, pagination, and more than cleanup needs.[^openai-sdks][^anthropic-sdks]                                                                                                  | Reject for this scope: additional surface area without reducing the endpoint-specific semantics MiniWhisper must own.                                                                          |

For this particular non-streamed, token-bounded call, hand-rolling two shapes is modest: an authenticated `URLRequest`, an `Encodable` request, a `Decodable` success/error envelope, and an explicit extraction/validation function per native protocol. It is _less_ code and risk than integrating an SDK designed to abstract entire expanding APIs. Keep a shared internal cleanup result and transport/timeout policy; isolate only `OpenAIChatCompletionsAdapter`, future `OpenAIResponsesAdapter`, and future `AnthropicMessagesAdapter` request/response mapping. This is a recommendation based on the project's existing zero-dependency package and allowlist, not a claim that SDKs are inherently poor.[^cleanup-package][^map]

## Subscription authentication: product boundary, not a credential feature

### ChatGPT / Codex

OpenAI officially documents ChatGPT sign-in and browser/device-code flows for the **ChatGPT desktop app, Codex CLI, and Codex IDE extension**. The headless Codex CLI device-code flow is beta and must be enabled in ChatGPT account/workspace settings.[^openai-codex-auth] It also states that general OpenAI API calls should use Platform API keys; even its enterprise Codex access tokens are for trusted Codex local workflows, while API keys remain the route for general API calls.[^openai-codex-auth]

Pi's readable source shows how third-party coding tools reproduce the Codex flow. It uses the Codex public client ID `app_EMoamEEZ73f0CkXaXp7hrann`, browser authorization at `auth.openai.com/oauth/authorize`, a localhost PKCE callback on port 1455, scope `openid profile email offline_access`, token refresh, and a device-code variant at `/codex/device` / `api/accounts/deviceauth/*`.[^pi-openai-oauth] The official open-source Codex repository likewise has separate PKCE, callback-server, and device-code login modules.[^codex-source]

That describes a working implementation, **not** a published “Login with ChatGPT for arbitrary third-party applications” grant. OpenAI's public documentation scopes the subscription sign-in surface to its named Codex clients and directs general API calls to API keys; it does not publish an independent third-party client-registration or subscription-API contract in the cited material.[^openai-codex-auth] Treat the technique as dependency on an undocumented/product-bound client flow with revocation and corporate-review risk, not as a credential option for MiniWhisper. In particular, do not embed the Codex client ID or route dictation through the ChatGPT Codex backend.

### Claude subscriptions

The boundary is explicit for Anthropic. Its Claude Code legal page says OAuth is exclusively for Free/Pro/Max/Team/Enterprise purchasers' ordinary use of Claude Code and other native Anthropic apps; developers building products/services must use Console API keys or a supported cloud provider. It expressly forbids third-party developers from offering Claude.ai login or routing requests through Free/Pro/Max credentials, and reserves enforcement without notice.[^anthropic-legal]

Pi's source illustrates why a seemingly normal OAuth implementation is not a MiniWhisper option: it performs PKCE against `claude.ai/oauth/authorize` and `platform.claude.com/v1/oauth/token` using client ID `9d1c250a-e61b-44d9-88ed-5944d1962f5e`, asks for Claude-Code-specific scopes, then sends Claude-Code identity/beta headers and a Claude Code system identity when it sees the subscription-token form.[^pi-anthropic-oauth][^pi-anthropic-identity] Those observed details are useful for understanding tools such as pi; they are not a license to copy them. Anthropic's published policy rules MiniWhisper's “log in with Claude” out.

### Learn from, do not ship

Useful readable sources are OpenAI's own [`openai/codex`](https://github.com/openai/codex/tree/main/codex-rs/login/src) login implementation and this machine's pinned Pi source for both Codex and Claude flows.[^codex-source][^pi-openai-oauth][^pi-anthropic-oauth] They demonstrate PKCE, state validation, local callback handling, device-code polling, refresh-token storage, and credential sensitivity. They do not substitute for vendor permission, a registered client, egress review, storage review, or an API billing relationship. No subscription OAuth belongs in the cleanup provider menu.

## Decision-session inputs

- **Keep as the default:** the custom OpenAI-compatible Chat Completions endpoint/key/model and the existing measured harness. This preserves the corporate gateway and lets ticket 39 retain Custom even if native providers are ever curated.[^map][^ticket-39]
- **If native Anthropic is proposed:** require written egress/credential approval and a benchmark showing an end-to-end median _and p95_ improvement versus the gateway at the same cleanup quality. Use API-key Messages, not Claude subscription OAuth.[^anthropic-overview][^anthropic-legal]
- **If native OpenAI Responses is proposed:** require the same benchmark and an actual need for Responses-only functionality. “Responses is recommended for new projects” is not latency evidence for this single text completion.[^openai-migration][^openai-latency]
- **SDK gate:** `URLSession` is the recommended default. A later exception should document the exact SDK version, transitive dependency/license review, gateway compatibility smoke test, and why the small adapter is inadequate.[^openai-sdks][^anthropic-sdks]
- **Subscription-auth gate:** exclude it. Anthropic forbids the proposed third-party usage; OpenAI's official docs support Codex clients but provide no public third-party subscription-API contract and direct general API use to Platform keys.[^anthropic-legal][^openai-codex-auth]

[^ticket-18]: [Ticket 18: LLM cleanup pass](../tickets/18-llm-cleanup.md).

[^map]: [Wayfinding map: hard constraints and fixed points](../map.md).

[^benchmark]: [Ticket 38 benchmark findings](38-cleanup-model-benchmark.md).

[^cleanup-package]: [`Packages/TranscriptCleanup/Package.swift`](../../../../Packages/TranscriptCleanup/Package.swift).

[^ticket-39]: [Ticket 39: Recommended cleanup providers](../tickets/39-recommended-cleanup-providers.md).

[^openai-migration]: OpenAI, [Migrate to the Responses API](https://developers.openai.com/api/docs/guides/migrate-to-responses).

[^openai-latency]: OpenAI, [Latency optimization](https://developers.openai.com/api/docs/guides/latency-optimization).

[^openai-chat]: OpenAI, [Create chat completion API reference](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create).

[^openai-responses]: OpenAI, [Create a model response API reference](https://developers.openai.com/api/reference/resources/responses/methods/create).

[^anthropic-overview]: Anthropic, [Claude API overview](https://platform.claude.com/docs/en/api/overview).

[^anthropic-messages]: Anthropic, [Create a Message API reference](https://platform.claude.com/docs/en/api/messages/create).

[^anthropic-openai-compat]: Anthropic, [OpenAI SDK compatibility](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk).

[^openai-sdks]: OpenAI, [SDKs and CLI](https://developers.openai.com/api/docs/libraries).

[^anthropic-sdks]: Anthropic, [CLI, SDKs, and libraries](https://platform.claude.com/docs/en/cli-sdks-libraries/overview).

[^macpaw-readme]: MacPaw/OpenAI, [repository README](https://github.com/MacPaw/OpenAI).

[^macpaw-releases]: MacPaw/OpenAI, [release history](https://github.com/MacPaw/OpenAI/releases).

[^anthropic-swift]: fumito-ito/AnthropicSwiftSDK, [repository README](https://github.com/fumito-ito/AnthropicSwiftSDK).

[^anthropic-swift-releases]: fumito-ito/AnthropicSwiftSDK, [release history](https://github.com/fumito-ito/AnthropicSwiftSDK/releases).

[^openai-codex-auth]: OpenAI, [Codex authentication](https://developers.openai.com/codex/auth).

[^anthropic-legal]: Anthropic, [Claude Code legal and compliance: Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance).

[^codex-source]: OpenAI, [`openai/codex` login source directory](https://github.com/openai/codex/tree/main/codex-rs/login/src).

[^pi-openai-oauth]: Local primary implementation: [`openai-codex.ts` lines 26–38, 191–263, 293–311, 427–543](file:///Users/thurstonsand/.cache/pi-source/v0.84.2/packages/ai/src/auth/oauth/openai-codex.ts).

[^pi-anthropic-oauth]: Local primary implementation: [`anthropic.ts` lines 28–37, 190–255, 314–363](file:///Users/thurstonsand/.cache/pi-source/v0.84.2/packages/ai/src/auth/oauth/anthropic.ts).

[^pi-anthropic-identity]: Local primary implementation: [`anthropic-messages.ts` lines 858–928 and 993–1008](file:///Users/thurstonsand/.cache/pi-source/v0.84.2/packages/ai/src/api/anthropic-messages.ts).
