import Foundation
import Vapor

/// Generate a QR code PNG for a URL, in Twitarr style by default.
///
/// Handy for making posters and handouts that point at the server or at a page on it, for example the Client Apps
/// page. The styled output has the outer corners of each connected shape of blocks rounded and an "ARR" icon in the
/// center; both can be turned off.
struct GenerateQRCodeCommand: AsyncCommand {
	struct Signature: CommandSignature {
		@Argument(name: "url", help: "The URL (or any text) to encode in the QR code.")
		var url: String

		@Option(name: "output", short: "o", help: "Where to write the PNG. If omitted, a new file in the system temp directory is used. The path is printed either way.")
		var output: String?

		@Flag(name: "no-rounded", help: "Draw plain square blocks instead of rounding the corners of connected shapes.")
		var noRounded: Bool

		@Flag(name: "no-icon", help: "Don't put the ARR icon in the center of the code.")
		var noIcon: Bool

		init() {}
	}

	var help: String {
		"""
		Generates a QR code PNG for a URL. By default the code is drawn with rounded shapes and an "ARR" icon in the \
		center. Use --no-rounded and --no-icon for a plain code. The icon is skipped, with a warning, if the code is \
		too small or too dense to give up its center. Writes to --output, or to a new temp file if none is given, and \
		prints the path of the file written.
		"""
	}

	func run(using context: CommandContext, signature: Signature) async throws {
		let text = signature.url.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else {
			throw Abort(.badRequest, reason: "A non-empty url is required.")
		}
		var destination: URL
		if let output = signature.output {
			destination = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
			var isDirectory: ObjCBool = false
			if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue {
				throw Abort(.badRequest, reason: "Output path \(destination.path) is a directory; specify a file name.")
			}
		}
		else {
			destination = FileManager.default.temporaryDirectory.appendingPathComponent("swiftarr-qr-\(UUID().uuidString).png")
		}

		let renderer = QRCodeRenderer(rounded: !signature.noRounded, icon: !signature.noIcon)
		let result = try renderer.render(text)
		if !signature.noIcon, !result.iconApplied {
			context.console.warning("This code is too small or too dense for the icon, so it was left out.")
		}
		try result.png.write(to: destination, options: .atomic)
		context.console.print(destination.path)
	}
}
