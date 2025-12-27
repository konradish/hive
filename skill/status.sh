#!/bin/bash
# Hive Status Check Script
# Shows status of all workers or a specific worker
#
# Usage: ./status.sh [hive-dir] [worker-id]
# Example: ./status.sh .hive
# Example: ./status.sh .hive my-project-abc123

set -e

HIVE_DIR="${1:-.hive}"
WORKER_FILTER="${2:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ ! -d "$HIVE_DIR/workers" ]]; then
    echo "No workers directory found at $HIVE_DIR/workers"
    exit 0
fi

echo -e "${CYAN}=== Hive Worker Status ===${NC}"
echo ""

for worker_dir in "$HIVE_DIR/workers/"*/; do
    if [[ ! -d "$worker_dir" ]]; then
        continue
    fi

    worker_id=$(basename "$worker_dir")

    # Filter if specified
    if [[ -n "$WORKER_FILTER" ]] && [[ "$worker_id" != *"$WORKER_FILTER"* ]]; then
        continue
    fi

    status_file="$worker_dir/status.json"
    session_file="$worker_dir/session-id"
    transcript_file="$worker_dir/transcript.jsonl"

    echo -e "${BLUE}[$worker_id]${NC}"

    # Check if status file exists
    if [[ -f "$status_file" ]]; then
        status=$(jq -r '.status // "unknown"' "$status_file" 2>/dev/null || echo "parse_error")

        case "$status" in
            "working")
                progress=$(jq -r '.progress // "No progress info"' "$status_file" 2>/dev/null)
                echo -e "  Status: ${BLUE}working${NC}"
                echo "  Progress: $progress"
                ;;
            "need_input")
                question=$(jq -r '.question // "No question"' "$status_file" 2>/dev/null)
                echo -e "  Status: ${YELLOW}need_input${NC}"
                echo "  Question: $question"
                if [[ -f "$session_file" ]]; then
                    session_id=$(cat "$session_file")
                    echo "  Resume: claude --resume $session_id -p \"Your answer\" --print --dangerously-skip-permissions"
                fi
                ;;
            "done")
                result=$(jq -r '.result // "No result"' "$status_file" 2>/dev/null)
                echo -e "  Status: ${GREEN}done${NC}"
                echo "  Result: $result"
                ;;
            "error")
                error=$(jq -r '.error // "No error info"' "$status_file" 2>/dev/null)
                echo -e "  Status: ${RED}error${NC}"
                echo "  Error: $error"
                ;;
            "context_full")
                progress=$(jq -r '.progress // "Unknown"' "$status_file" 2>/dev/null)
                echo -e "  Status: ${YELLOW}context_full${NC}"
                echo "  Progress: $progress"
                ;;
            *)
                echo -e "  Status: ${RED}$status${NC}"
                ;;
        esac
    else
        # No status file - check transcript
        if [[ -f "$transcript_file" ]]; then
            lines=$(wc -l < "$transcript_file")
            echo -e "  Status: ${YELLOW}running (no status yet)${NC}"
            echo "  Transcript: $lines lines"
        else
            echo -e "  Status: ${RED}unknown (no files)${NC}"
        fi
    fi

    echo ""
done

# Summary
total=$(find "$HIVE_DIR/workers" -maxdepth 1 -type d | wc -l)
total=$((total - 1))  # Subtract the workers dir itself

if [[ $total -eq 0 ]]; then
    echo "No workers found."
else
    working=$(grep -l '"status": "working"' "$HIVE_DIR/workers/"*/status.json 2>/dev/null | wc -l || echo 0)
    need_input=$(grep -l '"status": "need_input"' "$HIVE_DIR/workers/"*/status.json 2>/dev/null | wc -l || echo 0)
    done_count=$(grep -l '"status": "done"' "$HIVE_DIR/workers/"*/status.json 2>/dev/null | wc -l || echo 0)
    errors=$(grep -l '"status": "error"' "$HIVE_DIR/workers/"*/status.json 2>/dev/null | wc -l || echo 0)

    echo -e "${CYAN}Summary:${NC} $total workers | ${BLUE}$working working${NC} | ${YELLOW}$need_input need input${NC} | ${GREEN}$done_count done${NC} | ${RED}$errors errors${NC}"
fi
