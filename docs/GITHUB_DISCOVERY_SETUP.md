# GitHub discovery setup

This file contains the one-time repository settings that cannot be committed as
source files. Apply them after the repository becomes public.

## Repository About

**Description**

> Open-source macOS control plane for verified Codex and local-LLM agent loops,
> dependency-aware multi-agent graphs, and adaptive watchers.

**Website**

> https://godicewang.github.io/LoopForge/

**Topics** (15 of GitHub's 20-topic maximum)

```text
agent-loop
autonomous-agents
coding-agent
ai-coding
codex
codex-cli
multi-agent-systems
agent-orchestration
local-llm
ollama
macos
swift
developer-tools
workflow-automation
ai-agents
```

Use the prepared `docs/assets/social-preview.png` as the repository social
preview. It is the recommended 1280 × 640 pixels and is under 1 MB.

## GitHub Pages

In **Settings → Pages → Build and deployment**, choose **GitHub Actions**. The
committed `Pages` workflow publishes the static `docs` directory to:

> https://godicewang.github.io/LoopForge/

After the first successful deployment, verify:

- `/LoopForge/`
- `/LoopForge/robots.txt`
- `/LoopForge/sitemap.xml`
- `/LoopForge/llms.txt`
- `/LoopForge/examples/completion-report/`

## Search registration

After Pages is live:

1. Add the site to Google Search Console and Bing Webmaster Tools.
2. Submit `https://godicewang.github.io/LoopForge/sitemap.xml`.
3. Request indexing for the home page after significant releases.
4. Do not manufacture backlinks, reviews, download counts, or keyword variants.

The committed crawler policy explicitly permits OAI-SearchBot. With the default
project Pages URL, crawler policy is read from the origin root
(`https://godicewang.github.io/robots.txt`), not the `/LoopForge/` subpath, so
verify that the account-level file does not block it. If a custom domain points
directly at this site, the committed `robots.txt` becomes the root policy.

`llms.txt` is an additive, experimental machine-readable synopsis; it does not
replace crawlable HTML, a sitemap, or structured data, and no ranking benefit is
claimed for it.

## Launch assets

Use the same canonical positioning everywhere:

> Autonomous coding that stays observable, recoverable, and verified.

Use the prepared social preview instead of inventing a new screenshot per
channel. Link launch posts to the GitHub repository for Star conversion, and
link documentation searches to the Pages site for question-level discovery.

Recommended release surfaces, only where community rules allow:

- GitHub Release and the maintainer's pinned profile repository
- Hacker News `Show HN`
- Product Hunt
- relevant macOS, Swift, local-LLM, and coding-agent communities
- a short engineering post showing one failed direct run and the evidence
  LoopForge used to recover it

The product claim should stay measurable. Use the release validation results,
real screenshots, known limitations, and reproducible commands already in the
repository. Never promise a Star count or imply affiliation with OpenAI.
