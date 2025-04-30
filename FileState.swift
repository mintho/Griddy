//
//  FileState.swift
//  Griddy
//
//  Created by Thomas Minzenmay on 16.04.25.
//

import SwiftUI
import Combine
import AppKit

// Define GRID_CELL_SIZE if it's used globally or ensure it's passed where needed
// let GRID_CELL_SIZE: CGFloat = 8.0 // Assuming it's defined elsewhere like AppState or globally

// Constants specific to FileState can be defined here if needed
private let contentMarginForFileState: CGFloat = 100.0

class FileState: ObservableObject, Identifiable, Equatable {
    // MARK: - Properties
    let id = UUID()

    // File Data Properties
    @Published var image: NSImage?
    @Published var gridData: [[Int]] = []
    @Published var fileURL: URL?
    @Published var fileName: String = "Untitled"
    @Published var gridColumns: Int = 0
    @Published var gridRows: Int = 0
    @Published var hasUnsavedChanges: Bool = false
    @Published var uniqueTileCount: Int = 0

    // View-Specific State (Persistent Per File)
    @Published var zoomLevel: CGFloat = 1.0           // Stores the current zoom level for this file
    @Published var scrollOffset: CGPoint = .zero      // Stores the scroll position for this file
    @Published var isNewlyOpened: Bool = true // Flag for initial view setup

    // Internal Calculated Properties
    var imageWidth: CGFloat = 0
    var imageHeight: CGFloat = 0

    // Combine cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializers
    init(image: NSImage, url: URL?) {
        // Validate image
        guard image.isValid, image.size.width > 0, image.size.height > 0 else {
            print("Error [FileState init(image:url:)]: Invalid/zero size image.")
            // Initialize non-optional properties to default values even on failure
            self.fileName = "Invalid Image"
            return // Exit initialization
        }
        // Validate dimensions against grid size (assuming GRID_CELL_SIZE is accessible)
        guard image.size.width.truncatingRemainder(dividingBy: GRID_CELL_SIZE) == 0,
              image.size.height.truncatingRemainder(dividingBy: GRID_CELL_SIZE) == 0 else {
            print("Error [FileState init(image:url:)]: Dimensions not multiple of \(GRID_CELL_SIZE).")
            self.fileName = "Invalid Dimensions"
            return // Exit initialization
        }

        // print("[FileState init(image:url:)] Initializing for URL: \(url?.lastPathComponent ?? "nil")")
        self.image = image
        self.fileURL = url
        self.fileName = url?.lastPathComponent ?? "Untitled Image"
        self.imageWidth = image.size.width
        self.imageHeight = image.size.height
        self.gridColumns = Int(imageWidth / GRID_CELL_SIZE)
        self.gridRows = Int(imageHeight / GRID_CELL_SIZE)

        // Initialize grid data
        self.gridData = Array(repeating: Array(repeating: 0, count: gridColumns), count: gridRows)
        self.hasUnsavedChanges = true // New image is unsaved

        // Setup observers and calculate initial values
        setupGridDataChangeObserver()
        self.uniqueTileCount = computeUniqueTileCount()
        // Note: zoomLevel, committedZoomLevel, scrollOffset, isNewlyOpened use default values
    }

    init(projectData: ProjectData, url: URL?) {
        // print("[FileState init(projectData:url:)] Initializing from project data. URL: \(url?.lastPathComponent ?? "nil")")
        // Validate image data from project
        guard let pngData = projectData.pngData,
              let loadedImage = NSImage(data: pngData),
              loadedImage.isValid,
              loadedImage.size.width > 0,
              loadedImage.size.height > 0 else {
            print("Error [FileState init(projectData:url:)]: Invalid project image data.")
            self.fileName = "Invalid Project Image"
            return // Exit initialization
        }
        // Validate dimensions
        guard loadedImage.size.width.truncatingRemainder(dividingBy: GRID_CELL_SIZE) == 0,
              loadedImage.size.height.truncatingRemainder(dividingBy: GRID_CELL_SIZE) == 0 else {
            print("Error [FileState init(projectData:url:)]: Invalid project dimensions.")
            self.fileName = "Invalid Project Dimensions"
            return // Exit initialization
        }

        self.image = loadedImage
        self.imageWidth = loadedImage.size.width
        self.imageHeight = loadedImage.size.height
        self.gridColumns = Int(imageWidth / GRID_CELL_SIZE)
        self.gridRows = Int(imageHeight / GRID_CELL_SIZE)
        self.fileURL = url
        self.fileName = url?.lastPathComponent ?? projectData.originalFileName ?? "Untitled Project"

        // Load grid data if dimensions match, otherwise initialize fresh
        if projectData.gridData.count == self.gridRows && projectData.gridData.first?.count == self.gridColumns {
            self.gridData = projectData.gridData
            self.hasUnsavedChanges = false // Loaded from saved project
            // print("[FileState init(projectData:url:)] Loaded grid data ok.")
        } else {
            print("Warning [FileState init(projectData:url:)]: Grid data mismatch or missing. Reinitializing.")
            self.gridData = Array(repeating: Array(repeating: 0, count: gridColumns), count: gridRows)
            self.hasUnsavedChanges = true // Mark as unsaved if grid was reinitialized
        }

        // Setup observers and calculate initial values
        setupGridDataChangeObserver()
        self.uniqueTileCount = computeUniqueTileCount()
        // Note: zoomLevel, committedZoomLevel, scrollOffset, isNewlyOpened use default values
    }

    // MARK: - Private Methods

    private func setupGridDataChangeObserver() {
        // Mark file as having unsaved changes when gridData is modified
        $gridData
            .dropFirst() // Ignore initial setting
            .sink { [weak self] _ in
                guard let self = self, !self.hasUnsavedChanges else { return }
                // print("[FileState sink] Grid data changed for \(self.fileName). Marking unsaved.")
                self.hasUnsavedChanges = true
            }
            .store(in: &cancellables)
    }

    private func computeUniqueTileCount() -> Int {
        // Computes unique 8x8 tiles considering rotations
        guard let unwrappedImage = self.image,
              let rep = unwrappedImage.representations.first as? NSBitmapImageRep,
              rep.bitsPerPixel == 32, // Requires RGBA
              rep.samplesPerPixel == 4,
              let bitmapData = rep.bitmapData else {
            // print("Warning: Cannot compute unique tiles. Unsupported image format or nil bitmap data.")
            return 0
        }

        var uniqueTiles = Set<Data>()
        let tileSize = Int(GRID_CELL_SIZE) // Typically 8
        let bytesPerPixel = rep.bitsPerPixel / 8 // Should be 4

        // Ensure calculated values are valid
        guard tileSize > 0, bytesPerPixel > 0, gridRows > 0, gridColumns > 0 else { return 0 }

        for row in 0..<gridRows {
            for col in 0..<gridColumns {
                let tileData = extractTileData(row: row, col: col, bitmap: rep, tileSize: tileSize, bytesPerPixel: bytesPerPixel, dataPtr: bitmapData)
                guard !tileData.isEmpty else { continue } // Skip if extraction failed

                // Consider rotations (implement these functions if needed)
                // let r90 = rotate90(tileData, tileSize: tileSize, bytesPerPixel: bytesPerPixel)
                // let r180 = rotate180(tileData, tileSize: tileSize, bytesPerPixel: bytesPerPixel)
                // let r270 = rotate270(tileData, tileSize: tileSize, bytesPerPixel: bytesPerPixel)
                // let rotations = [tileData, r90, r180, r270]
                // For now, just use original tile data
                let rotations = [tileData]

                if let minData = rotations.min(by: { $0.lexicographicallyPrecedes($1) }) {
                    uniqueTiles.insert(minData)
                }
            }
        }
        return uniqueTiles.count
    }

    private func extractTileData(row: Int, col: Int, bitmap: NSBitmapImageRep, tileSize: Int, bytesPerPixel: Int, dataPtr: UnsafeMutablePointer<UInt8>) -> Data {
        // Extracts raw pixel data for a specific tile
        let xPx = col * tileSize
        let yPx = row * tileSize
        let bytesPerRow = bitmap.bytesPerRow
        let tileByteCount = tileSize * tileSize * bytesPerPixel
        var tileData = Data(capacity: tileByteCount)

        // Check bounds to prevent reading outside bitmap data
         guard yPx + tileSize <= bitmap.pixelsHigh, xPx + tileSize <= bitmap.pixelsWide else {
             print("Warning: Tile extraction out of bounds.")
             return Data()
         }


        for tRow in 0..<tileSize { // Iterate through pixel rows within the tile
            let srcRowOffsetInBytes = (yPx + tRow) * bytesPerRow
            let srcPixelOffsetInRowBytes = xPx * bytesPerPixel
            let srcOffset = srcRowOffsetInBytes + srcPixelOffsetInRowBytes

            // Ensure we don't read past the end of the bitmap data buffer
            guard srcOffset + (tileSize * bytesPerPixel) <= bitmap.pixelsHigh * bitmap.bytesPerRow else { // << CORRECTED
                 print("Warning: Tile row read out of bounds for calculated buffer size.")
                 continue // Skip this row if out of bounds
            }


            // Append one row of pixel data for the tile
            tileData.append(dataPtr + srcOffset, count: tileSize * bytesPerPixel)
        }
        return tileData
    }

    // Placeholder rotation functions - Implement if needed for unique tile logic
    // private func rotate90(_ data: Data, tileSize: Int, bytesPerPixel: Int) -> Data { /* ... impl ... */ return data }
    // private func rotate180(_ data: Data, tileSize: Int, bytesPerPixel: Int) -> Data { /* ... impl ... */ return data }
    // private func rotate270(_ data: Data, tileSize: Int, bytesPerPixel: Int) -> Data { /* ... impl ... */ return data }

    // MARK: - Equatable Conformance
    static func == (lhs: FileState, rhs: FileState) -> Bool {
        return lhs.id == rhs.id
    }
}
