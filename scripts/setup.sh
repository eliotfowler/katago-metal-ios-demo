#!/bin/bash
# One-shot setup: initializes submodules, copies KataGo sources, and downloads
# neural net weights. Safe to re-run — all steps are idempotent.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

step() { echo ""; echo "▶ $1"; }
ok()   { echo "  ✓ $1"; }
warn() { echo "  ⚠ $1"; }

# ── 1. Git submodules ──────────────────────────────────────────────────────────
step "Checking git submodules..."
cd "$REPO_ROOT"
if git submodule status | grep -q "^-"; then
    echo "  Initializing submodules..."
    git submodule update --init --recursive
    ok "Submodules initialized"
else
    ok "Submodules already initialized"
fi

# ── 2. Copy KataGo source files into KataGoEngine/ ────────────────────────────
step "Copying KataGo source files..."
bash "$REPO_ROOT/scripts/copy_katago_files.sh"

# ── 3. Download neural net weights ───────────────────────────────────────────
step "Downloading neural net weights..."
bash "$REPO_ROOT/scripts/download_weights.sh"

# ── 4. Verify weights exist ───────────────────────────────────────────────────
step "Verifying weights..."
WEIGHTS_DIR="$REPO_ROOT/KataGoMetalDemo/Resources"
MISSING=0
for NET in b6c96 b10c128 b15c192 b18c384nbt; do
    FILE="$WEIGHTS_DIR/model_${NET}.bin.gz"
    if [ -f "$FILE" ]; then
        ok "$(basename "$FILE") ($(du -h "$FILE" | cut -f1))"
    else
        warn "Missing: $FILE"
        MISSING=$((MISSING + 1))
    fi
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
if [ "$MISSING" -eq 0 ]; then
    echo "✅ Setup complete — open KataGoMetalDemo.xcodeproj in Xcode and build on device."
else
    echo "⚠  Setup complete with $MISSING missing weight file(s). Check output above."
    exit 1
fi
