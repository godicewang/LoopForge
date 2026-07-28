# Third-party notices

LoopForge 1.0 bundles the following command-line runtimes so the app does not depend on a Homebrew or npm setup:

- OpenAI Codex CLI `0.145.0-alpha.30` (`openai/codex`), distributed under the Apache License 2.0. The full license is included as `Licenses/Codex-Apache-2.0.txt`.
- Ollama `0.32.0` (`ollama/ollama`), distributed under the MIT License. The full license is included as `Licenses/Ollama-MIT.txt`.

Model weights are not embedded in the application archive. On first use, Ollama downloads the selected model into the user's LoopForge Application Support directory. Each model remains subject to the license and notice published with that model by its provider. The built-in catalog currently routes among OpenAI gpt-oss 20B, Qwen3-Coder 30B-A3B, Qwen3-VL 8B, and Qwen3-VL 30B-A3B. Depending on the user's role selection, these models can control the loop or perform project work through the bundled Codex OSS harness.

LoopForge is an independent local controller and is not an official OpenAI or Ollama product.
