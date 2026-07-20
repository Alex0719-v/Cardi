#include <metal_stdlib>
using namespace metal;

static float cardaSmoothStep(float value) {
    value = clamp(value, 0.0, 1.0);
    return value * value * (3.0 - 2.0 * value);
}

static float cardaGeniePhase(
    float normalizedY,
    float progress,
    bool targetIsBelow
) {
    float leadingEdge = targetIsBelow ? normalizedY : (1.0 - normalizedY);
    float delay = (1.0 - leadingEdge) * 0.20;
    float local = (progress - delay) / max(1.0 - delay, 0.001);
    return cardaSmoothStep(local);
}

static float cardaMappedY(
    float normalizedY,
    float2 cardOrigin,
    float2 cardSize,
    float2 target,
    float progress,
    bool targetIsBelow
) {
    float sourceY = cardOrigin.y + normalizedY * cardSize.y;
    float phase = cardaGeniePhase(normalizedY, progress, targetIsBelow);
    return mix(sourceY, target.y, phase);
}

/// Continuously warps one rectangular card into a compact target point.
///
/// The edge closest to the target leads the movement. Every horizontal band
/// remains connected to its neighbours, producing a single elastic surface
/// instead of a visible stack of independently moving slices.
[[ stitchable ]] float2 cardaGenieWarp(
    float2 position,
    float2 cardOrigin,
    float2 cardSize,
    float2 target,
    float progress,
    float targetWidth,
    float bend
) {
    progress = clamp(progress, 0.0, 1.0);
    float2 cardCenter = cardOrigin + cardSize * 0.5;
    bool targetIsBelow = target.y >= cardCenter.y;

    float mappedTop = cardaMappedY(
        0.0,
        cardOrigin,
        cardSize,
        target,
        progress,
        targetIsBelow
    );
    float mappedBottom = cardaMappedY(
        1.0,
        cardOrigin,
        cardSize,
        target,
        progress,
        targetIsBelow
    );

    float lowerY = min(mappedTop, mappedBottom) - 1.0;
    float upperY = max(mappedTop, mappedBottom) + 1.0;
    if (position.y < lowerY || position.y > upperY) {
        return float2(0.0, 0.0);
    }

    // The vertical mapping is monotonic. Invert it with a short bisection so
    // every destination pixel samples the matching row of the original card.
    float low = 0.0;
    float high = 1.0;
    for (int index = 0; index < 11; ++index) {
        float middle = (low + high) * 0.5;
        float mapped = cardaMappedY(
            middle,
            cardOrigin,
            cardSize,
            target,
            progress,
            targetIsBelow
        );
        if (mapped < position.y) {
            low = middle;
        } else {
            high = middle;
        }
    }

    float normalizedY = (low + high) * 0.5;
    float phase = cardaGeniePhase(normalizedY, progress, targetIsBelow);
    float pinch = pow(phase, 0.78);
    float warpedWidth = mix(cardSize.x, targetWidth, pinch);
    float warpedCenterX = mix(cardCenter.x, target.x, phase)
        + sin(phase * M_PI_F) * bend;
    float warpedLeft = warpedCenterX - warpedWidth * 0.5;
    float warpedRight = warpedCenterX + warpedWidth * 0.5;

    if (position.x < warpedLeft || position.x > warpedRight || warpedWidth < 0.5) {
        return float2(0.0, 0.0);
    }

    float sourceX = cardOrigin.x
        + ((position.x - warpedLeft) / warpedWidth) * cardSize.x;
    float sourceY = cardOrigin.y + normalizedY * cardSize.y;
    return float2(sourceX, sourceY);
}
