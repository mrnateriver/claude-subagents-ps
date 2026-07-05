# claude-subagents

Lists currently-running Claude Code subagents across all live sessions, with their model, thinking effort, and task description.

```
./claude-subagents.sh
```

```
SESSION      AGENT              TYPE                   MODEL                EFFORT   DESCRIPTION
my-session   abc123             Explore                claude-sonnet-5      inherit  Find auth call sites
```

## How it works

1. Reads `~/.claude/sessions/*.json` and keeps only sessions whose PID is still alive.
2. For each live session, scans `~/.claude/projects/<slug>/<session-id>/subagents/agent-*.meta.json`.
3. A subagent is "running" if the parent session transcript has no `tool_result` for the tool call that spawned it.
4. Model comes from the subagent's transcript (last assistant message); effort and fallback model come from the agent definition's frontmatter in `.claude/agents/` (project, then `~/.claude/agents`). Blank means it inherits the session's setting.

Requires `jq`. Set `CLAUDE_DIR` to override the default `~/.claude`.

## License

MIT
