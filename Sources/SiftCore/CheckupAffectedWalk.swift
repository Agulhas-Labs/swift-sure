//
// Copyright © Agulhas Labs
//

/// One `affected` walk over a checkup's range, run on first ask and shared by every reader of it.
public actor CheckupAffectedWalk {
    private let engine: SiftEngine
    private let range: DiffRange
    private var walk: Task<AffectedRenderer.Output, Error>?

    public init(engine: SiftEngine, range: DiffRange) {
        self.engine = engine
        self.range = range
    }

    /// The walk's output; the first call runs it, later calls return the same result.
    func output() async throws -> AffectedRenderer.Output {
        if let walk {
            return try await walk.value
        }
        let started = Task { [engine, range] in try await engine.affectedOutput(options: AffectedOptions(range: range.affectedRange)) }
        walk = started
        return try await started.value
    }
}
