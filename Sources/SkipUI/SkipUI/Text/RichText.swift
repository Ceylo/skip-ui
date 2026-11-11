// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.LinkInteractionListener
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.fromHtml
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.sp

/// Compose's HTML parser behind `Text(bridgedHTML:)`, and the inline views it splices in.
struct RichText {
    /// The Compose slots for the inline views; placeholders are positional:
    /// the i-th U+FFFC of the parsed markup takes the i-th view.
    static func inlineContent(views: [any View], widths: [Double], heights: [Double], context: ComposeContext) -> kotlin.collections.Map<String, InlineTextContent> {
        let content = mutableMapOf<String, InlineTextContent>()
        for index in 0..<views.count {
            let width = index < widths.count ? widths[index] : 1.0
            let height = index < heights.count ? heights[index] : 1.0
            content[inlineContentID(index)] = slot(for: views[index], width: width, height: height, context: context)
        }
        return content
    }

    private static func slot(for view: any View, width: Double, height: Double, context: ComposeContext) -> InlineTextContent {
        // `Center`, not `TextCenter`: the `Text*` alignments fit the placeholder
        // into the text's own vertical bounds, so anything taller than a line —
        // an avatar, say — spills over the line below instead of growing the line.
        let placeholder = Placeholder(
            width: width.sp,
            height: height.sp,
            placeholderVerticalAlign: PlaceholderVerticalAlign.Center
        )
        return InlineTextContent(placeholder) { _ in
            view.Compose(context: context)
        }
    }

    // MARK: HTML

    /// FA's markup as Compose parses it, with links styled and their taps intercepted.
    ///
    /// Without a `LinkInteractionListener` Compose answers a tap with its own
    /// `UriHandler`, which leaves for the browser before the app can decide whether the
    /// URL is one it can open itself.
    static func annotatedString(html: String, linkColor: androidx.compose.ui.graphics.Color, onLinkTap: @escaping (String) -> Void) -> AnnotatedString {
        let listener = LinkInteractionListener { link in
            if let url = link as? LinkAnnotation.Url {
                onLinkTap(url.url)
            }
        }
        return AnnotatedString.fromHtml(
            html,
            linkStyles: TextLinkStyles(style: SpanStyle(color: linkColor, textDecoration: TextDecoration.Underline)),
            linkInteractionListener: listener
        )
    }

    /// `parsed` with its first `count` U+FFFC placeholders — the marks `fromHtml` leaves
    /// where it dropped an `<img>` — turned into inline-content slots.
    ///
    /// The slots are annotated in place, as `appendInlineContent` would, rather than the
    /// text being rebuilt around them: every range the copy cut would come back as
    /// several, and Compose lays out each `ParagraphStyle` range as its own paragraph.
    static func splicingInlineContent(_ parsed: AnnotatedString, count: Int) -> AnnotatedString {
        let builder = AnnotatedString.Builder(parsed)
        var offset = 0
        var index = 0
        // Transpiled, this iterates UTF-16 code units, which is the unit Compose counts
        // its offsets in — so an emoji earlier in the text can't shift a placeholder.
        for character in parsed.text {
            if character == placeholderCharacter, index < count {
                builder.addStringAnnotation(inlineContentTag, inlineContentID(index), offset, offset + 1)
                index += 1
            }
            offset += 1
        }
        return builder.toAnnotatedString()
    }

    static func inlineContentID(_ index: Int) -> String {
        return "skip.inline.\(index)"
    }

    /// U+FFFC, the object-replacement character.
    private static let placeholderCharacter: Character = "\u{FFFC}"
    private static let inlineContentTag = "androidx.compose.foundation.text.inlineContent"
}
#endif
#endif
