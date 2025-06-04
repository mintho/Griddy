//
// ContentView.swift
// Griddy
//
// Created by Thomas Minzenmay on 20.04.25.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine
import AppKit
import Foundation

enum FileType {
    case png
    case project
}

struct ContentView: View {
    @State private var selectedTabId: UUID?
    @EnvironmentObject var appState: AppState
    
    let uniqueProjectUTIString = "com.minzenmay.Griddy.griddy"
    let uniqueProjectUTType: UTType
    let supportedImageTypes: [UTType] = [.png]
    let supportedProjectTypes: [UTType]
    let supportedImportTypes: [UTType] = [.commaSeparatedText, .cSource]
    let supportedCHExportTypes: [UTType] = [.cSource]
    let supportedDropTypes: [UTType]
    
    init() {
        let projectType = UTType(exportedAs: uniqueProjectUTIString)
        
        self.uniqueProjectUTType = projectType
        self.supportedProjectTypes = [projectType]
        self.supportedDropTypes = [.fileURL, .png, projectType]
    }
    
    private var selectedFileState: FileState? {
        guard let id = selectedTabId else { return nil }
        
        return appState.openFiles.first { $0.id == id }
    }
    
    // Combines multiple app state triggers into a single publisher
    private var appStatePublisher: AnyPublisher<Void, Never> {
        let publishers = [
            appState.$saveProjectTrigger.map { _ in () }.eraseToAnyPublisher(),
            appState.$saveProjectAsTrigger.map { _ in () }.eraseToAnyPublisher(),
            appState.$importCSVTrigger.map { _ in () }.eraseToAnyPublisher(),
            appState.$closeTabTrigger.map { _ in () }.eraseToAnyPublisher(),
            appState.$droppedFileURL.map { _ in () }.eraseToAnyPublisher()
        ]
        
        return Publishers.MergeMany(publishers).eraseToAnyPublisher()
    }
    
    var body: some View {
        ZStack {
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    Text("No file selected.\n\nDrag & Drop a PNG file here\nor use File > Open PNG...")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding()
                    
                    Spacer()
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if let currentFile = selectedFileState {
                VStack(spacing: 0) {
                    if !appState.openFiles.isEmpty {
                        TabBarView(
                            openFiles: $appState.openFiles,
                            selectedTabId: $selectedTabId,
                            closeTabAction: closeTab
                        )
                        
                        Divider()
                    }
                    
                    FileView(fileState: currentFile)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onDrop(of: supportedDropTypes, isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .onReceive(appStatePublisher) { _ in
            if appState.saveProjectTrigger != nil {
                saveProject()
                
                appState.saveProjectTrigger = nil
            }
            
            if appState.saveProjectAsTrigger != nil {
                saveProjectAs()
                
                appState.saveProjectAsTrigger = nil
            }
            
            if appState.importCSVTrigger != nil {
                importCSV()
            }
            
            if appState.closeTabTrigger != nil {
                if let id = selectedTabId {
                    closeTab(id: id)
                }
                
                appState.closeTabTrigger = nil
            }
            
            if let url = appState.droppedFileURL {
                handleDroppedURL(url: url)
                
                appState.droppedFileURL = nil
            }
        }
        .overlay(
            Color.clear
                .fileImporter(
                    isPresented: $appState.showOpenProject,
                    allowedContentTypes: supportedProjectTypes,
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImporterResult(result: result, type: .project)
                }
        )
        .overlay(
            Color.clear
                .fileImporter(
                    isPresented: $appState.showOpenPNG,
                    allowedContentTypes: supportedImageTypes,
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImporterResult(result: result, type: .png)
                }
        )
        .alert(isPresented: $appState.showAlert) {
            Alert(
                title: Text(appState.alertTitle),
                message: Text(appState.alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: appState.showExportCSVPanel) { if $1 { presentCSVSavePanel() } }
        .onChange(of: appState.showExportCHPanel) { if $1 { presentCHSavePanel() } }
        .onChange(of: appState.showImportCPanel) { if $1 { presentCSourceOpenPanel() } }
        .onChange(of: appState.showExportTMXPanel) { if $1 { presentTMXSavePanel() } }
    }
    
    private func handleFileImporterResult(result: Result<[URL], Error>, type: FileType) {
        DispatchQueue.main.async {
            switch type {
            case .png:
                if appState.showOpenPNG { appState.showOpenPNG = false }
            case .project:
                if appState.showOpenProject { appState.showOpenProject = false }
            }
        }
        
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            
            guard secured else {
                appState.presentAlert(
                    title: "Permission Error",
                    message: "Could not get permission to access \(url.lastPathComponent). You may need to grant Full Disk Access or select the file again."
                )
                
                return
            }
            
            switch type {
            case .png:
                loadFile(url: url)
            case .project:
                loadProject(from: url)
            }
            
        case .failure(let error):
            let nsError = error as NSError
            
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                // User cancelled, do nothing
            } else {
                appState.presentAlert(
                    title: "Open Failed",
                    message: "Could not open selected file (\(type)): \(error.localizedDescription)"
                )
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // 1) Prefer real file URLs from Finder
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                DispatchQueue.main.async {
                    if let url = (item as? URL) ?? (item as? NSURL as URL?) {
                        let secured = url.startAccessingSecurityScopedResource()
                        defer { if secured { url.stopAccessingSecurityScopedResource() } }
                        self.handleDroppedURL(url: url)
                    } else {
                        // Fall back to other strategies
                        self.handleDropFallback(provider: provider)
                    }
                }
            }
            return true
        }

        // 2) Otherwise try to load a file representation in place (keeps filename)
        if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, inPlace, error in
                DispatchQueue.main.async {
                    if let url = url {
                        let secured = url.startAccessingSecurityScopedResource()
                        defer { if secured { url.stopAccessingSecurityScopedResource() } }
                        self.handleDroppedURL(url: url)
                    } else {
                        // Fall back to raw data + suggested name
                        self.handleDropFallback(provider: provider)
                    }
                }
            }
            return true
        }

        // 3) Project files or anything else -> fallback handler
        handleDropFallback(provider: provider)
        return true
    }
    
    private func handleDropFallback(provider: NSItemProvider) {
        let projectUTI = uniqueProjectUTType

        // Project (.griddy)
        if provider.hasItemConformingToTypeIdentifier(projectUTI.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: projectUTI.identifier) { data, error in
                DispatchQueue.main.async {
                    if let data = data {
                        self.decodeAndLoadProject(data: data, url: nil)
                    } else {
                        self.appState.presentAlert(
                            title: "Drop Error",
                            message: "Could not load dropped project data: \(error?.localizedDescription ?? "unknown")"
                        )
                    }
                }
            }
            return
        }

        // PNG bytes + suggestedName fallback
        if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
                DispatchQueue.main.async {
                    if let data = data, let image = NSImage(data: data) {
                        var preferredName: String?
                        if let s = provider.suggestedName, !s.isEmpty {
                            preferredName = s.lowercased().hasSuffix(".png") ? s : (s + ".png")
                        } else {
                            preferredName = "Dropped Image.png"
                        }
                        self.loadImageAndCreateState(image: image,
                                                     url: nil,
                                                     originalPNGData: data,
                                                     preferredFileName: preferredName)
                    } else {
                        self.appState.presentAlert(
                            title: "Drop Error",
                            message: "Could not load dropped PNG data: \(error?.localizedDescription ?? "unknown")"
                        )
                    }
                }
            }
            return
        }

        // Unsupported
        DispatchQueue.main.async {
            self.appState.presentAlert(
                title: "Drop Error",
                message: "Unsupported item dropped."
            )
        }
    }
    
    private func handleDroppedURL(url: URL) {
        guard let uti = UTType(filenameExtension: url.pathExtension) else {
            appState.presentAlert(
                title: "Unsupported",
                message: "Cannot determine file type: \(url.lastPathComponent)"
            )
            
            return
        }
        
        if uti.conforms(to: .png) {
            loadFile(url: url)
        } else if uti.conforms(to: uniqueProjectUTType) {
            loadProject(from: url)
        } else {
            appState.presentAlert(
                title: "Unsupported",
                message: "Cannot open type (\(uti.preferredFilenameExtension ?? "?")): \(url.lastPathComponent)"
            )
        }
    }
    
    private func loadFile(url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            appState.presentAlert(title: "Load Error", message: "Could not load image: \(url.lastPathComponent)")
            return
        }
        let originalData = try? Data(contentsOf: url)
        loadImageAndCreateState(image: image, url: url, originalPNGData: originalData)
    }
    
    private func loadImageAndCreateState(image: NSImage,
                                         url: URL?,
                                         originalPNGData: Data? = nil,
                                         preferredFileName: String? = nil) {
        let sourceName = url?.lastPathComponent ?? (preferredFileName ?? "Dropped Data")

        if image.size.width.truncatingRemainder(dividingBy: GRID_CELL_SIZE) != 0 ||
           image.size.height.truncatingRemainder(dividingBy: GRID_CELL_SIZE) != 0 {
            appState.presentAlert(
                title: "Invalid Dimensions",
                message: "Image (\(Int(image.size.width))x\(Int(image.size.height))) not multiple of \(Int(GRID_CELL_SIZE))."
            )
            return
        }

        if let url = url, let existingFile = appState.openFiles.first(where: { $0.fileURL == url }) {
            selectedTabId = existingFile.id
            return
        }

        let newFileState = FileState(image: image, url: url)
        newFileState.originalPNGData = originalPNGData

        // If there’s no URL, use the preferred file name for the tab title
        if url == nil, let nice = preferredFileName, !nice.isEmpty {
            newFileState.fileName = nice
        }

        if newFileState.image != nil {
            appState.openFiles.append(newFileState)
            selectedTabId = newFileState.id
        } else {
            appState.presentAlert(
                title: "Error",
                message: "Failed state init for \(sourceName)."
            )
        }
    }
    
    private func loadProject(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            
            decodeAndLoadProject(data: data, url: url)
        } catch {
            appState.presentAlert(
                title: "Load Failed",
                message: "Could not read project '\(url.lastPathComponent)': \(error.localizedDescription)"
            )
        }
    }
    
    private func decodeAndLoadProject(data: Data, url: URL?) {
        let sourceName = url?.lastPathComponent ?? "Dropped Data"
        
        if let url = url, let existingFile = appState.openFiles.first(where: { $0.fileURL == url }) {
            selectedTabId = existingFile.id
            
            return
        }
        
        do {
            let projectData = try JSONDecoder().decode(ProjectData.self, from: data)
            
            let newFileState = FileState(projectData: projectData, url: url)
            
            if newFileState.image != nil {
                appState.openFiles.append(newFileState)
                
                selectedTabId = newFileState.id
            } else {
                appState.presentAlert(
                    title: "Load Error",
                    message: "Failed state init from \(sourceName)."
                )
            }
        } catch {
            appState.presentAlert(
                title: "Load Failed",
                message: "Could not parse project data from \(sourceName): \(error.localizedDescription)"
            )
        }
    }
    
    private func saveProject(forceSaveAs: Bool = false) {
        guard let currentFile = getCurrentFileState() else {
            appState.presentAlert(title: "No File", message: "Select tab.")
            
            return
        }
        
        let projectType = uniqueProjectUTType
        var urlToSave: URL? = currentFile.fileURL
        let needsSaveAsPanel = forceSaveAs || urlToSave == nil || urlToSave?.pathExtension.lowercased() != projectType.preferredFilenameExtension
        
        if needsSaveAsPanel {
            let panel = NSSavePanel()
            
            panel.allowedContentTypes = supportedProjectTypes
            
            let baseName = currentFile.fileURL?.deletingPathExtension().lastPathComponent ??
                           currentFile.fileName.replacingOccurrences(of: ".png", with: "")
            
            panel.nameFieldStringValue = baseName + "." + (projectType.preferredFilenameExtension ?? "griddy")
            panel.message = "Save Griddy Project"
            
            guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
            
            urlToSave = selectedURL
        }
        
        guard let finalURL = urlToSave else {
            appState.presentAlert(title: "Save Error", message: "No save location.")
            
            return
        }
        
        var pngData: Data?
        
        if let image = currentFile.image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            pngData = bitmap.representation(using: .png, properties: [:])
        }
        
        guard let finalPNGData = pngData else {
            appState.presentAlert(title: "Save Error", message: "PNG data failed.")
            
            return
        }
        
        let projectData = ProjectData(
            pngData: currentFile.originalPNGData ?? finalPNGData,  // prefer original bytes
            gridData: currentFile.gridData,
            originalFileName: currentFile.fileName
        )
        
        do {
            let encoder = JSONEncoder()
            
            encoder.outputFormatting = .prettyPrinted
            
            let dataToSave = try encoder.encode(projectData)
            
            let secured = finalURL.startAccessingSecurityScopedResource()
            defer { if secured { finalURL.stopAccessingSecurityScopedResource() } }
            
            try dataToSave.write(to: finalURL)
            
            currentFile.fileURL = finalURL
            currentFile.fileName = finalURL.lastPathComponent
            currentFile.hasUnsavedChanges = false
        } catch {
            let nsError = error as NSError
            let message = nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError ?
                          error.localizedDescription :
                          "\(error.localizedDescription)"
            
            appState.presentAlert(
                title: nsError.code == NSFileWriteNoPermissionError ? "Save Permission Error" : "Save Failed",
                message: message
            )
        }
    }
    
    private func saveProjectAs() {
        saveProject(forceSaveAs: true)
    }
    
    private func presentCSVSavePanel() {
        guard let currentFile = getCurrentFileState() else {
            appState.presentAlert(title: "No File", message: "Select tab.")
            
            DispatchQueue.main.async { appState.showExportCSVPanel = false }
            
            return
        }
        
        guard !currentFile.gridData.isEmpty else {
            appState.presentAlert(title: "No Grid", message: "Grid empty.")
            
            DispatchQueue.main.async { appState.showExportCSVPanel = false }
            
            return
        }
        
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            
            panel.allowedContentTypes = [.commaSeparatedText]
            
            let baseName = currentFile.fileURL?.deletingPathExtension().lastPathComponent ??
                           currentFile.fileName.replacingOccurrences(of: ".png", with: "")
                                              .replacingOccurrences(of: ".griddy", with: "")
            
            panel.nameFieldStringValue = baseName + "_grid.csv"
            panel.message = "Export CSV"
            panel.canCreateDirectories = true
            
            let result = panel.runModal()
            
            appState.showExportCSVPanel = false
            
            guard result == .OK, let url = panel.url else { return }
            
            let csvString = currentFile.gridData.map { row in
                row.map { String($0) }.joined(separator: ",")
            }.joined(separator: "\n")
            
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            
            guard secured else {
                appState.presentAlert(
                    title: "Permission Error",
                    message: "Could not get permission to save file."
                )
                
                return
            }
            
            do {
                try csvString.write(to: url, atomically: true, encoding: .utf8)
                
                appState.presentAlert(
                    title: "Success",
                    message: "CSV exported to \(url.lastPathComponent)."
                )
            } catch {
                appState.presentAlert(
                    title: "Export Failed",
                    message: "Could not write CSV: \(error.localizedDescription)"
                )
            }
        }
    }
    
    private func importCSV() {
        appState.importCSVTrigger = nil
        
        guard let currentFile = getCurrentFileState() else {
            appState.presentAlert(title: "No File", message: "Select tab.")
            
            return
        }
        
        guard currentFile.image != nil else {
            appState.presentAlert(title: "No Image", message: "Image needed.")
            
            return
        }
        
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.message = "Select CSV (comma/semicolon)"
            
            let result = panel.runModal()
            
            guard result == .OK, let url = panel.url else { return }
            
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            
            guard secured else {
                appState.presentAlert(
                    title: "Permission Error",
                    message: "Could not get permission to read file."
                )
                
                return
            }
            
            do {
                let csvString = try String(contentsOf: url, encoding: .utf8)
                
                let lines = csvString.split(whereSeparator: \.isNewline)
                var detectedSeparator: Character = ","
                
                if let firstDataLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    if firstDataLine.filter({ $0 == ";" }).count > firstDataLine.filter({ $0 == "," }).count {
                        detectedSeparator = ";"
                    }
                }
                
                var importedGrid: [[Int]] = []
                
                for (rIndex, line) in lines.enumerated() {
                    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    
                    let columns = line.split(separator: detectedSeparator).map { $0.trimmingCharacters(in: .whitespaces) }
                    
                    let row = try columns.enumerated().map { (cIndex, colStr) -> Int in
                        guard let v = Int(colStr) else {
                            throw NSError(
                                domain: "CSV",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid num '\(colStr)' @ R\(rIndex+1):C\(cIndex+1)"]
                            )
                        }
                        
                        guard v >= 0 && v < ColorPalette.colors.count else {
                            throw NSError(
                                domain: "CSV",
                                code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Out of range (\(v)) @ R\(rIndex+1):C\(cIndex+1)"]
                            )
                        }
                        
                        return v
                    }
                    
                    importedGrid.append(row)
                }
                
                let expectedRows = currentFile.gridRows
                let expectedCols = currentFile.gridColumns
                
                guard !importedGrid.isEmpty else {
                    throw NSError(
                        domain: "CSV",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "CSV file appears empty or contains no valid data."]
                    )
                }
                
                guard importedGrid.count == expectedRows else {
                    throw NSError(
                        domain: "CSV",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Row count mismatch (\(importedGrid.count) != \(expectedRows))."]
                    )
                }
                
                guard let firstRow = importedGrid.first, firstRow.count == expectedCols else {
                    throw NSError(
                        domain: "CSV",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "Column count mismatch (\(importedGrid.first?.count ?? 0) != \(expectedCols))."]
                    )
                }
                
                currentFile.gridData = importedGrid
                currentFile.hasUnsavedChanges = true
                
                appState.presentAlert(
                    title: "Import OK",
                    message: "Loaded grid data from \(url.lastPathComponent)."
                )
            } catch {
                appState.presentAlert(
                    title: "Import Failed",
                    message: "Could not parse CSV: \(error.localizedDescription)"
                )
            }
        }
    }
    
    private func presentCSourceOpenPanel() {
        guard let currentFile = getCurrentFileState() else {
            appState.presentAlert(title: "No File Selected", message: "Select tab.")
            
            DispatchQueue.main.async { appState.showImportCPanel = false }
            
            return
        }
        
        guard currentFile.image != nil else {
            appState.presentAlert(title: "No Image", message: "Image needed.")
            
            DispatchQueue.main.async { appState.showImportCPanel = false }
            
            return
        }
        
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.cSource]
            panel.message = "Select C source file"
            
            let result = panel.runModal()
            
            appState.showImportCPanel = false
            
            guard result == .OK, let url = panel.url else { return }
            
            loadAndParseCSource(from: url)
        }
    }
    
    private func loadAndParseCSource(from url: URL) {
        guard let currentFile = getCurrentFileState() else { return }
        
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        
        guard secured else {
            appState.presentAlert(
                title: "Permission Error",
                message: "Could not get permission to read file."
            )
            
            return
        }
        
        do {
            let fileContent = try String(contentsOf: url, encoding: .utf8)
            
            guard let importedGrid = parseCSource(content: fileContent) else {
                appState.presentAlert(
                    title: "Import Error",
                    message: "Could not parse array from C file."
                )
                
                return
            }
            
            let expectedRows = currentFile.gridRows
            let expectedCols = currentFile.gridColumns
            
            guard !importedGrid.isEmpty else {
                appState.presentAlert(
                    title: "Import Error",
                    message: "C file empty array."
                )
                
                return
            }
            
            guard importedGrid.count == expectedRows else {
                appState.presentAlert(
                    title: "Dim Mismatch",
                    message: "Rows (\(importedGrid.count)!=\(expectedRows))."
                )
                
                return
            }
            
            guard let firstRow = importedGrid.first, firstRow.count == expectedCols else {
                appState.presentAlert(
                    title: "Dim Mismatch",
                    message: "Cols (\(importedGrid.first?.count ?? 0)!=\(expectedCols))."
                )
                
                return
            }
            
            currentFile.gridData = importedGrid
            currentFile.hasUnsavedChanges = true
            
            appState.presentAlert(
                title: "Import OK",
                message: "Loaded \(url.lastPathComponent)."
            )
        } catch {
            appState.presentAlert(
                title: "Import Failed",
                message: "Could not read C file: \(error.localizedDescription)"
            )
        }
    }
    
    // Parses a 2D array from C source content
    private func parseCSource(content: String) -> [[Int]]? {
        let pattern = #"const\s+u16\s+\w+\s*\[\s*\d+\s*\]\s*\[\s*\d+\s*\]\s*=\s*\{(.*?)\};"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        
        guard let match = regex.firstMatch(in: content, options: [], range: nsRange),
              let contentRange = Range(match.range(at: 1), in: content) else { return nil }
        
        let arrayContent = String(content[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        var importedGrid: [[Int]] = []
        
        let potentialRows = arrayContent.split(whereSeparator: { $0 == "}" })
        
        for rowString in potentialRows {
            if let openingBraceRange = rowString.range(of: "{") {
                let numbersString = String(rowString[openingBraceRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                
                if numbersString.isEmpty { continue }
                
                let numberStrings = numbersString.split(separator: ",")
                var rowData: [Int] = []
                
                for numStr in numberStrings {
                    let trimmedNumStr = numStr.trimmingCharacters(in: .whitespaces)
                    
                    guard let value = Int(trimmedNumStr) else { return nil }
                    guard value >= 0 && value < ColorPalette.colors.count else { return nil }
                    
                    rowData.append(value)
                }
                
                if !rowData.isEmpty {
                    importedGrid.append(rowData)
                }
            }
        }
        
        if let firstRowCount = importedGrid.first?.count {
            if !importedGrid.allSatisfy({ $0.count == firstRowCount }) { return nil }
        } else if !importedGrid.isEmpty { return nil }
        
        return importedGrid.isEmpty ? nil : importedGrid
    }
    
    private func generateCContent(baseName: String, gridData: [[Int]]) -> String? {
        guard !gridData.isEmpty, let firstRow = gridData.first, !firstRow.isEmpty else { return nil }
        
        let rows = gridData.count
        let cols = firstRow.count
        
        guard gridData.allSatisfy({ $0.count == cols }) else { return nil }
        
        let arrayName = baseName.uppercased()
        var cContent = "#include \"\(baseName).h\"\n\n"
        
        cContent += "const u16 \(arrayName)[\(rows)][\(cols)] = {\n"
        
        for (rowIndex, row) in gridData.enumerated() {
            cContent += "\t{\(row.map { String($0) }.joined(separator: ","))}"
            
            if rowIndex < rows - 1 { cContent += "," }
            
            cContent += "\n"
        }
        
        cContent += "};\n"
        
        return cContent
    }
    
    private func generateHContent(baseName: String, rows: Int, cols: Int) -> String {
        let arrayName = baseName.uppercased()
        let guardName = arrayName + "_H"
        
        return """
        #ifndef \(guardName)
        #define \(guardName)
        
        #include <genesis.h>
        
        extern const u16 \(arrayName)[\(rows)][\(cols)];
        
        #endif // \(guardName)
        """
    }
    
    private func presentCHSavePanel() {
        guard let currentFile = getCurrentFileState() else {
            appState.presentAlert(title: "No File", message: "Select tab.")
            
            DispatchQueue.main.async { appState.showExportCHPanel = false }
            
            return
        }
        
        guard !currentFile.gridData.isEmpty, let firstRow = currentFile.gridData.first, !firstRow.isEmpty else {
            appState.presentAlert(title: "No Grid", message: "Grid empty.")
            
            DispatchQueue.main.async { appState.showExportCHPanel = false }
            
            return
        }
        
        DispatchQueue.main.async {
            let openPanel = NSOpenPanel()
            
            openPanel.title = "Choose Directory and Base Name for C/H Files"
            openPanel.message = "Select directory for 'baseName.c' & 'baseName.h'"
            openPanel.prompt = "Choose Directory"
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.canCreateDirectories = true
            openPanel.allowsMultipleSelection = false
            
            let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
            
            let label = NSTextField(labelWithString: "Base Name:")
            
            label.frame = NSRect(x: 0, y: 25, width: 80, height: 20)
            
            let textField = NSTextField(frame: NSRect(x: 85, y: 25, width: 165, height: 20))
            
            let defaultBaseName = currentFile.fileURL?.deletingPathExtension().lastPathComponent ??
                                  currentFile.fileName.replacingOccurrences(of: ".png", with: "")
                                                     .replacingOccurrences(of: ".griddy", with: "")
            
            textField.stringValue = defaultBaseName
            textField.placeholderString = "e.g., level_map"
            
            accessoryView.addSubview(label)
            accessoryView.addSubview(textField)
            
            openPanel.accessoryView = accessoryView
            openPanel.isAccessoryViewDisclosed = true
            
            let result = openPanel.runModal()
            
            appState.showExportCHPanel = false
            
            guard result == .OK, let directoryURL = openPanel.urls.first else { return }
            
            let baseName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !baseName.isEmpty else {
                appState.presentAlert(
                    title: "Export Failed",
                    message: "Base name cannot be empty."
                )
                
                return
            }
            
            let cFileURL = directoryURL.appendingPathComponent(baseName).appendingPathExtension("c")
            let hFileURL = directoryURL.appendingPathComponent(baseName).appendingPathExtension("h")
            
            let fileManager = FileManager.default
            var filesToOverwrite: [String] = []
            
            if fileManager.fileExists(atPath: cFileURL.path) {
                filesToOverwrite.append(cFileURL.lastPathComponent)
            }
            
            if fileManager.fileExists(atPath: hFileURL.path) {
                filesToOverwrite.append(hFileURL.lastPathComponent)
            }
            
            if !filesToOverwrite.isEmpty {
                let alert = NSAlert()
                
                let fileListString = filesToOverwrite.joined(separator: "\n")
                
                alert.messageText = "Replace Existing Files?"
                alert.informativeText = "The following file(s) already exist in the selected directory:\n\n\(fileListString)\n\nDo you want to replace them?"
                alert.addButton(withTitle: "Replace")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                
                let replaceResponse = alert.runModal()
                
                if replaceResponse != .alertFirstButtonReturn { return }
            }
            
            guard let cContent = generateCContent(baseName: baseName, gridData: currentFile.gridData) else {
                appState.presentAlert(
                    title: "Export Failed",
                    message: "C content generation failed."
                )
                
                return
            }
            
            let rows = currentFile.gridData.count
            let cols = firstRow.count
            
            let hContent = generateHContent(baseName: baseName, rows: rows, cols: cols)
            
            let secured = directoryURL.startAccessingSecurityScopedResource()
            defer { if secured { directoryURL.stopAccessingSecurityScopedResource() } }
            
            guard secured else {
                appState.presentAlert(
                    title: "Permission Error",
                    message: "Could not get permission to save files in the selected directory."
                )
                
                return
            }
            
            do {
                try cContent.write(to: cFileURL, atomically: true, encoding: .utf8)
                
                try hContent.write(to: hFileURL, atomically: true, encoding: .utf8)
                
                appState.presentAlert(
                    title: "Success",
                    message: "Exported \(baseName).c/.h to \(directoryURL.lastPathComponent)."
                )
            } catch {
                var failedFileName = hFileURL.lastPathComponent
                
                if !FileManager.default.fileExists(atPath: cFileURL.path) {
                    failedFileName = cFileURL.lastPathComponent
                }
                
                appState.presentAlert(
                    title: "Export Failed",
                    message: "Could not write '\(failedFileName)': \(error.localizedDescription)"
                )
            }
        }
    }
    
    private func presentTMXSavePanel() {
        guard let currentFile = getCurrentFileState(), let image = currentFile.image else {
            appState.presentAlert(title: "No Image", message: "Load a PNG first.")
            DispatchQueue.main.async { appState.showExportTMXPanel = false }
            return
        }
        // Validate size
        if image.size.width.truncatingRemainder(dividingBy: GRID_CELL_SIZE) != 0 ||
           image.size.height.truncatingRemainder(dividingBy: GRID_CELL_SIZE) != 0 {
            appState.presentAlert(title: "Invalid Dimensions",
                                  message: "Image size must be a multiple of \(Int(GRID_CELL_SIZE)).")
            DispatchQueue.main.async { appState.showExportTMXPanel = false }
            return
        }

        DispatchQueue.main.async {
            let openPanel = NSOpenPanel()
            openPanel.title = "Choose Directory and Base Name for TMX/TSX/PNG"
            openPanel.message = "Select output directory. Files written: <base>.tmx, <base>_tileset.tsx, <base>_tiles.png"
            openPanel.prompt = "Choose Directory"
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.canCreateDirectories = true
            openPanel.allowsMultipleSelection = false

            // Simple accessory view for base name
            let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
            let label = NSTextField(labelWithString: "Base Name:")
            label.frame = NSRect(x: 0, y: 28, width: 80, height: 20)
            let textField = NSTextField(frame: NSRect(x: 85, y: 26, width: 170, height: 22))
            let defaultBase = (currentFile.fileURL?.deletingPathExtension().lastPathComponent
                               ?? currentFile.fileName.replacingOccurrences(of: ".png", with: "")
                                                 .replacingOccurrences(of: ".griddy", with: ""))
            textField.stringValue = defaultBase
            textField.placeholderString = "e.g., level_map"
            accessoryView.addSubview(label)
            accessoryView.addSubview(textField)
            openPanel.accessoryView = accessoryView
            openPanel.isAccessoryViewDisclosed = true

            let result = openPanel.runModal()
            self.appState.showExportTMXPanel = false
            guard result == .OK, let directoryURL = openPanel.urls.first else { return }

            let baseName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !baseName.isEmpty else {
                self.appState.presentAlert(title: "Export Failed", message: "Base name cannot be empty.")
                return
            }

            // Security scope
            let secured = directoryURL.startAccessingSecurityScopedResource()
            defer { if secured { directoryURL.stopAccessingSecurityScopedResource() } }
            guard secured else {
                self.appState.presentAlert(title: "Permission Error", message: "No permission to write in the selected directory.")
                return
            }

            do {
                // Export with defaults: 8×8 tiles, external TSX
                let result = try TiledExporter.exportTMX(from: currentFile,
                                                         to: directoryURL,
                                                         baseName: baseName,
                                                         options: .init(tileSize: Int(GRID_CELL_SIZE)))

                // Optional: update “Unique Tiles” in sidebar
                currentFile.uniqueTileCount = result.uniqueTileCount
                self.appState.presentAlert(title: "Export OK",
                                           message: "Wrote:\n\(result.mapURL.lastPathComponent)\n\(result.tilesetURL.lastPathComponent)\n\(result.tilesetImageURL.lastPathComponent)")
            } catch {
                self.appState.presentAlert(title: "Export Failed", message: error.localizedDescription)
            }
        }
    }

    private func closeTab(id: UUID) {
        guard let index = appState.openFiles.firstIndex(where: { $0.id == id }) else { return }
        
        let fileToClose = appState.openFiles[index]
        let closingSelectedTab = (id == selectedTabId)
        
        if fileToClose.hasUnsavedChanges {
            let alert = NSAlert()
            
            alert.messageText = "Unsaved Changes"
            alert.informativeText = "Save changes to \"\(fileToClose.fileName)\"?"
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            
            let response = alert.runModal()
            
            switch response {
            case .alertFirstButtonReturn:
                saveProject()
                
                guard !fileToClose.hasUnsavedChanges else { return }
            case .alertSecondButtonReturn:
                break
            default:
                return
            }
        }
        
        appState.openFiles.remove(at: index)
        
        if appState.openFiles.isEmpty {
            selectedTabId = nil
        } else if closingSelectedTab {
            selectedTabId = appState.openFiles[max(0, index - 1)].id
        }
    }
    
    private func getCurrentFileState() -> FileState? {
        guard let currentId = selectedTabId else { return nil }
        
        return appState.openFiles.first { $0.id == currentId }
    }
}

struct TabButton: View {
    @ObservedObject var fileState: FileState
    let isSelected: Bool
    let selectAction: () -> Void
    let closeAction: () -> Void
    @State private var isHoveringClose = false
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: selectAction) {
                Text(fileState.fileName + (fileState.hasUnsavedChanges ? "*" : ""))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? Color(nsColor: .selectedControlTextColor) : Color(nsColor: .controlTextColor))
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isHoveringClose ? Color(nsColor: .alternateSelectedControlTextColor) : Color(nsColor: .secondaryLabelColor))
                    .padding(3)
                    .background(
                        Circle()
                            .fill(isHoveringClose ? Color(nsColor: .secondaryLabelColor).opacity(0.7) : Color.clear)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                isHoveringClose = hovering
            }
            .frame(width: 16, height: 16)
            .padding(.leading, 2)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color(nsColor: .selectedControlColor) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(.trailing, 2)
    }
}

#Preview {
    ContentView().environmentObject(AppState())
}
