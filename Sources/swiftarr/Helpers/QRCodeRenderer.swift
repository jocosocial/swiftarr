import Foundation
import QRCodeSwift

/// Renders a QR code as a PNG, optionally in Twitarr style: outer corners of each connected shape rounded, and an "ARR"
/// icon in the center built out of half-size blocks.
///
/// This rasterizes the image itself (via `SwiftarrImage` for PNG encoding) rather than using Core Graphics, because
/// Linux has no access to it.
///
/// Yes this was some vibe-coded nonsense. What gave it away?
struct QRCodeRenderer {
	/// Round the outer corners of each connected shape of blocks.
	var rounded = true
	/// Put the "ARR" icon in the middle of the code.
	var icon = true
	/// Pixels per QR module. Must be even, as the icon is built from half-size blocks.
	var moduleSize = 32
	/// Width of the blank border, in modules. The QR spec calls for 4.
	var quietZone = 4

	struct Output {
		var png: Data
		/// False if an icon was requested but the code was unsuitable for one (too small or too dense).
		var iconApplied: Bool
	}

	/// Codes smaller than this don't have enough redundancy to give up the center, and codes at or above `maxIconModules` have
	/// alignment patterns near the center that must not be erased. 29 is a version 3 code; 45 is version 7.
	static let minIconModules = 29
	static let maxIconModules = 45

	// 7x9 pixel font with 2-block strokes.
	private static let glyphA = [
		"..###..", ".##.##.", "##...##", "##...##", "#######", "#######", "##...##", "##...##", "##...##",
	]
	private static let glyphR = [
		"######.", "##...##", "##...##", "##...##", "######.", "##.##..", "##..##.", "##...##", "##...##",
	]
	private static let iconGlyphs = [glyphA, glyphR, glyphR]
	private static let iconWidth = 23  // 3 glyphs of 7 columns, with 1-column gaps
	private static let iconHeight = 9

	/// A grid of square blocks, rasterized with the outer corners of connected shapes optionally rounded.
	private struct BlockLayer {
		var cells: [[Bool]]
		var cellSize: Double
		var origin: Double
		var radius: Double
		var rounded: Bool

		private func lit(_ r: Int, _ c: Int) -> Bool {
			r >= 0 && c >= 0 && r < cells.count && c < cells.count && cells[r][c]
		}

		func covers(_ x: Double, _ y: Double) -> Bool {
			let fx = (x - origin) / cellSize
			let fy = (y - origin) / cellSize
			guard fx >= 0, fy >= 0 else { return false }
			let c = Int(fx), r = Int(fy)
			guard lit(r, c) else { return false }
			guard rounded else { return true }
			// Position within the block, in pixels.
			let u = (fx - Double(c)) * cellSize
			let v = (fy - Double(r)) * cellSize
			let far = cellSize - radius
			// A corner is rounded only when both neighbors that meet at it are empty (an outer corner of the shape).
			let cx: Double, cy: Double
			if u < radius, v < radius, !lit(r - 1, c), !lit(r, c - 1) {
				(cx, cy) = (radius, radius)
			}
			else if u > far, v < radius, !lit(r - 1, c), !lit(r, c + 1) {
				(cx, cy) = (far, radius)
			}
			else if u < radius, v > far, !lit(r + 1, c), !lit(r, c - 1) {
				(cx, cy) = (radius, far)
			}
			else if u > far, v > far, !lit(r + 1, c), !lit(r, c + 1) {
				(cx, cy) = (far, far)
			}
			else {
				return true
			}
			return (u - cx) * (u - cx) + (v - cy) * (v - cy) <= radius * radius
		}
	}

	/// Renders `text` as a PNG QR code.
	func render(_ text: String) throws -> Output {
		precondition(moduleSize > 0 && moduleSize % 2 == 0, "moduleSize must be a positive even number")
		let code = try QRCode(text, errorCorrectLevel: .H, withBorder: false)
		var modules = code.imageCodes
		let n = modules.count

		var iconCells: [[Bool]]?
		if icon, n >= Self.minIconModules, n < Self.maxIconModules {
			iconCells = Self.placeIcon(in: &modules)
		}

		let m = Double(moduleSize)
		var layers = [
			BlockLayer(cells: modules, cellSize: m, origin: Double(quietZone) * m, radius: m * 0.32, rounded: rounded)
		]
		if let iconCells {
			layers.append(
				BlockLayer(cells: iconCells, cellSize: m / 2, origin: Double(quietZone) * m, radius: m / 2 * 0.42, rounded: rounded)
			)
		}

		let size = (n + 2 * quietZone) * moduleSize
		var pixels = [UInt8](repeating: 0xFF, count: size * size * 3)
		func covers(_ x: Double, _ y: Double) -> Bool { layers.contains { $0.covers(x, y) } }
		for py in 0..<size {
			for px in 0..<size {
				let x = Double(px), y = Double(py)
				// Cheap test first: if the pixel's corners and center agree, no antialiasing is needed.
				let probe = [covers(x, y), covers(x + 1, y), covers(x, y + 1), covers(x + 1, y + 1), covers(x + 0.5, y + 0.5)]
				let coverage: Double
				if probe.allSatisfy({ $0 }) {
					coverage = 1
				}
				else if !probe.contains(true) {
					continue
				}
				else {
					var hits = 0
					for sy in 0..<4 {
						for sx in 0..<4 where covers(x + (Double(sx) + 0.5) / 4, y + (Double(sy) + 0.5) / 4) {
							hits += 1
						}
					}
					coverage = Double(hits) / 16
				}
				let value = UInt8((1 - coverage) * 255)
				let offset = (py * size + px) * 3
				pixels[offset] = value
				pixels[offset + 1] = value
				pixels[offset + 2] = value
			}
		}
		let png = try SwiftarrImage(width: size, height: size, pixels: pixels).exportAsPNG()
		return Output(png: png, iconApplied: iconCells != nil)
	}

	/// Clears the center of the module grid and returns the icon as a grid of half-size blocks (2n x 2n), centered on the code.
	private static func placeIcon(in modules: inout [[Bool]]) -> [[Bool]] {
		let n = modules.count
		let fineCount = n * 2
		var fine = [[Bool]](repeating: [Bool](repeating: false, count: fineCount), count: fineCount)
		let sx = fineCount / 2 - iconWidth / 2
		let sy = fineCount / 2 - iconHeight / 2
		for (index, glyph) in iconGlyphs.enumerated() {
			for (r, row) in glyph.enumerated() {
				for (c, ch) in row.enumerated() where ch == "#" {
					fine[sy + r][sx + index * 8 + c] = true
				}
			}
		}
		// Clear every module the icon touches, plus a 1-module margin. Never clear the timing patterns (row/column 6).
		for r in (sy / 2 - 1)...((sy + iconHeight - 1) / 2 + 1) {
			for c in (sx / 2 - 1)...((sx + iconWidth - 1) / 2 + 1) where r != 6 && c != 6 {
				modules[r][c] = false
			}
		}
		return fine
	}
}
