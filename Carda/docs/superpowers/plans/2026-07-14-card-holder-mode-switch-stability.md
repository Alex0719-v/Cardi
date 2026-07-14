# Card Holder Mode-Switch Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate stale pan callbacks and stale grouped-header geometry during rapid list/name/company switching without changing any current visual or animation behavior.

**Architecture:** Add two small value-semantic correctness helpers: a gesture-generation gate and a stable last-value identity reducer. Integrate them at the existing UIKit pan-observer and SwiftUI anchor-preference boundaries; leave all animation, layout, scrolling, and rendering code unchanged.

**Tech Stack:** Swift 5, SwiftUI, UIKit `UIPanGestureRecognizer`, XCTest UI tests, standalone `swiftc` logic test runner.

## Global Constraints

- Do not change any Figma coordinate, size, spacing, color, corner radius, material, z-index, or mask geometry.
- Do not change any `Animation`, `withAnimation`, `timingCurve`, `snappy`, `transition`, `opacity`, `offset`, duration, delay, scale, or Union morphing expression.
- Do not debounce, throttle, delay, disable, or lock the three mode buttons.
- Do not change `groupedScrollPosition`, `listScrollPosition`, mode scroll-position semantics, sorting, expansion, or scroll physics.
- Preserve all unrelated dirty-worktree changes. Do not stage or commit the overlapping implementation files.
- Execute in the current workspace because the affected CardHolder implementation is uncommitted and does not exist in HEAD.

---

### Task 1: Add failing correctness tests

**Files:**
- Create: `../CardaLogicTests/CardHolderInteractionIsolationTests.swift`
- Modify: `../CardaUITests/CardHolderScrollStabilityUITests.swift`

- [ ] **Step 1: Create the standalone logic test runner before production helpers exist**

```swift
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
```

- [ ] **Step 2: Run the standalone test and verify RED**

Run:

```bash
xcrun swiftc \
  ../CardaLogicTests/CardHolderInteractionIsolationTests.swift \
  -o /tmp/CardHolderInteractionIsolationTests
```

Expected: compilation fails because `InteractionGenerationGate` and `StableIdentityReducer` do not exist yet. The failure must name those missing symbols; syntax or path failures do not count.

- [ ] **Step 3: Add the rapid UI stress regression**

Add this test method to `CardHolderScrollStabilityUITests`:

```swift
func testRapidModeSwitchingAndScrollingKeepsChromeHeadersAndCardsVisible() throws {
    enterCardHolder()

    let window = app.windows.firstMatch
    let modeSequence = ["公司", "列表", "姓名"]

    for cycle in 0..<9 {
        let label = modeSequence[cycle % modeSequence.count]
        let modeButton = app.buttons[label]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 2), "缺少模式按钮：\(label)")
        modeButton.tap()
        window.swipeUp(velocity: .fast)
        window.swipeDown(velocity: .fast)
    }

    assertModeChromeIsVisibleAndInsideCanvas()

    app.buttons["姓名"].tap()
    app.buttons["跳转到 A"].tap()
    XCTAssertTrue(waitForVisibleText("A"), "姓名模式 A 分组标题应保持可见")
    XCTAssertTrue(waitForVisibleText("安晨"), "姓名模式名片文字应保持可见")

    app.buttons["公司"].tap()
    app.buttons["跳转到 B"].tap()
    XCTAssertTrue(waitForVisibleText("B"), "公司模式 B 分组标题应保持可见")
    XCTAssertTrue(waitForVisibleText("唐一鸣"), "公司模式名片文字应保持可见")

    attachScreenshot(named: "05-after-rapid-mode-scroll-stress")
}
```

Add these helpers to the same test class:

```swift
private func enterCardHolder() {
    let holderTab = app.buttons["名片夹"]
    XCTAssertTrue(holderTab.waitForExistence(timeout: 3))
    holderTab.tap()
    XCTAssertTrue(app.buttons["姓名"].waitForExistence(timeout: 3))
}

private func assertModeChromeIsVisibleAndInsideCanvas() {
    let canvas = app.windows.firstMatch.frame
    XCTAssertTrue(waitForVisibleText("名片夹"), "名片夹标题应保持可见")

    for label in ["列表", "姓名", "公司"] {
        let button = app.buttons[label]
        XCTAssertTrue(button.exists, "缺少模式按钮：\(label)")
        XCTAssertFalse(button.frame.isEmpty, "模式按钮 frame 为空：\(label)")
        XCTAssertTrue(button.frame.intersects(canvas), "模式按钮移出画板：\(label)")
    }
}

private func waitForVisibleText(
    _ label: String,
    timeout: TimeInterval = 2
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let canvas = app.windows.firstMatch.frame
        let hasVisibleMatch = app.staticTexts[label]
            .allElementsBoundByIndex
            .contains { element in
                element.exists
                    && !element.frame.isEmpty
                    && element.frame.intersects(canvas)
            }
        if hasVisibleMatch {
            return true
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    } while Date() < deadline

    return false
}
```

- [ ] **Step 4: Run the new UI stress test as a pre-fix baseline**

Run:

```bash
xcodebuild test \
  -project ../Carda.xcodeproj \
  -scheme Carda \
  -destination 'platform=iOS Simulator,id=AD68EC66-4579-421C-8916-80253E4B6A70' \
  -only-testing:CardaUITests/CardHolderScrollStabilityUITests/testRapidModeSwitchingAndScrollingKeepsChromeHeadersAndCardsVisible
```

Expected: the stress test may expose the intermittent visual failure. Regardless of its single-run outcome, Task 1 Step 2 is the deterministic RED gate proving the missing correctness boundary.

---

### Task 2: Implement the minimal value-semantic isolation helpers

**Files:**
- Create: `Components/CardHolderInteractionIsolation.swift`
- Test: `../CardaLogicTests/CardHolderInteractionIsolationTests.swift`

- [ ] **Step 1: Add the generation gate and stable identity reducer**

```swift
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
```

- [ ] **Step 2: Run the standalone test and verify GREEN**

Run:

```bash
xcrun swiftc \
  Components/CardHolderInteractionIsolation.swift \
  ../CardaLogicTests/CardHolderInteractionIsolationTests.swift \
  -o /tmp/CardHolderInteractionIsolationTests && \
  /tmp/CardHolderInteractionIsolationTests
```

Expected: exit 0 and `CardHolderInteractionIsolationTests: PASS`.

---

### Task 3: Gate stale pan sessions without changing gesture or animation behavior

**Files:**
- Modify: `Views/CardHolder/CardHolderView.swift:66-97, 1370-1386, 1519-1526, 2639-2743`
- Test: `../CardaLogicTests/CardHolderInteractionIsolationTests.swift`

- [ ] **Step 1: Add a mode interaction generation state**

Add beside the existing grouped-header transition state:

```swift
@State private var modeInteractionGeneration = 0
```

- [ ] **Step 2: Pass the generation into the existing pan observer**

Change only the observer construction:

```swift
ScrollViewPanObserver(
    generation: modeInteractionGeneration,
    onChanged: { delta in
        handleHeaderPanDelta(
            delta,
            source: source
        )
    },
    onEnded: {
        finishHeaderPan(source: source)
    }
)
```

- [ ] **Step 3: Advance generation before the existing mode reset and animation**

Keep every existing statement and animation unchanged; insert one line after the guard:

```swift
private func selectMode(_ item: HolderMode) {
    guard item != mode else { return }
    modeInteractionGeneration &+= 1
    resetHeaderTrackingForModeChange()
    setHeaderCollapseOffset(0, animated: false)
    retainedGroupedHeaderTitle = nil
    prepareGroupedHeaderTransition(to: item)
    updateSelectedMode(item)
}
```

- [ ] **Step 4: Gate callbacks inside `ScrollViewPanObserver.Coordinator`**

Add `generation`, initialize the coordinator with it, update it from `updateUIView`, and use the gate in `handlePan`:

```swift
private struct ScrollViewPanObserver: UIViewRepresentable {
    let generation: Int
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            generation: generation,
            onChanged: onChanged,
            onEnded: onEnded
        )
    }

    // makeUIView stays unchanged.

    func updateUIView(_ uiView: AttachmentView, context: Context) {
        context.coordinator.updateGeneration(generation)
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject {
        var onChanged: (CGSize) -> Void
        var onEnded: () -> Void
        private var generationGate: InteractionGenerationGate
        private weak var panGestureRecognizer: UIPanGestureRecognizer?
        private var previousTranslation: CGPoint = .zero

        init(
            generation: Int,
            onChanged: @escaping (CGSize) -> Void,
            onEnded: @escaping () -> Void
        ) {
            generationGate = InteractionGenerationGate(
                currentGeneration: generation
            )
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func updateGeneration(_ generation: Int) {
            generationGate.updateCurrentGeneration(generation)
        }

        // deinit and attachIfNeeded stay unchanged.

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let point = recognizer.translation(in: recognizer.view)
            switch recognizer.state {
            case .began:
                generationGate.beginGesture()
                previousTranslation = point
            case .changed:
                let delta = CGSize(
                    width: point.x - previousTranslation.x,
                    height: point.y - previousTranslation.y
                )
                previousTranslation = point
                guard generationGate.acceptsCurrentGestureEvent() else { return }
                if abs(delta.width) > 0.01 || abs(delta.height) > 0.01 {
                    onChanged(delta)
                }
            case .ended, .cancelled, .failed:
                let shouldNotify = generationGate.endGesture()
                if shouldNotify {
                    onEnded()
                }
                previousTranslation = .zero
            default:
                break
            }
        }
    }
}
```

- [ ] **Step 5: Build after the pan-session integration**

Run:

```bash
xcodebuild build \
  -project ../Carda.xcodeproj \
  -scheme Carda \
  -destination 'platform=iOS Simulator,id=AD68EC66-4579-421C-8916-80253E4B6A70'
```

Expected: `** BUILD SUCCEEDED **`.

---

### Task 4: Isolate and deduplicate grouped-header anchors by mode

**Files:**
- Modify: `Views/CardHolder/CardHolderView.swift:530-679, 2581-2618`
- Test: `../CardaLogicTests/CardHolderInteractionIsolationTests.swift`

- [ ] **Step 1: Capture the grouped mode as the anchor-tree identity source**

At the start of `groupedCardContent`, preserve the current mode value:

```swift
private var groupedCardContent: some View {
    let groupedMode = mode

    return ScrollViewReader { scrollProxy in
        // Existing content stays unchanged except for the anchor calls below.
    }
}
```

Change the tracked header call to:

```swift
trackedGroupTitle(group.title, mode: groupedMode)
```

- [ ] **Step 2: Filter the overlay preference to the current grouped mode**

Inside `overlayPreferenceValue`, derive frames only from current-mode anchors:

```swift
let activeHeaders = headers.filter { $0.mode == groupedMode }
let frames = activeHeaders.map { proxy[$0.bounds] }
let pinnedTitle = resolvedGroupedPinnedHeaderTitle(
    headers: activeHeaders,
    frames: frames
)
```

Update the foreground loop and opacity resolver to use `activeHeaders`:

```swift
ForEach(Array(activeHeaders.enumerated()), id: \.element.id) { index, header in
    let frame = frames[index]
    if header.title != pinnedTitle {
        groupTitle(header.title)
            .position(x: frame.midX, y: frame.midY)
            .transition(
                groupedHeaderTransitionActive
                    ? groupedHeaderTransition(for: header.title)
                    : .identity
            )
    }
}

if let pinnedTitle {
    groupTitle(pinnedTitle)
        .opacity(
            groupedPinnedHeaderOpacity(
                pinnedTitle: pinnedTitle,
                headers: activeHeaders,
                frames: frames
            )
        )
        .position(
            x: CardaTheme.canvasWidth / 2,
            y: currentGroupedHeaderPinTop
                + (groupedHeaderHeight + groupedHeaderTransitionGap) / 2
        )
}
```

Guard the retention callback so an outgoing tree cannot write the current state:

```swift
PinnedHeaderRetentionObserver(value: pinnedTitle) { title in
    guard mode == groupedMode else { return }
    guard retainedGroupedHeaderTitle != title else { return }
    retainedGroupedHeaderTitle = title
}
```

- [ ] **Step 3: Add mode identity to tracked anchors**

Replace the tracked helper and anchor model with:

```swift
private func trackedGroupTitle(
    _ title: String,
    mode: HolderMode
) -> some View {
    groupTitle(title)
        .anchorPreference(
            key: GroupedHeaderAnchorPreferenceKey.self,
            value: .bounds
        ) {
            [
                GroupedHeaderAnchor(
                    mode: mode,
                    title: title,
                    bounds: $0
                )
            ]
        }
        .opacity(0)
}

private struct GroupedHeaderAnchor: Identifiable {
    let mode: HolderMode
    let title: String
    let bounds: Anchor<CGRect>

    var id: String { "\(mode.rawValue):\(title)" }
}
```

- [ ] **Step 4: Deduplicate preference values by mode-and-title identity**

Replace append-only reduction with:

```swift
private struct GroupedHeaderAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [GroupedHeaderAnchor] = []

    static func reduce(
        value: inout [GroupedHeaderAnchor],
        nextValue: () -> [GroupedHeaderAnchor]
    ) {
        StableIdentityReducer.merge(
            into: &value,
            next: nextValue(),
            id: { $0.id }
        )
    }
}
```

- [ ] **Step 5: Re-run logic tests and build**

Run:

```bash
xcrun swiftc \
  Components/CardHolderInteractionIsolation.swift \
  ../CardaLogicTests/CardHolderInteractionIsolationTests.swift \
  -o /tmp/CardHolderInteractionIsolationTests && \
  /tmp/CardHolderInteractionIsolationTests

xcodebuild build \
  -project ../Carda.xcodeproj \
  -scheme Carda \
  -destination 'platform=iOS Simulator,id=AD68EC66-4579-421C-8916-80253E4B6A70'
```

Expected: logic runner prints `PASS`; build prints `** BUILD SUCCEEDED **`.

---

### Task 5: Verify the original stress path and prove zero animation/visual changes

**Files:**
- Verify: `Views/CardHolder/CardHolderView.swift`
- Verify: `Views/AppShellView.swift`
- Verify: `../CardaUITests/CardHolderScrollStabilityUITests.swift`

- [ ] **Step 1: Run the complete CardHolder UI test class**

Run:

```bash
xcodebuild test \
  -project ../Carda.xcodeproj \
  -scheme Carda \
  -destination 'platform=iOS Simulator,id=AD68EC66-4579-421C-8916-80253E4B6A70' \
  -only-testing:CardaUITests/CardHolderScrollStabilityUITests
```

Expected: all tests pass with zero failures, including the rapid mode-switch stress test.

- [ ] **Step 2: Prove the implementation did not edit animation or visual expressions**

Run:

```bash
diff -u \
  /tmp/CardHolderView.before-stability-fix.swift \
  Views/CardHolder/CardHolderView.swift | \
  rg '^[+-].*(Animation|withAnimation|timingCurve|snappy|transition|opacity|offset|duration|delay|scaleEffect|frame\(|position\(|padding\(|mask\()'
```

Expected: no output. If any line appears, inspect it and revert the visual/animation change before continuing.

Run:

```bash
git diff --no-index -- \
  /tmp/CardHolderScrollStabilityUITests.before-stability-fix.swift \
  ../CardaUITests/CardHolderScrollStabilityUITests.swift
```

Expected: only the new stress test and its assertion helpers differ.

- [ ] **Step 3: Capture final simulator evidence in all grouped modes**

Run the app and inspect normal-speed list, name, and company states. Capture screenshots after the stress test and confirm:

- title and three mode labels remain visible and in their existing positions;
- grouped header and card text remain visible;
- Union, header collapse, fade, and scroll animations retain their current timing and appearance.

---

### Task 6: Synchronize project documentation

**Files:**
- Modify: `AGENTS.md`
- Modify: `contributing_ai.md`
- Modify: `README.md`
- Modify: `Designsystem.md`
- Modify: `ROADMAP.md`

- [ ] **Step 1: Add the permanent correctness constraint to `AGENTS.md`**

Add this rule in the CardHolder scrolling/mode-switch section:

```markdown
- 名片夹快速切换列表/姓名/公司时，旧模式已经开始的原生 pan 回调与分组标题 Anchor Preference 不得写入新模式状态。实现必须以手势开始时的交互代际过滤迟到回调，并以“模式 + 标题”作为分组锚点身份进行去重和当前模式过滤。该稳定性修复不得修改既有 Figma 布局、动画曲线、时长、延迟、透明度、位移、Union 形变或滚动物理。
```

- [ ] **Step 2: Add the implementation protocol to `contributing_ai.md`**

```markdown
- 修改名片夹模式切换或滚动观察器时，必须保留原生 `UIScrollView.panGestureRecognizer`，并使用模式交互代际阻断切换前已开始手势的迟到 `.changed` / `.ended`。分组标题偏好必须按“模式 + 标题”去重且只消费当前模式；禁止用节流、禁用点击或改动画参数掩盖竞态。
```

- [ ] **Step 3: Update current status in `README.md`**

```markdown
- 名片夹已覆盖列表/姓名/公司快速切换与快速上下滚动的稳定性回归：旧手势回调和旧模式分组锚点不会污染当前模式；现有视觉与动画参数保持不变。
```

- [ ] **Step 4: Record zero visual change in `Designsystem.md`**

```markdown
- 名片夹模式切换稳定性修复仅增加交互代际与分组锚点身份隔离；不修改任何 Figma 坐标、材质、层级或动画曲线/时长/延迟/透明度/位移。
```

- [ ] **Step 5: Add the completed stability item to `ROADMAP.md`**

```markdown
- 修复名片夹快速切换列表/姓名/公司并快滑时的时序竞态：旧 pan 会话按交互代际失效，分组标题锚点按模式与标题去重过滤；新增逻辑与 UI 压力回归，视觉和动画参数零改动 `[done]`
```

- [ ] **Step 6: Run final documentation and build checks**

Run:

```bash
git diff --check

xcodebuild build \
  -project ../Carda.xcodeproj \
  -scheme Carda \
  -destination 'platform=iOS Simulator,id=AD68EC66-4579-421C-8916-80253E4B6A70'
```

Expected: `git diff --check` exits 0; build prints `** BUILD SUCCEEDED **`.

## Completion Audit

- The original rapid switch + rapid vertical scroll path has a passing UI regression.
- Stale pan events are rejected by a deterministic logic test.
- Duplicate/stale grouped-header preference identities are rejected by a deterministic logic test.
- Existing CardHolder UI tests all pass.
- The application builds for the booted iPhone 17 Pro simulator.
- Diff audit proves no animation or visual expression changed.
- All five project guidance/status documents match the implementation.
