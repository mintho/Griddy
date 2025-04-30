//
//  Grid_Image_EditorApp.swift
//  Griddy
//
//  Created by Thomas Minzenmay on 16.04.25.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct Grid_Image_EditorApp: App {
    // Connect AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Provide AppState to the environment
                .environmentObject(appDelegate.appState)
        }
        .commands {
            MenuCommands(
                openPNGAction: { appDelegate.appState.showOpenPNG = true },
                openProjectAction: { appDelegate.appState.showOpenProject = true },
                saveProjectAction: { appDelegate.appState.saveProjectTrigger = UUID() },
                saveProjectAsAction: { appDelegate.appState.saveProjectAsTrigger = UUID() },
                importCSVAction: { appDelegate.appState.importCSVTrigger = UUID() },
                exportCSVAction: { appDelegate.appState.showExportCSVPanel = true },
                importCAction: { appDelegate.appState.showImportCPanel = true },
                exportCHAction: { appDelegate.appState.showExportCHPanel = true },
                closeTabAction: { appDelegate.appState.closeTabTrigger = UUID() }
            )
        }
    }
}
