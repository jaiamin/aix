# Handoff

## Done
- CLI: `aix <request>` (or `aix` to type it), one-key confirm (y run · r refine · c copy), fix-after-failure, `-n`, `-y`.
- On-device model only. Private Cloud Compute needs Apple's managed entitlement; without it requests fail with ModelManagerError 1046.
- Prompt: machine facts + 2-level file tree (relative paths only) + the 10 library examples most related to the request.
- Safety: deny list, blocks reading and overwriting the same file, names what a command deletes/moves/overwrites/pushes.
- Homebrew tap `jaiamin/homebrew-aix` installs the release binary.

## Eval (on-device AFM 3 Core, Oct 2026)
- Never-seen requests ~55% right, common tasks ~80%, average 1.8s.
- Harness was a scratch script: run `aix -n` over a list of requests in a fixture folder, then run each plan in a `sandbox-exec` copy.

## Next
- Grow `Sources/AixCore/Examples.swift` from real failures; it's the biggest quality lever.
- Optional: PCC backend if Apple grants the entitlement.

## Gotchas
- Avoid backslashes and double quotes in examples: the model must escape them in JSON and often derails.
- The model copies examples literally; destructive examples get matched on surface words. Keep them few.
- Model calls fail (ModelManagerError 1008) inside the Claude Code sandbox; run evals unsandboxed.
- Release: `make dist`, upload the tarball to the GitHub release, update version + sha256 in the tap's Formula/aix.rb.
