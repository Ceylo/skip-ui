// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.boundsInRoot
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
        let rememberedGlobalFramePx = remember { mutableStateOf<Rect?>(nil) }
        // `BoxWithConstraints` rather than `Box` so the content composes on the measure
        // pass. Waiting for `onGloballyPositionedInRoot` costs a frame of nothing at every
        // `GeometryReader`, which SwiftUI does not: it sizes its content on the first pass.
        BoxWithConstraints(modifier: context.modifier.fillSize().onGloballyPositionedInRoot {
            rememberedGlobalFramePx.value = $0
        }) {
            var globalFramePx = rememberedGlobalFramePx.value
            // The modifier is `fillSize()`, so bounded constraints already *are* the final
            // size. The one thing placement still owns is the global origin: until it
            // arrives, `frame(in: .global)` reads (0, 0) — one recomposition early.
            // Unbounded on either axis (a `GeometryReader` inside a scroll axis) would
            // report `Constraints.Infinity` as its size, which is worse than nothing, so
            // there we keep waiting.
            if globalFramePx == nil && constraints.hasBoundedWidth && constraints.hasBoundedHeight {
                globalFramePx = Rect(left: Float(0.0), top: Float(0.0), right: Float(constraints.maxWidth), bottom: Float(constraints.maxHeight))
            }
            if let globalFramePx {
                let proxy = GeometryProxy(globalFramePx: globalFramePx, density: LocalDensity.current, safeArea: EnvironmentValues.shared._safeArea)
                content(proxy).Compose(context.content())
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
