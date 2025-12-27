#!/bin/bash
# Hive Cleanup Script
# Archives or removes completed/failed workers
#
# Usage: ./cleanup.sh [hive-dir] [--archive|--delete]
# Example: ./cleanup.sh .hive --archive   # Move done workers to archive
# Example: ./cleanup.sh .hive --delete    # Delete done workers

set -e

HIVE_DIR="${1:-.hive}"
ACTION="${2:---archive}"

if [[ ! -d "$HIVE_DIR/workers" ]]; then
    echo "No workers directory found"
    exit 0
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleaned=0

for worker_dir in "$HIVE_DIR/workers/"*/; do
    if [[ ! -d "$worker_dir" ]]; then
        continue
    fi

    worker_id=$(basename "$worker_dir")
    status_file="$worker_dir/status.json"

    # Check if done or error
    if [[ -f "$status_file" ]]; then
        status=$(jq -r '.status // "unknown"' "$status_file" 2>/dev/null || echo "unknown")

        if [[ "$status" == "done" ]] || [[ "$status" == "error" ]]; then
            if [[ "$ACTION" == "--archive" ]]; then
                mkdir -p "$HIVE_DIR/archive"
                mv "$worker_dir" "$HIVE_DIR/archive/"
                echo -e "${GREEN}Archived:${NC} $worker_id ($status)"
            elif [[ "$ACTION" == "--delete" ]]; then
                rm -rf "$worker_dir"
                echo -e "${YELLOW}Deleted:${NC} $worker_id ($status)"
            fi
            cleaned=$((cleaned + 1))
        fi
    else
        # No status file - check if transcript is empty (failed spawn)
        transcript_file="$worker_dir/transcript.jsonl"
        if [[ -f "$transcript_file" ]]; then
            lines=$(wc -l < "$transcript_file")
            if [[ $lines -le 2 ]]; then
                # Probably a failed spawn
                if [[ "$ACTION" == "--delete" ]]; then
                    rm -rf "$worker_dir"
                    echo -e "${YELLOW}Deleted (failed spawn):${NC} $worker_id"
                    cleaned=$((cleaned + 1))
                else
                    echo -e "${YELLOW}Skipped (failed spawn, use --delete):${NC} $worker_id"
                fi
            fi
        fi
    fi
done

echo ""
echo "Cleaned up $cleaned workers"
