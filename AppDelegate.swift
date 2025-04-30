//
//  AppDelegate.swift
//  Griddy
//
//  Created by Thomas Minzenmay on 17.04.25.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var appState = AppState()
    private var windowDelegateMap = NSMapTable<NSWindow, AppDelegate>.weakToStrongObjects()
    private var delegateSetAttemptTimer: Timer?

    override init() {
        super.init()
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationDidFinishLaunching. Initial window count: \(NSApplication.shared.windows.count)")
        
        // Attempt to set the delegate shortly after launch, and retry briefly
        var attempts = 0
        delegateSetAttemptTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            attempts += 1
            print("[AppDelegate] Delegate setting attempt \(attempts)")

            var delegateSet = false
            for window in NSApplication.shared.windows {
                if self.windowDelegateMap.object(forKey: window) == nil {
                    print("[AppDelegate] Setting delegate for window: \(window.title)")
                    window.delegate = self
                    self.windowDelegateMap.setObject(self, forKey: window)
                    delegateSet = true
                }
            }

            if delegateSet || attempts >= 5 {
                print("[AppDelegate] Delegate setting timer finished. Delegate set: \(delegateSet)")
                timer.invalidate()
                self.delegateSetAttemptTimer = nil
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        print("[AppDelegate] applicationShouldTerminate called.")
        let unsavedFiles = self.appState.openFiles.filter { $0.hasUnsavedChanges }
        if unsavedFiles.isEmpty {
            print("[AppDelegate] Terminating now (no unsaved files).")
            return .terminateNow
        } else {
            print("[AppDelegate] Unsaved files exist. Showing alert before terminating.")
            let cancel = self.showUnsavedChangesAlert(forTermination: true, window: NSApplication.shared.mainWindow)
            print("[AppDelegate] Alert response indicates cancel termination: \(cancel)")
            return cancel ? .terminateCancel : .terminateNow
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        print("[AppDelegate] windowShouldClose entered for window: \(sender.title)")

        let unsavedFiles = self.appState.openFiles.filter { $0.hasUnsavedChanges }

        if unsavedFiles.isEmpty {
            print("[AppDelegate] windowShouldClose: No unsaved changes. Clearing open files.")
            self.appState.openFiles.removeAll()
            self.windowDelegateMap.removeObject(forKey: sender)
            print("[AppDelegate] Allowing window to close (no unsaved changes).")
            return true
        } else {
            print("[AppDelegate] windowShouldClose: Unsaved changes detected. Showing alert.")
            let cancel = self.showUnsavedChangesAlert(forTermination: false, window: sender)
            print("[AppDelegate] Alert response indicates cancel close: \(cancel)")

            if !cancel {
                print("[AppDelegate] windowShouldClose: User confirmed 'Close Anyway'. Clearing open files.")
                self.appState.openFiles.removeAll()
                self.windowDelegateMap.removeObject(forKey: sender)
                print("[AppDelegate] Allowing window to close (user confirmed).")
                return true
            } else {
                print("[AppDelegate] Preventing window close (user cancelled).")
                return false
            }
        }
    }

    @discardableResult
    private func showUnsavedChangesAlert(forTermination isTerminating: Bool, window: NSWindow?) -> Bool {
        let unsavedFiles = self.appState.openFiles.filter { $0.hasUnsavedChanges }
        guard !unsavedFiles.isEmpty else {
            print("[AppDelegate showUnsavedChangesAlert] Called with no unsaved files - returning false (proceed).")
            return false
        }

        let fileList = unsavedFiles.map { $0.fileName }.joined(separator: "\n")
        let alert = NSAlert()
        alert.messageText = isTerminating ? "Quit with Unsaved Changes?" : "Close Window with Unsaved Changes?"
        alert.informativeText = "You have unsaved changes in:\n\(fileList)\n\nIf you \(isTerminating ? "quit" : "close the window"), your changes will be lost."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: isTerminating ? "Quit Anyway" : "Close Anyway")
        alert.alertStyle = .warning

        let response: NSApplication.ModalResponse
        if let _ = window, !isTerminating {
            print("[AppDelegate showUnsavedChangesAlert] Running modal sheet for window.")
            response = alert.runModal()
        } else {
            print("[AppDelegate showUnsavedChangesAlert] Running modal application alert.")
            response = alert.runModal()
        }

        if response == .alertFirstButtonReturn {
            print("[AppDelegate showUnsavedChangesAlert] User cancelled close/quit.")
            return true
        } else {
            print("[AppDelegate showUnsavedChangesAlert] User confirmed close/quit despite unsaved changes.")
            return false
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        print("[AppDelegate] applicationShouldHandleReopen called. hasVisibleWindows: \(flag)")
        print("[AppDelegate] Current window count before action: \(sender.windows.count)")

        if !flag {
            if let _ = sender.windows.first {
                print("[AppDelegate] Found existing hidden window: \(sender.windows.first!.title). Making key and ordering front.")
                if self.windowDelegateMap.object(forKey: sender.windows.first!) == nil {
                    print("[AppDelegate] Re-setting delegate on reopen for window: \(sender.windows.first!.title)")
                    sender.windows.first!.delegate = self
                    self.windowDelegateMap.setObject(self, forKey: sender.windows.first!)
                }
                sender.windows.first!.makeKeyAndOrderFront(self)
                print("[AppDelegate] Returning false as we handled the reopen by showing an existing window.")
                return false
            } else {
                print("[AppDelegate] No existing windows found. Returning true to allow system creation.")
                return true
            }
        } else {
            print("[AppDelegate] Windows are already visible. Returning true for default behavior.")
            for window in sender.windows where window.isVisible {
                window.makeKeyAndOrderFront(self)
            }
            return true
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let firstUrl = filenames.first.flatMap(URL.init(fileURLWithPath:)) else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }
        let secured = firstUrl.startAccessingSecurityScopedResource()
        defer { if secured { firstUrl.stopAccessingSecurityScopedResource() } }
        guard secured else {
            print("[AppDelegate openFiles] Could not gain security access for \(firstUrl.lastPathComponent)")
            DispatchQueue.main.async {
                self.appState.presentAlert(title: "Open Error", message: "Could not get permission to open \(firstUrl.lastPathComponent).")
            }
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        DispatchQueue.main.async {
            print("[AppDelegate openFiles] Setting dropped file URL: \(firstUrl.lastPathComponent)")
            self.appState.droppedFileURL = firstUrl

            if let window = NSApplication.shared.windows.first(where: { $0.isMainWindow || $0.isKeyWindow }) ?? NSApplication.shared.windows.first {
                print("[AppDelegate openFiles] Ordering window front for opened file: \(window.title)")
                window.makeKeyAndOrderFront(self)
            } else {
                print("[AppDelegate openFiles] No window found to order front, relying on reopen/launch.")
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[AppDelegate] applicationWillTerminate.")
        delegateSetAttemptTimer?.invalidate()
        delegateSetAttemptTimer = nil
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }
}
