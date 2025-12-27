#!/bin/bash
# Hive Worker Spawn Script
# Spawns a single worker with proper setup
#
# Usage: ./spawn.sh <project> "<task>" [hive-dir]
# Example: ./spawn.sh my-project "Analyze next development steps" /path/to/notes/.hive

set -e

PROJECT="$1"
TASK="$2"
HIVE_DIR="${3:-.hive}"

if [[ -z "$PROJECT" ]] || [[ -z "$TASK" ]]; then
    echo "Usage: $0 <project> \"<task>\" [hive-dir]"
    echo "Example: $0 my-project \"Fix auth bug\" .hive"
    exit 1
fi

# Check projects.json exists
if [[ ! -f "$HIVE_DIR/projects.json" ]]; then
    echo "Error: $HIVE_DIR/projects.json not found"
    echo "Run setup.sh first or create projects.json manually"
    exit 1
fi

# Get project path
PROJECT_PATH=$(jq -r ".[\"$PROJECT\"]" "$HIVE_DIR/projects.json")
if [[ "$PROJECT_PATH" == "null" ]] || [[ -z "$PROJECT_PATH" ]]; then
    echo "Error: Project '$PROJECT' not found in projects.json"
    echo "Available projects:"
    jq -r 'keys[]' "$HIVE_DIR/projects.json"
    exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Error: Project path does not exist: $PROJECT_PATH"
    exit 1
fi

# Generate fresh UUID
WORKER_UUID=$(uuidgen)
WORKER_ID="${PROJECT}-${WORKER_UUID}"
WORKER_DIR="$HIVE_DIR/workers/$WORKER_ID"
STATUS_FILE="$WORKER_DIR/status.json"

# Create worker directory
mkdir -p "$WORKER_DIR"
echo "$WORKER_UUID" > "$WORKER_DIR/session-id"
echo "$TASK" > "$WORKER_DIR/task.md"

# Build the worker prompt
WORKER_PROMPT="You are a **hive worker** for the $PROJECT project.

## Your Identity
- Worker ID: $WORKER_ID
- Status file: $STATUS_FILE
- You are being coordinated by an orchestrator in another Claude Code instance

## Your Task
$TASK

## Communication Protocol

You MUST communicate via the status file. Write JSON to $STATUS_FILE.

### FIRST: Write initial status immediately
Before doing anything else, write:
{\"status\": \"working\", \"progress\": \"Starting task analysis\"}

### When You Need Orchestrator Input
If you hit ambiguity, need a decision, or have a question:
{\"status\": \"need_input\", \"question\": \"Your question\", \"options\": [\"A\", \"B\"]}
Then STOP and exit. The orchestrator will resume you.

### When You Complete the Task
**Before marking done, you MUST (in this order):**
1. Run /session:park to capture institutional knowledge
2. Write a run report to $WORKER_DIR/run-report.md with: task, approach, decisions, files changed, learnings
3. If you made code changes, commit them with a descriptive message
4. Then write the done status

{\"status\": \"done\", \"result\": \"Summary\", \"files_changed\": [], \"committed\": true, \"parked\": true, \"notes\": \"Follow-ups\"}

### When You Encounter an Error
{\"status\": \"error\", \"error\": \"What went wrong\", \"suggestion\": \"How to fix\"}

## Important Rules
1. Write status.json BEFORE stopping
2. STOP after writing need_input - don't guess
3. Be specific in questions
4. Include options to speed up decisions

Now begin. Write initial 'working' status, then analyze and complete the task."

# Spawn the worker
cd "$PROJECT_PATH" && \
claude \
  -p "$WORKER_PROMPT" \
  --session-id "$WORKER_UUID" \
  --print \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  2>&1 > "$WORKER_DIR/transcript.jsonl" &

WORKER_PID=$!

echo "Spawned $WORKER_ID (PID: $WORKER_PID)"
echo "Status file: $STATUS_FILE"
echo "Transcript: $WORKER_DIR/transcript.jsonl"
echo ""
echo "Monitor with: cat $STATUS_FILE"
echo "Resume with: claude --resume $WORKER_UUID -p \"Your message\" --print --dangerously-skip-permissions"
