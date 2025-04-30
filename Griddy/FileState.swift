//
//  FileState.swift
//  Griddy
//
//  Created by Thomas Minzenmay on 16.04.25.
//

import SwiftUI
import Combine
import AppKit

class FileState: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    
    // MARK: Published Properties
    @Published var image: NSImage?
    @Published var gridData: [[Int]] = []
    @Published var fileURL: URL?
    @Published var fileName: String = "Untitled"
    @Published var gridColumns: Int = 0
    @Published var gridRows: Int = 0
    @Published var hasUnsavedChanges: Bool = false
    @Published var uniqueTileCount: Int = 0
    
    // MARK: Internal Properties
    var imageWidth: CGFloat = 0
    var imageHeight: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initializers
    init(image: NSImage, url: URL?) {
        guard image.isValid, image.size.width > 0, image.size.height > 0 else {
            print("Error: Invalid or zero size image.")
            self.image = nil
            self.fileName = "Invalid Image"
            return
        }
        
        guard image.size.width.truncatingRemainder(dividingBy: GRID_CELL_SIZE) == 0,
              image.size.height.truncatingRemainder(dividingBy: GRID_CELL_SIZE) == 0 else {
            print("Error: Image dimensions not multiple of grid cell size.")
            self.image = nil
            self.fileName = "Invalid Dimensions"
            return
        }
        
        print("Initializing FileState for URL: \(url?.lastPathComponent ?? "nil")")
        self.image = image
        self.fileURL = url
        self.fileName = url?.lastPathComponent ?? "Untitled Image"
        self.imageWidth = image.size.width
        self.imageHeight = image.size.height
        self.gridColumns = Int(imageWidth / GRID_CELL_SIZE)
        self.gridRows = Int(imageHeight / GRID_CELL_SIZE)
        self.gridData = Array(repeating: Array(repeating: 0, count: gridColumns), count: gridRows)
        self.hasUnsavedChanges = true
        setupGridDataChangeObserver()
        self.uniqueTileCount = computeUniqueTileCount()
    }
    
    init(projectData: ProjectData, url: URL?) {
        print("Initializing FileState from project data. URL: \(url?.lastPathComponent ?? "nil")")
        guard let pngData = projectData.pngData,
              let loadedImage = NSImage(data: pngData),
              loadedImage.isValid else {
            print("Error: Invalid project image data.")
            self.image = nil
            self.fileName = "Invalid Project Image"
            return
        }
        
        guard loadedImage.size.width.truncatingRemainder(dividingBy: GRID_CELL_SIZE) == 0,
              loadedImage.size.height.truncatingRemainder(dividingBy: GRID_CELL_SIZE) == 0,
              loadedImage.size.width > 0,
              loadedImage.size.height > 0 else {
            print("Error: Invalid project image dimensions.")
            self.image = nil
            self.fileName = "Invalid Project Dimensions"
            return
        }
        
        self.image = loadedImage
        self.imageWidth = loadedImage.size.width
        self.imageHeight = loadedImage.size.height
        self.gridColumns = Int(imageWidth / GRID_CELL_SIZE)
        self.gridRows = Int(imageHeight / GRID_CELL_SIZE)
        
        if projectData.gridData.count == self.gridRows && projectData.gridData.first?.count == self.gridColumns {
            self.gridData = projectData.gridData
            self.hasUnsavedChanges = false
            print("Loaded grid data successfully.")
        } else {
            print("Warning: Grid data mismatch. Reinitializing grid data.")
            self.gridData = Array(repeating: Array(repeating: 0, count: gridColumns), count: gridRows)
            self.hasUnsavedChanges = true
        }
        
        self.fileURL = url
        self.fileName = url?.lastPathComponent ?? projectData.originalFileName ?? "Untitled Project"
        setupGridDataChangeObserver()
        self.uniqueTileCount = computeUniqueTileCount()
    }
    
    // MARK: - Private Methods
    private func setupGridDataChangeObserver() {
        $gridData
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self, !self.hasUnsavedChanges else { return }
                print("Grid data changed for \(self.fileName). Marking as unsaved.")
                self.hasUnsavedChanges = true
            }
            .store(in: &cancellables)
    }
    
    private func computeUniqueTileCount() -> Int {
        guard let image = self.image,
              let rep = image.representations.first as? NSBitmapImageRep,
              rep.bitsPerPixel == 32,
              rep.samplesPerPixel == 4 else {
            print("Unsupported image format")
            return 0
        }
        
        var uniqueTiles = Set<Data>()
        let tileSize = 8
        
        for row in 0..<gridRows {
            for col in 0..<gridColumns {
                let tileData = extractTileData(row: row, col: col, bitmap: rep, tileSize: tileSize)
                let rotations = [
                    tileData,
                    rotate90(tileData, tileSize: tileSize),
                    rotate180(tileData, tileSize: tileSize),
                    rotate270(tileData, tileSize: tileSize)
                ]
                // Use min(by:) with lexicographical comparison to find the smallest rotation
                if let minData = rotations.min(by: { $0.lexicographicallyPrecedes($1) }) {
                    uniqueTiles.insert(minData)
                }
            }
        }
        
        return uniqueTiles.count
    }
    
    private func extractTileData(row: Int, col: Int, bitmap: NSBitmapImageRep, tileSize: Int) -> Data {
        let x = col * tileSize
        let y = row * tileSize
        let bytesPerRow = bitmap.bytesPerRow
        let bytesPerPixel = bitmap.bitsPerPixel / 8
        var tileData = Data()
        
        for tRow in 0..<tileSize {
            let srcOffset = (y + tRow) * bytesPerRow + x * bytesPerPixel
            let rowData = Data(bytes: bitmap.bitmapData! + srcOffset, count: tileSize * bytesPerPixel)
            tileData.append(rowData)
        }
        
        return tileData
    }
    
    private func rotate90(_ data: Data, tileSize: Int) -> Data {
        var rotated = Data(count: data.count)
        let bytesPerPixel = 4
        
        for i in 0..<tileSize {
            for j in 0..<tileSize {
                let origOffset = (i * tileSize + j) * bytesPerPixel
                let rotatedOffset = (j * tileSize + (tileSize - 1 - i)) * bytesPerPixel
                rotated.replaceSubrange(rotatedOffset..<rotatedOffset + bytesPerPixel, with: data.subdata(in: origOffset..<origOffset + bytesPerPixel))
            }
        }
        
        return rotated
    }
    
    private func rotate180(_ data: Data, tileSize: Int) -> Data {
        var rotated = Data(count: data.count)
        let bytesPerPixel = 4
        
        for i in 0..<tileSize {
            for j in 0..<tileSize {
                let origOffset = (i * tileSize + j) * bytesPerPixel
                let rotatedOffset = ((tileSize - 1 - i) * tileSize + (tileSize - 1 - j)) * bytesPerPixel
                rotated.replaceSubrange(rotatedOffset..<rotatedOffset + bytesPerPixel, with: data.subdata(in: origOffset..<origOffset + bytesPerPixel))
            }
        }
        
        return rotated
    }
    
    private func rotate270(_ data: Data, tileSize: Int) -> Data {
        var rotated = Data(count: data.count)
        let bytesPerPixel = 4
        
        for i in 0..<tileSize {
            for j in 0..<tileSize {
                let origOffset = (i * tileSize + j) * bytesPerPixel
                let rotatedOffset = ((tileSize - 1 - j) * tileSize + i) * bytesPerPixel
                rotated.replaceSubrange(rotatedOffset..<rotatedOffset + bytesPerPixel, with: data.subdata(in: origOffset..<origOffset + bytesPerPixel))
            }
        }
        
        return rotated
    }
    
    // MARK: - Equatable Conformance
    static func == (lhs: FileState, rhs: FileState) -> Bool {
        lhs.id == rhs.id
    }
}
