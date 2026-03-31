# Metal Backend Investigation

## What I Tried

### Approach: CMake Cross-Compilation for iOS

I attempted to cross-compile KataGo's Metal backend as a static library for iOS arm64 using CMake + Ninja, the same toolchain KataGo uses for macOS Metal builds.

**Build command:**
```bash
cmake . \
  -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=scripts/ios.toolchain.cmake \
  -DKATAGO_SRC_DIR=katago/cpp \
  -DUSE_BACKEND=METAL \
  -DCMAKE_BUILD_TYPE=Release
```

### What Failed

The Swift compiler test failed during CMake configure:

```
Check for working Swift compiler: .../swiftc - broken

error: unable to load standard library for target 'arm64-apple-macosx26.0'
```

**Root cause:** CMake's Swift compiler detection compiles and *links* a test executable. Even though I set `CMAKE_SYSTEM_NAME=iOS` and pointed `CMAKE_OSX_SYSROOT` to the iPhoneOS SDK, the Swift compiler defaulted to a macOS target triple (`arm64-apple-macosx26.0`) instead of iOS. The `CMAKE_Swift_COMPILER_TARGET` variable I set was ignored during the initial compiler test.

I worked around the basic detection by adding explicit target flags:
```cmake
set(CMAKE_Swift_COMPILER_TARGET "arm64-apple-ios17.0")
set(CMAKE_C_FLAGS_INIT "-target arm64-apple-ios17.0")
set(CMAKE_CXX_FLAGS_INIT "-target arm64-apple-ios17.0")
```

This got the Swift compiler test to pass, but the actual Metal backend build has additional complexity:

### KataGo's Metal Build Architecture

KataGo's Metal backend (`cpp/neuralnet/metalbackend.swift`) uses **Swift 5.9+ bidirectional C++/Swift interoperability**. The CMake build:

1. Compiles `metalbackend.swift` into a static Swift library (`KataGoSwift`)
2. Generates a C++ header (`KataGoSwift-swift.h`) so C++ code can call Swift types
3. The C++ code in `metalbackend.cpp` includes this generated header and uses Swift types like `MetalComputeContext`, `MetalComputeHandle`

This requires:
- The Ninja generator (not Xcode generator)
- Custom CMake modules: `external/macos/cmake/modules/{InitializeSwift.cmake, AddSwift.cmake}`
- The `_swift_generate_cxx_header_target()` macro from those modules
- `CMAKE_OSX_DEPLOYMENT_TARGET` set to 13.0+

### Why This Is Hard for iOS Cross-Compilation

1. **CMake's iOS + Swift support is immature.** CMake 3.24 (the version installed) has limited support for iOS Swift cross-compilation. The Swift compiler target is not properly propagated through the build system.

2. **The custom Swift header generation** uses macOS-specific paths and assumptions in the `AddSwift.cmake` module.

3. **The generated `KataGoSwift-swift.h` header** depends on the Swift module being compiled for the correct target, and the module map needs to reference iOS-compatible framework paths.

## Historical Baseline

At this stage of investigation, the **Eigen (CPU) backend** compiled and linked successfully for iOS arm64. That provided a baseline for performance measurement without GPU acceleration.

Since then, I implemented Option A in this repo: the app now builds and runs KataGo's Metal backend natively in Xcode.

## Paths Forward for Metal

### Option A: Add KataGo Sources Directly to Xcode Project (Implemented / Recommended)

Instead of cross-compiling via CMake, add the KataGo C++ and Swift source files directly to the Xcode project. Xcode has native support for Swift/C++ interop and handles the iOS targeting automatically.

**Steps:**
1. Create a new static library target in the Xcode project (or a framework target)
2. Add these source files to it:
   - All `.cpp` files currently compiled by `scripts/CMakeLists-ios.txt` (the same ~70 files)
   - `neuralnet/metalbackend.swift` (the Swift Metal backend)
   - `neuralnet/metalbackend.cpp` (the C++ Metal wrapper)
3. Configure the target:
   - Enable "C++ and Objective-C Interoperability" in Build Settings → Swift Compiler
   - Set "C++ Interoperability Mode" to "C++17"
   - Add header search paths for KataGo's includes
   - Set preprocessor macros: `USE_COREML_BACKEND=1`, `NO_GIT_REVISION=1`, `NO_LIBZIP=1`
   - Link against: `Metal.framework`, `MetalPerformanceShaders.framework`, `MetalPerformanceShadersGraph.framework`, `Accelerate.framework`
4. Remove the Eigen backend source (`eigenbackend.cpp`) since you're using Metal
5. The main app target links against this static library target

**Pros:** Xcode handles all the Swift/C++ interop natively. No CMake workarounds needed.
**Cons:** Many source files to add to the project. Build times will be longer in Xcode.
**Effort:** ~1-2 hours of Xcode configuration.

### Option B: Fix the CMake iOS Toolchain

Debug the exact CMake/Swift interaction to make cross-compilation work.

**Steps:**
1. Upgrade CMake to latest (3.29+) which has better iOS + Swift support
2. Modify `scripts/ios.toolchain.cmake` to properly set `CMAKE_Swift_FLAGS` with `-target arm64-apple-ios17.0 -sdk <iphoneos-sdk-path>`
3. May need to patch `AddSwift.cmake` and `InitializeSwift.cmake` to handle iOS
4. Test iteratively until `_swift_generate_cxx_header_target()` succeeds for iOS

**Pros:** Cleaner build pipeline, reusable for CI.
**Cons:** Deep CMake debugging, may hit more issues.
**Effort:** Uncertain, could be 2-8 hours depending on how many issues surface.

### Option C: Convert Metal Shaders to CoreML

Instead of using KataGo's Metal backend directly, convert the neural net weights to CoreML format and use Apple's CoreML framework for inference. Keep the MCTS search in C++ (Eigen backend) but replace the neural net evaluation with CoreML calls.

**Steps:**
1. Write a Python script to convert KataGo `.bin.gz` weights to CoreML `.mlmodel` format
2. Implement a new `nninterface.h` backend that calls CoreML for inference
3. CoreML can automatically use the Apple Neural Engine (ANE) for best performance

**Pros:** Could leverage the Neural Engine for dramatically better performance. Apple-native approach.
**Cons:** Significant effort. Requires understanding both KataGo's weight format and CoreML model specification. The MCTS search still runs on CPU.
**Effort:** 1-2 weeks.

### Option D: Use an Existing iOS KataGo Implementation as Reference

Apps like "AI KataGo Go" and "KataGo Anytime" have solved this problem. Their source code isn't public, but you could:
- Contact the developers for guidance
- Reverse-engineer the binary to understand which backend they use
- Check if they use CoreML, Metal directly, or a custom approach

## Recommendation

**Start with Option A** — it's the most straightforward path with the highest certainty of success. The Metal shading language and MetalPerformanceShaders APIs are identical on iOS and macOS, so the Swift Metal backend code should compile without changes once the build system is configured correctly.

If Option A's GPU performance isn't sufficient (unlikely for b6/b10 nets), then Option C (CoreML + Neural Engine) would be the next investigation.
