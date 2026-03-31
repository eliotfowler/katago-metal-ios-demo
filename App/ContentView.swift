import SwiftUI

struct ContentView: View {
    @StateObject private var service = KataGoService()
    @State private var boardSize: BoardSize = .nine
    @State private var visitCount: VisitCount = .low
    @State private var modelSize: ModelSize = .b6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    controlsSection
                    if let result = service.lastResult {
                        resultsSection(result)
                    }
                    logSection
                }
                .padding()
            }
            .navigationTitle("KataGo Metal Demo")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            service.initialize(model: modelSize)
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 12) {
            // Model picker
            HStack {
                Text("Model")
                    .font(.subheadline.bold())
                Spacer()
                Picker("Model", selection: $modelSize) {
                    ForEach(ModelSize.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Load model button (shown when model differs from loaded)
            if service.currentModel != modelSize {
                Button(action: { service.initialize(model: modelSize) }) {
                    HStack {
                        if service.isInitializing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(service.isInitializing ? "Loading..." : "Load \(modelSize.rawValue) Model")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .disabled(service.isInitializing)
            }

            HStack {
                Text("Board")
                    .font(.subheadline.bold())
                Spacer()
                Picker("Board Size", selection: $boardSize) {
                    ForEach(BoardSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            HStack {
                Text("Visits")
                    .font(.subheadline.bold())
                Spacer()
                Picker("Visits", selection: $visitCount) {
                    ForEach(VisitCount.allCases) { count in
                        Text(count.label).tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            Button(action: { service.analyze(boardSize: boardSize, visits: visitCount) }) {
                HStack {
                    if service.isAnalyzing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(service.isAnalyzing ? "Analyzing..." : "Run Analysis")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!service.isInitialized || service.isAnalyzing || service.currentModel != modelSize)

            if service.isInitializing {
                HStack {
                    ProgressView()
                    Text("Loading \(modelSize.rawValue)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = service.initError {
                Text("Init Error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Results

    private func resultsSection(_ result: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results")
                .font(.headline)

            if let error = result.error {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else {
                // Timing and backend
                HStack {
                    StatView(label: "Time", value: String(format: "%.0fms", result.analysisTimeMs))
                    StatView(label: "Visits", value: "\(result.totalVisits)")
                    StatView(label: "Model", value: result.modelName)
                    StatView(label: "Backend", value: result.backendInfo)
                }

                // Root evaluation
                HStack {
                    StatView(label: "Win Rate", value: String(format: "%.1f%%", result.rootWinrate * 100))
                    StatView(label: "Score", value: String(format: "%+.1f", result.rootScoreLead))
                }

                // Top moves table
                if !result.moves.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Top Moves")
                            .font(.subheadline.bold())

                        // Header
                        HStack {
                            Text("Move").frame(width: 50, alignment: .leading)
                            Text("Visits").frame(width: 60, alignment: .trailing)
                            Text("Win%").frame(width: 60, alignment: .trailing)
                            Text("Score").frame(width: 60, alignment: .trailing)
                            Text("Prior").frame(width: 60, alignment: .trailing)
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                        ForEach(result.moves.prefix(5)) { move in
                            HStack {
                                Text(move.move).frame(width: 50, alignment: .leading)
                                Text("\(move.visits)").frame(width: 60, alignment: .trailing)
                                Text(String(format: "%.1f%%", move.winrate * 100)).frame(width: 60, alignment: .trailing)
                                Text(String(format: "%+.1f", move.scoreLead)).frame(width: 60, alignment: .trailing)
                                Text(String(format: "%.1f%%", move.prior * 100)).frame(width: 60, alignment: .trailing)
                            }
                            .font(.caption.monospaced())
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Log")
                    .font(.headline)
                Spacer()
                Button("Clear") { service.logMessages.removeAll() }
                    .font(.caption)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(service.logMessages.enumerated()), id: \.offset) { _, msg in
                        Text(msg)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StatView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold().monospaced())
        }
        .frame(maxWidth: .infinity)
    }
}
