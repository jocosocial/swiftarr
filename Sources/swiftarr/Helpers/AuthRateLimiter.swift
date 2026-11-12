import Vapor

/// Limits brute-force guessing against login, password change, password recovery, username lookup, and account creation.
///
/// Each guessable thing (a client IP, a username, a registration code) gets a bucket in Redis. Handlers call `reserve` before
/// checking credentials, which counts the attempt up front so that concurrent requests can't race past the limit, then call
/// `Reservation.refund` once the credentials check out. So in effect only failures count. Going over a bucket's limit locks it for
/// 15 minutes, doubling with each further lockout within a day, up to 24 hours. Locked callers get a 429 with a `Retry-After` header.
///
/// Buckets are keyed on the submitted username or code, not on whether it exists, so a lockout doesn't reveal which accounts exist.
///
/// `Settings.authRateLimitEnabled` turns all of this off; each limit in `Settings` can also be set to 0 to disable just that limit.
struct AuthRateLimiter {
	/// A counter for one thing an attacker might guess against, with its own limit and counting window.
	struct Bucket {
		let key: String
		let limit: Int
		/// Seconds
		let window: Int

		/// Every kind of failed attempt from one client IP.
		static func clientIP(_ ip: String) -> Bucket {
			Bucket(key: "ip:\(ip)", limit: Settings.shared.authRateLimitIPFailures, window: 15 * 60)
		}

		/// Failed logins and password changes for one username from one client IP.
		static func usernameAndIP(_ username: String, _ ip: String) -> Bucket {
			Bucket(
				key: "login-uip:\(username.lowercased())|\(ip)",
				limit: Settings.shared.authRateLimitLoginFailures,
				window: 15 * 60
			)
		}

		/// Failed logins and password changes for one username from all client IPs.
		static func username(_ username: String) -> Bucket {
			Bucket(
				key: "login-u:\(username.lowercased())",
				limit: Settings.shared.authRateLimitUsernameFailures,
				window: 60 * 60
			)
		}

		/// Failed password recoveries for one username.
		static func recovery(_ username: String) -> Bucket {
			Bucket(
				key: "recovery:\(username.lowercased())",
				limit: Settings.shared.authRateLimitRecoveryFailures,
				window: 60 * 60
			)
		}

		/// Failed username lookups for one registration code.
		static func usernameLookup(_ registrationCode: String) -> Bucket {
			Bucket(
				key: "lookup:\(RegistrationCode.normalized(registrationCode))",
				limit: Settings.shared.authRateLimitRecoveryFailures,
				window: 60 * 60
			)
		}

		/// The buckets for a login or password change attempt.
		static func login(_ username: String, ip: String) -> [Bucket] {
			[.clientIP(ip), .usernameAndIP(username, ip), .username(username)]
		}
	}

	/// Attempts counted by `reserve`. Call `refund` once the attempt succeeds.
	struct Reservation {
		fileprivate let keys: [String]

		func refund(on req: Request) async {
			for key in keys {
				try? await req.redis.refundAuthAttempt(key)
			}
		}
	}

	static let baseLockout = 15 * 60
	static let maxLockout = 24 * 60 * 60

	/// Counts an attempt against each bucket, in order. Throws a 429 if any bucket is locked or goes over its limit; buckets after
	/// that one aren't touched. List the client IP bucket first, so that a locked-out IP can't run up the counts on accounts.
	static func reserve(_ buckets: [Bucket], on req: Request) async throws -> Reservation {
		guard Settings.shared.authRateLimitEnabled else {
			return Reservation(keys: [])
		}
		var reserved: [String] = []
		for bucket in buckets where bucket.limit > 0 {
			let (wait, lockedAtCount) = try await req.redis.reserveAuthAttempt(
				bucket.key,
				limit: bucket.limit,
				window: bucket.window,
				baseLockout: baseLockout,
				maxLockout: maxLockout
			)
			// Log only the attempt that triggers the lockout, not the attempts rejected while it lasts.
			if let count = lockedAtCount {
				req.logger.warning(
					"Auth rate limit hit for \(bucket.key): \(count) attempts, limit \(bucket.limit) per \(bucket.window / 60) minutes. Locked out for \(wait) seconds."
				)
			}
			guard wait <= 0 else {
				let minutes = max(1, (wait + 59) / 60)
				throw Abort(
					.tooManyRequests,
					headers: ["Retry-After": "\(wait)"],
					reason: "Too many failed attempts. Try again in \(minutes) minute\(minutes == 1 ? "" : "s")."
				)
			}
			reserved.append(bucket.key)
		}
		return Reservation(keys: reserved)
	}

	/// Clears every current lockout, for every kind of bucket. Returns the number of lockouts cleared.
	static func clearAllLockouts(on req: Request) async throws -> Int {
		return try await req.redis.clearLockedAuthRateLimits()
	}

	/// Clears the counts and lockouts for these buckets. Used when staff unlock an account.
	static func clear(_ buckets: [Bucket], on req: Request) async throws {
		for bucket in buckets {
			try await req.redis.clearAuthRateLimit(bucket.key)
		}
	}
}

extension Request {
	/// The client's IP address, for rate limiting.
	///
	/// In production, Traefik replaces any client-supplied `X-Forwarded-For` with the address it received the request from, and
	/// the web UI's `apiQuery` passes that address along on its loopback API calls. So the rightmost `X-Forwarded-For` entry is
	/// the client. This relies on Traefik not being configured to trust forwarded headers from clients (`forwardedHeaders`), and
	/// on Swiftarr's port not being reachable except through Traefik.
	var rateLimitClientIP: String {
		if let forwarded = headers[.xForwardedFor].last?.split(separator: ",").last {
			let address = forwarded.trimmingCharacters(in: .whitespaces)
			if !address.isEmpty {
				return address
			}
		}
		return remoteAddress?.ipAddress ?? "unknown"
	}
}
