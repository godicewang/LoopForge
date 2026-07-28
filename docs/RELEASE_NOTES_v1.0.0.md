# LoopForge 1.0.0

LoopForge turns an outcome into supervised, recoverable Agent work on macOS.
Version 1.0 ships three production workflows:

- **Single Loop** for builds, repairs, optimization, experiments, and evidence-led
  iteration with an editable active-runtime target.
- **Auto Graph** for dependency-gated parallel work, isolated Git worktrees,
  incremental join-group review, retained branch history, and final integration.
- **Continuum Watcher** for long-lived monitoring and batch pipelines that wake
  intelligence only for anomalies, review, adaptation, or completion.

## Release evidence

- 17 comprehensive scenarios across two independent passes.
- 206 tests executed with 0 failures.
- Real process, Git worktree, AppKit screenshot, checkpoint recovery, timeout,
  pressure, cardinality, stale-data, and workspace-boundary coverage.
- Pinned, checksum-verified Codex `0.145.0-alpha.30` and Ollama `0.32.0`.
- No bundled model weights.

## Requirements

- Apple Silicon
- macOS 14 or later
- Existing Codex/ChatGPT sign-in for official Codex mode

The community binary is ad-hoc signed and not notarized. On first launch,
Control-click **LoopForge.app** and choose **Open** if Gatekeeper requests it.
Developer ID signing and notarization require the publisher's Apple credentials.

See [release validation](RELEASE_VALIDATION.md) and the
[security model](../SECURITY.md) for full details.
