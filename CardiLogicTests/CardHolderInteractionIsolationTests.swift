import Foundation

private struct SamplePreference {
    let id: String
    let value: String
}

@main
private enum CardHolderInteractionIsolationTests {
    static func main() {
        rejectsEventsFromAGestureThatBeganBeforeTheModeGenerationChanged()
        acceptsEventsFromAGestureThatBeganInTheCurrentGeneration()
        replacesDuplicatePreferenceIdentityWithTheLatestValue()
        print("CardHolderInteractionIsolationTests: PASS")
    }

    private static func rejectsEventsFromAGestureThatBeganBeforeTheModeGenerationChanged() {
        var gate = InteractionGenerationGate(currentGeneration: 7)
        gate.beginGesture()
        gate.updateCurrentGeneration(8)

        precondition(!gate.acceptsCurrentGestureEvent())
        precondition(!gate.endGesture())
    }

    private static func acceptsEventsFromAGestureThatBeganInTheCurrentGeneration() {
        var gate = InteractionGenerationGate(currentGeneration: 8)
        gate.beginGesture()

        precondition(gate.acceptsCurrentGestureEvent())
        precondition(gate.endGesture())
    }

    private static func replacesDuplicatePreferenceIdentityWithTheLatestValue() {
        var values = [
            SamplePreference(id: "name:A", value: "old-name-A"),
            SamplePreference(id: "name:B", value: "name-B")
        ]

        StableIdentityReducer.merge(
            into: &values,
            next: [
                SamplePreference(id: "name:A", value: "new-name-A"),
                SamplePreference(id: "organization:A", value: "organization-A")
            ],
            id: { $0.id }
        )

        precondition(values.map(\.id) == ["name:A", "name:B", "organization:A"])
        precondition(values.map(\.value) == ["new-name-A", "name-B", "organization-A"])
    }
}
