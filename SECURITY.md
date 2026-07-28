# LoopForge security model

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use the
repository's **Security → Report a vulnerability** private advisory form and
include the affected version, impact, reproduction, and any proposed
mitigation. Remove credentials and unrelated user data from evidence.

Maintainers will acknowledge a valid report as soon as practical, keep the
report private while a fix is prepared, and publish coordinated release notes
after affected users can upgrade. This community project does not promise a
fixed service-level response time.

## Runtime boundaries

- Both agents default to **Full Access**: the Codex harness receives `danger-full-access` and `approval_policy=never`, so it can read, write, execute, and use the network without pausing for confirmation. This is intentionally powerful and should be used only with trusted prompts and projects.
- **Workspace Only** is available independently for both agent roles before a task starts. Tool-using Codex/local/Responses Sub Agents use the `workspace-write` sandbox with project network access, blocking filesystem writes outside the selected project.
- Ollama listens only on `127.0.0.1:11434` and loads at most one model. Only a Local Deployment Loop Control Agent runs the initial three-way mission rewrite; it may issue three bounded requests concurrently to that same selected model, and no additional model is loaded. Codex and API control agents use the original request verbatim.
- The app bundle contains the Ollama runtime but no model weights. A curated or user-added model is downloaded only after the user sees and confirms the live Registry-reported size. LoopForge rechecks the official Ollama manifest immediately before pulling, inspects required capabilities, performs a real local response check, and records the installed digest before marking the model Ready. Background execution and recovery paths cannot initiate model downloads.
- LoopForge launches the bundled or current host official Codex CLI using the Mac's existing authenticated Codex identity. Its connection check runs `codex login status` and reads the CLI model catalog; LoopForge does not copy or persist the credential. Existing task sessions are not enumerated; only the session ID created for each LoopForge task is retained.
- User-added API keys are stored as device-only generic passwords in macOS Keychain. They are never encoded into `tasks.json`, `agent-models.json`, logs, or Codex command arguments. Direct Responses workers receive the secret through a per-process environment variable. Chat Completions workers receive only a one-turn random loopback token; the bridge reads the real key in the app process and sends it only to the configured HTTPS provider.
- Successful active Sub Agent subprocess wall time counts toward the user-confirmed hard target and is checkpointed every 15 seconds for crash safety. Mission rewriting, downloads, control audits, app downtime, deliberate sleep, and failed infrastructure turns are excluded.
- If Codex fails at the infrastructure layer three consecutive times, LoopForge pauses and surfaces the logs instead of creating an infinite crash loop. Quality failures continue iterating without a fixed retry cap.
