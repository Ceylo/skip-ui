// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.LinkInteractionListener
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.UrlAnnotation
import androidx.compose.ui.text.fromHtml
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
#endif

/// The wire format behind `Text(bridgedRichText:)`.
///
/// A Fuse `AttributedString` can say things markdown cannot — a literal colour, a font
/// size, an underline, a baseline shift — so its runs cross the bridge as records
/// rather than as re-emitted markdown. One record per run, separated by ASCII RS; one
/// field per attribute within a record, separated by ASCII US. Both are stripped from
/// the encoded text on the Fuse side, so neither can appear inside a field.
struct RichText {
    // Spelled with four hex digits so the transpiled Kotlin escape is well-formed.
    static let recordSeparator = "\u{001E}"
    static let fieldSeparator = "\u{001F}"

    static func runs(from payload: String) -> [RichTextRun] {
        return payload.components(separatedBy: recordSeparator).compactMap { record in
            let fields = record.components(separatedBy: fieldSeparator)
            guard fields.count >= 12, !fields[0].isEmpty else { return nil }
            let decorations = fields[6]
            return RichTextRun(
                text: fields[0],
                fontWeight: Int(fields[1]),
                isItalic: fields[2] == "1",
                isMonospaced: fields[3] == "1",
                fontSize: Double(fields[4]),
                color: fields[5].isEmpty ? nil : fields[5],
                isUnderlined: decorations.contains("u"),
                isStruckThrough: decorations.contains("s"),
                baseline: fields[7].isEmpty ? nil : fields[7],
                link: fields[8].isEmpty ? nil : fields[8],
                inlineViewIndex: Int(fields[9]),
                inlineViewWidth: Double(fields[10]),
                inlineViewHeight: Double(fields[11])
            )
        }
    }

    /// One segment of a `Text + Text`: the record carries the styling, and the text
    /// comes from the segment's own `Text`, which resolves it at compose time.
    static func run(from record: String, text: String) -> RichTextRun {
        let fields = record.components(separatedBy: fieldSeparator)
        func field(_ index: Int) -> String {
            return index < fields.count ? fields[index] : ""
        }
        let decorations = field(6)
        return RichTextRun(
            text: text,
            fontWeight: Int(field(1)),
            isItalic: field(2) == "1",
            isMonospaced: field(3) == "1",
            fontSize: Double(field(4)),
            color: field(5).isEmpty ? nil : field(5),
            isUnderlined: decorations.contains("u"),
            isStruckThrough: decorations.contains("s"),
            baseline: field(7).isEmpty ? nil : field(7),
            link: field(8).isEmpty ? nil : field(8),
            inlineViewIndex: nil,
            inlineViewWidth: nil,
            inlineViewHeight: nil
        )
    }

    /// The payload's text with all styling dropped.
    static func plainText(from payload: String) -> String {
        return runs(from: payload).map { $0.text }.joined()
    }
}

/// One styled span of a `RichText` payload.
struct RichTextRun {
    let text: String
    /// A `Font.Weight.value`, i.e. Skip's own -3…5 scale rather than a CSS weight.
    let fontWeight: Int?
    let isItalic: Bool
    let isMonospaced: Bool
    let fontSize: Double?
    /// A decimal ARGB literal, or one of the `primary`/`secondary`/`accent` tokens,
    /// which only the composition can resolve.
    let color: String?
    let isUnderlined: Bool
    let isStruckThrough: Bool
    /// `sub` or `super`.
    let baseline: String?
    let link: String?
    /// Set when this run is a placeholder for one of the `Text`'s inline views, which
    /// Compose splices in by id and needs a reserved size for.
    let inlineViewIndex: Int?
    let inlineViewWidth: Double?
    let inlineViewHeight: Double?

    var inlineContentID: String? {
        guard let inlineViewIndex else { return nil }
        return "skip.inline.\(inlineViewIndex)"
    }
}

#if SKIP
/// The environment-dependent colours a payload can name, resolved once per render.
struct RichTextPalette {
    let link: androidx.compose.ui.graphics.Color
    let primary: androidx.compose.ui.graphics.Color
    let secondary: androidx.compose.ui.graphics.Color
    let accent: androidx.compose.ui.graphics.Color

    func color(for token: String) -> androidx.compose.ui.graphics.Color? {
        switch token {
        case "primary":
            return primary
        case "secondary":
            return secondary
        case "accent":
            return accent
        default:
            guard let argb = Int64(token) else { return nil }
            return androidx.compose.ui.graphics.Color(argb.toInt())
        }
    }
}

extension RichText {
    // SKIP INSERT: @OptIn(ExperimentalTextApi::class)
    static func annotatedString(runs: [RichTextRun], palette: RichTextPalette, isUppercased: Bool, isLowercased: Bool, isRedacted: Bool) -> AnnotatedString {
        // An explicit builder rather than `buildAnnotatedString`: its receiver is a
        // Kotlin lambda receiver, which a static Swift function cannot name.
        let builder = AnnotatedString.Builder()
        for run in runs {
            var color = androidx.compose.ui.graphics.Color.Unspecified
            if let token = run.color, let resolved = palette.color(for: token) {
                color = resolved
            }
            if run.link != nil {
                color = palette.link
            }
            var fontSize = TextUnit.Unspecified
            if let size = run.fontSize {
                fontSize = size.sp
            }
            var decoration: TextDecoration? = nil
            if run.isUnderlined && run.isStruckThrough {
                decoration = TextDecoration.combine(listOf(TextDecoration.Underline, TextDecoration.LineThrough))
            } else if run.isUnderlined {
                decoration = TextDecoration.Underline
            } else if run.isStruckThrough {
                decoration = TextDecoration.LineThrough
            }
            var baselineShift: BaselineShift? = nil
            if run.baseline == "super" {
                baselineShift = BaselineShift.Superscript
            } else if run.baseline == "sub" {
                baselineShift = BaselineShift.Subscript
            }
            let style = SpanStyle(
                color: isRedacted && run.link != nil ? androidx.compose.ui.graphics.Color.Unspecified : color,
                fontSize: fontSize,
                fontWeight: Font.fontWeight(for: run.fontWeight == nil ? nil : Font.Weight(value: run.fontWeight!)),
                fontStyle: run.isItalic ? FontStyle.Italic : nil,
                fontFamily: run.isMonospaced ? FontFamily.Monospace : nil,
                background: isRedacted && run.link != nil ? palette.link : androidx.compose.ui.graphics.Color.Unspecified,
                baselineShift: baselineShift,
                textDecoration: decoration
            )
            builder.pushStyle(style)
            if let link = run.link {
                builder.pushUrlAnnotation(UrlAnnotation(link))
            }
            if let inlineContentID = run.inlineContentID {
                // The run's own text is the alternate, used when the id has no content.
                builder.appendInlineContent(inlineContentID, run.text)
            } else {
                var text = run.text
                if isUppercased {
                    text = text.uppercased()
                } else if isLowercased {
                    text = text.lowercased()
                }
                builder.append(text)
            }
            if run.link != nil {
                builder.pop()
            }
            builder.pop()
        }
        return builder.toAnnotatedString()
    }

    /// The Compose slots the annotated string's inline placeholders resolve against.
    static func inlineContent(runs: [RichTextRun], views: [any View], context: ComposeContext) -> kotlin.collections.Map<String, InlineTextContent> {
        let content = mutableMapOf<String, InlineTextContent>()
        for run in runs {
            guard let inlineContentID = run.inlineContentID,
                  let index = run.inlineViewIndex, index >= 0, index < views.count else {
                continue
            }
            let view = views[index]
            content[inlineContentID] = slot(for: view, width: run.inlineViewWidth ?? 1.0, height: run.inlineViewHeight ?? 1.0, context: context)
        }
        return content
    }

    /// The same slots for a `Text(bridgedHTML:)`, whose placeholders are positional:
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

    /// Rebuilds `parsed` with its first `count` U+FFFC placeholders — the marks
    /// `fromHtml` leaves where it dropped an `<img>` — turned into inline-content slots.
    ///
    /// `append(text:start:end:)` carries the spans of the range with it, so everything
    /// the parser resolved survives the rebuild.
    static func splicingInlineContent(_ parsed: AnnotatedString, count: Int) -> AnnotatedString {
        let builder = AnnotatedString.Builder()
        var last = 0
        var offset = 0
        var index = 0
        // Transpiled, this iterates UTF-16 code units, which is the unit Compose counts
        // its offsets in — so an emoji earlier in the text can't shift a placeholder.
        for character in parsed.text {
            if character == placeholderCharacter, index < count {
                builder.append(parsed, last, offset)
                builder.appendInlineContent(inlineContentID(index), placeholder)
                index += 1
                last = offset + 1
            }
            offset += 1
        }
        builder.append(parsed, last, parsed.length)
        return builder.toAnnotatedString()
    }

    static func inlineContentID(_ index: Int) -> String {
        return "skip.inline.\(index)"
    }

    /// U+FFFC, the object-replacement character.
    private static let placeholderCharacter: Character = "\u{FFFC}"
    private static let placeholder = "\u{FFFC}"
}
#endif
#endif
