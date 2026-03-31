#!/bin/bash

# Copy KataGo source files from the submodule into KataGoEngine/ for Xcode compilation.
# KataGoEngine/ uses Xcode's file system synchronization, so any .cpp/.swift/.h file
# placed there will be automatically compiled.
#
# Run this script after cloning the repo (with submodules) and before building in Xcode.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KATAGO_SRC="$PROJECT_DIR/katago/cpp"
DEST_DIR="$PROJECT_DIR/KataGoEngine"

if [ ! -d "$KATAGO_SRC" ]; then
  echo "Error: KataGo submodule not found at $KATAGO_SRC"
  echo "Run: git submodule update --init --recursive"
  exit 1
fi

# Subdirectories to copy headers from
HEADER_DIRS=(book core dataio game neuralnet program search)

# C++ source files needed for the Metal backend build
CPP_FILES=(
  "core/global.cpp"
  "core/base64.cpp"
  "core/bsearch.cpp"
  "core/commandloop.cpp"
  "core/config_parser.cpp"
  "core/datetime.cpp"
  "core/elo.cpp"
  "core/fancymath.cpp"
  "core/fileutils.cpp"
  "core/hash.cpp"
  "core/logger.cpp"
  "core/mainargs.cpp"
  "core/makedir.cpp"
  "core/md5.cpp"
  "core/multithread.cpp"
  "core/parallel.cpp"
  "core/rand.cpp"
  "core/rand_helpers.cpp"
  "core/sha2.cpp"
  "core/test.cpp"
  "core/threadsafecounter.cpp"
  "core/threadsafequeue.cpp"
  "core/threadtest.cpp"
  "core/timer.cpp"
  "game/board.cpp"
  "game/rules.cpp"
  "game/boardhistory.cpp"
  "game/graphhash.cpp"
  "dataio/sgf.cpp"
  "dataio/numpywrite.cpp"
  "dataio/poswriter.cpp"
  "dataio/trainingwrite.cpp"
  "dataio/loadmodel.cpp"
  "dataio/homedata.cpp"
  "dataio/files.cpp"
  "neuralnet/nninputs.cpp"
  "neuralnet/sgfmetadata.cpp"
  "neuralnet/modelversion.cpp"
  "neuralnet/nneval.cpp"
  "neuralnet/desc.cpp"
  "neuralnet/metalbackend.cpp"
  "neuralnet/coremlbackend.cpp"
  "search/evalcache.cpp"
  "search/timecontrols.cpp"
  "search/searchparams.cpp"
  "search/mutexpool.cpp"
  "search/search.cpp"
  "search/searchnode.cpp"
  "search/searchresults.cpp"
  "search/searchhelpers.cpp"
  "search/searchexplorehelpers.cpp"
  "search/searchmirror.cpp"
  "search/searchmultithreadhelpers.cpp"
  "search/searchnnhelpers.cpp"
  "search/searchtimehelpers.cpp"
  "search/searchupdatehelpers.cpp"
  "search/searchnodetable.cpp"
  "search/subtreevaluebiastable.cpp"
  "search/patternbonustable.cpp"
  "search/asyncbot.cpp"
  "search/distributiontable.cpp"
  "search/localpattern.cpp"
  "search/analysisdata.cpp"
  "search/reportedsearchvalues.cpp"
  "program/gtpconfig.cpp"
  "program/setup.cpp"
  "program/playutils.cpp"
  "program/playsettings.cpp"
  "program/play.cpp"
  "program/selfplaymanager.cpp"
  "book/book.cpp"
  "book/bookcssjs.cpp"
)

# Swift source files for the Metal/CoreML backend
SWIFT_FILES=(
  "neuralnet/metalbackend.swift"
  "neuralnet/coremlbackend.swift"
  "neuralnet/coremlmodel.swift"
)

echo "Copying KataGo source files into KataGoEngine/..."
echo "Source: $KATAGO_SRC"
echo "Destination: $DEST_DIR"
echo ""

copied=0
failed=0

# Copy all headers from each subdirectory
echo "=== Copying headers ==="
for dir in "${HEADER_DIRS[@]}"; do
  mkdir -p "$DEST_DIR/$dir"
  count=0
  for header in "$KATAGO_SRC/$dir"/*.h; do
    [ -f "$header" ] || continue
    cp "$header" "$DEST_DIR/$dir/"
    ((count++))
  done
  echo "  $dir/ — $count headers"
  ((copied += count))
done

# Copy C++ source files
echo ""
echo "=== Copying C++ sources ==="
for file in "${CPP_FILES[@]}"; do
  src_file="$KATAGO_SRC/$file"
  dest_file="$DEST_DIR/$file"
  mkdir -p "$(dirname "$dest_file")"

  if [ -f "$src_file" ]; then
    cp "$src_file" "$dest_file"
    ((copied++))
  else
    echo "  MISSING: $file"
    ((failed++))
  fi
done
echo "  $((${#CPP_FILES[@]} - failed)) copied"

# Copy Swift source files
echo ""
echo "=== Copying Swift sources ==="
for file in "${SWIFT_FILES[@]}"; do
  src_file="$KATAGO_SRC/$file"
  dest_file="$DEST_DIR/$file"
  mkdir -p "$(dirname "$dest_file")"

  if [ -f "$src_file" ]; then
    cp "$src_file" "$dest_file"
    ((copied++))
  else
    echo "  MISSING: $file"
    ((failed++))
  fi
done
echo "  ${#SWIFT_FILES[@]} copied"

# Patch metalbackend.h for static library target (Xcode generates KataGoSwift-Swift.h,
# not the framework-style <KataGoSwift/KataGoSwift-swift.h> that the upstream code uses)
echo ""
echo "=== Applying patches ==="
METAL_HEADER="$DEST_DIR/neuralnet/metalbackend.h"
if [ -f "$METAL_HEADER" ]; then
  sed -i '' 's|#include <KataGoSwift/KataGoSwift-swift.h>|#include "KataGoSwift-Swift.h"|' "$METAL_HEADER"
  echo "  Patched metalbackend.h include for static library"
fi

echo ""
echo "Done! Copied: $copied, Failed: $failed"

if [ "$failed" -gt 0 ]; then
  echo "WARNING: Some files were missing. Check that the katago submodule is up to date."
  exit 1
fi
