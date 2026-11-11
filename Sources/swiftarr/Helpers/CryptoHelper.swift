import Crypto
import Foundation
import Vapor

/// Helper for random crypto related stuff.
final class CryptoHelper {
	/// Bcrypt work factor for user passwords. `configureMiddleware` installs it as the app's password hasher.
	static let bcryptCost = 9

	/// Bcrypt hash of a random throwaway value, at `bcryptCost`. When an account lookup fails, verify the submitted
	/// secret against this anyway, so the response takes about as long as it would for a real account.
	static let dummyPasswordHash: String = try! Bcrypt.hash(UUID().uuidString, cost: bcryptCost)

	/// Burns one bcrypt verification's worth of time. The result is always discarded.
	static func dummyPasswordVerify(_ secret: String, on req: Request) async {
		_ = try? await req.password.async.verify(secret, created: dummyPasswordHash)
	}

	/// Bcrypt work factor for recovery keys. Higher than `bcryptCost` because a 3-word recovery key has far less
	/// entropy than a typical password, and recovery keys are hashed and verified rarely enough that the cost is cheap.
	static let recoveryKeyBcryptCost = 12

	/// Bcrypt hash of a random throwaway value, at `recoveryKeyBcryptCost`. See `dummyPasswordHash`.
	static let dummyRecoveryKeyHash: String = try! Bcrypt.hash(UUID().uuidString, cost: recoveryKeyBcryptCost)

	/// Hashes a normalized recovery key at `recoveryKeyBcryptCost` on the thread pool, off the event loop.
	static func hashRecoveryKey(_ normalizedKey: String, on req: Request) async throws -> String {
		return try await req.application.threadPool.runIfActive {
			try Bcrypt.hash(normalizedKey, cost: recoveryKeyBcryptCost)
		}
	}

	/// Burns one recovery-key verification's worth of time. The result is always discarded.
	static func dummyRecoveryKeyVerify(_ secret: String, on req: Request) async {
		_ = try? await req.password.async.verify(secret, created: dummyRecoveryKeyHash)
	}

	/// Hash a String. ChatGPT wrote this.
	///
	static func sha256Hash(of string: String) -> String {
		let data = Data(string.utf8)
		let sha256Digest = SHA256.hash(data: data)
		let sha256Hex = sha256Digest.map { String(format: "%02hhx", $0) }.joined()
		return sha256Hex
	}
}
