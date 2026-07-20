import Foundation

struct InteractionGenerationGate {
    private(set) var currentGeneration: Int
    private var gestureGeneration: Int?

    init(currentGeneration: Int) {
        self.currentGeneration = currentGeneration
    }

    mutating func updateCurrentGeneration(_ generation: Int) {
        currentGeneration = generation
    }

    mutating func beginGesture() {
        gestureGeneration = currentGeneration
    }

    func acceptsCurrentGestureEvent() -> Bool {
        gestureGeneration == currentGeneration
    }

    mutating func endGesture() -> Bool {
        let acceptsEvent = acceptsCurrentGestureEvent()
        gestureGeneration = nil
        return acceptsEvent
    }
}

enum StableIdentityReducer {
    static func merge<Value, ID: Hashable>(
        into values: inout [Value],
        next: [Value],
        id: (Value) -> ID
    ) {
        var indexByID: [ID: Int] = [:]
        var merged: [Value] = []

        for candidate in values + next {
            let candidateID = id(candidate)
            if let index = indexByID[candidateID] {
                merged[index] = candidate
            } else {
                indexByID[candidateID] = merged.count
                merged.append(candidate)
            }
        }

        values = merged
    }
}
