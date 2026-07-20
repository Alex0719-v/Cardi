//
//  ScrollOffsetBridge.swift
//  Cardi
//

import SwiftUI
import UIKit

struct ScrollOffsetMetrics: Equatable {
    let offsetY: CGFloat
    let maximumOffsetY: CGFloat
}

struct ScrollOffsetRequest: Equatable {
    let id = UUID()
    let y: CGFloat
    var animated = true
}

/// Backports the small part of iOS 18 ScrollPosition/ScrollGeometry used by
/// Cardi to iOS 17 while preserving the existing UIScrollView gesture pipeline.
struct ScrollOffsetBridge: UIViewRepresentable {
    @Binding var request: ScrollOffsetRequest?
    var onMetrics: (ScrollOffsetMetrics) -> Void

    func makeUIView(context: Context) -> ScrollOffsetBridgeView {
        ScrollOffsetBridgeView()
    }

    func updateUIView(_ uiView: ScrollOffsetBridgeView, context: Context) {
        uiView.configure(
            request: $request,
            onMetrics: onMetrics
        )
    }
}

@MainActor
final class ScrollOffsetBridgeView: UIView {
    private weak var scrollView: UIScrollView?
    private var request: Binding<ScrollOffsetRequest?>?
    private var onMetrics: ((ScrollOffsetMetrics) -> Void)?
    private var lastAppliedRequestID: UUID?
    private var lastPublishedMetrics: ScrollOffsetMetrics?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    private var boundsObservation: NSKeyValueObservation?
    private var contentInsetObservation: NSKeyValueObservation?

    func configure(
        request: Binding<ScrollOffsetRequest?>,
        onMetrics: @escaping (ScrollOffsetMetrics) -> Void
    ) {
        self.request = request
        self.onMetrics = onMetrics
        attachToScrollViewIfNeeded()
        applyPendingRequestIfNeeded()
        publishMetricsIfNeeded()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachToScrollViewIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachToScrollViewIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachToScrollViewIfNeeded()
        publishMetricsIfNeeded()
    }

    private func attachToScrollViewIfNeeded() {
        guard window != nil || superview != nil else { return }

        if let scrollView, isDescendant(of: scrollView) {
            return
        }

        guard let discovered = nearestScrollView() else {
            DispatchQueue.main.async { [weak self] in
                self?.attachToScrollViewIfNeeded()
            }
            return
        }

        scrollView = discovered
        contentOffsetObservation = discovered.observe(
            \.contentOffset,
             options: [.initial, .new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.publishMetricsIfNeeded()
            }
        }
        contentSizeObservation = discovered.observe(
            \.contentSize,
             options: [.initial, .new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.publishMetricsIfNeeded()
            }
        }
        boundsObservation = discovered.observe(
            \.bounds,
             options: [.initial, .new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.publishMetricsIfNeeded()
            }
        }
        contentInsetObservation = discovered.observe(
            \.contentInset,
             options: [.initial, .new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.publishMetricsIfNeeded()
            }
        }

        applyPendingRequestIfNeeded()
    }

    private func nearestScrollView() -> UIScrollView? {
        var current: UIView? = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }

    private func applyPendingRequestIfNeeded() {
        guard
            let request,
            let pending = request.wrappedValue,
            pending.id != lastAppliedRequestID,
            let scrollView
        else {
            return
        }

        lastAppliedRequestID = pending.id
        let insetTop = scrollView.adjustedContentInset.top
        let maximumOffsetY = maximumOffsetY(in: scrollView)
        let clampedY = min(max(pending.y, 0), maximumOffsetY)
        let targetContentOffset = CGPoint(
            x: scrollView.contentOffset.x,
            y: clampedY - insetTop
        )
        scrollView.setContentOffset(targetContentOffset, animated: pending.animated)
        publishMetricsIfNeeded(force: true)

        DispatchQueue.main.async {
            if request.wrappedValue?.id == pending.id {
                request.wrappedValue = nil
            }
        }
    }

    private func publishMetricsIfNeeded(force: Bool = false) {
        guard let scrollView, let onMetrics else { return }

        let displayScale = UIScreen.main.scale
        let normalizedOffsetY = scrollView.contentOffset.y
            + scrollView.adjustedContentInset.top
        let metrics = ScrollOffsetMetrics(
            offsetY: roundToDisplayScale(
                min(max(normalizedOffsetY, 0), maximumOffsetY(in: scrollView)),
                displayScale: displayScale
            ),
            maximumOffsetY: roundToDisplayScale(
                maximumOffsetY(in: scrollView),
                displayScale: displayScale
            )
        )

        guard force || metrics != lastPublishedMetrics else { return }
        lastPublishedMetrics = metrics
        onMetrics(metrics)
    }

    private func maximumOffsetY(in scrollView: UIScrollView) -> CGFloat {
        max(
            0,
            scrollView.contentSize.height
                + scrollView.adjustedContentInset.top
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        )
    }

    private func roundToDisplayScale(
        _ value: CGFloat,
        displayScale: CGFloat
    ) -> CGFloat {
        guard displayScale > 0 else { return value }
        return (value * displayScale).rounded() / displayScale
    }
}
