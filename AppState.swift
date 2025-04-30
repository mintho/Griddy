//
//  AppState.swift
//  Griddy
//
//  Created by Thomas Minzenmay on 17.04.25.
//

import Foundation
import SwiftUI

let GRID_CELL_SIZE: CGFloat = 8.0

struct ColorPalette {
    static let colors: [Color] = [
        .clear,                // 0: No Color (Transparent)
        Color(hex: "#E6194B"), // 1: Red
        Color(hex: "#3CB44B"), // 2: Green
        Color(hex: "#4363D8"), // 3: Blue
        Color(hex: "#FFE119"), // 4: Yellow
        Color(hex: "#911EB4"), // 5: Purple
        Color(hex: "#F58231"), // 6: Orange
        Color(hex: "#42D4F4"), // 7: Cyan
        Color(hex: "#F032E6"), // 8: Magenta
        Color(hex: "#FABEBE")  // 9: Pink
    ]

    static func displayColor(for index: Int) -> Color {
        guard index >= 0 && index < colors.count else { return .gray }
        
        if index == 0 { return Color.white }
        
        return colors[index]
    }

    static func gridColor(for index: Int) -> Color {
        guard index > 0 && index < colors.count else { return .clear }
        
        return colors[index].opacity(0.6)
    }

    static func name(for index: Int) -> String {
        switch index {
        case 0:
            return "No Color"
        case 1:
            return "Red"
        case 2:
            return "Green"
        case 3:
            return "Blue"
        case 4:
            return "Yellow"
        case 5:
            return "Purple"
        case 6:
            return "Orange"
        case 7:
            return "Cyan"
        case 8:
            return "Magenta"
        case 9:
            return "Pink"
        default:
            return "Unknown"
        }
    }
}

class AppState: ObservableObject {
    // Menu Action Triggers
    @Published var showOpenPNG = false
    @Published var showOpenProject = false
    @Published var showExportCSVPanel = false
    @Published var showExportCHPanel = false
    @Published var showImportCPanel = false
    @Published var openFiles: [FileState] = []
    
    @Published var saveProjectTrigger: UUID? = nil
    @Published var saveProjectAsTrigger: UUID? = nil
    @Published var importCSVTrigger: UUID? = nil
    @Published var closeTabTrigger: UUID? = nil
    
    @Published var droppedFileURL: URL? = nil
    
    // Alert Properties
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""

    func presentAlert(title: String, message: String) {
        DispatchQueue.main.async {
            self.alertTitle = title
            
            self.alertMessage = message
            
            self.showAlert = true
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        
        var int: UInt64 = 0
        
        Scanner(string: hex).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        
        switch hex.count {
        case 3: // RGB (12-bit) e.g., #FFF
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit) e.g., #FF0000
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit) e.g., #FF0000FF
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: // Default to black if format is unrecognized
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
