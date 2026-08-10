import Foundation

extension Formatter {
  /// Serializes the selected attributed content back to Markdown so a
  /// selection crossing multiple rendered blocks keeps list, heading, quote,
  /// code, and table markers instead of flattening them to plain text.
  func markdown() -> String {
    blockNodes.renderMarkdown()
  }
}

// MARK: - Inline rendering

extension Formatter.InlineNode {
  fileprivate func renderMarkdown() -> String {
    switch self {
    case .text(let text):
      return text
    case .code(let code):
      return Self.inlineCode(code)
    case .strong(let children):
      return "**\(children.renderMarkdown())**"
    case .emphasized(let children):
      return "*\(children.renderMarkdown())*"
    case .strikethrough(let children):
      return "~~\(children.renderMarkdown())~~"
    case .link(let url, let children):
      return "[\(children.renderMarkdown())](\(url.absoluteString))"
    case .lineBreak:
      return "\n"
    case .attachment(let attachment):
      return attachment.description
    }
  }

  private static func inlineCode(_ code: String) -> String {
    let delimiter = code.contains("`") ? "``" : "`"
    return "\(delimiter)\(code)\(delimiter)"
  }
}

extension Array where Element == Formatter.InlineNode {
  fileprivate func renderMarkdown() -> String {
    map { $0.renderMarkdown() }.joined()
  }
}

// MARK: - Block rendering

extension Formatter.BlockNode {
  fileprivate func renderMarkdown() -> String {
    switch self {
    case .paragraph(let children):
      return children.renderMarkdown()
    case .header(let level, let children):
      let prefix = String(repeating: "#", count: max(1, min(6, level)))
      return "\(prefix) \(children.renderMarkdown())"
    case .orderedList(let children):
      return children.renderMarkdown { item in "\(item.ordinal). " }
    case .unorderedList(let children):
      return children.renderMarkdown { _ in "- " }
    case .codeBlock(let languageHint, let code):
      return Self.codeBlock(code, languageHint: languageHint)
    case .blockQuote(let children):
      return children.renderMarkdown()
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { "> \($0)" }
        .joined(separator: "\n")
    case .table(let columns, let children):
      return children.renderMarkdown(columns: columns)
    case .thematicBreak:
      return "---"
    }
  }

  private static func codeBlock(_ code: String, languageHint: String?) -> String {
    let language = (languageHint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let fence = code.contains("```") ? "~~~~" : "```"
    let languageSuffix = language.isEmpty ? "" : language
    let normalizedCode = code.hasSuffix("\n") ? String(code.dropLast()) : code
    return "\(fence)\(languageSuffix)\n\(normalizedCode)\n\(fence)"
  }
}

extension Array where Element == Formatter.BlockNode {
  fileprivate func renderMarkdown() -> String {
    map { $0.renderMarkdown() }.joined(separator: "\n\n")
  }
}

// MARK: - Lists

extension Array where Element == Formatter.ListItem {
  fileprivate func renderMarkdown(prefix: (Formatter.ListItem) -> String) -> String {
    map { item in
      let lines = item.blocks.renderMarkdown().split(
        separator: "\n",
        omittingEmptySubsequences: false
      )
      guard let first = lines.first else { return prefix(item).trimmingCharacters(in: .whitespaces) }
      var result = prefix(item) + first
      for line in lines.dropFirst() {
        result += "\n  \(line)"
      }
      return result
    }
    .joined(separator: "\n")
  }
}

// MARK: - Tables

extension Array where Element == Formatter.TableRow {
  fileprivate func renderMarkdown(columns: [PresentationIntent.TableColumn]) -> String {
    guard let header = first else { return "" }

    let headerRow = "| \(header.cells.map { $0.renderMarkdown() }.joined(separator: " | ")) |"
    let separatorRow = "| \(columns.map(Self.alignmentMark).joined(separator: " | ")) |"
    let bodyRows = dropFirst().map { row in
      "| \(row.cells.map { $0.renderMarkdown() }.joined(separator: " | ")) |"
    }
    return ([headerRow, separatorRow] + bodyRows).joined(separator: "\n")
  }

  private static func alignmentMark(for column: PresentationIntent.TableColumn) -> String {
    switch column.alignment {
    case .left:
      return ":---"
    case .center:
      return ":---:"
    case .right:
      return "---:"
    @unknown default:
      return "---"
    }
  }
}
