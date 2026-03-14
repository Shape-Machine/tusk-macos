import SwiftUI

enum TuskFontDesign: String, CaseIterable {
    case sansSerif  = "sans"
    case serif      = "serif"
    case monospaced = "mono"
    case rounded    = "rounded"

    var label: String {
        switch self {
        case .sansSerif:  return "Sans"
        case .serif:      return "Serif"
        case .monospaced: return "Mono"
        case .rounded:    return "Round"
        }
    }

    var design: Font.Design {
        switch self {
        case .sansSerif:  return .default
        case .serif:      return .serif
        case .monospaced: return .monospaced
        case .rounded:    return .rounded
        }
    }
}
