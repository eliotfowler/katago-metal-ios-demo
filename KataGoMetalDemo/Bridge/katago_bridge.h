// katago_bridge.h — C API between Swift and KataGo's C++ engine.
//
// Swift cannot call C++ directly (even with Swift/C++ interop, the KataGo
// headers use features not yet supported by the interop layer). This thin C
// bridge wraps the minimum KataGo surface area needed for analysis and exposes
// it as plain C types that Swift can import through a bridging header.
//
// All structs use fixed-size arrays (no pointers) so they cross the C ABI
// boundary safely: Swift receives them by value on the stack without any heap
// allocation or ownership transfer.

#ifndef KATAGO_BRIDGE_H
#define KATAGO_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle — Swift holds this as OpaquePointer and never dereferences it.
typedef struct KataGoEngine KataGoEngine;

// Fixed-size arrays keep the struct layout stable across the C ABI.
// move[8] fits the longest GTP coordinate ("pass" or "Q16\0" etc.).
typedef struct {
    char move[8];       // e.g. "D4", "Q16", "pass"
    int visits;
    double winrate;     // 0.0 to 1.0
    double scoreLead;   // positive = black leads
    double prior;       // policy prior, 0.0 to 1.0
} KataGoMoveInfo;

// Top-level result returned by value from katago_analyze.
// Fixed-size arrays avoid heap allocation and pointer ownership questions
// across the language boundary.
typedef struct {
    KataGoMoveInfo moves[10];
    int moveCount;
    double rootWinrate;     // from black's perspective
    double rootScoreLead;
    double analysisTimeMs;
    int totalVisits;
    char backendInfo[64];
    char errorMessage[256]; // empty string if no error
} KataGoAnalysisResult;

// Lifecycle
KataGoEngine* katago_create(const char* modelPath, const char* configPath);
void katago_destroy(KataGoEngine* engine);

// Analysis — moves is a space-separated string of alternating color/location pairs:
//   "B D4 W Q16 B D16 ..."
// Returns analysis of the position after all moves, for the player to move next.
KataGoAnalysisResult katago_analyze(
    KataGoEngine* engine,
    int boardWidth,
    int boardHeight,
    const char* moves,
    int maxVisits
);

// Returns a pointer to a null-terminated backend description string.
// The string is owned by the engine; do not free it.
const char* katago_get_backend(KataGoEngine* engine);

#ifdef __cplusplus
}
#endif

#endif // KATAGO_BRIDGE_H
