// Copyright 2026 Skip
// SPDX-License-Identifier: MPL-2.0
import XCTest
import SwiftUI

#if SKIP
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign

final class RichTextTests: XCTestCase {
    func testSplicedPlaceholdersKeepTheirParagraphStyle() {
        // Arrange
        let parsed = RichText.annotatedString(
            html: "<div style=\"text-align:center\">a<img src=\"x\"><img src=\"x\">b</div>",
            linkColor: Color.Blue,
            onLinkTap: { _ in }
        )

        // Act
        let spliced = RichText.splicingInlineContent(parsed, count: 2)

        // Assert
        let mark: Character = "\u{FFFC}"
        var placeholders: [Int] = []
        var offset = 0
        for character in spliced.text {
            if character == mark {
                placeholders.append(offset)
            }
            offset += 1
        }
        XCTAssertEqual(placeholders.count, 2)
        var spanningAlignment: TextAlign? = nil
        for range in spliced.paragraphStyles {
            if range.start <= placeholders[0] && placeholders[1] < range.end {
                spanningAlignment = range.item.textAlign
            }
        }
        XCTAssertEqual(spanningAlignment, TextAlign.Center)
    }
}
#endif
