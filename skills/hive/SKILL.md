---
name: hive
description: Multi-instance orchestration for parallel work across projects. Activate on "spawn workers", "parallel work", "work on X and Y", "orchestrate", "hive". Coordinates multiple Claude Code instances, handles two-way communication, and integrates with park for context management.
allowed-tools: Bash, Read, Write, Glob, Grep, Task, TodoWrite
---

# Hive - Multi-CC Orchestration

Coordinate multiple Claude Code instances to work on tasks in parallel across different projects.

## Overview

You are the **orchestrator**. You spawn **worker** Claude Code instances in project directories, monitor their progress, answer their questions, and collect results.

## Architecture

```
notes repo (you, orchestrator)
    │
    ├── .hive/
    │   ├── workers/<project>-<uuid>/
    │   │   ├── status.json      # Worker writes here
    │   │   ├── task.md          # Original assignment
    │   │   ├── session-id       # UUID for resume
    │   │   └── transcript.jsonl # Full output log
    │   ├── projects.json        # Project path registry
    │   └── learnings/           # Cross-project knowledge
    │
    └── spawns workers via CLI ──►  project-a/
                                    project-b/
                                    other projects...
```

## Activation Triggers

Use this skill when user says:
- "Work on project-a and project-b in parallel"
- "Spawn workers to handle X and Y"
- "Orchestrate work across projects"
- "Use hive to..."
- Any request for parallel work across multiple projects

## Critical Safety Rule

**The orchestrator NEVER directly SSH's, edits files, or runs commands in other repos.**

Always spawn a hive worker. Workers have:
- Full git history access (can see what changed)
- Project CLAUDE.md (knows deployment patterns)
- Local context (understands the architecture)

The orchestrator lacks this context. Direct action leads to confident-but-wrong changes.

## Pre-Flight Checklist

Before spawning workers for deployment/infrastructure tasks:

| Step | Action | Why |
|------|--------|-----|
| 1 | Read `.hive/projects.json` | Verify project path exists |
| 2 | Check task specifies environment | Dev vs prod matters |
| 3 | If debugging, include recent context | "Check git log first" |
| 4 | Load relevant learnings | Inject past lessons |

**For deployment workers, always include in task:**
```
ENVIRONMENT: [dev/prod] - confirm before making changes
VERIFICATION: [how to test the fix worked]
```

## Parallel Safety Matrix

| Task Type | Parallel Safe? | Reason |
|-----------|----------------|--------|
| Code analysis / audits | YES | Read-only |
| Feature dev in different apps | YES | Separate repos |
| Documentation updates | YES | No shared state |
| Deployment to SAME server | NO | Container conflicts |
| Database migrations | NO | Schema dependencies |
| Infrastructure changes | NO | Shared resources |

**Rule:** If tasks touch the same server/database/service, run sequentially.

## Orchestrator Context Detection

The orchestrator may run in two environments with different capabilities:

| Context | Detection | Worker Spawn | Chrome Access |
|---------|-----------|--------------|---------------|
| **PowerShell/Windows** | Bash tool uses `/c/` paths | `wsl.exe -d Debian -- bash -ilc '...'` | Native MCP (~2s) |
| **WSL** | Bash tool uses `/mnt/c/` or `/home/` paths | Direct `claude` spawn | WSL-Chrome bridge (~20s) |

### Why This Matters

- **PowerShell orchestrator** has native Chrome MCP access - no bridge overhead
- **WSL orchestrator** must use WSL-Chrome bridge for UI validation (spawns 2nd Claude)
- **PowerShell is superior for UI-heavy workflows** (QA, testing, forms)

### Context Detection Logic

Check your Bash tool's working directory:
```bash
pwd
# /c/ObsidianNotes → PowerShell context (Git Bash)
# /mnt/c/ObsidianNotes → WSL context
# /home/kodell/... → WSL context
```

## Spawning Workers

### 1. Setup Worker Directory

```bash
WORKER_ID="<project>-$(uuidgen)"
WORKER_DIR="$HIVE_DIR/workers/$WORKER_ID"
mkdir -p "$WORKER_DIR"
echo "<uuid>" > "$WORKER_DIR/session-id"
```

### 2. Write Task File

Write `$WORKER_DIR/task.md` with the assignment for reference.

### 3. Get Project Path

Read from `.hive/projects.json`:
```json
{
  "project-a": "/path/to/project-a",
  "project-b": "/path/to/project-b"
}
```

### 4. Spawn Worker

**IMPORTANT**: Always generate a FRESH UUID for each spawn. Never reuse session IDs.

#### WSL Orchestrator (Direct Spawn)

```bash
# Generate fresh UUID - MUST be new each time
WORKER_UUID=$(uuidgen)
WORKER_ID="${PROJECT}-${WORKER_UUID}"

cd "<project-path>" && \
claude \
  -p "$(cat <<'PROMPT'
<worker-prompt from worker-prompt.md, with variables substituted>

IMPORTANT: Write an initial status immediately:
echo '{"status": "working", "progress": "Starting task analysis"}' > <status-file>
PROMPT
)" \
  --session-id "$WORKER_UUID" \
  --print \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  2>&1 > "$WORKER_DIR/transcript.jsonl" &
```

#### PowerShell Orchestrator (WSL Bridge Spawn)

When running from PowerShell/Windows, spawn workers in WSL via:

```bash
# Critical flags:
# -d Debian → Target correct WSL distro
# bash -ilc → Interactive login shell (loads PATH with claude at ~/.local/bin)
# /mnt/c/ paths → Required for WSL filesystem access

WORKER_UUID=$(uuidgen)
PROJECT_PATH="/mnt/c/projects/myproject"  # Note: /mnt/c not /c
STATUS_FILE="/mnt/c/ObsidianNotes/.hive/workers/${PROJECT}-${WORKER_UUID}/status.json"

wsl.exe -d Debian -- bash -ilc "
  cd $PROJECT_PATH && \
  claude -p '<worker-prompt with variables>' \
    --session-id $WORKER_UUID \
    --dangerously-skip-permissions
" 2>&1 > "$WORKER_DIR/transcript.jsonl" &
```

**Path translation:** When in PowerShell context, convert `/c/` → `/mnt/c/` for any paths passed to WSL.

**Note**: `--output-format stream-json --verbose` captures the full conversation including every tool call. This is essential for debugging and learning from worker behavior.

### 5. Start Monitor

Run the monitor script in background to watch for status changes:
```bash
bash ~/.claude/skills/hive/monitor.sh "$HIVE_DIR" &
```

## Monitoring Workers

### Using inotifywait

The monitor.sh script watches for status.json changes and outputs them:
```
STATUS_CHANGE: .hive/workers/project-a-xxx/status.json
{"status": "need_input", "question": "Should I use JWT or sessions?"}
```

### Polling Fallback

If inotifywait unavailable, poll every 10 seconds:
```bash
while true; do
  for f in "$HIVE_DIR"/workers/*/status.json; do
    cat "$f" 2>/dev/null
  done
  sleep 10
done
```

## Handling Worker Communication

### Worker Needs Input

When you see `"status": "need_input"`:

1. Read the question and context from status.json
2. Decide the answer (ask user if unclear)
3. Resume the worker:

```bash
SESSION_ID=$(cat "$WORKER_DIR/session-id")
cd "<project-path>" && \
claude \
  --resume "$SESSION_ID" \
  -p "Orchestrator response: <answer>" \
  --print \
  --dangerously-skip-permissions \
  2>&1 >> "$WORKER_DIR/transcript.jsonl"
```

### Worker Done

When you see `"status": "done"`:

1. Read the result from status.json
2. Optionally park the session for knowledge capture
3. Report to user
4. Clean up or archive worker directory

### Worker Error

When you see `"status": "error"`:

1. Read error details
2. Decide: retry, escalate to user, or abort
3. Resume with fix or report failure

## Context Management

### Proactive Parking

After a worker completes a significant milestone, ask it to park:

```bash
claude \
  --resume "$SESSION_ID" \
  -p "Good checkpoint. Please run /session:park to capture your progress, then continue." \
  --print \
  --dangerously-skip-permissions
```

### Worker Context Full

If worker reports `"status": "context_full"`:

1. Resume and ask for park: `/session:park`
2. Capture the park document
3. Spawn fresh worker with park doc as context
4. Continue from where it left off

## Cross-Project Learnings

After workers complete, extract patterns to `.hive/learnings/`:
- Common solutions
- Project-specific patterns
- Reusable approaches

Inject relevant learnings when spawning new workers.

## Example Session

```
User: "Fix the auth bug in project-a and add the new API endpoint to project-b"

Orchestrator:
1. Create .hive/workers/project-a-abc123/
2. Create .hive/workers/project-b-def456/
3. Write task.md for each
4. Spawn both workers in background
5. Start monitor
6. Wait for status changes...

[project-a worker writes: need_input, "Should I add rate limiting?"]

Orchestrator:
7. See status change
8. Ask user or decide
9. Resume: "Yes, add rate limiting with 100 req/min"

[Both workers eventually write: done]

Orchestrator:
10. Collect results
11. Report to user
12. Optionally park sessions
```

## Helper Scripts

Use these scripts to simplify operations:

```bash
SKILL_DIR=~/.claude/skills/hive
HIVE_DIR=/path/to/notes/.hive

# Setup (first time)
bash $SKILL_DIR/setup.sh $HIVE_DIR

# Spawn a worker
bash $SKILL_DIR/spawn.sh project-a "Fix the auth bug" $HIVE_DIR

# Check all worker statuses
bash $SKILL_DIR/status.sh $HIVE_DIR

# Monitor for changes (real-time)
bash $SKILL_DIR/monitor.sh $HIVE_DIR

# Cleanup done/failed workers
bash $SKILL_DIR/cleanup.sh $HIVE_DIR --archive
bash $SKILL_DIR/cleanup.sh $HIVE_DIR --delete
```

## Files in This Skill

- `SKILL.md` - This file (orchestration instructions)
- `spawn.sh` - Spawn a single worker with proper setup
- `status.sh` - Check status of all workers
- `monitor.sh` - Real-time inotifywait monitor
- `cleanup.sh` - Archive/delete completed workers
- `setup.sh` - Initialize .hive directory
- `worker-prompt.md` - Template for worker instructions
- `PROTOCOL.md` - Detailed status.json protocol

## Integration with Session Management

This skill integrates with the `session-management` skill:
- Use `/session:park` to capture worker knowledge
- Store park docs in `.claude-sessions/`
- Use `/session:apply` to propagate learnings
