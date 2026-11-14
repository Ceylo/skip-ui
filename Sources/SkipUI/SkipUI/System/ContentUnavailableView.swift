// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
#endif

// SKIP @bridge
public struct ContentUnavailableView : View, Renderable {
    let label: ComposeBuilder
    let descriptionContent: ComposeBuilder
    let actions: ComposeBuilder

    public init(@ViewBuilder label: () -> any View, @ViewBuilder description: () -> any View = { EmptyView() }, @ViewBuilder actions: () -> any View = { EmptyView() }) {
        self.label = ComposeBuilder.from(label)
        self.descriptionContent = ComposeBuilder.from(description)
        self.actions = ComposeBuilder.from(actions)
    }

    // SKIP @bridge
    public init(bridgedLabel: any View, bridgedDescription: any View, bridgedActions: any View) {
        self.label = ComposeBuilder.from { bridgedLabel }
        self.descriptionContent = ComposeBuilder.from { bridgedDescription }
        self.actions = ComposeBuilder.from { bridgedActions }
    }

    public init(_ titleKey: LocalizedStringKey, image: String, description: Text? = nil) {
        self.init(label: { Label(titleKey, image: image) }, description: { Self.view(description) })
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.init(label: { Label(titleKey, systemImage: systemImage) }, description: { Self.view(description) })
    }

    public init(_ titleResource: LocalizedStringResource, image: String, description: Text? = nil) {
        self.init(label: { Label(titleResource, image: image) }, description: { Self.view(description) })
    }

    public init(_ titleResource: LocalizedStringResource, systemImage: String, description: Text? = nil) {
        self.init(label: { Label(titleResource, systemImage: systemImage) }, description: { Self.view(description) })
    }

    public init(_ title: String, image: String, description: Text? = nil) {
        self.init(label: { Label(title, image: image) }, description: { Self.view(description) })
    }

    public init(_ title: String, systemImage: String, description: Text? = nil) {
        self.init(label: { Label(title, systemImage: systemImage) }, description: { Self.view(description) })
    }

    private static func view(_ text: Text?) -> any View {
        if let text {
            return text
        }
        return EmptyView()
    }

    #if SKIP
    @Composable override func Render(context: ComposeContext) {
        let contentContext = context.content()
        Column(modifier: context.modifier.fillSize().padding(24.dp), verticalArrangement: Arrangement.spacedBy(8.dp, Alignment.CenterVertically), horizontalAlignment: Alignment.CenterHorizontally) {
            // Stacked as on iOS, not in the row a Label draws on its own.
            if let label = label.Evaluate(context: contentContext, options: 0).firstOrNull()?.strip() as? Label {
                label.image.font(Font.system(size: 48.0)).foregroundStyle(Color.secondary).Compose(context: contentContext)
                label.title.font(Font.title2.bold()).multilineTextAlignment(TextAlignment.center).Compose(context: contentContext)
            } else {
                label.font(Font.title2.bold()).multilineTextAlignment(TextAlignment.center).Compose(context: contentContext)
            }
            descriptionContent.foregroundStyle(Color.secondary).multilineTextAlignment(TextAlignment.center).Compose(context: contentContext)
            actions.Compose(context: contentContext.content(modifier: Modifier.padding(top: 8.dp)))
        }
    }
    #else
    public var body: some View {
        stubView()
    }
    #endif
}

/*
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension ContentUnavailableView where LabelX == SearchUnavailableContent.Label, Description == SearchUnavailableContent.Description, Actions == SearchUnavailableContent.Actions {
    public static var search: ContentUnavailableView<SearchUnavailableContent.Label, SearchUnavailableContent.Description, SearchUnavailableContent.Actions> { get { fatalError() } }

    public static func search(text: String) -> ContentUnavailableView<LabelX, Description, Actions> { fatalError() }
}
*/
#endif
