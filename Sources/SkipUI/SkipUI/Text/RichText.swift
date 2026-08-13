// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.UrlAnnotation
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
            // `Center`, not `TextCenter`: the `Text*` alignments fit the placeholder
            // into the text's own vertical bounds, so anything taller than a line —
            // an avatar, say — spills over the line below instead of growing the line.
            let placeholder = Placeholder(
                width: (run.inlineViewWidth ?? 1.0).sp,
                height: (run.inlineViewHeight ?? 1.0).sp,
                placeholderVerticalAlign: PlaceholderVerticalAlign.Center
            )
            content[inlineContentID] = InlineTextContent(placeholder) { _ in
                view.Compose(context: context)
            }
        }
        return content
    }
}
#endif
#endif
