#!/bin/bash
set -euo pipefail

DEST_DIR="$(cd "$(dirname "$0")/.." && pwd)/KataGoMetalDemo/Resources"
mkdir -p "$DEST_DIR"

# KataGo networks from katagoarchive.org (g170 training run)
# Smaller nets are faster but weaker; larger nets are stronger but slower.
# Inference cost scales roughly as blocks × channels².

download_net() {
    local NAME=$1
    local URL=$2
    local FILE="$DEST_DIR/model_${NAME}.bin.gz"

    echo "Downloading $NAME network..."
    if [ ! -f "$FILE" ]; then
        curl -L -o "$FILE" "$URL"
        echo "  Downloaded to $FILE ($(du -h "$FILE" | cut -f1))"
    else
        echo "  Already exists: $FILE ($(du -h "$FILE" | cut -f1))"
    fi
}

download_net "b6c96" "https://katagoarchive.org/g170/neuralnets/g170-b6c96-s175395328-d26788732.bin.gz"
download_net "b10c128" "https://katagoarchive.org/g170/neuralnets/g170-b10c128-s197428736-d67404019.bin.gz"
download_net "b15c192" "https://katagoarchive.org/g170/neuralnets/g170-b15c192-s497233664-d149638345.bin.gz"
download_net "b18c384nbt" "https://media.katagotraining.org/uploaded/networks/models/kata1/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz"

echo ""
echo "All weights downloaded:"
ls -lh "$DEST_DIR"/model_*.bin.gz 2>/dev/null || echo "No weight files found!"
