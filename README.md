# aix

Turn a plain-English request into shell commands using Apple Intelligence. It runs on your Mac and needs no API key.

```
$ aix find the 5 largest files here
■ Generating 1.8s

  The command finds all regular files here and lists the five largest.

  $ find . -type f -exec du -s {} + | sort -nr | head -5

Run? [y/N]
```

## Install

Requires an Apple silicon Mac on macOS 26+ with Apple Intelligence turned on.

```sh
git clone https://github.com/OWNER/aix && cd aix
make install            # builds and copies to ~/.local/bin (PREFIX=/usr/local to change)
```

## Usage

```
aix [options] <request...>
aix [options] -p "<request>"

  -y, --yes          run without asking
  -n, --dry-run      show the commands, don't run them
  -m, --model NAME   auto | local | cloud   (default: $AIX_MODEL or auto)
```

**Quoting tip:** zsh treats `?` and `*` as globs before aix sees them, so `aix what's my ip?` breaks. Either quote the request (`aix -p "what's my ip?"`) or add `alias aix='noglob aix'` to `~/.zshrc`. The alias handles `?` and `*`, but apostrophes still need quotes.

## How it works

1. **Context.** The instructions include your macOS version, shell, current/parent/home folders and the current folder's listing. They also include eight worked macOS examples, because a small model copies examples far more reliably than it follows rules.
2. **Structured output.** The model fills a `@Generable` `Plan { commands, explanation }`. It writes the commands *first*. When the explanation came first, the on-device model talked itself into refusing doable requests.
3. **Pre-flight checks.** Every plan goes through `$SHELL -n` (syntax) and `command -v` (each program exists). If a check fails, the errors go back to the model, up to 2 automatic repairs.
4. **Deny list.** `sudo`, recursive deletes of `/`, `~` or system folders, `dd` to disks, `curl | sh` and similar patterns are blocked outright.
5. **Confirm, then run.** The commands run as one `set -e` script in your shell, so `cd` carries over. If they fail, aix offers to send the error output back to the model for a fix (up to 2 times).

The deny list catches accidents, not attackers: `python -c`, `find -delete` on an odd path and base64 tricks get past it. The `[y/N]` prompt is the real safety gate, so read the plan before you press `y`.

## Models

| `-m` | Model | Speed | Notes |
|---|---|---|---|
| `local` | On-device `SystemLanguageModel` (AFM 3 Core, ~3B) | ~1.2–3 s | Offline, private, no quota. Your Mac determines the variant (`core3` or `coreAdvanced3`); apps can't choose it. |
| `cloud` | `PrivateCloudComputeLanguageModel` | — | Larger model with reasoning and a 32K context. **Requires Apple's managed entitlement `com.apple.developer.private-cloud-compute`.** Without it, `isAvailable` still returns `true`, but every request fails with `ModelManagerError 1046`. |
| `auto` | cloud, then local | | Falls back to on-device on any cloud error. Today it always ends up on-device. |

## Distributing

| Route | Effort | What users do |
|---|---|---|
| **Homebrew tap** (recommended) | Create a `homebrew-aix` repo containing [`packaging/homebrew/aix.rb`](packaging/homebrew/aix.rb), then fill in the sha256 for each release tag. | `brew install OWNER/aix/aix` |
| From source | Nothing | `git clone … && make install` |
| Release binary | `make dist`, then sign with a Developer ID, notarize (`xcrun notarytool submit`) and upload to GitHub Releases | download and put it on `PATH` |

Without notarization, Gatekeeper blocks a downloaded binary. Homebrew builds the formula from source, which sidesteps this. It does require the macOS 26+ Command Line Tools on the user's Mac.

To ship with the **cloud** model, request the PCC managed entitlement from Apple. You then have to ship aix code-signed with a provisioning profile, which in practice means a small `.app` bundle with the CLI symlinked onto `PATH`. This path is untested here.

## Development

```sh
make test      # unit tests for parsing, safety and prompt building (no model needed)
make build
.build/release/aix -n "your request"
```
