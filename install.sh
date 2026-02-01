#!/usr/bin/env bash
#
# Claude Context Kit - Unified Installer
#
# Installs both modules:
#   1. Canary Detection  - Monitor context rot via response pattern matching
#   2. Context Optimizer - Claude Code skill for context hygiene strategies
#
# Usage:
#   bash install.sh              # Interactive install
#   bash install.sh --all        # Install everything (non-interactive)
#   bash install.sh --canary     # Canary only
#   bash install.sh --optimizer  # Optimizer only
#   bash install.sh --dry-run    # Preview only
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
PLUGINS_DIR="${CLAUDE_DIR}/plugins"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Flags
DRY_RUN=false
INSTALL_CANARY=false
INSTALL_OPTIMIZER=false
INSTALL_ALL=false
NONINTERACTIVE=false

for arg in "$@"; do
    case $arg in
        --all)        INSTALL_ALL=true; NONINTERACTIVE=true ;;
        --canary)     INSTALL_CANARY=true; NONINTERACTIVE=true ;;
        --optimizer)  INSTALL_OPTIMIZER=true; NONINTERACTIVE=true ;;
        --dry-run)    DRY_RUN=true ;;
        --help|-h)
            echo "Claude Context Kit - Installer"
            echo ""
            echo "Usage: bash install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --all         Install everything (non-interactive)"
            echo "  --canary      Install canary detection only"
            echo "  --optimizer   Install context optimizer skill only"
            echo "  --dry-run     Preview what would happen"
            echo "  --help        Show this help"
            exit 0
            ;;
    esac
done

if $INSTALL_ALL; then
    INSTALL_CANARY=true
    INSTALL_OPTIMIZER=true
fi

log()  { echo -e "${GREEN}  [OK]${NC} $1"; }
warn() { echo -e "${YELLOW}  [!!]${NC} $1"; }
dry()  { echo -e "${YELLOW} [DRY]${NC} Would: $1"; }

# ─────────────────────────────────────────────
# Header
# ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       Claude Context Kit - Installer         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Module 1:${NC} Canary Detection"
echo "    Monitor context rot via response pattern matching"
echo "    Hooks + daemon + desktop notifications"
echo ""
echo -e "  ${CYAN}Module 2:${NC} Context Optimizer"
echo "    Claude Code skill with 5 research-backed strategies"
echo "    Sub-agent delegation, recite-then-solve, dual-end injection"
echo ""

# ─────────────────────────────────────────────
# Interactive selection
# ─────────────────────────────────────────────
if ! $NONINTERACTIVE; then
    echo "What to install?"
    echo ""
    echo "  1) Both (Recommended)"
    echo "  2) Canary Detection only"
    echo "  3) Context Optimizer only"
    echo ""
    read -p "Choose (1/2/3): " choice
    case "$choice" in
        1) INSTALL_CANARY=true; INSTALL_OPTIMIZER=true ;;
        2) INSTALL_CANARY=true ;;
        3) INSTALL_OPTIMIZER=true ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

mkdir -p "$CLAUDE_DIR" "$PLUGINS_DIR"

# ─────────────────────────────────────────────
# Module 1: Canary Detection
# ─────────────────────────────────────────────
if $INSTALL_CANARY; then
    echo ""
    echo -e "${BOLD}━━━ Installing Canary Detection ━━━${NC}"

    # Copy daemon
    if $DRY_RUN; then
        dry "Copy canary-daemon-global.sh to $PLUGINS_DIR/"
        dry "Copy canary-check-v2.sh to $PLUGINS_DIR/"
        dry "Create canary-config.json"
    else
        cp "$REPO_ROOT/canary/canary-daemon-global.sh" "$PLUGINS_DIR/"
        cp "$REPO_ROOT/canary/canary-check-v2.sh" "$PLUGINS_DIR/"
        chmod +x "$PLUGINS_DIR/canary-daemon-global.sh" "$PLUGINS_DIR/canary-check-v2.sh"
        log "Installed daemon: $PLUGINS_DIR/canary-daemon-global.sh"
        log "Installed hook:   $PLUGINS_DIR/canary-check-v2.sh"

        # Config
        if [ ! -f "${CLAUDE_DIR}/canary-config.json" ]; then
            cp "$REPO_ROOT/configs/canary-config.example.json" "${CLAUDE_DIR}/canary-config.json"
            log "Created config:   ${CLAUDE_DIR}/canary-config.json"
        else
            warn "Config already exists, skipped"
        fi
    fi

    # Configure hook in settings.json
    if ! $DRY_RUN; then
        if [ ! -f "$SETTINGS_FILE" ]; then
            cat > "$SETTINGS_FILE" << 'HOOK_EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/plugins/canary-check-v2.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
HOOK_EOF
            log "Created settings with canary hook"
        else
            if grep -q "canary-check" "$SETTINGS_FILE" 2>/dev/null; then
                warn "Canary hook already in settings.json"
            else
                warn "Please manually add canary hook to $SETTINGS_FILE"
                echo "         See configs/hooks-settings.example.json"
            fi
        fi
    fi

    # Auto Compact threshold
    if ! $DRY_RUN; then
        if [ -f "$SETTINGS_FILE" ] && grep -q "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" "$SETTINGS_FILE" 2>/dev/null; then
            warn "Auto Compact already configured"
        else
            if command -v python3 &>/dev/null && [ -f "$SETTINGS_FILE" ]; then
                python3 -c "
import json
with open('$SETTINGS_FILE') as f: d = json.load(f)
d.setdefault('env', {})['CLAUDE_AUTOCOMPACT_PCT_OVERRIDE'] = '60'
with open('$SETTINGS_FILE', 'w') as f: json.dump(d, f, indent=2)
" 2>/dev/null && log "Set Auto Compact threshold to 60%" || warn "Could not set Auto Compact (set manually)"
            fi
        fi
    fi

    echo ""
    echo "  Canary commands:"
    echo "    $PLUGINS_DIR/canary-daemon-global.sh start   # Start daemon"
    echo "    $PLUGINS_DIR/canary-daemon-global.sh status  # Check status"
    echo "    $PLUGINS_DIR/canary-daemon-global.sh stop    # Stop daemon"
fi

# ─────────────────────────────────────────────
# Module 2: Context Optimizer (Skill)
# ─────────────────────────────────────────────
if $INSTALL_OPTIMIZER; then
    echo ""
    echo -e "${BOLD}━━━ Installing Context Optimizer ━━━${NC}"

    # Find project root (look for CLAUDE.md or .git going up)
    PROJECT_ROOT="$(pwd)"

    # Create .claude/skills/ symlink
    SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
    LINK="$SKILLS_DIR/context-optimizer"

    if $DRY_RUN; then
        dry "Create $SKILLS_DIR"
        dry "Symlink $REPO_ROOT/optimizer -> $LINK"
        dry "Patch CLAUDE.md with context hygiene rules"
    else
        mkdir -p "$SKILLS_DIR"

        if [ -L "$LINK" ] || [ -d "$LINK" ]; then
            warn "Skill already linked at $LINK"
        else
            ln -s "$REPO_ROOT/optimizer" "$LINK"
            log "Linked skill: $LINK -> $REPO_ROOT/optimizer"
        fi

        # Patch project CLAUDE.md
        PATCH_MARKER="Context Hygiene Rules (auto-injected by context-optimizer)"
        if [ -f "$PROJECT_ROOT/CLAUDE.md" ]; then
            if grep -q "$PATCH_MARKER" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null; then
                warn "CLAUDE.md already patched"
            else
                echo "" >> "$PROJECT_ROOT/CLAUDE.md"
                cat "$REPO_ROOT/optimizer/patches/context-hygiene.md" >> "$PROJECT_ROOT/CLAUDE.md"
                log "Patched CLAUDE.md with context hygiene rules"
            fi
        else
            warn "No CLAUDE.md in $PROJECT_ROOT — create one and re-run"
        fi

        chmod +x "$REPO_ROOT/optimizer/scripts/recite.py"
        log "Made recite.py executable"
    fi

    echo ""
    echo "  Optimizer commands:"
    echo "    /recite          Recite core rules (attention refresh)"
    echo "    /context-check   Full context health report"
fi

# ─────────────────────────────────────────────
# Canary instruction check
# ─────────────────────────────────────────────
if ! $DRY_RUN; then
    GLOBAL_CLAUDE="${HOME}/.claude/CLAUDE.md"
    if [ -f "$GLOBAL_CLAUDE" ]; then
        if grep -q "Every response must start with" "$GLOBAL_CLAUDE" 2>/dev/null || \
           grep -q "每次回复.*先说\|每次回复.*start with" "$GLOBAL_CLAUDE" 2>/dev/null; then
            log "Canary instruction found in global CLAUDE.md"
        else
            warn "No canary instruction in $GLOBAL_CLAUDE"
            echo "         Add: 'Every response must start with ///'"
        fi
    fi
fi

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━ Installation Complete ━━━${NC}"
echo ""
echo "  Installed:"
$INSTALL_CANARY && echo "    Canary Detection   ~/.claude/plugins/canary-*"
$INSTALL_OPTIMIZER && echo "    Context Optimizer  .claude/skills/context-optimizer"
echo ""
echo "  To install in another project:"
echo "    cd /path/to/project && bash $REPO_ROOT/install.sh"
echo ""
