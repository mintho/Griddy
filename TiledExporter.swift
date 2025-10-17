//
//  TiledExporter.swift
//  Griddy
//
//  Export TMX (Base64 GIDs) + external TSX + indexed PNG tileset,
//  preserving the original palette and per-pixel indices.
//
//  Notes:
//  - We avoid manual zlib/IDAT inflation entirely.
//  - We parse PNG header/palette from chunks, obtain pixels via ImageIO.
//  - If CGImage remains indexed, we unpack indices; otherwise we map RGBA back to indices.
//  - TMX layer data is written as Base64-encoded 32-bit little-endian GIDs.
//    This avoids any CSV parsing issues in Tiled.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Public result & error types

struct TMXExportResult {
    let mapURL: URL
    let tilesetURL: URL
    let tilesetImageURL: URL
    let uniqueTileCount: Int
}

enum TMXExportError: Error, LocalizedError {
    case noImage
    case noPNGSource
    case notIndexedPNG               // IHDR colorType != 3
    case notMultipleOfTileSize
    case pngParseFailed(String)
    case imageCreateFailed
    case cannotReadPixelData
    case cannotCreateIndexedColorSpace
    case cannotCreateIndexedImage
    case cannotMapRGBAtoIndices(x: Int, y: Int)
    case writeFailed(URL)
    case internalSanityFailed(String)

    var errorDescription: String? {
        switch self {
        case .noImage: return "No image loaded."
        case .noPNGSource: return "No original PNG URL or data available."
        case .notIndexedPNG: return "Source PNG must be paletted (indexed)."
        case .notMultipleOfTileSize: return "Image size is not a multiple of tile size."
        case .pngParseFailed(let m): return "PNG parse failed: \(m)"
        case .imageCreateFailed: return "Could not decode image."
        case .cannotReadPixelData: return "Could not access pixel data."
        case .cannotCreateIndexedColorSpace: return "Could not create indexed color space."
        case .cannotCreateIndexedImage: return "Could not create indexed CGImage."
        case .cannotMapRGBAtoIndices(let x, let y): return "Could not map RGBA to palette index @(\(x),\(y))."
        case .writeFailed(let url): return "Failed to write: \(url.lastPathComponent)"
        case .internalSanityFailed(let m): return "Internal export sanity check failed: \(m)"
        }
    }
}

// MARK: - Tiny PNG chunk parser (IHDR / PLTE / tRNS)

private struct PNGMeta {
    let width: Int
    let height: Int
    let bitDepth: Int          // 1,2,4,8 expected for colorType 3
    let colorType: Int         // must be 3 (indexed)
    let interlaceMethod: Int   // 0 or 1
    let paletteRGB: [UInt8]    // PLTE bytes: r,g,b triplets
    let trnsAlpha: [UInt8]?    // optional: per-entry alpha (0..255), length ≤ palette count
}

@inline(__always)
private func readU32BE(_ d: Data, _ ofs: Int) throws -> UInt32 {
    guard ofs + 4 <= d.count else { throw TMXExportError.pngParseFailed("EOF reading U32 @\(ofs)") }
    return (UInt32(d[ofs]) << 24) | (UInt32(d[ofs + 1]) << 16) | (UInt32(d[ofs + 2]) << 8) | UInt32(d[ofs + 3])
}

private func parsePNGMeta(_ data: Data) throws -> PNGMeta {
    // PNG signature
    let sig: [UInt8] = [137,80,78,71,13,10,26,10]
    guard data.count >= 8, Array(data[0..<8]) == sig else {
        throw TMXExportError.pngParseFailed("Bad signature")
    }

    // Chunk tags
    let IHDR: [UInt8] = [73,72,68,82]
    let PLTE: [UInt8] = [80,76,84,69]
    let tRNS: [UInt8] = [116,82,78,83]
    let IEND: [UInt8] = [73,69,78,68]

    var pos = 8
    var width = 0, height = 0
    var bitDepth = 0, colorType = -1, interlaceMethod = 0
    var palette: [UInt8] = []
    var alpha: [UInt8]? = nil

    while pos + 8 <= data.count {
        let length = Int(try readU32BE(data, pos)); pos += 4
        guard pos + 4 <= data.count else { throw TMXExportError.pngParseFailed("Truncated chunk type") }
        let type = data[pos..<(pos+4)]; pos += 4
        guard pos + length + 4 <= data.count else { throw TMXExportError.pngParseFailed("Truncated chunk payload") }
        let payload = data[pos..<(pos+length)]; pos += length
        _ = try readU32BE(data, pos) // CRC (ignored)
        pos += 4

        if type.elementsEqual(IHDR) {
            guard length == 13 else { throw TMXExportError.pngParseFailed("IHDR length != 13") }
            let ih = Data(payload)
            width  = Int(try readU32BE(ih, 0))
            height = Int(try readU32BE(ih, 4))
            bitDepth = Int(ih[8])
            colorType = Int(ih[9])            // must be 3
            interlaceMethod = Int(ih[12])     // 0 = none, 1 = Adam7
        } else if type.elementsEqual(PLTE) {
            palette = Array(payload)          // r,g,b triples
        } else if type.elementsEqual(tRNS) {
            alpha = Array(payload)            // ≤ palette count entries
        } else if type.elementsEqual(IEND) {
            break
        } else {
            // ignore other chunks
        }
    }

    guard width > 0, height > 0 else { throw TMXExportError.pngParseFailed("Missing IHDR") }
    guard colorType == 3 else { throw TMXExportError.notIndexedPNG }
    guard [1,2,4,8].contains(bitDepth) else { throw TMXExportError.pngParseFailed("Unsupported bit depth \(bitDepth)") }
    guard !palette.isEmpty, palette.count % 3 == 0 else { throw TMXExportError.pngParseFailed("Missing/bad PLTE") }

    return PNGMeta(width: width,
                   height: height,
                   bitDepth: bitDepth,
                   colorType: colorType,
                   interlaceMethod: interlaceMethod,
                   paletteRGB: palette,
                   trnsAlpha: alpha)
}

// MARK: - Main exporter

struct TiledExporter {
    struct Options {
        var tileSize: Int = 8
        var tilesetColumns: Int? = nil
        var tiledVersion: String = "1.10.2"
        /// Which palette index should be considered "transparent" in Tiled (for <image trans="RRGGBB">).
        var assumedTransparentIndex: Int = 0
    }

    static func exportTMX(from file: FileState,
                          to directory: URL,
                          baseName: String,
                          options: Options = Options()) throws -> TMXExportResult
    {
        // 1) Get the original PNG bytes (from fileURL or preserved project bytes).
        guard file.image != nil else { throw TMXExportError.noImage }

        let pngData: Data
        if let url = file.fileURL,
           url.pathExtension.lowercased() == "png",
           let d = try? Data(contentsOf: url) {
            pngData = d
        } else if let d = file.originalPNGData {
            pngData = d
        } else {
            throw TMXExportError.noPNGSource
        }

        // 2) Parse lightweight PNG metadata (no zlib / no IDAT inflate).
        let meta = try parsePNGMeta(pngData)
        let w = meta.width, h = meta.height
        let ts = max(1, options.tileSize)

        guard w % ts == 0, h % ts == 0 else { throw TMXExportError.notMultipleOfTileSize }
        let mapCols = w / ts
        let mapRows = h / ts

        // 3) Decode the image via ImageIO.
        guard let src = CGImageSourceCreateWithData(pngData as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw TMXExportError.imageCreateFailed
        }

        // 4) Obtain per-pixel **palette indices** (width*height, 0..N-1).
        let indices8: [UInt8] = try extractIndices(from: cg,
                                                   expectedWidth: w,
                                                   expectedHeight: h,
                                                   bitDepth: meta.bitDepth,
                                                   paletteRGB: meta.paletteRGB,
                                                   trnsAlpha: meta.trnsAlpha)

        // 5) Deduplicate tiles based on index bytes.
        let tileIndexByteCount = ts * ts
        var tileIdGrid = Array(repeating: Array(repeating: 0, count: mapCols), count: mapRows)
        var dedup: [Data: Int] = [:]
        var uniqueTiles: [Data] = []

        func tileData(at tx: Int, _ ty: Int) -> Data {
            var out = Data(count: tileIndexByteCount)
            indices8.withUnsafeBytes { srcRaw in
                guard let src = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                out.withUnsafeMutableBytes { dstRaw in
                    guard let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    var p = 0
                    let x0 = tx * ts, y0 = ty * ts
                    for yy in 0..<ts {
                        let rowStart = (y0 + yy) * w + x0
                        memcpy(dst + p, src + rowStart, ts)
                        p += ts
                    }
                }
            }
            return out
        }

        for ty in 0..<mapRows {
            for tx in 0..<mapCols {
                let bytes = tileData(at: tx, ty)
                if let id = dedup[bytes] {
                    tileIdGrid[ty][tx] = id
                } else {
                    let newId = uniqueTiles.count
                    dedup[bytes] = newId
                    uniqueTiles.append(bytes)
                    tileIdGrid[ty][tx] = newId
                }
            }
        }
        let uniqueCount = uniqueTiles.count

        // 6) Build tileset atlas (still 8-bit indices in memory).
        let atlasColumns: Int = {
            if let c = options.tilesetColumns, c > 0 { return c }
            let sq = Int(ceil(sqrt(Double(uniqueCount))))
            return max(1, sq)
        }()
        let atlasRows = Int(ceil(Double(uniqueCount) / Double(atlasColumns)))
        let atlasW = atlasColumns * ts
        let atlasH = atlasRows * ts

        var atlasIndexData = Data(count: atlasW * atlasH)
        atlasIndexData.withUnsafeMutableBytes { dstRaw in
            guard let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for i in 0..<uniqueCount {
                let ax = (i % atlasColumns) * ts
                let ay = (i / atlasColumns) * ts
                uniqueTiles[i].withUnsafeBytes { srcRaw in
                    guard let src = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    for y in 0..<ts {
                        let dstRow = (ay + y) * atlasW
                        memcpy(dst + dstRow + ax, src + y * ts, ts)
                    }
                }
            }
        }

        // 7) Recreate an **indexed** CGImage using the original palette.
        let paletteCount = meta.paletteRGB.count / 3
        let baseSpace = CGColorSpaceCreateDeviceRGB()
        let indexedCS: CGColorSpace = meta.paletteRGB.withUnsafeBufferPointer { buf in
            guard let pBase = buf.baseAddress,
                  let cs = CGColorSpace(indexedBaseSpace: baseSpace, last: paletteCount - 1, colorTable: pBase) else {
                return CGColorSpaceCreateDeviceRGB() // dummy; we’ll error below
            }
            return cs
        }
        guard indexedCS.model == .indexed else { throw TMXExportError.cannotCreateIndexedColorSpace }

        let provider = CGDataProvider(data: atlasIndexData as CFData)!
        guard let atlasIndexed = CGImage(width: atlasW,
                                         height: atlasH,
                                         bitsPerComponent: 8,
                                         bitsPerPixel: 8,
                                         bytesPerRow: atlasW,
                                         space: indexedCS,
                                         bitmapInfo: CGBitmapInfo(rawValue: 0),
                                         provider: provider,
                                         decode: nil,
                                         shouldInterpolate: false,
                                         intent: .defaultIntent)
        else {
            throw TMXExportError.cannotCreateIndexedImage
        }

        // 8) File URLs
        let mapURL = directory.appendingPathComponent("\(baseName).tmx")
        let tilesetImageURL = directory.appendingPathComponent("\(baseName)_tiles.png")
        let tilesetURL = directory.appendingPathComponent("\(baseName)_tileset.tsx")

        // 9) Write PNG tileset (indexed). We do NOT attempt to embed tRNS here;
        //    instead the TSX will use <image trans="RRGGBB"> for Tiled compatibility.
        try writePNG(cgImage: atlasIndexed, to: tilesetImageURL)

        // 10) Build GIDs array (row-major), 32-bit little-endian, base64 encode.
        //     firstgid = 1 (we only write one external tileset).
        var gidsLE = Data(capacity: mapRows * mapCols * 4)
        var maxGID: Int = 0
        for r in 0..<mapRows {
            for c in 0..<mapCols {
                let gid = tileIdGrid[r][c] + 1 // 1-based GID
                if gid > maxGID { maxGID = gid }
                var v = UInt32(gid).littleEndian
                withUnsafeBytes(of: &v) { gidsLE.append(contentsOf: $0) }
            }
        }
        // Sanity: exact number of entries?
        let total = gidsLE.count / 4
        guard total == mapRows * mapCols else {
            throw TMXExportError.internalSanityFailed("GID count \(total) != \(mapRows * mapCols)")
        }
        let base64 = gidsLE.base64EncodedString()

        // 11) Transparent color (from chosen palette index)
        let tIndex = max(0, min(options.assumedTransparentIndex, paletteCount - 1))
        let tr = meta.paletteRGB[tIndex * 3 + 0]
        let tg = meta.paletteRGB[tIndex * 3 + 1]
        let tb = meta.paletteRGB[tIndex * 3 + 2]
        // Tiled’s TSX uses <image trans="RRGGBB"> (no #).
        let transHex = String(format: "%02X%02X%02X", tr, tg, tb)

        // 12) TSX (external tileset referencing the PNG)
        let tsx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tileset version="1.10" tiledversion="\(options.tiledVersion)" name="\(baseName)_tileset" tilewidth="\(ts)" tileheight="\(ts)" tilecount="\(uniqueCount)" columns="\(atlasColumns)">
          <image source="\(tilesetImageURL.lastPathComponent)" width="\(atlasW)" height="\(atlasH)" trans="\(transHex)"/>
        </tileset>
        """
        try tsx.data(using: .utf8)!.write(to: tilesetURL)

        // 13) TMX map (base64 layer data)
        let tmx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <map version="1.10" tiledversion="\(options.tiledVersion)" orientation="orthogonal" renderorder="right-down" width="\(mapCols)" height="\(mapRows)" tilewidth="\(ts)" tileheight="\(ts)" infinite="0">
          <tileset firstgid="1" source="\(tilesetURL.lastPathComponent)"/>
          <layer id="1" name="Tile Layer 1" width="\(mapCols)" height="\(mapRows)">
            <data encoding="base64">
        \(base64)
            </data>
          </layer>
        </map>
        """
        try tmx.data(using: .utf8)!.write(to: mapURL)

        // Optional: sanity—highest GID must be within tileset range
        // tileset covers GIDs [1, uniqueCount]
        guard maxGID <= uniqueCount else {
            throw TMXExportError.internalSanityFailed("Max GID \(maxGID) exceeds tileset tilecount \(uniqueCount)")
        }

        return TMXExportResult(mapURL: mapURL,
                               tilesetURL: tilesetURL,
                               tilesetImageURL: tilesetImageURL,
                               uniqueTileCount: uniqueCount)
    }

    // MARK: - Pixel extraction helpers

    /// Returns width*height indices (0..paletteCount-1) for an indexed PNG.
    /// Fast path: use CGImage’s indexed provider bytes if available.
    /// Fallback path: map RGBA back to indices using the palette (+ tRNS).
    private static func extractIndices(from cg: CGImage,
                                       expectedWidth w: Int,
                                       expectedHeight h: Int,
                                       bitDepth: Int,
                                       paletteRGB: [UInt8],
                                       trnsAlpha: [UInt8]?) throws -> [UInt8] {

        if let cs = cg.colorSpace, cs.model == .indexed {
            // ImageIO kept the image **indexed**. Great: provider data contains packed indices.
            guard cg.width == w, cg.height == h else { throw TMXExportError.cannotReadPixelData }
            guard let cfData = cg.dataProvider?.data as Data? else { throw TMXExportError.cannotReadPixelData }

            let bytesPerRow = cg.bytesPerRow
            var out = [UInt8](repeating: 0, count: w * h)

            switch bitDepth {
            case 8:
                // 1 byte per pixel
                for y in 0..<h {
                    let row = cfData.withUnsafeBytes { raw -> UnsafePointer<UInt8> in
                        raw.baseAddress!.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                    }
                    out.withUnsafeMutableBytes { dstRaw in
                        let dst = dstRaw.baseAddress!.advanced(by: y * w).assumingMemoryBound(to: UInt8.self)
                        memcpy(dst, row, w)
                    }
                }

            case 4, 2, 1:
                // Packed bits, MSB first per PNG spec
                for y in 0..<h {
                    let srcRow = cfData.withUnsafeBytes { raw -> UnsafePointer<UInt8> in
                        raw.baseAddress!.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                    }
                    var x = 0
                    var byteIndex = 0
                    while x < w {
                        let b = srcRow[byteIndex]
                        byteIndex += 1
                        switch bitDepth {
                        case 4:
                            let hi = (b & 0xF0) >> 4
                            let lo = (b & 0x0F)
                            if x < w { out[y * w + x] = hi; x += 1 }
                            if x < w { out[y * w + x] = lo; x += 1 }
                        case 2:
                            let vals: [UInt8] = [(b >> 6) & 0x03, (b >> 4) & 0x03, (b >> 2) & 0x03, b & 0x03]
                            for v in vals where x < w { out[y * w + x] = v; x += 1 }
                        case 1:
                            for s in (0..<8).reversed() where x < w {
                                out[y * w + x] = (b >> s) & 0x01
                                x += 1
                            }
                        default: break
                        }
                    }
                }

            default:
                throw TMXExportError.pngParseFailed("Unsupported indexed bit depth \(bitDepth)")
            }
            return out
        }

        // Fallback: ImageIO decoded to RGBA/BGRA. Draw into a known RGBA8 premultiplied buffer,
        // then map back to indices using the palette. For alpha == 0, choose a transparent index.
        guard let ctx = CGContext(data: nil,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw TMXExportError.cannotReadPixelData }

        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let buf = ctx.data?.assumingMemoryBound(to: UInt8.self) else {
            throw TMXExportError.cannotReadPixelData
        }

        // Build palette lookups
        let count = paletteRGB.count / 3
        var alphaTable = [UInt8](repeating: 255, count: count)
        if let a = trnsAlpha {
            for i in 0..<min(count, a.count) { alphaTable[i] = a[i] }
        }

        // Preferred transparent index: either the provided one (if alpha==0), else first alpha==0
        let preferredTransparentIndex: Int = {
            let idx = max(0, min(count - 1, 0))
            if alphaTable[idx] == 0 { return idx }
            if let firstZero = alphaTable.firstIndex(of: 0) { return firstZero }
            return 0
        }()

        // Create RGB -> index map (no alpha) and RGBA -> index for alpha==255
        var rgbToIndex: [UInt32: Int] = [:]      // key = 0xRRGGBB
        var rgbaToIndex: [UInt32: Int] = [:]     // key = 0xRRGGBBAA
        for i in 0..<count {
            let r = UInt32(paletteRGB[i * 3 + 0])
            let g = UInt32(paletteRGB[i * 3 + 1])
            let b = UInt32(paletteRGB[i * 3 + 2])
            let a = UInt32(alphaTable[i])
            let rgbKey = (r << 16) | (g << 8) | b
            if rgbToIndex[rgbKey] == nil { rgbToIndex[rgbKey] = i }
            let rgbaKey = (rgbKey << 8) | a
            if rgbaToIndex[rgbaKey] == nil { rgbaToIndex[rgbaKey] = i }
        }

        var out = [UInt8](repeating: 0, count: w * h)

        for y in 0..<h {
            let row = buf + y * w * 4
            for x in 0..<w {
                let p = row + x * 4
                let r = UInt32(p[0]), g = UInt32(p[1]), b = UInt32(p[2]), a = UInt32(p[3])

                let idx: Int
                if a == 0 {
                    idx = preferredTransparentIndex
                } else if a == 255 {
                    let key: UInt32 = (r << 16) | (g << 8) | b
                    if let found = rgbToIndex[key] { idx = found }
                    else { throw TMXExportError.cannotMapRGBAtoIndices(x: x, y: y) }
                } else {
                    // Un-premultiply to estimate original palette color.
                    let rr = UInt32(min(255, Int((Double(r) * 255.0 / Double(a)).rounded())))
                    let gg = UInt32(min(255, Int((Double(g) * 255.0 / Double(a)).rounded())))
                    let bb = UInt32(min(255, Int((Double(b) * 255.0 / Double(a)).rounded())))
                    let rgbaKey = ((rr << 16) | (gg << 8) | bb) << 8 | a
                    if let found = rgbaToIndex[rgbaKey] {
                        idx = found
                    } else {
                        let rgbKey = (rr << 16) | (gg << 8) | bb
                        if let cand = rgbToIndex[rgbKey], alphaTable[cand] == a {
                            idx = cand
                        } else {
                            throw TMXExportError.cannotMapRGBAtoIndices(x: x, y: y)
                        }
                    }
                }
                out[y * w + x] = UInt8(idx)
            }
        }

        return out
    }

    // MARK: - PNG writer

    private static func writePNG(cgImage: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw TMXExportError.writeFailed(url)
        }
        // No properties → keep it indexed as provided by the CGImage
        CGImageDestinationAddImage(dest, cgImage, nil)
        if !CGImageDestinationFinalize(dest) {
            throw TMXExportError.writeFailed(url)
        }
    }
}

// MARK: - Small pointer helper (to mimic pointer arithmetic succinctly)

private func +(ptr: UnsafePointer<UInt8>, _ offset: Int) -> UnsafePointer<UInt8> {
    return ptr.advanced(by: offset)
}
