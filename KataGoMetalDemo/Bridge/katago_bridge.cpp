#include "katago_bridge.h"

#include <string>
#include <vector>
#include <sstream>
#include <cstring>
#include <chrono>

// KataGo headers
#include "game/board.h"
#include "game/boardhistory.h"
#include "game/rules.h"
#include "neuralnet/nninterface.h"
#include "neuralnet/nneval.h"
#include "neuralnet/nninputs.h"
#include "search/asyncbot.h"
#include "search/search.h"
#include "search/searchparams.h"
#include "search/analysisdata.h"
#include "core/global.h"
#include "core/config_parser.h"
#include "core/logger.h"
#include "core/rand.h"
#include "core/timer.h"
#include "program/setup.h"

using namespace std;

struct KataGoEngine {
    NNEvaluator* nnEval;
    Logger* logger;
    string backendStr;
    bool initialized;
};

static bool sGlobalsInitialized = false;

// KataGo's static tables (Zobrist hashes, score value tables) and the neural
// net backend's global state must be initialized exactly once per process.
// This guard is not a synchronization primitive; it assumes katago_create is
// never called concurrently. The current app design enforces that assumption.
static void ensureGlobalsInitialized() {
    if (!sGlobalsInitialized) {
        Board::initHash();
        ScoreValue::initTables();
        NeuralNet::globalInitialize();
        sGlobalsInitialized = true;
    }
}

KataGoEngine* katago_create(const char* modelPath, const char* configPath) {
    KataGoEngine* engine = new KataGoEngine();
    engine->nnEval = nullptr;
    engine->logger = nullptr;
    engine->initialized = false;

    try {
        ensureGlobalsInitialized();

        engine->logger = new Logger(nullptr, false, false);

        // Parse config for search params
        ConfigParser cfg;
        cfg.initialize(string(configPath));

        Rand seedRand;

        int expectedConcurrentEvals = 1;
        int maxBoardLen = NNPos::MAX_BOARD_LEN; // 19
        int defaultMaxBatchSize = 1;
        bool defaultRequireExactNNLen = false;
        bool disableFP16 = false;

        // katago_create is called once per model load. It reads the .bin.gz
        // weight file, allocates the NNEvaluator, and — on the first call —
        // compiles Metal shaders for the current device. Compilation can take
        // several seconds and is why initialization runs off the main thread.
        engine->nnEval = Setup::initializeNNEvaluator(
            string(modelPath),
            string(modelPath),
            "",  // no expected sha256
            cfg,
            *engine->logger,
            seedRand,
            expectedConcurrentEvals,
            maxBoardLen,
            maxBoardLen,
            defaultMaxBatchSize,
            defaultRequireExactNNLen,
            disableFP16,
            Setup::SETUP_FOR_ANALYSIS
        );

        // USE_COREML_BACKEND is the CMake/Xcode preprocessor flag that enables
        // KataGo's combined Metal + CoreML backend. Despite the name, it covers
        // the MPSGraph/Metal path used here — CoreML is an optional accelerator
        // within that backend, not a separate one.
#if defined(USE_COREML_BACKEND)
        engine->backendStr = "Metal";
#elif defined(USE_EIGEN_BACKEND)
        engine->backendStr = "Eigen (CPU)";
#else
        engine->backendStr = "Unknown";
#endif
        engine->initialized = true;

    } catch (const exception& e) {
        if (engine->logger) {
            engine->logger->write(string("ERROR: ") + e.what());
        }
        // Leave initialized = false
    }

    return engine;
}

void katago_destroy(KataGoEngine* engine) {
    if (!engine) return;

    if (engine->nnEval) {
        engine->nnEval->killServerThreads();
        delete engine->nnEval;
    }
    if (engine->logger) {
        delete engine->logger;
    }
    delete engine;
}

static bool parseMoves(const string& movesStr, int boardXSize, int boardYSize,
                       vector<pair<Player, Loc>>& moves) {
    istringstream iss(movesStr);
    string colorStr, locStr;
    while (iss >> colorStr >> locStr) {
        Player pla;
        if (colorStr == "B" || colorStr == "b")
            pla = P_BLACK;
        else if (colorStr == "W" || colorStr == "w")
            pla = P_WHITE;
        else
            return false;

        Loc loc;
        if (locStr == "pass" || locStr == "Pass" || locStr == "PASS") {
            loc = Board::PASS_LOC;
        } else {
            if (!Location::tryOfString(locStr, boardXSize, boardYSize, loc))
                return false;
        }
        moves.push_back({pla, loc});
    }
    return true;
}

KataGoAnalysisResult katago_analyze(
    KataGoEngine* engine,
    int boardWidth,
    int boardHeight,
    const char* moves,
    int maxVisits
) {
    KataGoAnalysisResult result;
    memset(&result, 0, sizeof(result));

    if (!engine || !engine->initialized) {
        strncpy(result.errorMessage, "Engine not initialized", sizeof(result.errorMessage) - 1);
        return result;
    }

    try {
        // Set up board and history
        Board board(boardWidth, boardHeight);
        Rules rules = Rules::getTrompTaylorish();
        rules.komi = 7.5;
        BoardHistory hist(board, P_BLACK, rules, 0);

        // Parse and apply moves
        vector<pair<Player, Loc>> moveList;
        if (!parseMoves(string(moves), boardWidth, boardHeight, moveList)) {
            strncpy(result.errorMessage, "Failed to parse moves", sizeof(result.errorMessage) - 1);
            return result;
        }

        for (auto& [pla, loc] : moveList) {
            if (!hist.isLegal(board, loc, pla)) {
                strncpy(result.errorMessage, "Illegal move in sequence", sizeof(result.errorMessage) - 1);
                return result;
            }
            hist.makeBoardMoveAssumeLegal(board, loc, pla, nullptr);
        }

        // Determine who plays next
        Player nextPla = moveList.empty() ? P_BLACK : getOpp(moveList.back().first);

        // Set up search params
        SearchParams params;
        params.maxVisits = maxVisits;
        params.numThreads = 2;
        params.conservativePass = true;

        // Create bot
        AsyncBot bot(params, engine->nnEval, engine->logger, "analysis");
        bot.setPosition(nextPla, board, hist);
        bot.setAlwaysIncludeOwnerMap(true);

        // Run search with timing.
        // genMoveSynchronous blocks until the visit budget is exhausted and
        // returns the best move. A blocking call is intentional here: the
        // caller (KataGoService.analyze) already runs this on a detached Task
        // so the main actor is never blocked.
        auto startTime = chrono::high_resolution_clock::now();

        TimeControls tc;
        Loc bestMove = bot.genMoveSynchronous(nextPla, tc);
        (void)bestMove;

        auto endTime = chrono::high_resolution_clock::now();
        double elapsedMs = chrono::duration<double, milli>(endTime - startTime).count();

        // Extract results
        Search* search = bot.getSearchStopAndWait();
        result.analysisTimeMs = elapsedMs;
        result.totalVisits = (int)search->getRootVisits();

        // Get analysis data (top moves)
        vector<AnalysisData> analysisData;
        search->getAnalysisData(analysisData, 10, false, 15, false);

        // Root values
        if (!analysisData.empty()) {
            // winLossValue is from white's perspective (-1 to 1)
            // Convert to black winrate (0 to 1)
            double whiteWL = analysisData[0].winLossValue;
            result.rootWinrate = 0.5 - whiteWL * 0.5;  // black's winrate
            result.rootScoreLead = -analysisData[0].scoreMean;  // flip to black's perspective
        }

        int count = min((int)analysisData.size(), 10);
        result.moveCount = count;

        for (int i = 0; i < count; i++) {
            const AnalysisData& ad = analysisData[i];

            string moveStr = Location::toString(ad.move, board);
            strncpy(result.moves[i].move, moveStr.c_str(), sizeof(result.moves[i].move) - 1);
            result.moves[i].visits = (int)ad.numVisits;
            result.moves[i].winrate = 0.5 - ad.winLossValue * 0.5;  // black's winrate
            result.moves[i].scoreLead = -ad.scoreMean;  // black's perspective
            result.moves[i].prior = ad.policyPrior;
        }

        strncpy(result.backendInfo, engine->backendStr.c_str(), sizeof(result.backendInfo) - 1);

    } catch (const exception& e) {
        strncpy(result.errorMessage, e.what(), sizeof(result.errorMessage) - 1);
    }

    return result;
}

const char* katago_get_backend(KataGoEngine* engine) {
    if (!engine) return "null";
    return engine->backendStr.c_str();
}
