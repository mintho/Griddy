//
//  ProjectData.swift
//  Griddy
//
//  Created by Thomas Minzenmay on 17.04.25.
//

import Foundation

// A simple Codable struct to define the format for saving and loading project files.
struct ProjectData: Codable {
    // The raw PNG image data associated with the project, or nil if not available.
    let pngData: Data?
    
    // The 2D array representing the colored grid state.
    let gridData: [[Int]]
    
    // The original filename (from PNG or previous project save) for context, or nil if not available.
    let originalFileName: String?
}
