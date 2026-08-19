import AppKit
import SwiftUI
import UniformTypeIdentifiers
// MARK: - Header material

/// The header's elevated chrome background. Uses a system Material on macOS 15
/// (`.regular` over the window, AppKit vibrancy under the hood) and the native
/// Liquid Glass chrome on macOS 26 — never a hand-drawn blur, backdrop filter,
/// or hard-coded translucent fill. The material supplies its own legibility,
/// so the header's text and icons render directly on it.
struct HeaderMaterial: View { var body: some View {
    if #available(macOS 26, *) {
        Color.clear
            .glassEffect(.regular, in: .rect)
    } else {
        Rectangle()
            .fill(.regularMaterial)
    }
} }

// MARK: - Brand tokens

/// The six SpotAsk brand tokens from the redesign contract. Hover and glow
/// variants are derived with `darker` / `opacity` (the oklch-relative
/// adjustments of the prototype), never with a new hard-coded color.
enum Brand {
    static let bg = dynamic(light: 0xFFFFFF, dark: 0x17191D)
    static let surface = dynamic(light: 0xF7F8FA, dark: 0x22252B)
    static let fg = dynamic(light: 0x111111, dark: 0xF4F5F7)
    static let muted = dynamic(light: 0x6B7280, dark: 0xA9B1BD)
    static let border = dynamic(light: 0xD9DEE7, dark: 0x3C424C)
    static let accent = Color(red: 0x16 / 255, green: 0x77 / 255, blue: 0xFF / 255)

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension Color { /// Darkens toward black in sRGB, standing in for the prototype's
/// `oklch(from c calc(l - amount) c h)` hover adjustment.
func darker(_ amount: Double) -> Color {
    let clamped = min(max(amount, 0), 1)
    let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
    func scaled(_ component: CGFloat) -> Double {
        Double(component) * (1 - clamped)
    }
    return Color(red: scaled(ns.redComponent),
                 green: scaled(ns.greenComponent),
                 blue: scaled(ns.blueComponent),
                 opacity: Double(ns.alphaComponent))
} }

// MARK: - Preset placeholder copy

/// The prototype switches the placeholder per preset. The preset prompt text
/// is localized, so per-preset guidance is derived here (the resource tables
/// are read-only for this change). Built-in presets are matched by their
/// stable identity or localized title; anything else falls back to a generic
/// task-oriented prompt.
enum PresetPlaceholder { private static let translateID = UUID(uuidString: "EF8CF35C-386A-4389-A137-C207E4DB11FD")!
private static let polishID = UUID(uuidString: "1C85A324-65B3-4EBD-B2C4-0C6B072E284A")!
private static let summarizeID = UUID(uuidString: "5D03D444-EC3D-4F5D-9FB1-91EA5BD4E5B2")!
private static let explainID = UUID(uuidString: "BF43F694-E4AE-4B5B-9AE9-B4D6D4A4F248")!

private static var isChinese: Bool {
    L10n.string("chat.inputPlaceholder").contains("输入")
}

static func text(for id: UUID, title: String) -> String {
    if id == translateID || title == L10n.string("preset.translate.title") {
        return isChinese ? "输入要翻译的内容…" : "Enter text to translate..."
    }
    if id == polishID || title == L10n.string("preset.polish.title") {
        return isChinese ? "输入要润色的文字…" : "Enter text to polish..."
    }
    if id == summarizeID || title == L10n.string("preset.summarize.title") {
        return isChinese ? "粘贴要总结的内容…" : "Paste content to summarize..."
    }
    if id == explainID || title == L10n.string("preset.explain.title") {
        return isChinese ? "输入要解释的内容…" : "Enter content to explain..."
    }
    return L10n.string("chat.usePrompt", title)
} }

// MARK: - Brand mark

/// Returns the app icon only when the executable app bundle provides it.
/// SwiftPM tests run from a different main bundle, so callers retain a local
/// SF Symbol fallback instead of depending on `Bundle.module`.
func spotAskAppIconImage(bundle: Bundle = .main) -> NSImage? {
    guard let url = bundle.url(forResource: "AppIcon", withExtension: "icns") else {
        return nil
    }
    return NSImage(contentsOf: url)
}

/// The compact app icon shown alongside the title wordmark.
struct BrandMark: View { var body: some View {
    Group {
        if let appIcon = spotAskAppIconImage() {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                // App icon resources are opaque; match the icon's native
                // silhouette so its square corners do not show in the titlebar.
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Brand.accent)
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
    }
    .accessibilityHidden(true)
} }

/// The app icon gives the first empty conversation screen the same identity
/// as the app bundle while retaining the prior lightweight fallback.
struct EmptyStateBrandMark: View { var body: some View {
    Group {
        if let appIcon = spotAskAppIconImage() {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Brand.muted)
        }
    }
    .accessibilityLabel(Text("SpotAsk"))
} }

// MARK: - Header icon button

/// The prototype's `.icon-btn`: a 28×28 hit target whose hover fills a
/// `surface` rounded square and darkens the glyph to `fg` (never grays it),
/// with a 2pt accent ring standing in for `:focus-visible`. Wraps the button's
/// label only; its behavior and accessibility stay on the caller.
struct HeaderIconButton<Label: View>: View { let action: () -> Void
@ViewBuilder let label: () -> Label

@State private var isHovering = false
@FocusState private var isFocused: Bool

var body: some View {
    Button(action: action) {
        label()
            .font(.system(size: 16))
            .foregroundStyle(isHovering ? Brand.fg : Brand.muted)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(isHovering ? Brand.surface : Color.clear)
            )
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.accent, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focused($isFocused)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovering)
} }

struct ShortcutKeycap: View {
    let shortcut: InAppShortcut?

    var body: some View {
        if let shortcut {
            HStack(spacing: 2) {
                ForEach(InAppShortcutDisplay.labels(for: shortcut, includeCommand: false), id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Brand.border, lineWidth: 0.5)
                        }
                }
            }
            .fixedSize()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}
