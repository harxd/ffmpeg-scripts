#!/bin/bash

# --- CONFIGURATION ---
CONFIG_FILE="$(dirname "$0")/config.yaml"
CONTAINER_NAME="ffmpeg"
CONTAINER_ENGINE="podman"

# Parse config to find out the engine and container name
if [ -f "$CONFIG_FILE" ]; then
    CONF_CONTAINER=$(grep -E "^[[:space:]]*container_name[[:space:]]*:" "$CONFIG_FILE" | head -n1 | sed -E 's/^[[:space:]]*container_name[[:space:]]*:[[:space:]]*//' | sed -E 's/^"//; s/"$//; s/^'\''//; s/'\''$//')
    [ -n "$CONF_CONTAINER" ] && CONTAINER_NAME="$CONF_CONTAINER"
    
    CONF_ENGINE=$(grep -E "^[[:space:]]*container_engine[[:space:]]*:" "$CONFIG_FILE" | head -n1 | sed -E 's/^[[:space:]]*container_engine[[:space:]]*:[[:space:]]*//' | sed -E 's/^"//; s/"$//; s/^'\''//; s/'\''$//')
    [ -n "$CONF_ENGINE" ] && CONTAINER_ENGINE="$CONF_ENGINE"
fi

if [ $# -eq 0 ]; then
    echo "Usage: ./queue.sh <file1> <file2> ..."
    echo "Example: ./queue.sh *.mp4"
    exit 1
fi

echo "Queuing $# files for transcoding..."
echo

QUEUE_STATUS_FILE="$(dirname "$0")/.queue_status"
QUEUE_TOTAL=$#
QUEUE_CURRENT=0

# Handle Ctrl+C cleanly
trap 'echo -e "\nQueue interrupted by user. Stopping container..."; $CONTAINER_ENGINE stop "$CONTAINER_NAME" >/dev/null 2>&1; rm -f "$QUEUE_STATUS_FILE"; exit 130' INT TERM

# Initialize
echo "0/$QUEUE_TOTAL" > "$QUEUE_STATUS_FILE"

for file in "$@"; do
    if [ ! -f "$file" ]; then
        echo "File not found: $file, skipping..."
        continue
    fi

    echo "========================================================="
    echo "Starting: $file"
    echo "========================================================="
    
    QUEUE_CURRENT=$((QUEUE_CURRENT + 1))
    echo "$QUEUE_CURRENT/$QUEUE_TOTAL" > "$QUEUE_STATUS_FILE"

    # Run the existing transcode script
    "$(dirname "$0")/transcode.sh" "$file"
    
    # Because transcode.sh uses '-d' to run podman/docker in the background,
    # the script exits immediately. To make it a queue, we use the 'wait' 
    # command to block until the container finishes.
    $CONTAINER_ENGINE wait "$CONTAINER_NAME" > /dev/null
    WAIT_EXIT=$?
    
    # If docker wait is interrupted with Ctrl+C, its exit code is 130
    if [ $WAIT_EXIT -eq 130 ]; then
        echo -e "\nQueue interrupted by user. Stopping container..."
        $CONTAINER_ENGINE stop "$CONTAINER_NAME" >/dev/null 2>&1
        rm -f "$QUEUE_STATUS_FILE"
        exit 130
    fi
    
    # Check exit code
    if [ $WAIT_EXIT -ne 0 ]; then
        echo "Warning: Transcoding may have failed for $file"
    else
        echo "Finished: $file"
    fi
    echo
done

echo "DONE" > "$QUEUE_STATUS_FILE"
echo "Queue finished!"
