import SwiftUI

enum PopupChrome {
  static let cornerRadius: CGFloat = 12
  static let chromeInset: CGFloat = 10
  static let borderOpacity: Double = 0.16
  static let shadowOpacity: Double = 0.16
  static let shadowRadius: CGFloat = 18
  static let shadowYOffset: CGFloat = 6

  static var totalHorizontalInset: CGFloat {
    chromeInset * 2
  }

  static var totalVerticalInset: CGFloat {
    chromeInset * 2
  }
}
