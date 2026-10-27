import SwiftUI

/// Properties that control how Textual renders math expressions.
public struct MathProperties: Sendable, Hashable {
  public struct FontName: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
      self.rawValue = value
    }
  }

  /// The math font family to use.
  public var fontName: FontName

  /// Scales the math font relative to the surrounding text.
  public var fontScale: CGFloat

  /// The alignment applied to block math paragraphs.
  public var textAlignment: TextAlignment

  public init(
    fontName: FontName = .latinModern,
    fontScale: CGFloat = 1.2,
    textAlignment: TextAlignment = .center
  ) {
    self.fontName = fontName
    self.fontScale = fontScale
    self.textAlignment = textAlignment
  }
}

extension MathProperties.FontName {
  public static let latinModern: Self = "latinmodern-math"
  public static let kpMathLight: Self = "kpmath-light"
  public static let kpMathSans: Self = "kpmath-sans"
  public static let xits: Self = "xits-math"
  public static let termes: Self = "texgyretermes-math"
  public static let asana: Self = "asana-math"
  public static let euler: Self = "euler-math"
  public static let fira: Self = "firamath-regular"
  public static let notoSans: Self = "notosansmath-regular"
  public static let libertinus: Self = "libertinusmath-regular"
  public static let garamond: Self = "garamond-math"
  public static let leteSans: Self = "letesansmath"
}

extension EnvironmentValues {
  @Entry var mathProperties = MathProperties()
}
