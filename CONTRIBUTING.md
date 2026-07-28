# Contributing to LoopForge

Thank you for helping make long-running Agent work safer and more observable.
Small, focused changes with reproducible evidence are the easiest to review.

## Before opening a change

1. Search existing issues and discussions.
2. For substantial behavior changes, open a proposal before implementation.
3. Never include API keys, Codex credentials, task databases, model weights, or
   private project output.

## Local development

LoopForge requires Apple Silicon, macOS 14 or later, and Xcode Command Line
Tools.

```bash
git clone https://github.com/godicewang/LoopForge.git
cd LoopForge
swift test
swift build -c release -Xswiftc -warnings-as-errors
```

Run `zsh Scripts/bootstrap_vendor.sh` only when you need to build the complete
application bundle. It downloads pinned official runtimes and verifies their
SHA-256 checksums.

## Pull requests

- Keep one concern per pull request.
- Add or update regression tests for behavior changes.
- Preserve crash recovery, bounded resource use, and honest active-time
  accounting.
- Include exact commands and outcomes. UI changes should include a current
  screenshot with personal paths and secrets removed.
- Update both `README.md` and `README.zh-CN.md` when public behavior changes.

By contributing, you agree that your contribution is licensed under Apache-2.0.
