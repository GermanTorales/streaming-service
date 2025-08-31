#!/bin/bash
set -euo pipefail

# Parámetros recibidos
SRC="$1"
DST_DIR="$2"
DST_FILE="$3"
MEDIA_TYPE="${4:-general}"  # anime, tv, movies, o general

mkdir -p "$DST_DIR"

echo "[INFO] Procesando $MEDIA_TYPE: $(basename "$SRC")"

if ! command -v ffprobe > /dev/null 2>&1; then
    echo "[ERROR] ffprobe no encontrado. Moviendo sin verificación"
    mv -n "$SRC" "$DST_DIR/$DST_FILE"
    exit 0
fi

# Obtener codecs
vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 "$SRC" 2>/dev/null || echo "unknown")
acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 "$SRC" 2>/dev/null || echo "unknown")

vcodec=$(echo "$vcodec" | tr '[:upper:]' '[:lower:]' | xargs)
acodec=$(echo "$acodec" | tr '[:upper:]' '[:lower:]' | xargs)

echo "[INFO] Video: $vcodec, Audio: $acodec"

# Validar codec de video
if [[ "$vcodec" != "h264" && "$vcodec" != "h265" && "$vcodec" != "av1" && "$vcodec" != "unknown" ]]; then
    echo "[WARN] Codec de video no soportado: $vcodec. Moviendo sin cambios."
    mv -n "$SRC" "$DST_DIR/$DST_FILE"
    exit 0
fi

# Configurar bitrate según tipo de media
case "$MEDIA_TYPE" in
    "anime")
        AUDIO_BITRATE="192k"
        AUDIO_CHANNELS=""  # Sin forzar canales para anime
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

# Verificar si necesita transcodificación
if [[ ! "$acodec" =~ ^($SUPPORTED_CODECS|unknown)$ ]]; then
    if command -v ffmpeg >/dev/null 2>&1; then
        echo "[INFO] Transcodificando audio $acodec -> AAC"
        TMP="$DST_DIR/.tmp.$(basename "$DST_FILE")"

        if ffmpeg -hide_banner -loglevel error -hwaccel auto -y -i "$SRC" \
            -map 0 -c:v copy -c:s copy -c:a aac -b:a "$AUDIO_BITRATE" $AUDIO_CHANNELS "$TMP"; then
            echo "[INFO] Transcodificación exitosa"
            mv "$TMP" "$DST_DIR/$DST_FILE"
            rm -f "$SRC"
        else
            echo "[ERROR] Error en transcodificación. Moviendo original."
            rm -f "$TMP" 2>/dev/null || true
            mv -n "$SRC" "$DST_DIR/$DST_FILE"
        fi
    else
        echo "[WARN] ffmpeg no disponible. Moviendo sin cambios."
        mv -n "$SRC" "$DST_DIR/$DST_FILE"
    fi
else
    echo "[INFO] Codecs compatibles. Moviendo sin cambios."
    mv -n "$SRC" "$DST_DIR/$DST_FILE"
fi

echo "[INFO] Completado: $DST_FILE"
