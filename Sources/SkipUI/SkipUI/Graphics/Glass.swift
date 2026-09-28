// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.foundation.background
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import skip.model.StateTracking
#elseif canImport(CoreGraphics)
import struct CoreGraphics.CGFloat
#endif

public struct Glass : Equatable, Sendable {
    public static var regular: Glass {
        return Glass()
    }

    public func tint(_ color: Color?) -> Glass {
        return self
    }

    public func interactive(_ isEnabled: Bool = true) -> Glass {
        return self
    }
}

public struct GlassEffectContainer<Content> : View, Sendable where Content : View {
    @available(*, unavailable)
    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
    }

    public var body: some View {
        EmptyView()
    }
}

public struct GlassEffectTransition : Sendable {
    @available(*, unavailable)
    public static var matchedGeometry: GlassEffectTransition {
        return GlassEffectTransition()
    }

    @available(*, unavailable)
    public static func matchedGeometry(properties: MatchedGeometryProperties = .frame, anchor: UnitPoint = .center) -> GlassEffectTransition {
        return GlassEffectTransition()
    }

    public static var identity: GlassEffectTransition {
        return GlassEffectTransition()
    }
}

extension View {
    /// Compose has no Liquid Glass, so this draws the Material 3 floating-control surface
    /// instead: `surfaceContainer` in `shape`, under a level-2 elevation shadow.
    public func glassEffect(_ glass: Glass = .regular, in shape: any Shape = Capsule(), isEnabled: Bool = true) -> any View {
        #if SKIP
        guard isEnabled else {
            return self
        }
        return ModifiedContent(content: self, modifier: RenderModifier {
            let composeShape = shape.asComposeShape(density: LocalDensity.current)
            return $0.modifier
                .shadow(elevation: 3.dp, shape: composeShape, clip: false)
                .background(MaterialTheme.colorScheme.surfaceContainer, composeShape)
        })
        #else
        return self
        #endif
    }

    // SKIP @bridge
    public func glassEffect(bridgedShape: any Shape, isEnabled: Bool) -> any View {
        return glassEffect(.regular, in: bridgedShape, isEnabled: isEnabled)
    }

    public func glassEffectTransition(_ transition: GlassEffectTransition, isEnabled: Bool = true) -> some View {
        return self
    }

    /// A pass-through: `#available(iOS 26, *)` is vacuously true off-Apple, so shared
    /// sources take their glass branch, and each glass shape draws on its own.
    public func glassEffectUnion(id: (any Hashable)?, namespace: Namespace.ID) -> some View {
        return self
    }

    /// A pass-through, like `glassEffectUnion`.
    public func glassEffectID(_ id: (any Hashable)?, in namespace: Namespace.ID) -> some View {
        return self
    }
}

#endif
