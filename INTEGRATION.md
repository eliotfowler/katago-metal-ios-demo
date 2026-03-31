# Integration Guide: Adding KataGo Metal to Your iOS App

This guide explains how to embed the KataGo Metal GPU engine into your own iOS app. It documents every non-obvious configuration step that the `KataGoMetalDemo.xcodeproj` already has in place.

---

## Overview

The integration requires:
1. A static library Xcode target (`KataGoEngine`) containing the KataGo C++ and Swift Metal backend sources
2. A thin C bridge (`katago_bridge.h/.cpp`) so Swift can call the C++ engine
3. Specific build settings for C++17 / Swift interop
4. Framework dependencies for Metal GPU computation

---

## Step 1: Get the source files

Add this repo as a submodule (or copy the relevant files):

```bash
git submodule add https://github.com/ChinChangYang/KataGo.git katago
git -C katago checkout metal-coreml-stable
```

Then run the copy script to populate `KataGoEngine/`:

```bash
./scripts/copy_katago_files.sh
```

This copies ~70 C++ source files, 3 Swift files, and all headers from `katago/cpp/` into `KataGoEngine/`. See the script for the exact file list. **Do not edit files in `KataGoEngine/` directly** — they will be overwritten on the next copy.

---

## Step 2: Create the Xcode targets

### KataGoEngine (static library target)

1. In Xcode, add a new **Static Library** target named `KataGoEngine`.
2. Set the target membership of the `KataGoEngine/` folder to this target using Xcode's file system synchronization (folder reference), so new files added by `copy_katago_files.sh` are compiled automatically.
3. Also add `KataGoMetalDemo/Bridge/katago_bridge.cpp` to this target.

### App target

Your app target links against `libKataGoEngine.a` and the Metal frameworks (see Step 4).

---

## Step 3: Configure build settings

### KataGoEngine target

| Setting | Value | Why |
|---------|-------|-----|
| **Preprocessor Macros** | `USE_COREML_BACKEND=1 NO_LIBZIP NO_GIT_REVISION OS_IS_IOS COMPILE_MAX_BOARD_LEN=19` | Enables Metal+CoreML backend; removes unused dependencies; caps board size at 19×19 |
| **C++ Language Dialect** | `GNU++17` | KataGo uses C++17 features (structured bindings, `std::optional`, etc.) |
| **Swift Compiler — C++ Interoperability Mode** | `objcxx` | Required for bidirectional Swift/C++ interop used by `metalbackend.swift` |
| **Product Module Name** | `KataGoSwift` | The generated header is `KataGoSwift-Swift.h`; this name is hardcoded in the patched `metalbackend.h` |
| **Header Search Paths** | `$(SRCROOT)/katago/cpp` `$(SRCROOT)/katago/cpp/external` `$(SRCROOT)/katago/cpp/external/tclap-1.2.2/include` | KataGo's own includes; tclap is a header-only CLI library included in the source tree |
| **System Header Search Paths** | `$(SRCROOT)/katago/cpp/external/filesystem-1.5.8/include` | Polyfill for `<filesystem>` on older SDKs |

### App target

| Setting | Value |
|---------|-------|
| **Preprocessor Macros** | `USE_COREML_BACKEND=1 NO_GIT_REVISION=1 NO_LIBZIP=1 COMPILE_MAX_BOARD_LEN=19` |
| **Linked Libraries** | `libKataGoEngine.a` (your static lib target) |

---

## Step 4: Link frameworks

Both targets (or just the app target, depending on your linking setup) need these frameworks:

| Framework | Why |
|-----------|-----|
| **Metal** | Core GPU command submission |
| **MetalPerformanceShaders** | Convolution and matrix primitives used by the neural net |
| **MetalPerformanceShadersGraph** | Graph-based execution of the full neural net; this is the primary computation path |
| **CoreML** | Optional accelerator within the Metal backend; also used for the CoreML model path |
| **Accelerate** | Fast CPU math (used in parts of KataGo's C++ that run on CPU, e.g. softmax, board scoring) |

---

## Step 5: Add the C bridge

Copy `KataGoMetalDemo/Bridge/katago_bridge.h` and `katago_bridge.cpp` into your project. Add the `.cpp` file to the `KataGoEngine` target's sources.

Create a bridging header for your app target (or add to an existing one):

```objc
// YourApp-Bridging-Header.h
#import "katago_bridge.h"
```

The bridge exposes four functions:
- `katago_create(modelPath, configPath)` — loads weights, compiles Metal shaders
- `katago_destroy(engine)` — frees all resources
- `katago_analyze(engine, width, height, moves, maxVisits)` — runs MCTS and returns top moves
- `katago_get_backend(engine)` — returns a string like `"Metal"` or `"Eigen (CPU)"`

---

## Step 6: The `metalbackend.h` include patch

The upstream `metalbackend.h` uses a framework-style include:

```cpp
#include <KataGoSwift/KataGoSwift-swift.h>
```

Xcode generates the Swift-to-C++ header at a different path when building a static library. `scripts/copy_katago_files.sh` patches this automatically:

```cpp
// Patched to:
#include "KataGoSwift-Swift.h"
```

If you update the submodule and re-run `copy_katago_files.sh`, the patch is reapplied automatically.

---

## Step 7: Bundle neural net weights

1. Download `.bin.gz` weight files using `scripts/download_weights.sh` (or manually from [katagoarchive.org](https://katagoarchive.org)).
2. Add them to your app target's bundle resources in Xcode.
3. At runtime, locate them with `Bundle.main.path(forResource:ofType:)`.

KataGo weight files use the `bin.gz` format (compressed binary). The resource name used in this project follows the pattern `model_<size>.bin.gz`, e.g. `model_b10c128.bin.gz`.

---

## Step 8: Configuration file

Copy `KataGoMetalDemo/Resources/analysis.cfg` to your project's resources and add it to the app bundle. The key settings are:

```ini
numSearchThreads = 2         # MCTS tree search threads
numNNServerThreadsPerModel = 1   # GPU inference thread
nnMaxBatchSize = 1           # Batch size for GPU calls (1 is optimal for single-query use)
nnCacheSizePowerOfTwo = 16   # Neural net result cache (~65k entries)
```

---

## Common build errors

### `Use of undeclared identifier 'KataGoMetal'` or similar Swift type errors
The `Product Module Name` must be exactly `KataGoSwift`. The generated header is `KataGoSwift-Swift.h` and is included by `metalbackend.h`. Mismatched names break this include.

### `'filesystem' file not found`
Add `$(SRCROOT)/katago/cpp/external/filesystem-1.5.8/include` to **System** Header Search Paths (not regular Header Search Paths). The distinction matters for how the compiler handles warnings in those headers.

### `Undefined symbol: _katago_create` (linker error)
`katago_bridge.cpp` is not in the `KataGoEngine` target's sources. Check target membership.

### `Unable to load model` at runtime
The `.bin.gz` file is not in the app bundle. Verify it appears under the app target's "Copy Bundle Resources" build phase in Xcode.

### Slow first launch (10–20 seconds)
This is expected on first run: Metal shaders are compiled and cached in the device's shader library. Subsequent launches use the cached shaders and initialize in under a second.

### Build works in simulator but crashes on device
Metal is not available in the simulator. Always test on a physical device. The `katago_create` function will return an engine with `initialized = false` if the Metal backend fails to initialize.

---

## Running on older devices

- **iPhone 12+** (A14 Bionic or later) — recommended; good performance on b10/b15
- **iPhone X / 11** (A11/A13) — works but slower; b6 is the practical choice
- **iPad Pro (M-series)** — excellent performance; b18 is viable

The `COMPILE_MAX_BOARD_LEN=19` macro limits the board size to 19×19, reducing memory usage vs. KataGo's default of 29×29.
