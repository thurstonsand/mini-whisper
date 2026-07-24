#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 AVFOUNDATION_AUDIO_INDEX DURATION_SECONDS OUTPUT.wav" >&2
  echo "list devices: ffmpeg -f avfoundation -list_devices true -i ''" >&2
  exit 2
fi

mkdir -p "$(dirname "$3")"
ffmpeg -hide_banner -loglevel warning -y \
  -f avfoundation -i ":$1" -t "$2" -ac 1 -ar 16000 -c:a pcm_s16le "$3"
ffprobe -v error -show_entries stream=codec_name,sample_rate,channels,duration \
  -of default=noprint_wrappers=1 "$3"
