# Hive Protocol Reference

Detailed specification for orchestrator-worker communication.

## Directory Structure

```
.hive/
├── workers/
│   └── <project>-<uuid>/
│       ├── status.json       # Current worker state (worker writes)
│       ├── task.md           # Original task assignment (orchestrator writes)
│       ├── session-id        # UUID for --resume (orchestrator writes)
│       ├── transcript.jsonl  # Full stream-json output (every tool call)
│       └── run-report.md     # Worker's summary of the run (worker writes)
├── projects.json             # Project path registry
└── learnings/
    ├── patterns.md           # Cross-project patterns
    └── <project>-insights.md # Project-specific learnings
```

## Status File Schema

### status.json

```typescript
interface WorkerStatus {
  // Required
  status: "working" | "need_input" | "done" | "error" | "context_full";

  // Optional - depends on status
  progress?: string;           // What's been done so far
  question?: string;           // For need_input: the question
  context?: string;            // For need_input: background info
  options?: string[];          // For need_input: suggested choices
  result?: string;             // For done: summary of work
  files_changed?: string[];    // For done: list of modified files
  committed?: boolean;         // For done: whether changes were committed
  parked?: boolean;            // For done: whether session was parked
  notes?: string;              // For done: follow-up items
  error?: string;              // For error: what went wrong
  attempted?: string;          // For error: what was tried
  suggestion?: string;         // For error: how to fix
  remaining?: string;          // For context_full: what's left to do

  // Metadata (optional)
  timestamp?: string;          // ISO 8601 timestamp
  turn_count?: number;         // How many turns the worker has taken
}
```

### Examples

**Working:**
```json
{
  "status": "working",
  "progress": "Analyzed auth flow, found session timeout issue",
  "timestamp": "2025-12-18T21:30:00Z",
  "turn_count": 3
}
```

**Need Input:**
```json
{
  "status": "need_input",
  "question": "The session timeout is set to 5 minutes. Should I increase it to 30 minutes or make it configurable?",
  "context": "Found hardcoded value in auth.py:42. The config system supports env vars.",
  "options": [
    "Increase to 30 minutes (simple)",
    "Make configurable via SESSION_TIMEOUT env var (flexible)",
    "Both - default 30min, override via env var (recommended)"
  ],
  "timestamp": "2025-12-18T21:32:00Z"
}
```

**Done:**

Workers MUST park and commit before marking done:
1. Run `/session:park` to capture institutional knowledge
2. Commit code changes with descriptive message
3. Then write done status

```json
{
  "status": "done",
  "result": "Fixed session timeout. Now defaults to 30 minutes, configurable via SESSION_TIMEOUT env var.",
  "files_changed": [
    "src/auth.py",
    "src/config.py",
    ".env.example"
  ],
  "committed": true,
  "parked": true,
  "notes": "Consider adding session refresh on activity in future iteration",
  "timestamp": "2025-12-18T21:45:00Z",
  "turn_count": 8
}
```

**Error:**
```json
{
  "status": "error",
  "error": "Cannot find auth.py - project structure different than expected",
  "attempted": "Searched for auth.py, authentication.py, login.py",
  "suggestion": "Please provide the path to the authentication module",
  "timestamp": "2025-12-18T21:31:00Z"
}
```

**Context Full:**
```json
{
  "status": "context_full",
  "progress": "Completed auth fix, started on API rate limiting",
  "remaining": "Need to add rate limit tests and update documentation",
  "timestamp": "2025-12-18T22:00:00Z",
  "turn_count": 45
}
```

## Projects Registry

### projects.json

```json
{
  "project-a": "/path/to/project-a",
  "project-b": "/path/to/project-b",
  "notes": "/path/to/notes",
  "infra": "/path/to/infra"
}
```

Add projects as needed. The orchestrator reads this to know where to spawn workers.

## Orchestrator Commands

### Spawn Worker

```bash
PROJECT="project-a"
PROJECT_PATH=$(jq -r ".[\"$PROJECT\"]" .hive/projects.json)
WORKER_UUID=$(uuidgen)
WORKER_ID="${PROJECT}-${WORKER_UUID}"
WORKER_DIR=".hive/workers/$WORKER_ID"

mkdir -p "$WORKER_DIR"
echo "$WORKER_UUID" > "$WORKER_DIR/session-id"
echo "Task description here" > "$WORKER_DIR/task.md"

cd "$PROJECT_PATH" && \
claude \
  -p "<worker prompt with substitutions>" \
  --session-id "$WORKER_UUID" \
  --print \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  2>&1 > "$WORKER_DIR/transcript.jsonl" &
```

### Resume Worker

```bash
WORKER_ID="project-a-abc123"
WORKER_DIR=".hive/workers/$WORKER_ID"
SESSION_ID=$(cat "$WORKER_DIR/session-id")
PROJECT=$(echo "$WORKER_ID" | cut -d'-' -f1)
PROJECT_PATH=$(jq -r ".[\"$PROJECT\"]" .hive/projects.json)

cd "$PROJECT_PATH" && \
claude \
  --resume "$SESSION_ID" \
  -p "Orchestrator response: <your answer here>" \
  --print \
  --dangerously-skip-permissions \
  2>&1 >> "$WORKER_DIR/transcript.jsonl"
```

### Check All Workers

```bash
for status_file in .hive/workers/*/status.json; do
  worker_dir=$(dirname "$status_file")
  worker_id=$(basename "$worker_dir")
  echo "=== $worker_id ==="
  cat "$status_file" 2>/dev/null || echo "No status yet"
done
```

### Park Worker

```bash
SESSION_ID=$(cat "$WORKER_DIR/session-id")
cd "$PROJECT_PATH" && \
claude \
  --resume "$SESSION_ID" \
  -p "Please run /session:park to capture your progress." \
  --print \
  --dangerously-skip-permissions
```

## Monitor Events

The monitor.sh script outputs lines like:

```
STATUS_CHANGE:<worker-dir>/status.json
```

Parse and react:
1. Read the status.json file
2. Check the `status` field
3. Take appropriate action

## Error Handling

### Worker Crashes (No Status Update)

If a worker hasn't updated status in a while:
1. Check if process is still running
2. Check transcript.jsonl for errors
3. Either resume or spawn fresh worker

### Stale Workers

Workers with old timestamps (> 1 hour without update):
1. Attempt resume with "Are you still working?"
2. If no response, consider dead
3. Park and spawn fresh if needed

### Cleanup

After task completion or abandonment:
```bash
# Archive
mv ".hive/workers/$WORKER_ID" ".hive/archive/"

# Or delete
rm -rf ".hive/workers/$WORKER_ID"
```

## Transcript Format

With `--output-format stream-json --verbose`, the transcript captures:

```jsonl
{"type": "system", "subtype": "init", "session_id": "...", "tools": [...], ...}
{"type": "user", "message": {"content": "..."}, ...}
{"type": "assistant", "message": {"content": [{"type": "tool_use", ...}]}, ...}
{"type": "tool_result", "tool_use_id": "...", "content": "...", ...}
{"type": "result", "total_cost_usd": 0.07, "duration_ms": 45000, ...}
```

Useful for:
- Debugging worker behavior
- Extracting tool calls and decisions
- Calculating costs
- Learning from worker approaches

## Cost Tracking

The final result line includes cost:
```json
{"type": "result", "total_cost_usd": 0.07, "usage": {...}}
```

Extract with:
```bash
tail -1 transcript.jsonl | jq '.total_cost_usd'
```

Sum costs across workers for total spend.
