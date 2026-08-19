import Foundation
import Testing
@testable import SpotAsk

@Suite("Quick Action Builder and Validator")
struct QuickActionBuilderTests {

    // MARK: - QuickActionBuilder.makeURL Tests

    @Test("Encodes exact string with ASCII, Chinese, emoji, spaces, and reserved URL characters")
    func testMakeURLExactStringAssertion() {
        let template = "https://example.com/search?q={query}&lang=en"
        let input = "hello 世界 🚀 & = ? + / # [ ] @"
        let expected = "https://example.com/search?q=hello%20%E4%B8%96%E7%95%8C%20%F0%9F%9A%80%20%26%20%3D%20%3F%20%2B%20%2F%20%23%20%5B%20%5D%20%40&lang=en"

        let url = QuickActionBuilder.makeURL(template: template, query: input)
        #expect(url?.absoluteString == expected)
    }

    @Test("Correctly formats ChatGPT built-in template")
    func testChatGPTTemplate() {
        let template = "https://chatgpt.com/?q={query}"
        let input = "swift concurrency tutorial"
        let expected = "https://chatgpt.com/?q=swift%20concurrency%20tutorial"

        let url = QuickActionBuilder.makeURL(template: template, query: input)
        #expect(url?.absoluteString == expected)
    }

    @Test("Correctly formats Grok built-in template")
    func testGrokTemplate() {
        let template = "https://grok.com/?q={query}"
        let input = "explain quantum computing"
        let expected = "https://grok.com/?q=explain%20quantum%20computing"

        let url = QuickActionBuilder.makeURL(template: template, query: input)
        #expect(url?.absoluteString == expected)
    }

    @Test("Supports custom URI schemes (e.g. raycast, obsidian, raycast://)")
    func testCustomURIScheme() {
        let template = "raycast://extensions/author/command?query={query}"
        let input = "find file"
        let expected = "raycast://extensions/author/command?query=find%20file"

        let url = QuickActionBuilder.makeURL(template: template, query: input)
        #expect(url?.absoluteString == expected)
    }

    @Test("Replaces multiple occurrences of {query} in template")
    func testMultipleQueryPlaceholders() {
        let template = "https://search.com/?q={query}&alias={query}"
        let input = "test"
        let expected = "https://search.com/?q=test&alias=test"

        let url = QuickActionBuilder.makeURL(template: template, query: input)
        #expect(url?.absoluteString == expected)
    }

    @Test("Preserves existing URL query parameters and fragments")
    func testPreservesExistingQueryParamsAndFragment() {
        let template = "https://example.com/search?sort=desc&q={query}&page=1#results"
        let input = "apple"
        let expected = "https://example.com/search?sort=desc&q=apple&page=1#results"

        let url = QuickActionBuilder.makeURL(template: template, query: input)
        #expect(url?.absoluteString == expected)
    }

    @Test("Returns nil when raw query is empty or whitespace-only")
    func testMakeURLEmptyQuery() {
        let template = "https://chatgpt.com/?q={query}"
        #expect(QuickActionBuilder.makeURL(template: template, query: "") == nil)
        #expect(QuickActionBuilder.makeURL(template: template, query: "   ") == nil)
        #expect(QuickActionBuilder.makeURL(template: template, query: "\n\t  \r\n") == nil)
    }

    @Test("Returns nil when template lacks {query} placeholder")
    func testMakeURLMissingPlaceholder() {
        let template = "https://chatgpt.com/?q=static"
        #expect(QuickActionBuilder.makeURL(template: template, query: "hello") == nil)
    }

    @Test("Returns nil when template has no scheme")
    func testMakeURLNoScheme() {
        let template = "chatgpt.com/?q={query}"
        #expect(QuickActionBuilder.makeURL(template: template, query: "hello") == nil)
    }

    @Test("Returns nil when final URL string is malformed")
    func testMakeURLMalformed() {
        let template = "https://:invalid-host/?q={query}"
        #expect(QuickActionBuilder.makeURL(template: template, query: "hello") == nil)
    }

    @Test("Handles very long text without truncation or crash (e.g. 8000 characters)")
    func testMakeURLLongQuery() {
        let longQuery = String(repeating: "a", count: 8000)
        let template = "https://chatgpt.com/?q={query}"

        let url = QuickActionBuilder.makeURL(template: template, query: longQuery)
        #expect(url != nil)
        #expect(url?.scheme == "https")
        #expect(url?.host == "chatgpt.com")
    }

    // MARK: - Shell Escaping & Terminal Command Builder Tests

    @Test("Shell escaping handles spaces, quotes, and special characters")
    func testShellEscape() {
        #expect(QuickActionBuilder.shellEscape("simple") == "'simple'")
        #expect(QuickActionBuilder.shellEscape("hello world") == "'hello world'")
        #expect(QuickActionBuilder.shellEscape("don't stop") == "'don'\\''t stop'")
        #expect(QuickActionBuilder.shellEscape("what's up 'mate'") == "'what'\\''s up '\\''mate'\\'''")
        #expect(QuickActionBuilder.shellEscape("你好 世界 $VAR `cmd`") == "'你好 世界 $VAR `cmd`'")
    }

    @Test("makeTerminalCommand formats command template correctly")
    func testMakeTerminalCommand() {
        let template = "omp {query}"
        let input = "hello world"
        let cmd = QuickActionBuilder.makeTerminalCommand(template: template, query: input)
        #expect(cmd == "omp 'hello world'")

        let quotesInput = "don't fail"
        let cmdQuotes = QuickActionBuilder.makeTerminalCommand(template: template, query: quotesInput)
        #expect(cmdQuotes == "omp 'don'\\''t fail'")

        let chineseInput = "写一个快速排序"
        let cmdChinese = QuickActionBuilder.makeTerminalCommand(template: "llm ask {query}", query: chineseInput)
        #expect(cmdChinese == "llm ask '写一个快速排序'")
    }

    @Test("makeTerminalCommand returns nil for empty query or missing placeholder")
    func testMakeTerminalCommandEdgeCases() {
        #expect(QuickActionBuilder.makeTerminalCommand(template: "omp {query}", query: "") == nil)
        #expect(QuickActionBuilder.makeTerminalCommand(template: "omp {query}", query: "   \n\t") == nil)
        #expect(QuickActionBuilder.makeTerminalCommand(template: "omp static", query: "hello") == nil)
    }

    // MARK: - QuickActionTemplateValidation Tests

    @Test("Validates empty or whitespace-only template as .empty")
    func testValidateTemplateEmpty() {
        #expect(QuickActionBuilder.validateURLTemplate("") == .empty)
        #expect(QuickActionBuilder.validateURLTemplate("   \n\t ") == .empty)
        #expect(QuickActionBuilder.validate(kind: .web(urlTemplate: "")) == .empty)
        #expect(QuickActionBuilder.validate(kind: .terminal(commandTemplate: "")) == .empty)
    }

    @Test("Validates template without {query} as .missingQueryPlaceholder")
    func testValidateTemplateMissingPlaceholder() {
        #expect(QuickActionBuilder.validateURLTemplate("https://chatgpt.com") == .missingQueryPlaceholder)
        #expect(QuickActionBuilder.validateURLTemplate("https://chatgpt.com/?q=query") == .missingQueryPlaceholder)
        #expect(QuickActionBuilder.validate(kind: .web(urlTemplate: "https://chatgpt.com")) == .missingQueryPlaceholder)
        #expect(QuickActionBuilder.validate(kind: .terminal(commandTemplate: "omp test")) == .missingQueryPlaceholder)
    }

    @Test("Validates template with invalid URL structure as .invalidURL")
    func testValidateTemplateInvalidURL() {
        #expect(QuickActionBuilder.validateURLTemplate("not-a-valid-url-{query}") == .invalidURL)
        #expect(QuickActionBuilder.validateURLTemplate("://missing-scheme?q={query}") == .invalidURL)
        #expect(QuickActionBuilder.validate(kind: .web(urlTemplate: "not-a-valid-url-{query}")) == .invalidURL)
    }

    @Test("Validates web and URI scheme templates as .valid")
    func testValidateTemplateValid() {
        #expect(QuickActionBuilder.validateURLTemplate("https://chatgpt.com/?q={query}") == .valid)
        #expect(QuickActionBuilder.validateURLTemplate("http://localhost:8080/ask?q={query}") == .valid)
        #expect(QuickActionBuilder.validateURISchemeTemplate("raycast://extensions?q={query}") == .valid)
        #expect(QuickActionBuilder.validate(kind: .terminal(commandTemplate: "omp {query}")) == .valid)
    }

    // MARK: - isHTTPScheme Tests

    @Test("isHTTPScheme correctly identifies HTTPS URLs")
    func testIsHTTPScheme() {
        #expect(QuickActionBuilder.isHTTPScheme("https://chatgpt.com/?q={query}") == true)
        #expect(QuickActionBuilder.isHTTPScheme("HTTPS://CHATGPT.COM/?q={query}") == true)
        #expect(QuickActionBuilder.isHTTPScheme("http://example.com/?q={query}") == false)
        #expect(QuickActionBuilder.isHTTPScheme("raycast://extensions?q={query}") == false)
        #expect(QuickActionBuilder.isHTTPScheme("invalid-url") == false)
        #expect(QuickActionBuilder.isHTTPScheme("") == false)
    }
}
