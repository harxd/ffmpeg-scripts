#!/bin/bash

# --- CONFIGURATION ---
CONFIG_FILE="$(dirname "$0")/config.yaml"
CONTAINER_NAME="ffmpeg"
CONTAINER_ENGINE="podman"

if [ -f "$CONFIG_FILE" ]; then
    get_config_value() {
        local key="$1"
        grep -E "^[[:space:]]*${key}[[:space:]]*:" "$CONFIG_FILE" | head -n1 | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" | sed -E 's/^"//; s/"$//; s/^'\''//; s/'\''$//'
    }
    CONF_CONTAINER=$(get_config_value "container_name")
    if [ -n "$CONF_CONTAINER" ]; then
        CONTAINER_NAME="$CONF_CONTAINER"
    fi
    CONF_ENGINE=$(get_config_value "container_engine")
    if [ -n "$CONF_ENGINE" ]; then
        CONTAINER_ENGINE="$CONF_ENGINE"
    fi
fi
SHOW_NAME=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --name)
      SHOW_NAME=1
      shift
      ;;
    *)
      CONTAINER_NAME="$1"
      shift
      ;;
  esac
done
QUEUE_STATUS_FILE="$(dirname "$0")/.queue_status"

# Hide cursor and disable line wrap while running, explicitly restore both when shutting down via Ctrl+C
trap "printf '\033[?25h\033[?7h\n'; exit" INT TERM EXIT
printf "\033[?25l\033[?7l"

HAS_RUN=0

while true; do
    QUEUE_INFO=""
    IS_QUEUE=0
    if [ -f "$QUEUE_STATUS_FILE" ]; then
        IS_QUEUE=1
        QUEUE_INFO=$(cat "$QUEUE_STATUS_FILE")
        if [ "$QUEUE_INFO" = "DONE" ]; then
            printf "\r\033[2K Queue finished.\n"
            rm -f "$QUEUE_STATUS_FILE"
            break
        fi
    fi

    if [ "$HAS_RUN" -eq 1 ]; then
        # Move cursor up to overwrite previous block and clear below
        if [ "$IS_QUEUE" -eq 1 ] && [ -n "$QUEUE_INFO" ]; then
            printf "\r\033[8A\033[J"
        else
            printf "\r\033[7A\033[J"
        fi
        HAS_RUN=0
    fi

    # Check if the container is running or exists
    if ! $CONTAINER_ENGINE ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
        if [ "$IS_QUEUE" -eq 1 ]; then
            printf "\r\033[2K Waiting for next container in queue ($QUEUE_INFO)...\n"
            sleep 1
            # Go up one line to overwrite the waiting message next time
            printf "\033[1A"
            continue
        else
            echo "Error: Container '$CONTAINER_NAME' not found."
            break
        fi
    fi

    printf "\r\033[2K Waiting for ffmpeg to initialize..."

    # The ffmpeg console outputs progress using carriage returns (\r).
    # We convert those to newlines (\n) so awk can read them line-by-line.
    # Awk calculates percentage, formats ETA, and nicely aligns multiple lines.
    $CONTAINER_ENGINE logs -f "$CONTAINER_NAME" 2>&1 | tr '\r' '\n' | awk -v show_name="$SHOW_NAME" -v q_info="$QUEUE_INFO" '
BEGIN {
    total_seconds = 0
    printed_lines = 0
    parsed_video_name = ""
}
/Input #0, .* from \047/ {
    # Parse the input file name from the ffmpeg log: Input #0, ... from '\''/input/file.mp4'\''
    if (match($0, /from \047[^\047]+\047/)) {
        full_path = substr($0, RSTART + 6, RLENGTH - 7)
        # Extract basename
        n = split(full_path, path_parts, "/")
        parsed_video_name = path_parts[n]
    }
}
/Duration: / && total_seconds == 0 {
    # Extract total duration to calculate ETA and Percentage
    if (match($0, /Duration: [0-9]+:[0-9]+:[0-9]+/)) {
        d_str = substr($0, RSTART + 10, RLENGTH - 10)
        split(d_str, arr, ":")
        total_seconds = arr[1]*3600 + arr[2]*60 + arr[3]
    }
}
/^frame=/ {
    frame = "0"
    if (match($0, /frame=\s*[0-9]+/)) {
        frame_str = substr($0, RSTART, RLENGTH)
        sub(/frame=\s*/, "", frame_str)
        frame = frame_str
    }
    
    fps = "0.0"
    if (match($0, /fps=\s*[0-9.]+/)) {
        fps_str = substr($0, RSTART, RLENGTH)
        sub(/fps=\s*/, "", fps_str)
        fps = fps_str
    }
    
    time_str = "00:00:00"
    curr_seconds = 0
    if (match($0, /time=[0-9]+:[0-9]+:[0-9.]+/)) {
        time_str_ext = substr($0, RSTART+5, RLENGTH-5)
        time_str = time_str_ext
        sub(/\.[0-9]+$/, "", time_str)
        split(time_str_ext, t_arr, ":")
        curr_seconds = t_arr[1]*3600 + t_arr[2]*60 + t_arr[3]
    }
    
    bitrate = "N/A"
    if (match($0, /bitrate=\s*[0-9.]+[a-zA-Z\/]+/)) {
        br_str = substr($0, RSTART, RLENGTH)
        sub(/bitrate=\s*/, "", br_str)
        bitrate = br_str
    }
    
    speed = "N/A"
    if (match($0, /speed=\s*[0-9.]+x/)) {
        sp_str = substr($0, RSTART, RLENGTH)
        sub(/speed=\s*/, "", sp_str)
        speed = sp_str
    }
    
    real_elapsed = "N/A"
    if (match($0, /elapsed=\s*[0-9]+:[0-9]+:[0-9.]+/)) {
        el_str = substr($0, RSTART, RLENGTH)
        sub(/elapsed=\s*/, "", el_str)
        sub(/\.[0-9]+$/, "", el_str)
        if (el_str ~ /^[0-9]:/) {
            el_str = "0" el_str
        }
        real_elapsed = el_str
    }
    
    perc = 0
    eta_str = "Calculating..."
    if (total_seconds > 0) {
        perc = (curr_seconds / total_seconds) * 100
        if (perc > 100) perc = 100
        
        sp_val = speed + 0
        # Wait until speed is registered to show an ETA
        if (sp_val > 0) {
            eta_sec = (total_seconds - curr_seconds) / sp_val
            if (eta_sec < 0) eta_sec = 0
            
            eh = int(eta_sec / 3600)
            em = int((eta_sec % 3600) / 60)
            es = int(eta_sec % 60)
            eta_str = sprintf("%02d:%02d:%02d", eh, em, es)
        }
    }
    
    # Generate visual progress bar using ASCII characters for compatibility
    bar_length = 30
    filled = int((perc / 100) * bar_length)
    bar = ""
    for(i=1; i<=bar_length; i++) {
        if(i<=filled) bar = bar "#"
        else bar = bar "-"
    }
    
    # If we already printed status block, navigate terminal cursor UP to overwrite it
    if (printed_lines > 0) {
        printf "\033[%dA", printed_lines
    }
    
    # Build clean interface
    out = ""
    if (q_info != "") {
        out = out sprintf("\r\033[2K Queue:    %s\n", q_info)
    }

    if (show_name == "1") {
        if (parsed_video_name != "") {
            out = out sprintf("\r\033[2K File:     %s\n", parsed_video_name)
        } else {
            out = out sprintf("\r\033[2K File:     Parsing...\n")
        }
    } else {
        out = out sprintf("\r\033[2K File:     Pass --name\n")
    }
    
    out = out sprintf("\r\033[2K Progress: [%s] %.1f%%\n", bar, perc)
    out = out sprintf("\r\033[2K Frame:    %s\n", frame)
    out = out sprintf("\r\033[2K FPS:      %s\n", fps)
    out = out sprintf("\r\033[2K Bitrate:  %s\n", bitrate)
    out = out sprintf("\r\033[2K Position: %s\n", time_str)
    out = out sprintf("\r\033[2K Elapsed:  %s\n", real_elapsed)
    out = out sprintf("\r\033[2K ETA:      %s", eta_str)
    
    printf "%s", out
    fflush()
    
    printed_lines = (q_info != "") ? 8 : 7
}
/Conversion failed/ || /Error/ {
    printf "\033[?7h\n[!] %s\n\033[?7l", $0
    fflush()
}
'

    HAS_RUN=1

    # If it was just a single transcode, exit the loop.
    if [ "$IS_QUEUE" -eq 0 ]; then
        break
    fi
    
    sleep 1
done
