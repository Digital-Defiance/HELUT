/// Fail-closed errors raised before an n-gram score can become evidence.
enum MuleinNGramEvaluationError: Error, Equatable, Sendable {
    case emptyModelID(modelIndex: Int)
    case duplicateModelID(modelID: String)
    case invalidModelOrder(modelID: String, order: Int)

    case invalidAdjacencyOrder(orderTraceIndex: Int, order: Int)
    case duplicateAdjacencyOrder(order: Int)
    case missingAdjacencyOrder(modelID: String, order: Int)
    case missingModelForAdjacencyOrder(order: Int)

    case tableIndexSpaceOverflow(order: Int, symbolOffset: Int)
    case entryCountMismatch(modelID: String, order: Int, expected: Int, actual: Int)
    case windowOrderMismatch(
        order: Int,
        windowIndex: Int,
        transmittedStepCount: Int,
        symbolCount: Int
    )
    case tableIndexOverflow(order: Int, windowIndex: Int, symbolOffset: Int)
    case tableIndexOutOfBounds(
        modelID: String,
        order: Int,
        tableIndex: Int,
        entryCount: Int
    )

    case nonFiniteLogProbability(modelID: String, order: Int, tableIndex: Int)
    case nonFiniteTotal(modelID: String, order: Int, windowIndex: Int)
}

/// One model lookup with explicit observed-versus-smoothed provenance.
enum MuleinNGramLookup: Equatable, Sendable {
    case entry(logProbability: Double)
    case floor(logProbability: Double)
}

/// Fixed-order lookup boundary used only by the typed reference evaluator.
///
/// Models receive an already-reduced table index and cannot reinterpret symbols, coordinates, or
/// physical adjacency. `entryCount` must equal 26^order; the evaluator checks it before lookup.
protocol MuleinNGramModel: Sendable {
    var modelID: String { get }
    var order: Int { get }
    var entryCount: Int { get }

    func lookup(tableIndex: Int) -> MuleinNGramLookup
}
