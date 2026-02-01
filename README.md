# Claude Context Kit

Context health toolkit for Claude Code. Two modules:

1. **Canary Detection** — Monitor context rot by checking if Claude still follows a trivial instruction
2. **Context Optimizer** — Claude Code skill implementing 5 research-backed strategies to slow context degradation

## Quick Install

```bash
git clone https://github.com/MichaelYangzk/claude-context-kit.git
cd claude-context-kit
bash install.sh --all
```

Or selective:
```bash
bash install.sh --canary      # Canary only
bash install.sh --optimizer   # Optimizer only
bash install.sh --dry-run     # Preview changes
```

## How It Works

### Module 1: Canary Detection

The "canary in the coal mine" approach. Add a trivial instruction to CLAUDE.md:

```
Every response must start with ///
```

When Claude stops following it, context has rotted. The system detects this automatically.

**Two detection methods:**

| Method | How | Best For |
|--------|-----|----------|
| Hook (`canary-check-v2.sh`) | Checks on `UserPromptSubmit` event | Lightweight, per-project |
| Daemon (`canary-daemon-global.sh`) | Background process monitoring all sessions | Global, real-time alerts |

**What happens on detection:**
- Desktop notification (macOS/Linux)
- Warning injected into next Claude response
- Failure counter tracks consecutive misses
- After threshold (default 2): critical alert

**Post-install:**
```bash
~/.claude/plugins/canary-daemon-global.sh start    # Start
~/.claude/plugins/canary-daemon-global.sh status   # Check
~/.claude/plugins/canary-daemon-global.sh stop     # Stop
```

### Module 2: Context Optimizer

A Claude Code skill that teaches Claude 5 context hygiene strategies. Auto-discovered when installed to `.claude/skills/`.

| # | Strategy | Source | Mechanism |
|---|----------|--------|-----------|
| 1 | Sub-Agent Delegation | [Anthropic Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) | Files >30KB handled by sub-agent, only summary returns to main context |
| 2 | Tool Result Clearing | Anthropic "lightweight compaction" | Summarize every tool output in 1-3 sentences, discard raw data |
| 3 | Recite-then-Solve | [Du et al. EMNLP 2025](https://arxiv.org/abs/2510.05381) | Periodically recite safety/style rules to refresh attention |
| 4 | Dual-End Injection | Lost-in-the-Middle research | Re-inject rules at end of context after compact (U-curve) |
| 5 | Index Refinement | [Chroma context-rot study](https://research.trychroma.com/context-rot) | Give pointers not documents; structured content rots faster |

**Commands after install:**
```
/recite          — Force attention refresh on core rules
/context-check   — Full 5-point context health report
```

**Auto-trigger rules:**

| Condition | Strategy Activated |
|-----------|-------------------|
| Reading file >30KB | Sub-Agent Delegation |
| Any tool call completes | Tool Result Clearing |
| Conversation >20 turns | Recite-then-Solve |
| After `/compact` | Dual-End Injection |
| Browsing directories | Index Refinement |

## Repo Structure

```
claude-context-kit/
├── install.sh                    # Unified installer
├── canary/                       # Module 1: Canary Detection
│   ├── canary-check.sh           #   Hook v1 (Stop event)
│   ├── canary-check-v2.sh        #   Hook v2 (UserPromptSubmit) [recommended]
│   ├── canary-daemon.sh          #   Project-level daemon
│   ├── canary-daemon-global.sh   #   Global daemon (no jq dependency)
│   ├── install.sh                #   Standalone canary installer
│   ├── install-global.sh         #   Global canary installer
│   └── setup-combined.sh         #   Canary + Auto Compact setup
├── optimizer/                    # Module 2: Context Optimizer
│   ├── SKILL.md                  #   Claude Code skill definition
│   ├── scripts/
│   │   └── recite.py             #   Recite-then-Solve extraction
│   └── patches/
│       └── context-hygiene.md    #   CLAUDE.md appendable rules
└── configs/                      # Shared configurations
    ├── canary-config.example.json
    └── hooks-settings.example.json
```

## Installed Files

After `bash install.sh --all`:

```
~/.claude/
├── plugins/
│   ├── canary-daemon-global.sh   # Daemon binary
│   └── canary-check-v2.sh        # Hook script
├── canary-config.json            # Canary settings
├── canary-state.json             # Runtime state (auto-created)
└── settings.json                 # Hooks + Auto Compact config

<project>/.claude/skills/
└── context-optimizer -> /path/to/claude-context-kit/optimizer
```

## Configuration

### Canary Config (`~/.claude/canary-config.json`)

```json
{
  "canary_pattern": "^///",
  "failure_threshold": 2,
  "auto_action": "warn"
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `canary_pattern` | `^///` | Regex to match against Claude responses |
| `failure_threshold` | `2` | Consecutive failures before critical alert |
| `auto_action` | `warn` | `warn` = inject warning, `block` = block message |

### Auto Compact

The installer sets `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=60` in settings.json. This triggers automatic context compression at 60% usage instead of the default 95%.

## Research

This toolkit is based on:

- **Anthropic** — [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- **Chroma** — [Context Rot: Measuring & Mitigating Context Window Degradation](https://research.trychroma.com/context-rot)
- **Du et al.** — [Recite-then-Solve (EMNLP 2025)](https://arxiv.org/abs/2510.05381)
- **Liu et al.** — Lost in the Middle: How Language Models Use Long Contexts

## License

MIT
