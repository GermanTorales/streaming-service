#!/usr/bin/with-contenv bash
set -e

echo "Instalando mediainfo y ffmpeg..."
apk add -q --no-cache mediainfo ffmpeg
echo "Instalación terminada ✅"

