#!/bin/bash

# --- CONFIGURATION ---
CONFIG_FILE="$(dirname "$0")/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found!"
    exit 1
fi

get_config_value() {
    local key="$1"
    grep -E "^[[:space:]]*${key}[[:space:]]*:" "$CONFIG_FILE" | head -n1 | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" | sed -E 's/^"//; s/"$//; s/^'\''//; s/'\''$//'
}

OUTPUT_DIR=$(get_config_value "output_dir")
CONTAINER_NAME=$(get_config_value "container_name")
CONTAINER_ENGINE=$(get_config_value "container_engine")
SELINUX=$(get_config_value "selinux")

AUDIO_PASSTHROUGH_CODECS=$(get_config_value "audio_passthrough_codecs")
AUDIO_FALLBACK_CODEC=$(get_config_value "audio_fallback_codec")
AUDIO_FALLBACK_BITRATE=$(get_config_value "audio_fallback_bitrate")

VIDEO_CODEC=$(get_config_value "video_codec")
VIDEO_PRESET=$(get_config_value "video_preset")
VIDEO_CRF=$(get_config_value "video_crf")
VIDEO_TUNE=$(get_config_value "video_tune")
VIDEO_PIX_FMT=$(get_config_value "video_pix_fmt")
VIDEO_FPS_MODE=$(get_config_value "video_fps_mode")

OUTPUT_SUFFIX=$(get_config_value "output_suffix")
OUTPUT_CONTAINER=$(get_config_value "output_container")

# Apply defaults if empty
: "${CONTAINER_NAME:="ffmpeg"}"
: "${CONTAINER_ENGINE:="podman"}"
: "${SELINUX:="true"}"
: "${AUDIO_PASSTHROUGH_CODECS:="aac"}"
: "${AUDIO_FALLBACK_CODEC:="libopus"}"
: "${AUDIO_FALLBACK_BITRATE:="128k"}"
: "${VIDEO_CODEC:="libsvtav1"}"
: "${VIDEO_PRESET:="2"}"
: "${VIDEO_CRF:="23"}"
: "${VIDEO_TUNE:="0"}"
: "${VIDEO_PIX_FMT:="yuv420p10le"}"
: "${VIDEO_FPS_MODE:="cfr"}"
: "${OUTPUT_CONTAINER:="mkv"}"

if [ -z "$1" ]; then
    echo "Usage: ./transcode.sh <input_file>"
    exit 1
fi

INPUT_PATH=$(realpath "$1")
INPUT_DIR=$(dirname "$INPUT_PATH")
INPUT_FILE=$(basename "$INPUT_PATH")

if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$INPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR"

if [ -z "$OUTPUT_SUFFIX" ]; then
    OUTPUT_SUFFIX="[${VIDEO_CODEC}]"
fi

VOL_SUFFIX=""
if [ "${SELINUX,,}" = "true" ] || [ "$SELINUX" = "1" ] || [ "${SELINUX,,}" = "yes" ]; then
    VOL_SUFFIX=":z"
fi

# 1. Check if the first audio stream is in our passthrough list using ffprobe
AUDIO_CODEC=$($CONTAINER_ENGINE run --rm --entrypoint ffprobe -v "$INPUT_DIR:/input${VOL_SUFFIX}" lscr.io/linuxserver/ffmpeg \
  -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "/input/$INPUT_FILE" | tr -d '\r\n[:space:]')

CLEAN_PASSTHROUGH=$(echo "$AUDIO_PASSTHROUGH_CODECS" | tr -d ' ')
if [[ ",$CLEAN_PASSTHROUGH," == *",$AUDIO_CODEC,"* ]]; then
    AUDIO_SETTINGS="-c:a copy"
    echo "Detected $AUDIO_CODEC audio. Using passthrough."
else
    AUDIO_SETTINGS="-c:a $AUDIO_FALLBACK_CODEC -b:a $AUDIO_FALLBACK_BITRATE"
    echo "Detected $AUDIO_CODEC audio. Converting to $AUDIO_FALLBACK_CODEC $AUDIO_FALLBACK_BITRATE."
fi

# 2. Construct the FFmpeg flags based on your requirements
# -map 0: Includes all streams (data, subtitles, etc.)
# -pix_fmt yuv420p10le: Forces 10-bit
# -vsync cfr: Constant Framerate
# tune=0: This is the 'VQ' (Visual Quality) tune in SVT-AV1
VIDEO_SETTINGS="-c:v $VIDEO_CODEC -preset $VIDEO_PRESET -crf $VIDEO_CRF -svtav1-params tune=$VIDEO_TUNE -pix_fmt $VIDEO_PIX_FMT -fps_mode $VIDEO_FPS_MODE"
DATA_SETTINGS="-map 0 -map_metadata 0 -c:s copy -c:d copy"

# 3. Run the transcode in the background
$CONTAINER_ENGINE run -d --rm \
  --name "$CONTAINER_NAME" \
  -v "$INPUT_DIR:/input${VOL_SUFFIX}" \
  -v "$OUTPUT_DIR:/output${VOL_SUFFIX}" \
  lscr.io/linuxserver/ffmpeg \
  -y \
  -i "/input/$INPUT_FILE" \
  $VIDEO_SETTINGS \
  $AUDIO_SETTINGS \
  $DATA_SETTINGS \
  "/output/${INPUT_FILE%.*} ${OUTPUT_SUFFIX}.${OUTPUT_CONTAINER}" > /dev/null

echo "Background task started: $CONTAINER_NAME"
echo "Monitor with: $CONTAINER_ENGINE logs -f $CONTAINER_NAME"