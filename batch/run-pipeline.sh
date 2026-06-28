#!/bin/bash

# Career-Ops Batch Pipeline Orchestrator
# This script runs the evaluation loop in headless mode.

BASE_DIR="/mnt/f/Development/career-ops"
LOG_DIR="$BASE_DIR/batch/logs"
BATCH_LOG="$LOG_DIR/batch-run.log"
FAILED_LOG="$LOG_DIR/failed.log"
PIPELINE_FILE="$BASE_DIR/data/pipeline.md"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Trap for interruption (Suggestion - Interruption)
trap "echo 'Interrupted by user'; exit 1" SIGINT SIGTERM

DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "--- DRY RUN MODE ---"
fi

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$BATCH_LOG"
}

if [[ "$DRY_RUN" == "false" ]]; then
    log "Starting batch processing loop"
fi

# Loop through each URL directly from the extraction script (Minor - Scalability)
# Using process substitution to keep variables in the main shell if needed
while IFS= read -r URL; do
    if [[ -z "$URL" ]]; then continue; fi

    # Escape URL for safe shell usage (Major - Shell Injection)
    SAFE_URL=$(printf '%q' "$URL")

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "gemini -p \"/career-ops batch $SAFE_URL\""
    else
        log "Processing URL: $URL"
        
        # Execute gemini command and capture all output to batch log
        # Redirect stdin from /dev/null to prevent consuming the loop's stdin
        # Added -y for auto-approval in headless mode
        # Added --include-directories for mirrored protocols to satisfy policy
        # Explicitly using gemini-1.5-flash for stability and higher capacity
        # Disabled extensions to prevent triggering the TechLead persona
        gemini -y \
            --model gemini-1.5-flash \
            --include-directories "$BASE_DIR,$BASE_DIR/.maestro-protocols" \
            --extensions none \
            -p "/career-ops batch $SAFE_URL" < /dev/null >> "$BATCH_LOG" 2>&1
        
        # Check exit code
        if [[ $? -ne 0 ]]; then
            log "ERROR: Failed to process $URL"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $URL" >> "$FAILED_LOG"
        else
            log "SUCCESS: Processed $URL"
            # Mark as processed in pipeline.md (Major - Idempotency)
            sed -i "s|^- \[ \] \(.*$URL\)|- [x] \1|" "$PIPELINE_FILE"
        fi
        
        log "Sleeping 10 seconds..."
        sleep 10
    fi
done < <(node "$BASE_DIR/batch/extract-pipeline.mjs")

if [[ "$DRY_RUN" == "false" ]]; then
    log "Batch processing loop finished"
fi
