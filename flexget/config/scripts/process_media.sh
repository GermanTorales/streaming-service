#!/bin/bash
set -euo pipefail

SRC="$1"
DST_DIR="$2"
DST_FILE="$3"
MEDIA_TYPE="${4:-general}"

LOCK_FILE="/tmp/processing_$(echo "$SRC" | md5sum | cut -d' ' -f1).lock"
TEMP_DIR="/tmp/media_processing_$$"

acquire_lock() {
  local timeout=300
  local count=0

  while ! mkdir "$LOCK_FILE" 2>/dev/null; do
    if [ $count -ge $timeout ]; then
      echo "[ERROR] Timeout waiting lock for $(basename "$SRC")"
      exit 1
    fi
    sleep 1
    ((count++))
  done
  echo "[INFO] Lock for $(basename "$SRC")"
}

cleanup() {
  rm -rf "$TEMP_DIR" 2>/dev/null || true
  rmdir "$LOCK_FILE" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

acquire_lock

mkdir -p "$TEMP_DIR"
mkdir -p "$DST_DIR"

echo "[INFO] Processing $MEDIA_TYPE: $(basename "$SRC")"

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "[ERROR] ffprobe not found. Moving without verification"
  mv -n "$SRC" "$DST_DIR/$DST_FILE"
  exit 0
fi

vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
  -of default=noprint_wrappers=1:nokey=1 "$SRC" 2>/dev/null || echo "unknown")
vcodec=$(echo "$vcodec" | tr '[:upper:]' '[:lower:]' | xargs)

echo "[INFO] Analyzing audio streams..."

audio_info=$(ffprobe -v error -select_streams a -show_entries stream=index,codec_name \
  -of csv=p=0:nk=1 "$SRC" 2>/dev/null || echo "")

if [ -z "$audio_info" ]; then
  echo "[WARN] Audio streams not found."
  acodecs_list=""
  needs_transcoding=false
else
  acodecs_list=""
  needs_transcoding=false

  while IFS=',' read -r stream_index codec_name; do
    codec_clean=$(echo "$codec_name" | tr '[:upper:]' '[:lower:]' | xargs)
    acodecs_list="$acodecs_list $codec_clean"
    echo "[INFO] Stream $stream_index: $codec_clean"
  done <<<"$audio_info"
fi

echo "[INFO] Video: $vcodec, Audio streams: $acodecs_list"

if [[ "$vcodec" != "h264" && "$vcodec" != "h265" && "$vcodec" != "av1" && "$vcodec" != "unknown" ]]; then
  echo "[WARN] Video codec doesn't supported: $vcodec. Moving without changes."
  mv -n "$SRC" "$DST_DIR/$DST_FILE"
  exit 0
fi

case "$MEDIA_TYPE" in
"anime")
  AUDIO_BITRATE="192k"
  AUDIO_CHANNELS=""
  SUPPORTED_CODECS="aac|ac3|flac|opus"
  ;;
"tv")
  AUDIO_BITRATE="192k"
  AUDIO_CHANNELS="-ac 2"
  SUPPORTED_CODECS="aac|ac3"
  ;;
"movies")
  AUDIO_BITRATE="256k"
  AUDIO_CHANNELS="-ac 2"
  SUPPORTED_CODECS="aac|ac3"
  ;;
*)
  AUDIO_BITRATE="192k"
  AUDIO_CHANNELS="-ac 2"
  SUPPORTED_CODECS="aac|ac3"
  ;;
esac

for acodec in $acodecs_list; do
  if [[ ! "$acodec" =~ ^($SUPPORTED_CODECS|unknown)$ ]]; then
    echo "[INFO] Stream codec $acodec require transcodification"
    needs_transcoding=true
    break
  fi
done

if [ "$needs_transcoding" = true ]; then
  if command -v ffmpeg >/dev/null 2>&1; then
    echo "[INFO] Transcoding incopatibles audio streams to AAC"

    TMP_FILE="$TEMP_DIR/$(basename "$DST_FILE")"

    if ffmpeg -hide_banner -loglevel error -hwaccel auto -y -i "$SRC" \
      -map 0 -c:v copy -c:s copy -c:a aac -b:a "$AUDIO_BITRATE" $AUDIO_CHANNELS "$TMP_FILE"; then
      echo "[INFO] Transcoding success"

      mv "$TMP_FILE" "$DST_DIR/$DST_FILE"
    else
      echo "[ERROR] Transcoding error. Moving the original."

      rm -f "$TMP_FILE" 2>/dev/null || true

      cp "$SRC" "$DST_DIR/$DST_FILE"
    fi
  else
    echo "[WARN] ffmpeg not available. Moving without changes."

    cp "$SRC" "$DST_DIR/$DST_FILE"
  fi
else
  echo "[INFO] All codecs are compatibles. Moving without changes."

  cp "$SRC" "$DST_DIR/$DST_FILE"
fi

echo "[INFO] Completed: $DST_FILE"
