---
status: closed
type: research
claimed: subagent:native-endpoints-research
blocked-by: []
---

# Native LLM endpoints: Anthropic, OpenAI Responses, and subscription auth

## Question

The cleanup client speaks OpenAI-compatible chat completions today. Establish what supporting native endpoints would cost and buy:

1. **OpenAI Responses API** — is it actually more performant than chat completions for a small bounded completion (TTFT, latency)? What changes in the request/response shape?
2. **Anthropic Messages API** — shape, auth, and whether first-party access beats an OpenAI-compat gateway for latency on small models (Haiku-class).
3. **Swift SDKs** — official or credible community SDKs for both (and their allowlist plausibility), versus hand-rolling the two request shapes over URLSession, which the app can already do.
4. **Subscription auth** — "login with ChatGPT"/Claude subscription OAuth as pi supports: is there a sanctioned or de-facto flow an app like this can use (device auth, OAuth client), what are its ToS boundaries, and what do open-source tools that do this actually implement?

Findings to `../assets/40-native-llm-endpoints.md`, primary sources cited; recommend, don't decide.

## Resolution

The endpoint, SDK, and subscription-auth findings are in [the native-endpoints research asset](../assets/40-native-llm-endpoints.md). It recommends retaining the sanctioned OpenAI-compatible Chat Completions `URLSession` baseline: public primary sources provide no Responses latency advantage for this tiny blocking completion; native Anthropic remains conditional on egress approval and a real A/B latency win; SDKs add unallowlisted supply-chain surface; and subscription authentication is excluded (explicitly forbidden by Anthropic for third-party products and not published by OpenAI as a general third-party subscription API).
