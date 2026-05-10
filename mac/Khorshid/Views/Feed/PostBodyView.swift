import SwiftSoup
import SwiftUI

struct PostBodyView: View {

    let html: String
    let plainText: String

    private var attributed: AttributedString? {
        try? AttributedHTMLBuilder.build(html: html)
    }

    var body: some View {
        Group {
            if let attributed {
                Text(attributed)
                    .environment(\.layoutDirection, .rightToLeft)
            } else {
                Text(plainText)
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }
}

private enum AttributedHTMLBuilder {

    static func build(html: String) throws -> AttributedString {
        let doc = try SwiftSoup.parseBodyFragment(html)
        var result = AttributedString()
        try appendChildren(of: doc.body()!, into: &result, bold: false, italic: false, link: nil)
        return result
    }

    private static func appendChildren(
        of element: Element,
        into result: inout AttributedString,
        bold: Bool,
        italic: Bool,
        link: URL?
    ) throws {
        for node in element.getChildNodes() {
            switch node {
            case let textNode as TextNode:
                let raw = textNode.text()
                guard !raw.isEmpty else { continue }
                var chunk = AttributedString(raw)
                apply(bold: bold, italic: italic, link: link, to: &chunk)
                result.append(chunk)

            case let el as Element:
                let tag = el.tagName().lowercased()
                switch tag {
                case "b", "strong":
                    try appendChildren(of: el, into: &result, bold: true, italic: italic, link: link)
                case "i", "em":
                    try appendChildren(of: el, into: &result, bold: bold, italic: true, link: link)
                case "a":
                    let href = (try? el.attr("href")).flatMap { URL(string: $0) }
                    try appendChildren(of: el, into: &result, bold: bold, italic: italic, link: href ?? link)
                case "br":
                    var newline = AttributedString("\n")
                    apply(bold: false, italic: false, link: nil, to: &newline)
                    result.append(newline)
                case "p", "div":
                    try appendChildren(of: el, into: &result, bold: bold, italic: italic, link: link)
                    var newline = AttributedString("\n")
                    apply(bold: false, italic: false, link: nil, to: &newline)
                    result.append(newline)
                case "code", "pre":
                    var chunk = AttributedString(try el.text())
                    chunk.inlinePresentationIntent = .code
                    apply(bold: bold, italic: italic, link: link, to: &chunk)
                    result.append(chunk)
                case "s", "del", "strike":
                    var chunk = AttributedString(try el.text())
                    chunk.strikethroughStyle = Text.LineStyle(pattern: .solid)
                    apply(bold: bold, italic: italic, link: link, to: &chunk)
                    result.append(chunk)
                case "u":
                    var chunk = AttributedString(try el.text())
                    chunk.underlineStyle = Text.LineStyle(pattern: .solid)
                    apply(bold: bold, italic: italic, link: link, to: &chunk)
                    result.append(chunk)
                case "span":
                    try appendChildren(of: el, into: &result, bold: bold, italic: italic, link: link)
                default:
                    try appendChildren(of: el, into: &result, bold: bold, italic: italic, link: link)
                }
            default:
                break
            }
        }
    }

    private static func apply(
        bold: Bool,
        italic: Bool,
        link: URL?,
        to chunk: inout AttributedString
    ) {
        var traits: InlinePresentationIntent = []
        if bold { traits.insert(.stronglyEmphasized) }
        if italic { traits.insert(.emphasized) }
        if !traits.isEmpty {
            chunk.inlinePresentationIntent = traits
        }
        if let link {
            chunk.link = link
        }
    }
}
