#!/bin/bash
# Hive Worker Monitor
# Watches for status.json changes and reports them
#
# Usage: ./monitor.sh <hive-dir>
# Example: ./monitor.sh /path/to/notes/.hive

set -e

HIVE_DIR="${1:-.hive}"
WORKERS_DIR="$HIVE_DIR/workers"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "[$(date '+%H:%M:%S')] $1"
}

# Ensure workers directory exists
mkdir -p "$WORKERS_DIR"

# Check if inotifywait is available
if command -v inotifywait &> /dev/null; then
    log "${GREEN}Using inotifywait for real-time monitoring${NC}"

    # Watch for modifications and creations
    inotifywait -m -r -e modify -e create --format '%w%f %e' "$WORKERS_DIR" 2>/dev/null | \
    while read file event; do
        # Only process status.json files
        if [[ "$file" == */status.json ]]; then
            worker_dir=$(dirname "$file")
            worker_id=$(basename "$worker_dir")

            # Read and parse status
            if [[ -f "$file" ]]; then
                status=$(jq -r '.status // "unknown"' "$file" 2>/dev/null || echo "parse_error")

                case "$status" in
                    "working")
                        log "${BLUE}[$worker_id]${NC} Working..."
                        ;;
                    "need_input")
                        question=$(jq -r '.question // "No question provided"' "$file" 2>/dev/null)
                        log "${YELLOW}[$worker_id]${NC} NEEDS INPUT: $question"
                        echo "STATUS_CHANGE:$file"
                        ;;
                    "done")
                        result=$(jq -r '.result // "No result provided"' "$file" 2>/dev/null)
                        log "${GREEN}[$worker_id]${NC} DONE: $result"
                        echo "STATUS_CHANGE:$file"
                        ;;
                    "error")
                        error=$(jq -r '.error // "No error details"' "$file" 2>/dev/null)
                        log "${RED}[$worker_id]${NC} ERROR: $error"
                        echo "STATUS_CHANGE:$file"
                        ;;
                    "context_full")
                        progress=$(jq -r '.progress // "Unknown progress"' "$file" 2>/dev/null)
                        log "${YELLOW}[$worker_id]${NC} CONTEXT FULL: $progress"
                        echo "STATUS_CHANGE:$file"
                        ;;
                    *)
                        log "${RED}[$worker_id]${NC} Unknown status: $status"
                        ;;
                esac
            fi
        fi
    done
else
    log "${YELLOW}inotifywait not available, falling back to polling (10s interval)${NC}"

    # Store last known status for each worker
    declare -A last_status

    while true; do
        for status_file in "$WORKERS_DIR"/*/status.json; do
            if [[ -f "$status_file" ]]; then
                worker_dir=$(dirname "$status_file")
                worker_id=$(basename "$worker_dir")

                # Get current status hash
                current_hash=$(md5sum "$status_file" 2>/dev/null | cut -d' ' -f1 || echo "")

                # Check if changed
                if [[ "${last_status[$worker_id]}" != "$current_hash" ]]; then
                    last_status[$worker_id]="$current_hash"

                    status=$(jq -r '.status // "unknown"' "$status_file" 2>/dev/null || echo "parse_error")

                    case "$status" in
                        "need_input"|"done"|"error"|"context_full")
                            log "${YELLOW}[$worker_id]${NC} Status: $status"
                            echo "STATUS_CHANGE:$status_file"
                            ;;
                        "working")
                            log "${BLUE}[$worker_id]${NC} Working..."
                            ;;
                    esac
                fi
            fi
        done

        sleep 10
    done
fi
