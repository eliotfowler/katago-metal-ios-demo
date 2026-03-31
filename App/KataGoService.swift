import Foundation

struct MoveInfo: Identifiable {
    let id = UUID()
    let move: String
    let visits: Int
    let winrate: Double
    let scoreLead: Double
    let prior: Double
}

struct AnalysisResult {
    let moves: [MoveInfo]
    let rootWinrate: Double
    let rootScoreLead: Double
    let analysisTimeMs: Double
    let totalVisits: Int
    let backendInfo: String
    let modelName: String
    let error: String?
}

enum BoardSize: Int, CaseIterable, Identifiable {
    case nine = 9
    case thirteen = 13
    case nineteen = 19

    var id: Int { rawValue }
    var label: String { "\(rawValue)×\(rawValue)" }
}

enum VisitCount: Int, CaseIterable, Identifiable {
    case low = 100
    case medium = 500
    case high = 1000

    var id: Int { rawValue }
    var label: String { "\(rawValue)" }
}

enum ModelSize: String, CaseIterable, Identifiable {
    case b6 = "b6c96"
    case b10 = "b10c128"
    case b15 = "b15c192"
    case b18 = "b18c384nbt"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .b6: return "b6"
        case .b10: return "b10"
        case .b15: return "b15"
        case .b18: return "b18"
        }
    }
    var resourceName: String { "model_\(rawValue)" }
}

@MainActor
class KataGoService: ObservableObject {
    @Published var isInitialized = false
    @Published var isInitializing = false
    @Published var isAnalyzing = false
    @Published var lastResult: AnalysisResult?
    @Published var logMessages: [String] = []
    @Published var initError: String?
    @Published var currentModel: ModelSize?

    private var engine: OpaquePointer?

    func initialize(model: ModelSize) {
        guard !isInitializing else { return }

        // If switching models, destroy old engine first
        if let oldEngine = engine {
            log("Destroying previous engine...")
            katago_destroy(oldEngine)
            engine = nil
            isInitialized = false
        }

        isInitializing = true
        initError = nil
        log("Initializing KataGo with \(model.rawValue) model...")

        let resourceName = model.resourceName

        // KataGo initialization is CPU-intensive (reads weights, compiles Metal
        // shaders on first launch). Task.detached ensures it never executes on
        // the main actor, keeping the UI responsive during loading.
        Task.detached { [weak self] in
            guard let modelPath = Bundle.main.path(forResource: resourceName, ofType: "bin.gz"),
                  let configPath = Bundle.main.path(forResource: "analysis", ofType: "cfg") else {
                await self?.onInitError("Model '\(resourceName)' or config not found in bundle")
                return
            }

            await self?.log("Model path: \(modelPath)")

            // katago_create loads the neural net weights and — on the very first
            // call — compiles Metal shaders for the current GPU. Subsequent
            // model switches reuse already-compiled shaders and are faster.
            let engine = katago_create(modelPath, configPath)

            if let backendCStr = katago_get_backend(engine) {
                let backend = String(cString: backendCStr)
                await self?.log("Backend: \(backend)")
            }

            await MainActor.run {
                self?.engine = engine
                self?.currentModel = model
                self?.isInitialized = true
                self?.isInitializing = false
                self?.log("Engine initialized with \(model.rawValue)")
            }
        }
    }

    private func onInitError(_ message: String) {
        log("ERROR: \(message)")
        isInitializing = false
        initError = message
    }

    func analyze(boardSize: BoardSize, visits: VisitCount) {
        guard isInitialized, let engine = engine, let model = currentModel else { return }
        isAnalyzing = true

        let moves = TestPositions.movesFor(boardSize: boardSize)
        let size = Int32(boardSize.rawValue)
        let maxVisits = Int32(visits.rawValue)
        let modelName = model.rawValue

        log("Analyzing: \(boardSize.label), \(visits.rawValue) visits, \(modelName)...")
        log("Position: \(moves.split(separator: " ").count / 2) moves")

        Task.detached { [weak self] in
            let result = katago_analyze(engine, size, size, moves, maxVisits)

            let analysisResult = Self.convertResult(result, modelName: modelName)

            await MainActor.run {
                self?.lastResult = analysisResult
                self?.isAnalyzing = false

                if let error = analysisResult.error {
                    self?.log("ERROR: \(error)")
                } else {
                    self?.log("Done in \(String(format: "%.0f", analysisResult.analysisTimeMs))ms (\(analysisResult.totalVisits) visits)")
                    for (i, move) in analysisResult.moves.prefix(3).enumerated() {
                        self?.log("  #\(i+1): \(move.move) v=\(move.visits) wr=\(String(format: "%.1f%%", move.winrate * 100)) sc=\(String(format: "%+.1f", move.scoreLead))")
                    }
                }
            }
        }
    }

    private nonisolated static func convertResult(_ r: KataGoAnalysisResult, modelName: String) -> AnalysisResult {
        var moves: [MoveInfo] = []
        let count = Int(r.moveCount)

        // KataGoAnalysisResult.moves is a fixed-size C array (not a Swift Array),
        // so Swift exposes it as a tuple. We reinterpret it as a pointer to read
        // elements by index. withUnsafePointer gives us a stable address for the
        // tuple storage without copying, and assumingMemoryBound reinterprets the
        // raw bytes as KataGoMoveInfo — safe because the C struct layout is
        // identical on both sides of the bridge.
        withUnsafePointer(to: r.moves) { ptr in
            let movesPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: KataGoMoveInfo.self)
            for i in 0..<count {
                let m = movesPtr[i]
                let moveStr = withUnsafePointer(to: m.move) { ptr in
                    String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
                }
                moves.append(MoveInfo(
                    move: moveStr,
                    visits: Int(m.visits),
                    winrate: m.winrate,
                    scoreLead: m.scoreLead,
                    prior: m.prior
                ))
            }
        }

        let errorStr = withUnsafePointer(to: r.errorMessage) { ptr in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }
        let backendStr = withUnsafePointer(to: r.backendInfo) { ptr in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }

        return AnalysisResult(
            moves: moves,
            rootWinrate: r.rootWinrate,
            rootScoreLead: r.rootScoreLead,
            analysisTimeMs: r.analysisTimeMs,
            totalVisits: Int(r.totalVisits),
            backendInfo: backendStr,
            modelName: modelName,
            error: errorStr.isEmpty ? nil : errorStr
        )
    }

    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logMessages.append("[\(timestamp)] \(message)")
    }
}
