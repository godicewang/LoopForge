<p align="center">
  <img src="docs/assets/loopforge-icon.png" width="120" alt="LoopForge 图标">
</p>

<h1 align="center">LoopForge</h1>

<p align="center">
  <strong>把一句话变成经过验证的软件，或一条可长期运行的本地自动化管线。</strong><br>
  面向 macOS 的原生自治编程控制台：单 Agent 循环、依赖感知的多 Agent 图，以及可自适应修复的 Watcher。
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-native-111111">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="测试" src="https://img.shields.io/badge/tests-205%20passed-24A148">
  <img alt="许可证" src="https://img.shields.io/badge/license-Apache--2.0-4C6EF5">
</p>

![LoopForge Auto Graph 完成一个真实项目](docs/assets/auto-graph.png)

LoopForge 让长时间 Agent 工作持续推进，同时保持可见、可暂停、可恢复和可审计。它可以监督官方 Codex、兼容 API 或本地 Ollama 模型，验证真实命令和截图，并以本地 HTML 交付页结束任务，而不是停在一句“已经完成”。

## 目录

- [为什么使用 LoopForge](#为什么使用-loopforge)
- [三种工作方式](#三种工作方式)
- [快速开始](#快速开始)
- [运行逻辑](#运行逻辑)
- [关键控制项](#关键控制项)
- [模型隐私与权限](#模型隐私与权限)
- [验证结果](#验证结果)
- [参与贡献](#参与贡献)

## 为什么使用 LoopForge

- **面向结果，而不是回复。** 硬工作时长、循环审计、真实命令、视觉证据和最终交付门禁共同决定完成。
- **只在安全时并行。** Auto Graph 只有在前驱完成、合并并通过审计后，才会真正创建后继节点。
- **不让 Agent 为等待付费。** Continuum Watcher 把重复工作固化为本地管线，仅在异常、复核、适配或完成时唤醒智能模型。
- **全过程可追溯。** 指令、迭代、检查点、分支替换、阻塞时间和 Main Agent 决策均可查看。

## 三种工作方式

### Single Loop：完成一个明确结果

![LoopForge Single Loop 修复真实 CLI](docs/assets/single-loop.png)

适合新建项目、修复 Bug、迁移依赖、优化性能、跑实验和补齐测试。LoopForge 持续检查代码与证据，并向 Sub Agent 给出当前价值最高的下一步，直到时间和质量门禁都通过。

示例：修复持久化竞态 · 完成可发布工具 · 复现并优化慢路径 · 建立机器学习 baseline。

### Auto Graph：协同完成复杂系统

![LoopForge Auto Graph 执行图](docs/assets/auto-graph.png)

Main Graph Agent 只创建当前可以执行的节点。相互独立的节点可使用 Git worktree 并行；依赖节点要等完整 join group 审计后才会出现。被终止的错误路线仍以红色历史保留，并明确指向替代节点。

示例：后端 + 原生 UI + 数据迁移 · 多模块重构 · 产品、测试、文档和打包协同 · 研究结论收敛到实现。

### Continuum Watcher：自动处理长期工作

![LoopForge Continuum Watcher 运行真实管线](docs/assets/continuum-watcher.png)

Codex 首先把常规部分固化为一次性、幂等、带原子遥测和检查点的程序；轻量调度器负责运行。只有规则、陈旧数据、失败、阈值或周期复核才会唤醒 Agent，分析当前状态并改进管线本身。

示例：服务与安全异常监控 · 大批量数据处理 · 条件达成通知 · 周期性数据质量检查。

## 快速开始

### 下载应用

1. 在 [最新 Release](https://github.com/godicewang/LoopForge/releases/latest) 下载 `LoopForge-macOS-arm64.zip`。
2. 解压并把 **LoopForge.app** 拖入 `/Applications`。
3. 打开应用，按任务需要授予权限，并使用已有 Codex/ChatGPT 登录连接。

LoopForge v1.0 支持 Apple Silicon 与 macOS 14 及以上。当前社区包为 ad-hoc 签名；在提供 Developer ID 公证包前，首次启动可能需要 **按住 Control 点击 → 打开**。

### 从源码构建

需要 Xcode Command Line Tools、`curl` 和 Apple Silicon。

```bash
git clone https://github.com/godicewang/LoopForge.git
cd LoopForge
zsh Scripts/bootstrap_vendor.sh
zsh Scripts/package_app.sh
open dist/LoopForge.app
```

脚本会下载并校验固定版本的官方 Codex 与 Ollama 发行文件；仓库和应用包均不携带模型权重。

### 运行测试

```bash
swift test
swift build -c release -Xswiftc -warnings-as-errors
```

## 运行逻辑

```mermaid
flowchart LR
    U["一句目标"] --> C["Loop Control / Main Graph Agent"]
    C --> W["Sub Agent 循环"]
    W --> E["命令 · 测试 · 截图 · 产物"]
    E --> C
    C -->|门禁通过| R["本地 HTML 交付页"]
    C -->|仍有缺口| W
```

只有成功且真正工作的 Sub Agent 时间会计入硬目标。下载、控制审计、基础设施失败、暂停、睡眠和应用离线时间都不会计入。状态使用原子检查点持久化，意外退出后不会虚增工作时长。

Auto Graph 额外保证：所有必需前驱完成、合并并通过 Main Agent 审计前，后继任务不会被派发。Main Agent 使用信号量等待节点，而非长期轮询。

Watcher 每次只执行一个有界确定性 pass 然后退出。遥测、检查点、信号与规则数量、文件大小、子进程输出、超时和工作区路径都受到验证与上限保护。

## 关键控制项

| 控制项 | 作用 |
| --- | --- |
| **Task Quality** | Lightweight、Normal、Enhanced、Ultra 四档证据深度 |
| **Active runtime** | 根据目标建议，开始前可增减 |
| **Single / Graph / Candidates** | 单循环、依赖图或隔离候选结果 |
| **Loop Control Agent** | 规划、审计、恢复并决定下一条指令 |
| **Sub Agent** | 执行具体项目任务 |
| **Full Access / Workspace Only** | 为两个角色分别设置权限边界 |
| **Pause Task** | 保存检查点并等待进程安全退出 |
| **End Task…** | 停止 Agent，同时保留项目与证据 |
| **Final Report** | 打开完整本地交付页 |

## 模型隐私与权限

两个角色默认使用本机官方 Codex CLI 返回的最新模型、最强可用推理和 Full Access。用户也可以选择：

- 使用 Mac 已有 ChatGPT 身份的官方 Codex；
- 保存的 OpenAI-compatible API；
- 通过 Codex OSS 工具框架工作的 Ollama 本地模型。

API Key 只保存在 macOS Keychain，不进入任务 JSON 或命令参数。Watcher 子进程使用最小环境，不能继承无关 API/CI 密钥。本地模型必须由用户确认下载，并通过大小、能力、摘要与真实响应检查。详见 [SECURITY.md](SECURITY.md)。

## 验证结果

v1.0 候选版本已完成两轮独立验证：

- Single Loop、Auto Graph、Continuum Watcher 共 **17 个复杂综合场景**；
- 第一轮含 **至少 5 类 Watcher 任务**，第二轮重新覆盖压力、超时、恢复与高基数边界；
- **205 项测试、0 失败**；另有 6 项需要外部密钥、本地模型或已登录浏览器的测试，默认明确跳过。

全部场景与实际修复见 [发布验证报告](docs/RELEASE_VALIDATION.md)。

## 参与贡献

欢迎提交 Issue 和范围清晰的 Pull Request。请先阅读
[贡献指南](CONTRIBUTING.md)、[安全模型](SECURITY.md) 与
[行为准则](CODE_OF_CONDUCT.md)。

LoopForge 是独立开源项目，并非 OpenAI 或 Ollama 官方产品。第三方组件保留各自许可证，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
