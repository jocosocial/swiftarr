import CryptoKit
import Foundation

/// Helper for random crypto related stuff.
final class CryptoHelper {
	/// Hash a String. ChatGPT wrote this.
	///
	static func sha256Hash(of string: String) -> String {
		let data = Data(string.utf8)
		let sha256Digest = SHA256.hash(data: data)
		let sha256Hex = sha256Digest.map { String(format: "%02hhx", $0) }.joined()
		return sha256Hex
	}
}
