import AppKit
import SwiftUI

/// Maps provider/model text to the LobeHub icon slug used by the bundle.
/// Matching is intentionally coarse: a miss returns nil so callers keep their
/// existing generic icon instead of showing a misleading brand.
enum ProviderBrandIconMatcher {
    static func match(
        providerName: String? = nil,
        address: String? = nil,
        modelName: String? = nil,
        upstreamModelID: String? = nil
    ) -> String? {
        let providerText = [providerName, address].compactMap { $0 }.joined(separator: " ")
        if let slug = match(providerText) {
            return slug
        }
        let modelText = [modelName, upstreamModelID].compactMap { $0 }.joined(separator: " ")
        return match(modelText)
    }

    static func match(_ rawText: String) -> String? {
        let text = Self.normalized(rawText)
        guard !text.isEmpty else { return nil }
        for rule in rules where rule.patterns.contains(where: { text.contains($0) }) {
            return rule.slug
        }
        return nil
    }

    private static func normalized(_ rawText: String) -> String {
        rawText.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let rules: [(patterns: [String], slug: String)] = [
        (["azure"], "azure-color"),
        (["openrouter"], "openrouter-color"),
        (["anthropic", "claude"], "claude-color"),
        (["gemini", "google", "bard", "vertex", "gemma"], "gemini-color"),
        (["deepseek", "深度求索"], "deepseek-color"),
        (["kimi", "moonshot", "月之暗面"], "kimi-color"),
        (["qwen", "tongyi", "通义"], "qwen-color"),
        (["zai", "z.ai"], "zai"),
        (["zhipu", "chatglm", "glm", "bigmodel", "智谱"], "zhipu-color"),
        (["siliconflow", "siliconcloud", "silicon", "硅基流动"], "siliconcloud-color"),
        (["ollama"], "ollama"),
        (["perplexity", "sonar"], "perplexity-color"),
        (["grok", "xai"], "grok"),
        (["mistral", "lechat", "codestral", "ministral"], "mistral-color"),
        (["llama", "meta"], "meta-color"),
        (["ernie", "baidu", "wenxin", "文心", "百度"], "baidu-color"),
        (["hunyuan", "tencent", "混元", "腾讯"], "tencent-color"),
        (["doubao", "volcengine", "volc", "ark", "豆包"], "doubao-color"),
        (["spark", "iflytek", "xinghuo", "星火", "讯飞"], "spark-color"),
        (["minimax", "abab"], "minimax-color"),
        (["groq"], "groq"),
        (["cohere", "command"], "cohere-color"),
        (["bedrock", "aws"], "aws"),
        (["huggingface", "hugging face"], "huggingface-color"),
        (["deepinfra"], "deepinfra-color"),
        (["openai", "chatgpt", "gpt", "davinci", "codex", "o1", "o3", "o4"], "openai")
    ]
}

/// Loads the bundled LobeHub light/dark PNG variant for a matched slug.
enum ProviderBrandIcon {
    static func image(for slug: String, dark: Bool) -> NSImage? {
        let resourceName = slug + (dark ? "-dark" : "-light")
        guard let url = iconURL(resourceName: resourceName) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func iconURL(resourceName: String) -> URL? {
        var candidates: [URL] = []
#if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: resourceName, withExtension: "png") {
            candidates.append(url)
        }
        if let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: "ProviderIcons"
        ) {
            candidates.append(url)
        }
#endif
        if let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: "ProviderIcons"
        ) {
            candidates.append(url)
        }
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png") {
            candidates.append(url)
        }
        return candidates.first
    }
}

/// Renders a matched provider logo, falling back to a symbol when unknown.
struct ProviderBrandIconView: View {
    let slug: String?
    var size: CGFloat = 18
    var fallbackSymbol = "brain.head.profile"
    var fallbackColor: Color = .secondary

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let slug,
               let image = ProviderBrandIcon.image(for: slug, dark: colorScheme == .dark) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: max(9, size * 0.55), weight: .semibold))
                    .foregroundStyle(fallbackColor)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}
