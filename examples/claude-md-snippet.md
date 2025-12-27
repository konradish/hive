# CLAUDE.md Snippet for Hive Enforcement

Add this to your global `~/.claude/CLAUDE.md` or your orchestration repo's `CLAUDE.md`.

---

## Cross-Project Work (Hive Enforcement)

**CRITICAL: When working from notes repo on other project repos, ALWAYS use hive workers.**

### The Rule:
- **NEVER** directly SSH, edit files, or run commands in other repos (infra, my-app, my-api, etc.)
- **ALWAYS** spawn a hive worker to operate in that repo's context
- Workers have access to git history, project CLAUDE.md, and full repo context

### Why This Matters:
- Workers understand the repo's git history and can investigate what changed
- Workers read the project's CLAUDE.md for deployment patterns, env vars, etc.
- Orchestrator lacks context to make safe changes directly
- Destructive commands (sed, rm, docker) without full context cause cascading failures

### Anti-Patterns (from real incidents):
- Running `sed -i 's/old/new/g' compose.yaml` directly -> broke configuration
- Deleting containers without understanding the architecture
- Investigating "what broke" without checking git history
- Making 5+ infrastructure changes without approval

### Correct Pattern:
```bash
# From notes repo (orchestrator), spawn worker to investigate
/hive spawn my-project "Investigate git history to find what broke. Check recent commits, compare config versions."

# Worker operates in /path/to/my-project with full context
# Worker reads project CLAUDE.md for deployment docs
# Worker checks git log, git diff to understand changes
```

### When to Use Hive:
- Any deployment operation
- Any infrastructure changes
- Investigating what broke in another repo
- Making changes that require understanding project context

### When NOT to Use Hive:
- Simple read-only queries (checking a file exists)
- Operations that don't modify state
- Tasks within the current repo
