// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.unit.dp
#elseif canImport(CoreGraphics)
import struct CoreGraphics.CGFloat
#endif

/// A leading-aligned row that wraps onto additional lines.
///
/// SwiftUI expresses this with the `Layout` protocol, which SkipUI does not implement;
/// Compose has it natively as `FlowRow`, so it is exposed here as a container instead.
// SKIP @bridge
public struct FlowRow : View, Renderable {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    let content: ComposeBuilder

    public init(spacing: CGFloat = 8.0, lineSpacing: CGFloat = 8.0, @ViewBuilder content: () -> any View) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = ComposeBuilder.from(content)
    }

    // SKIP @bridge
    public init(spacing: CGFloat, lineSpacing: CGFloat, bridgedContent: any View) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = ComposeBuilder.from { bridgedContent }
    }

    #if SKIP
    // SKIP INSERT: @OptIn(ExperimentalLayoutApi::class)
    @Composable override func Render(context: ComposeContext) {
        let renderables = content.Evaluate(context: context, options: 0).filter { !$0.isSwiftUIEmptyView }
        androidx.compose.foundation.layout.FlowRow(
            modifier: context.modifier,
            horizontalArrangement: Arrangement.spacedBy(spacing.dp),
            verticalArrangement: Arrangement.spacedBy(lineSpacing.dp)
        ) {
            let contentContext = context.content()
            for renderable in renderables {
                renderable.Render(context: contentContext)
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
