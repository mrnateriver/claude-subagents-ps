#!/bin/bash
# List currently-running Claude Code subagents with their model and thinking effort.
# Sources: ~/.claude/sessions/*.json (live sessions) and
#          ~/.claude/projects/<slug>/<session-id>/subagents/ (subagent transcripts).
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

# frontmatter_field <file> <key>
frontmatter_field() {
  sed -n '2,/^---$/p' "$1" 2>/dev/null | awk -F': *' -v k="$2" '$1==k{print $2; exit}'
}

printf '%-12s %-18s %-22s %-20s %-8s %s\n' SESSION AGENT TYPE MODEL EFFORT DESCRIPTION
found=0

for sess in "$CLAUDE_DIR"/sessions/*.json; do
  [ -e "$sess" ] || continue
  pid=$(jq -r .pid "$sess")
  kill -0 "$pid" 2>/dev/null || continue          # session process is dead
  sid=$(jq -r .sessionId "$sess")
  cwd=$(jq -r .cwd "$sess")
  slug=$(printf %s "$cwd" | tr '/.' '--')
  parent="$CLAUDE_DIR/projects/$slug/$sid.jsonl"
  subdir="$CLAUDE_DIR/projects/$slug/$sid/subagents"
  [ -d "$subdir" ] || continue

  for meta in "$subdir"/agent-*.meta.json; do
    [ -e "$meta" ] || continue
    tool_use_id=$(jq -r '.toolUseId // empty' "$meta")
    # a tool_result for the spawning tool_use means the subagent finished
    if [ -n "$tool_use_id" ] && grep -q "\"tool_use_id\":\"$tool_use_id\"" "$parent" 2>/dev/null; then
      continue
    fi
    agent_type=$(jq -r '.agentType // "?"' "$meta")
    desc=$(jq -r '.description // ""' "$meta")
    agent_id=$(basename "$meta" .meta.json); agent_id=${agent_id#agent-}

    transcript="${meta%.meta.json}.jsonl"
    model=$(grep '"type":"assistant"' "$transcript" 2>/dev/null | tail -1 | jq -r '.message.model // empty')

    # effort comes from the agent definition's frontmatter; blank = inherits session effort
    effort="" model_fm=""
    for d in "$cwd/.claude/agents" "$CLAUDE_DIR/agents"; do
      if [ -f "$d/$agent_type.md" ]; then
        effort=$(frontmatter_field "$d/$agent_type.md" effort)
        model_fm=$(frontmatter_field "$d/$agent_type.md" model)
        break
      fi
    done

    printf '%-12s %-18s %-22s %-20s %-8s %s\n' \
      "$(jq -r .name "$sess")" "$agent_id" "$agent_type" \
      "${model:-${model_fm:-inherit}}" "${effort:-inherit}" "$desc"
    found=1
  done
done

[ "$found" = 1 ] || echo '(no running subagents)'
