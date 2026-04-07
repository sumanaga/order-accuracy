#!/bin/sh
set -eu

# =============================================================================
# On-Demand RTSP Streamer
# =============================================================================
# Uses MediaMTX with on-demand streaming. No 2PC sync, no ffmpeg pre-start.
#
# How it works:
#   1. MediaMTX starts and listens on RTSP port
#   2. When a GStreamer client connects to rtsp://rtsp-streamer:8554/<path>
#   3. MediaMTX spawns ffmpeg to stream /media/<path>.mp4
#   4. Client receives frame 0 immediately — no race condition
#   5. When all clients disconnect, ffmpeg exits after 30s timeout
#
# Stream naming:
#   rtsp://rtsp-streamer:8554/station_1  → streams /media/station_1.mp4
#   rtsp://rtsp-streamer:8554/test       → streams /media/test.mp4
# =============================================================================

MEDIA_DIR=${MEDIA_DIR:-/media}
RTSP_PORT=${RTSP_PORT:-8554}
MEDIAMTX_BIN=${MEDIAMTX_BIN:-/opt/rtsp-streamer/mediamtx}

# Logging helper — prefixes every message with ISO timestamp
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S.%3N') [rtsp-streamer] $*"
}

if [ ! -d "$MEDIA_DIR" ]; then
  log "ERROR Media directory $MEDIA_DIR does not exist" >&2
  exit 1
fi

if [ ! -x "$MEDIAMTX_BIN" ]; then
  log "ERROR mediamtx binary $MEDIAMTX_BIN not found or not executable" >&2
  exit 1
fi

# Verify at least one video file exists
set -- "$MEDIA_DIR"/*.mp4
if [ ! -e "$1" ]; then
  log "ERROR No .mp4 files found in $MEDIA_DIR" >&2
  exit 1
fi

# Find the source video (first .mp4 or RTSP_STREAM_NAME if set)
SOURCE_VIDEO=${RTSP_STREAM_NAME:-}
if [ -n "$SOURCE_VIDEO" ] && [ -f "$MEDIA_DIR/${SOURCE_VIDEO}.mp4" ]; then
  source_file="$MEDIA_DIR/${SOURCE_VIDEO}.mp4"
else
  set -- "$MEDIA_DIR"/*.mp4
  source_file="$1"
fi

source_name=$(basename "$source_file" .mp4)

log "=== On-Demand RTSP Streamer ==="
log "Media directory: $MEDIA_DIR"
log "Source video: $source_file"
log "Available video files and stream mappings:"
for f in "$MEDIA_DIR"/*.mp4; do
  name=$(basename "$f" .mp4)
  log "  $f → rtsp://rtsp-streamer:${RTSP_PORT}/${name}"
done
log "Default fallback video: $source_file"
log "On-demand mode: streams start when station_worker connects"
NUM_WORKERS=${WORKERS:-2}
log "Expected station connections (WORKERS=$NUM_WORKERS):"
i=1
while [ "$i" -le "$NUM_WORKERS" ]; do
  log "  station_${i} → rtsp://rtsp-streamer:${RTSP_PORT}/station_${i} → /media/station_${i}.mp4 (or fallback: $source_file)"
  i=$((i + 1))
done
log "================================"

# Start MediaMTX — it handles everything via mediamtx.yml config
log "Starting mediamtx on port $RTSP_PORT ..."
exec "$MEDIAMTX_BIN"
