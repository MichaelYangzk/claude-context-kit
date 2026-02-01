#!/bin/bash
#
# Claude Context Canary v2 - Context Rot Detection Hook (no jq dependency)
#
# Triggered by UserPromptSubmit hook event.
# Checks the last Claude response against a canary pattern.
# If the pattern is missing, increments failure count and warns Claude.
#

# ─── Config ───
CONFIG_FILE="${HOME}/.claude/canary-config.json"
STATE_FILE="${HOME}/.claude/canary-state.json"

DEFAULT_CANARY_PATTERN="^///"
DEFAULT_FAILURE_THRESHOLD=2
DEFAULT_AUTO_ACTION="warn"  # warn | block

# ─── Pure bash JSON helpers (no jq dependency) ───

# Extract a JSON value from a string
json_val() {
    echo "$2" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" | \
        sed 's/.*:[[:space:]]*//; s/"//g; s/[[:space:]]*$//' | head -1
}

# Extract a JSON value from a file
json_val_file() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" "$2" 2>/dev/null | \
        sed 's/.*:[[:space:]]*//; s/"//g; s/[[:space:]]*$//' | head -1
}

# Escape a string for safe JSON embedding
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# ─── Read hook input ───

HOOK_INPUT=$(cat)
TRANSCRIPT_PATH=$(json_val "transcript_path" "$HOOK_INPUT")
SESSION_ID=$(json_val "session_id" "$HOOK_INPUT")

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# ─── Load config ───

if [ -f "$CONFIG_FILE" ]; then
    CANARY_PATTERN=$(json_val_file "canary_pattern" "$CONFIG_FILE")
    FAILURE_THRESHOLD=$(json_val_file "failure_threshold" "$CONFIG_FILE")
    AUTO_ACTION=$(json_val_file "auto_action" "$CONFIG_FILE")
fi

CANARY_PATTERN="${CANARY_PATTERN:-$DEFAULT_CANARY_PATTERN}"
FAILURE_THRESHOLD="${FAILURE_THRESHOLD:-$DEFAULT_FAILURE_THRESHOLD}"
AUTO_ACTION="${AUTO_ACTION:-$DEFAULT_AUTO_ACTION}"

# ─── Extract last assistant response ───
# Read only the last 50 lines for performance

LAST_RESPONSE=""
while IFS= read -r line; do
    if echo "$line" | grep -q '"type"[[:space:]]*:[[:space:]]*"assistant"'; then
        # Handle escaped quotes in JSON text field
        text=$(echo "$line" | \
            sed 's/\\"/_ESQ_/g' | \
            sed -n 's/.*"text"[[:space:]]*:[[:space:]]*"//p' | \
            sed 's/".*//' | \
            sed 's/_ESQ_/"/g' | \
            head -c 500)
        if [ -n "$text" ]; then
            LAST_RESPONSE="$text"
        fi
    fi
done < <(tail -50 "$TRANSCRIPT_PATH")

# No response found (new session) -> allow through
if [ -z "$LAST_RESPONSE" ]; then
    exit 0
fi

# ─── Check canary pattern ───

TRIMMED=$(echo "$LAST_RESPONSE" | sed 's/^[[:space:]]*//')
if echo "$TRIMMED" | grep -qE "$CANARY_PATTERN"; then
    # Canary alive - reset failure count
    if [ -f "$STATE_FILE" ]; then
        echo '{"failure_count": 0}' > "$STATE_FILE"
    fi
    exit 0
fi

# ─── Canary failed - update state ───

mkdir -p "$(dirname "$STATE_FILE")"

CURRENT_COUNT=0
if [ -f "$STATE_FILE" ]; then
    CURRENT_COUNT=$(json_val_file "failure_count" "$STATE_FILE")
    CURRENT_COUNT="${CURRENT_COUNT:-0}"
fi

NEW_COUNT=$((CURRENT_COUNT + 1))
TIMESTAMP=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

cat > "$STATE_FILE" << STATEEOF
{"failure_count": ${NEW_COUNT}, "last_failure": "${TIMESTAMP}", "session_id": "${SESSION_ID}"}
STATEEOF

# ─── Emit JSON response (properly escaped) ───

if [ "$NEW_COUNT" -ge "$FAILURE_THRESHOLD" ]; then
    REASON=$(json_escape "[Context Canary] Context rot detected! ${NEW_COUNT} consecutive failures. Run /compact or /clear")
    if [ "$AUTO_ACTION" = "block" ]; then
        printf '{"decision":"block","reason":"%s"}\n' "$REASON"
        exit 0
    fi
fi

MSG=$(json_escape "[Context Canary] Warning: response did not match canary pattern (${CANARY_PATTERN}). Failures: ${NEW_COUNT}/${FAILURE_THRESHOLD}. Follow CLAUDE.md instructions.")
printf '{"decision":"allow","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$MSG"
exit 0
