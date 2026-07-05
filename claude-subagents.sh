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

list_agents() {
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

  for meta in "$subdir"/agent-*.meta.json "$subdir"/workflows/*/agent-*.meta.json; do
    [ -e "$meta" ] || continue
    agent_id=$(basename "$meta" .meta.json); agent_id=${agent_id#agent-}
    tool_use_id=$(jq -r '.toolUseId // empty' "$meta")
    agent_type=$(jq -r '.agentType // "?"' "$meta")
    desc=$(jq -r '.description // ""' "$meta")
    if [ -n "$tool_use_id" ]; then
      # a tool_result for the spawning tool_use means the subagent finished
      if grep -q "\"tool_use_id\":\"$tool_use_id\"" "$parent" 2>/dev/null; then
        continue
      fi
    else
      # workflow agent: no toolUseId; the run's journal logs a result event on finish
      # ponytail: agents killed mid-run never get a result entry and show as running
      journal="$(dirname "$meta")/journal.jsonl"
      if jq -e --arg id "$agent_id" 'select(.type=="result" and .agentId==$id)' "$journal" >/dev/null 2>&1; then
        continue
      fi
      [ -n "$desc" ] || desc=$(basename "$(dirname "$meta")")   # show workflow run id
    fi

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

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(jq -r .name "$sess")" "$agent_id" "$agent_type" \
      "${model:-${model_fm:-inherit}}" "${effort:-inherit}" "$desc"
  done
done
}

# resumed sessions symlink workflow run dirs back to the original -> dedupe by agent id
rows=$(list_agents | awk -F'\t' '!seen[$2]++')
if [ -n "$rows" ]; then
  printf 'SESSION\tAGENT\tTYPE\tMODEL\tEFFORT\tDESCRIPTION\n%s\n' "$rows" | column -t -s$'\t'
else
  echo '(no running subagents)'
fi
