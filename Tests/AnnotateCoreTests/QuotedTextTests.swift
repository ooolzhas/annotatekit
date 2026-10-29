// Annotation.quotedText: the element text the comment card quotes like a message being replied to.

import Foundation
import Testing
@testable import AnnotateCore

@Suite struct QuotedTextTests {
    private static func element(label: String?, value: String? = nil) -> Annotation {
        Annotation(
            index: 1, kind: .element,
            frame: AnnotationRect(x: 0, y: 0, width: 100, height: 40),
            element: ElementInfo(role: "text", label: label, value: value)
        )
    }

    @Test func elementLabelIsQuotedTrimmed() {
        #expect(Self.element(label: "  Get started \n").quotedText == "Get started")
        #expect(Fixtures.element.quotedText == "Get started")
    }

    @Test func valueStandsInForABlankLabel() {
        #expect(Self.element(label: " ", value: "42%").quotedText == "42%")
        #expect(Self.element(label: nil, value: "On").quotedText == "On")
    }

    @Test func noTextNoQuote() {
        #expect(Self.element(label: nil).quotedText == nil)
        #expect(Self.element(label: "\t", value: "").quotedText == nil)
    }

    @Test("only element pins quote", arguments: [Fixtures.spot, Fixtures.region])
    func otherKindsNeverQuote(annotation: Annotation) {
        #expect(annotation.quotedText == nil)
    }
}
