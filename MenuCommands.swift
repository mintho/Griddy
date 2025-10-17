//
//  MenuCommands.swift
//  Griddy
//
//  Created by Thomas Minzenmay on 21.04.25.
//

import SwiftUI

struct MenuCommands: Commands {
    let openPNGAction: () -> Void
    let openProjectAction: () -> Void
    let saveProjectAction: () -> Void
    let saveProjectAsAction: () -> Void
    let importCSVAction: () -> Void
    let exportCSVAction: () -> Void
    let importCAction: () -> Void
    let exportCHAction: () -> Void
    let exportTMXAction: () -> Void
    let closeTabAction: () -> Void
    
    @Environment(\.undoManager) var undoManager
    
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open PNG...") { openPNGAction() }
                .keyboardShortcut("o", modifiers: [.command])
            
            Button("Open Project...") { openProjectAction() }
                .keyboardShortcut("O", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Save Project") { saveProjectAction() }
                .keyboardShortcut("s", modifiers: [.command])
            
            Button("Save Project As...") { saveProjectAsAction() }
                .keyboardShortcut("S", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Import C Source...") { importCAction() }
                .keyboardShortcut("i", modifiers: [.command])
            
            Button("Export C/H Source...") { exportCHAction() }
                .keyboardShortcut("e", modifiers: [.command])
            
            Divider()
            
            Button("Import CSV...") { importCSVAction() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            
            Button("Export CSV...") { exportCSVAction() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            
            Divider()

            Button("Export TMX/TSX/PNG…") { exportTMXAction() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Close Tab") { closeTabAction() }
                .keyboardShortcut("w", modifiers: [.command])
        }
        
        CommandGroup(replacing: .pasteboard) {}
        
        CommandGroup(replacing: .textEditing) {}
        
        CommandGroup(replacing: .appInfo) {}
        
        CommandGroup(replacing: .windowList) {}
        
        CommandGroup(replacing: .help) {}
        
        CommandGroup(replacing: .systemServices) {}
    }
}
