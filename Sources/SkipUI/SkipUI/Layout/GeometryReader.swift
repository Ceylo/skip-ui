// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
#endif

// SKIP @bridge
public struct GeometryReader : View, Renderable {
    public let content: (GeometryProxy) -> any View

    // SKIP @bridge
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> any View) {
        self.content = content
    }

    #if SKIP
    @Composable override func Render(context: ComposeContext) {
        let geometry = remember { GeometryReaderState() }
        UpdateGeometryReaderSafeArea(geometry)
        // `BoxWithConstraints` rather than `Box` so the content composes on the measure
        // pass. Waiting for `onGloballyPositioned` costs a frame of nothing at every
        // `GeometryReader`, which SwiftUI does not: it sizes its content on the first pass.
        // It is a `SubcomposeLayout`, though, which throws on intrinsic queries, so the
        // modifiers go on `GeometryReaderLayout` around it, and that node answers them.
        GeometryReaderLayout(modifier: context.modifier.fillSize().onGloballyPositioned {
            // The laid-out frame, not `boundsInRoot()`: that is intersected with every clipping
            // ancestor, so a partially scrolled row would pin its origin to the viewport edge.
            let size = $0.size
            let origin = $0.positionInRoot()
            geometry.update(size: size, frame: Rect(left: origin.x, top: origin.y, right: origin.x + Float(size.width), bottom: origin.y + Float(size.height)))
        }) {
            BoxWithConstraints(modifier: Modifier.fillMaxSize()) {
                if geometry.isPositioned {
                    // Constructing the proxy must not read its frame or safe area. The content decides
                    // which properties it needs, including across the native Swift bridge.
                    let proxy = GeometryProxy(geometry: geometry, density: LocalDensity.current)
                    content(proxy).Compose(context.content())
                } else if constraints.hasBoundedWidth && constraints.hasBoundedHeight {
                    // The outer node is `fillSize()` and this box fills it, so bounded constraints
                    // already *are* the final size; only the global origin waits for placement, and
                    // reads (0, 0) until then. Unbounded on either axis (inside a scroll axis) would
                    // report `Constraints.Infinity` as the size, so there we keep waiting.
                    let framePx = Rect(left: Float(0.0), top: Float(0.0), right: Float(constraints.maxWidth), bottom: Float(constraints.maxHeight))
                    let proxy = GeometryProxy(globalFramePx: framePx, density: LocalDensity.current, safeArea: EnvironmentValues.shared._safeArea)
                    content(proxy).Compose(context.content())
                }
            }
        }
    }
    #else
    public var body: some View {
        stubView()
    }
    #endif
}

#endif
