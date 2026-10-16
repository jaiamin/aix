# Handoff

## Done
- Swift package `aix` (macOS 26+): CLI, 3×3 cube spinner, confirm/run, pre-flight checks with automatic repair, fix-after-failure loop, deny list.
- Unit tests for `AixCore` (options, safety, shell tokenizer, prompt).
- Prompt tuned on the on-device model: worked examples, and commands generated before the explanation.

## Next
- Pick a GitHub owner/repo, tag v0.1.0, create the `homebrew-aix` tap from `packaging/homebrew/aix.rb`.
- Optional: an `fm`-CLI backend for Private Cloud Compute (needs `sudo fm license` per machine), or request the PCC managed entitlement.
- Optional: run read-only allowlisted commands without confirmation; `sandbox-exec` profile restricting writes to the cwd.

## Gotchas
- `PrivateCloudComputeLanguageModel.isAvailable` returns true without the entitlement, and then requests fail with ModelManagerError 1046. `auto` falls back to local on any non-content error.
- Model calls fail with ModelManagerError 1008 inside the Claude Code Bash sandbox. Run model tests unsandboxed.
- `swift build` and `swift test` need SwiftPM's own sandbox disabled when nested in another sandbox (`--disable-sandbox` in the Makefile).
- Custom adapters (`SystemLanguageModel.Adapter`) are obsoleted in macOS 27, so fine-tuning isn't an option.
