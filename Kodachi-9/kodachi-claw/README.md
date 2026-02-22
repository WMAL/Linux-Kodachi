# Kodachi Claw — Anonymous AI Agent Runtime

<div align="center">

[![Version](https://img.shields.io/badge/Version-9.0.1-00ffff?style=for-the-badge)](https://www.kodachi.cloud/wiki/bina/ai/kodachi-claw.html)
[![Language](https://img.shields.io/badge/Language-Rust-ff8f00?style=for-the-badge&logo=rust&logoColor=white)](https://www.rust-lang.org/)
[![Size](https://img.shields.io/badge/Size-28.3MB-blue?style=for-the-badge)](https://www.kodachi.cloud/apps/os/install/kodachi-claw/kodachi-claw)
[![License](https://img.shields.io/badge/License-Proprietary-yellow?style=for-the-badge)](https://github.com/WMAL/Linux-Kodachi/blob/main/LICENSE.md)
[![Tor](https://img.shields.io/badge/Embedded-Tor%20(Arti)-7D4698?style=for-the-badge&logo=torproject&logoColor=white)](https://www.kodachi.cloud/wiki/bina/ai/kodachi-claw.html)

**The only AI agent runtime that operates entirely inside the Tor network.**

[Full Documentation](https://www.kodachi.cloud/wiki/bina/ai/kodachi-claw.html) · [CLI Reference](https://www.kodachi.cloud/wiki/bina/binaries/kodachi-claw.html) · [Download](#download)

</div>

---

## What is Kodachi Claw?

Kodachi Claw is forged from [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw), the ultra-lightweight Rust AI agent runtime. It takes ZeroClaw's full agent engine — 29+ AI providers, 15+ communication channels, tools, memory, scheduler — and wraps it with Kodachi's production-grade anonymity stack:

- **Embedded Arti Tor** — Full Tor compiled into the binary, multi-circuit pool with load balancing
- **Identity Randomization** — MAC address, hostname, and timezone spoofed on startup
- **OPSEC Filter** — Scans all outbound messages, redacts identity leaks before they reach any provider
- **Namespace Isolation** — Kernel-level network isolation via oniux, zero leak possible
- **IP & DNS Leak Verification** — Automated checks on startup, blocks operation if verification fails

Every API call, model request, and channel message is routed through Tor circuits. Your agent cannot be tracked, fingerprinted, or traced back to you.

---

## The Claw Family

All variants of the open-source AI agent runtime family:

| Project | Language | Size | Description | Repository |
|---------|----------|------|-------------|------------|
| OpenClaw | Node.js | ~28MB dist · >1GB RAM | The original personal AI assistant | [openclaw/openclaw](https://github.com/openclaw/openclaw) |
| ZeroClaw | Rust | 3.4MB bin · <5MB RAM | Ultra-lightweight: 99% less memory, runs on $10 hardware | [zeroclaw-labs/zeroclaw](https://github.com/zeroclaw-labs/zeroclaw) |
| NullClaw | Zig | 678KB bin · ~1MB RAM | Fastest and smallest: 678KB binary, <2ms startup | [nullclaw/nullclaw](https://github.com/nullclaw/nullclaw) |
| PicoClaw | Go | ~8MB bin · <10MB RAM | Tiny personal agent: <10MB RAM footprint | [sipeed/picoclaw](https://github.com/sipeed/picoclaw) |
| IronClaw | Rust | ~4MB bin · <8MB RAM | Privacy-focused with WASM-sandboxed tools | [nearai/ironclaw](https://github.com/nearai/ironclaw) |
| NanoClaw | TypeScript | ~12MB dist · ~80MB RAM | Container-secured agent with Claude Agent SDK | [qwibitai/nanoclaw](https://github.com/qwibitai/nanoclaw) |
| **Kodachi Claw** | **Rust** | **28.3MB bin · ~45MB RAM** | **Anonymity-hardened: embedded Tor, OPSEC filter, namespace isolation** | **You are here** |

> **All the claws give you an AI agent. Only kodachi-claw makes that agent invisible.**

---

## What Kodachi Claw Adds on Top of ZeroClaw

| Addition | What It Does |
|----------|--------------|
| **Embedded Arti Tor** | Full Tor stack compiled into the binary. Multi-circuit pool (default 10 instances) with load balancing. Every request routed through Tor. |
| **Circuit Pool Manager** | Configurable circuit count (1-50), 4 strategies (round-robin, random, least-used, sticky), health monitoring per circuit. |
| **Identity Randomization** | MAC address, hostname, timezone randomization on startup. Auto-restored on exit. |
| **OPSEC Filter** | Scans all outbound agent messages, redacts identity leaks (real IPs, hostnames, usernames, MACs) before they reach any provider or channel. |
| **Namespace Isolation (oniux)** | Kernel-level network namespace. All traffic forced through Tor at the OS level. No DNS or IP leaks possible, even from child processes. |
| **IP & DNS Leak Verification** | Automated check on startup. Confirms traffic exits through Tor, blocks operation if verification fails. |
| **Kodachi Auth Gate** | In-process online-auth integration with device ID verification, auto-recovery, and session persistence. |
| **Extended Sandboxing** | Adds Bubblewrap and Firejail backends on top of ZeroClaw's Landlock and Docker support. |
| **Preflight Checks** | Full anonymity preflight: Tor bootstrap, identity randomization, IP/DNS verification, OPSEC filter init, instance locking. |
| **Cleanup on Exit** | Restores original MAC, hostname, timezone. Tears down Tor circuits and cleans instance locks. |
| **Internet Recovery** | Auto connectivity check after identity changes. Invokes health-control recovery when connectivity is lost. |
| **Claude Code CLI Provider** | No API key needed — invokes installed Claude Code CLI directly. Lazy path detection, 120s timeout, secret scrubbing. |
| **ai-gateway Integration** | Safe command execution through policy firewall. Three-tier risk classification with human-in-the-loop for dangerous operations. |
| **Signal Handler** | Graceful SIGINT/SIGTERM ensures cleanup (identity restore, internet recovery, Tor teardown) always runs, even on Ctrl+C. |
| **Service Libraries** | Integrates online-auth, ip-fetch, tor-switch, oniux, dns-leak, permission-guard, integrity-check, health-control as in-process Rust libraries. |

---

## Download

kodachi-claw is a single static binary — no installer, no dependencies. Download, place both files in the same folder, and run.

| File | Link |
|------|------|
| **kodachi-claw** (binary) | [Download](https://www.kodachi.cloud/apps/os/install/kodachi-claw/kodachi-claw) |
| **kodachi-claw_v9.0.1.sig** (signature) | [Download](https://www.kodachi.cloud/apps/os/install/kodachi-claw/kodachi-claw_v9.0.1.sig) |

> **Both files required.** The binary verifies its own signature on startup — without the `.sig` file, kodachi-claw will refuse to run. Place both files in the same directory.

### Install via Terminal

```bash
# Option 1: wget
mkdir -p ~/kodachi-claw && cd ~/kodachi-claw
wget https://www.kodachi.cloud/apps/os/install/kodachi-claw/kodachi-claw
wget https://www.kodachi.cloud/apps/os/install/kodachi-claw/kodachi-claw_v9.0.1.sig
chmod 755 kodachi-claw

# Option 2: curl
mkdir -p ~/kodachi-claw && cd ~/kodachi-claw
curl -LO https://www.kodachi.cloud/apps/os/install/kodachi-claw/kodachi-claw
curl -LO https://www.kodachi.cloud/apps/os/install/kodachi-claw/kodachi-claw_v9.0.1.sig
chmod 755 kodachi-claw

# Run (requires sudo for identity randomization)
sudo ./kodachi-claw onboard --interactive
```

You can also download both files via your browser and place them in any directory you prefer (`~/Desktop`, `~/Downloads`, `/opt/kodachi-claw`, etc.) — just keep both files together.

### SHA256 Checksum

```
f62a591c302a284dbfe11b1b32251e85d20401eedcbbbb95a1923d22a43ccc5f
```

The public key is embedded at compile time — no separate key file needed. The binary verifies its own signature on startup.

---

## Quick Start

```bash
# 1. Onboard (guided 9-step wizard)
sudo ./kodachi-claw onboard --interactive

# 2. Start the AI agent
sudo ./kodachi-claw agent

# 3. Single message mode
sudo ./kodachi-claw agent --message "What is my IP?"

# 4. Start daemon (gateway + all channels + scheduler)
sudo ./kodachi-claw daemon

# 5. Check system status
sudo ./kodachi-claw status
```

### Tor Modes

```bash
# Multi-circuit (default) — 10 parallel Tor circuits
sudo ./kodachi-claw --mode multi-circuit --tor-instances 10 agent

# Namespace isolation — kernel-level network isolation
sudo ./kodachi-claw --mode isolated agent

# Single circuit — low resource environments
sudo ./kodachi-claw --mode single --tor-instances 1 agent

# Sticky circuits — same exit node per channel
sudo ./kodachi-claw --circuit-strategy sticky daemon

# Restore identity on exit
sudo ./kodachi-claw --restore-on-exit agent
```

### Providers & Channels

```bash
# Use Anthropic Claude
sudo ./kodachi-claw agent --provider anthropic --model claude-sonnet-4-5-20250929

# Use local Ollama model (Tor still active for tools)
sudo ./kodachi-claw agent --provider ollama --model llama3

# Use Claude Code CLI (no API key needed)
sudo ./kodachi-claw agent --provider claude-code --message "scan this"

# Add Telegram channel
kodachi-claw channel add telegram '{"bot_token":"...","allowed_users":["user1"]}'

# Start all channels as daemon
sudo ./kodachi-claw daemon
```

### Service Management

```bash
# Install as systemd service
sudo ./kodachi-claw service install
sudo ./kodachi-claw service start

# Check service status
kodachi-claw service status

# Run diagnostics
kodachi-claw doctor
```

---

## Other Ways to Get Kodachi Claw

Kodachi Claw ships pre-installed in the following packages — no separate download needed:

| Distribution | Description | Link |
|-------------|-------------|------|
| **Desktop XFCE ISO** | Full Kodachi desktop with GUI dashboard and all binaries | [Download & Info](https://www.kodachi.cloud/wiki/bina/desktop-debian.html) |
| **Terminal Server ISO** | Lightweight ISO with all binaries pre-configured for servers | [Download & Info](https://www.kodachi.cloud/wiki/bina/terminal-version.html) |
| **Binary Package** | All standalone binaries bundled together for any Debian system | [Download & Info](https://www.kodachi.cloud/wiki/bina/binaries-overview.html) |
| **Standalone Download** | Just kodachi-claw binary + signature (this page) | [Download](#download) |

---

## Commands & Tutorials

For the complete list of commands, flags, examples, and scenarios:

- **[Full Documentation & Scenarios](https://www.kodachi.cloud/wiki/bina/ai/kodachi-claw.html)** — Anonymity features, identity management, internet recovery, architecture diagrams, and all usage scenarios
- **[CLI Reference](https://www.kodachi.cloud/wiki/bina/binaries/kodachi-claw.html)** — Every command, subcommand, flag, and example with expected output

### Command Summary

| Command | Description |
|---------|-------------|
| `onboard` | Initialize workspace and configuration (guided wizard) |
| `agent` | Start the AI agent loop |
| `gateway` | Start the gateway server (webhooks, websockets) |
| `daemon` | Start long-running runtime (gateway + channels + heartbeat + scheduler) |
| `service` | Manage OS service lifecycle (systemd) |
| `doctor` | Run diagnostics for daemon/scheduler/channel freshness |
| `status` | Show system status (identity, Tor, auth, channels) |
| `cron` | Configure and manage scheduled tasks |
| `models` | Manage provider model catalogs |
| `providers` | List 29+ supported AI providers |
| `channel` | Manage channels (Telegram, Discord, Slack, Matrix, etc.) |
| `integrations` | Browse 50+ integrations |
| `skills` | Manage user-defined capabilities |
| `migrate` | Migrate data from other agent runtimes |
| `auth` | Manage provider authentication profiles (OAuth, API keys) |
| `hardware` | Discover and introspect USB hardware |
| `peripheral` | Manage hardware peripherals (STM32, RPi GPIO) |
| `recover-internet` | Check and recover internet connectivity |

### Global Flags

| Flag | Description |
|------|-------------|
| `--mode <MODE>` | Anonymity mode: `multi-circuit` (default), `isolated`, `single` |
| `--tor-instances <N>` | Tor pool size (default: 10) |
| `--circuit-strategy <S>` | Circuit selection: `round-robin`, `random`, `least-used`, `sticky` |
| `--restore-on-exit` | Restore MAC/hostname/timezone on shutdown |
| `--auto-recover-internet` | Auto-check connectivity after identity changes |
| `--skip-anonymity` | Skip all anonymity (local testing only) |
| `--skip-identity` | Skip MAC/hostname/timezone randomization |
| `--skip-tor` | Skip embedded Tor startup |
| `--json` / `--json-pretty` | JSON output for scripting |
| `-V, --verbose` | Debug logging |
| `-q, --quiet` | Suppress non-error output |

---

## System Requirements

| Requirement | Value |
|-------------|-------|
| **OS** | Linux (Kodachi OS, Debian-based distributions) |
| **Architecture** | x86-64 |
| **Privileges** | Root/sudo required for MAC/hostname/timezone randomization |
| **Dependencies** | `macchanger` (MAC randomization), `ip` (network control) |

---

## License

Proprietary — Kodachi OS. See [LICENSE](https://github.com/WMAL/Linux-Kodachi/blob/main/LICENSE.md).

## Developed By

**Warith Al Maawali** — [digi77.com](https://www.digi77.com) · [GitHub](https://github.com/WMAL) · [Twitter](https://twitter.com/warith2020)
