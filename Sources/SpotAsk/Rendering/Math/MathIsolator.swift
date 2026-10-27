import Foundation

public struct ExtractedFormula: Sendable, Hashable {
    public let id: Int
    public let token: String
    public let tex: String
    public let display: Bool

    public init(id: Int, token: String, tex: String, display: Bool) {
        self.id = id
        self.token = token
        self.tex = tex
        self.display = display
    }
}

public struct IsolatedDocument: Sendable {
    public let sanitizedMarkdown: String
    public let formulas: [ExtractedFormula]

    public init(sanitizedMarkdown: String, formulas: [ExtractedFormula]) {
        self.sanitizedMarkdown = sanitizedMarkdown
        self.formulas = formulas
    }
}

public enum MathIsolator {
    public static func isolate(_ text: String) -> IsolatedDocument {
        guard !text.isEmpty else {
            return IsolatedDocument(sanitizedMarkdown: "", formulas: [])
        }

        var formulas: [ExtractedFormula] = []
        var output = ""
        output.reserveCapacity(text.count)

        var nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        while text.contains(nonce) {
            nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }

        func makeToken(_ id: Int) -> String {
            "⟦SPOTASK_MATH_\(nonce)_\(id)⟧"
        }

        var index = text.startIndex
        func isEscaped(at idx: String.Index) -> Bool {
            var count = 0
            var curr = idx
            while curr > text.startIndex {
                let prev = text.index(before: curr)
                if text[prev] == "\\" {
                    count += 1
                    curr = prev
                } else {
                    break
                }
            }
            return !count.isMultiple(of: 2)
        }

        while index < text.endIndex {
            // Check for fenced code block at line start
            let isLineStart = (index == text.startIndex || text[text.index(before: index)] == "\n")
            if isLineStart {
                var leadingSpaces = 0
                var lineIdx = index
                while lineIdx < text.endIndex && text[lineIdx] == " " && leadingSpaces < 4 {
                    leadingSpaces += 1
                    lineIdx = text.index(after: lineIdx)
                }
                if lineIdx < text.endIndex {
                    let marker = text[lineIdx]
                    if marker == "`" || marker == "~" {
                        var fenceCount = 0
                        var fIdx = lineIdx
                        while fIdx < text.endIndex && text[fIdx] == marker {
                            fenceCount += 1
                            fIdx = text.index(after: fIdx)
                        }
                        if fenceCount >= 3 {
                            // Read info string / language hint
                            var infoStart = fIdx
                            while infoStart < text.endIndex && (text[infoStart] == " " || text[infoStart] == "\t") {
                                infoStart = text.index(after: infoStart)
                            }
                            var infoEnd = infoStart
                            while infoEnd < text.endIndex && text[infoEnd] != "\n" {
                                infoEnd = text.index(after: infoEnd)
                            }
                            let infoString = String(text[infoStart..<infoEnd]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            let isMathFence = (infoString == "math" || infoString == "latex" || infoString == "tex")

                            // Find closing fence
                            var contentStart = infoEnd
                            if contentStart < text.endIndex && text[contentStart] == "\n" {
                                contentStart = text.index(after: contentStart)
                            }

                            var scan = contentStart
                            var foundClose = false
                            var closingFenceEnd = contentStart

                            while scan < text.endIndex {
                                if scan == text.startIndex || text[text.index(before: scan)] == "\n" {
                                    var cIdx = scan
                                    var cSpaces = 0
                                    while cIdx < text.endIndex && text[cIdx] == " " && cSpaces < 4 {
                                        cSpaces += 1
                                        cIdx = text.index(after: cIdx)
                                    }
                                    var cCount = 0
                                    while cIdx < text.endIndex && text[cIdx] == marker {
                                        cCount += 1
                                        cIdx = text.index(after: cIdx)
                                    }
                                    if cCount >= fenceCount {
                                        // This line is the closing fence
                                        let contentBeforeClose = scan
                                        while cIdx < text.endIndex && text[cIdx] != "\n" {
                                            cIdx = text.index(after: cIdx)
                                        }
                                        if cIdx < text.endIndex && text[cIdx] == "\n" {
                                            cIdx = text.index(after: cIdx)
                                        }
                                        closingFenceEnd = cIdx
                                        foundClose = true
                                        if isMathFence {
                                            let tex = String(text[contentStart..<contentBeforeClose]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            if !tex.isEmpty {
                                                let id = formulas.count
                                                let token = makeToken(id)
                                                formulas.append(ExtractedFormula(id: id, token: token, tex: tex, display: true))
                                                output.append("\n\n\(token)\n\n")
                                                index = closingFenceEnd
                                                break
                                            }
                                        }
                                        break
                                    }
                                }
                                scan = text.index(after: scan)
                            }

                            if foundClose {
                                if index != closingFenceEnd {
                                    // Either non-math fence or math fence with empty content: preserve verbatim
                                    output.append(contentsOf: text[index..<closingFenceEnd])
                                    index = closingFenceEnd
                                }
                                continue
                            } else {
                                // Unclosed code or math fence (e.g. streaming): protect remainder from math extraction
                                output.append(contentsOf: text[index..<text.endIndex])
                                index = text.endIndex
                                continue
                            }
                        }
                    }
                }
            }

            // Inline code span
            if text[index] == "`" && !isEscaped(at: index) {
                var tickCount = 0
                var tIdx = index
                while tIdx < text.endIndex && text[tIdx] == "`" {
                    tickCount += 1
                    tIdx = text.index(after: tIdx)
                }
                var search = tIdx
                var found = false
                while search < text.endIndex {
                    if text[search] == "`" {
                        var count = 0
                        var endSearch = search
                        while endSearch < text.endIndex && text[endSearch] == "`" {
                            count += 1
                            endSearch = text.index(after: endSearch)
                        }
                        if count == tickCount {
                            output.append(contentsOf: text[index..<endSearch])
                            index = endSearch
                            found = true
                            break
                        } else {
                            search = endSearch
                        }
                    } else {
                        search = text.index(after: search)
                    }
                }
                if found { continue }
            }

            // Math Delimiters:
            // 1. Block math: $$ ... $$
            if text[index] == "$" && !isEscaped(at: index) {
                let next = text.index(after: index)
                if next < text.endIndex && text[next] == "$" {
                    let contentStart = text.index(after: next)
                    var search = contentStart
                    var found = false
                    while search < text.endIndex {
                        if text[search] == "$" && !isEscaped(at: search) {
                            let sNext = text.index(after: search)
                            if sNext < text.endIndex && text[sNext] == "$" {
                                let tex = String(text[contentStart..<search]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !tex.isEmpty {
                                    let id = formulas.count
                                    let token = makeToken(id)
                                    formulas.append(ExtractedFormula(id: id, token: token, tex: tex, display: true))
                                    output.append("\n\n\(token)\n\n")
                                    index = text.index(after: sNext)
                                    found = true
                                    break
                                }
                            }
                        }
                        search = text.index(after: search)
                    }
                    if found { continue }
                }
            }

            // 2. Block math: \[ ... \]
            if text[index] == "\\" && !isEscaped(at: index) {
                let next = text.index(after: index)
                if next < text.endIndex && text[next] == "[" {
                    let contentStart = text.index(after: next)
                    var search = contentStart
                    var found = false
                    while search < text.endIndex {
                        if text[search] == "\\" && !isEscaped(at: search) {
                            let sNext = text.index(after: search)
                            if sNext < text.endIndex && text[sNext] == "]" {
                                let tex = String(text[contentStart..<search]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !tex.isEmpty {
                                    let id = formulas.count
                                    let token = makeToken(id)
                                    formulas.append(ExtractedFormula(id: id, token: token, tex: tex, display: true))
                                    output.append("\n\n\(token)\n\n")
                                    index = text.index(after: sNext)
                                    found = true
                                    break
                                }
                            }
                        }
                        search = text.index(after: search)
                    }
                    if found { continue }
                }
            }

            // 3. Inline math: \( ... \)
            if text[index] == "\\" && !isEscaped(at: index) {
                let next = text.index(after: index)
                if next < text.endIndex && text[next] == "(" {
                    let contentStart = text.index(after: next)
                    var search = contentStart
                    var found = false
                    while search < text.endIndex {
                        if text[search] == "\n" {
                            let afterNl = text.index(after: search)
                            if afterNl < text.endIndex && text[afterNl] == "\n" {
                                break // don't cross paragraph boundary
                            }
                        }
                        if text[search] == "\\" && !isEscaped(at: search) {
                            let sNext = text.index(after: search)
                            if sNext < text.endIndex && text[sNext] == ")" {
                                let tex = String(text[contentStart..<search]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !tex.isEmpty {
                                    let id = formulas.count
                                    let token = makeToken(id)
                                    formulas.append(ExtractedFormula(id: id, token: token, tex: tex, display: false))
                                    output.append(token)
                                    index = text.index(after: sNext)
                                    found = true
                                    break
                                }
                            }
                        }
                        search = text.index(after: search)
                    }
                    if found { continue }
                }
            }

            // 4. Inline math: $ ... $
            if text[index] == "$" && !isEscaped(at: index) {
                let next = text.index(after: index)
                if next < text.endIndex && text[next] != "$" && !text[next].isWhitespace {
                    var search = next
                    var found = false
                    while search < text.endIndex && text[search] != "\n" {
                        if text[search] == "$" && !isEscaped(at: search) {
                            let prev = text.index(before: search)
                            if !text[prev].isWhitespace {
                                let tex = String(text[next..<search])
                                if !tex.isEmpty {
                                    let id = formulas.count
                                    let token = makeToken(id)
                                    formulas.append(ExtractedFormula(id: id, token: token, tex: tex, display: false))
                                    output.append(token)
                                    index = text.index(after: search)
                                    found = true
                                    break
                                }
                            }
                        }
                        search = text.index(after: search)
                    }
                    if found { continue }
                }
            }

            output.append(text[index])
            index = text.index(after: index)
        }

        return IsolatedDocument(sanitizedMarkdown: output, formulas: formulas)
    }
}
