import Vapor

/// Limits brute-force guessing against login, password change, password recovery, username lookup, and account creation.
///
/// Each guessable thing (a client IP, a username, a registration code) gets a bucket in `AuthRateLimitStore`. Handlers call
/// `reserve` before checking credentials, which counts the attempt up front so that concurrent requests can't race past the
/// limit, then call `Reservation.refund` once the credentials check out. So in effect only failures count. Going over a bucket's limit locks it for
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
				await req.application.authRateLimitStore.refund(key)
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
			let (wait, lockedAtCount) = await req.application.authRateLimitStore.reserve(
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
	static func clearAllLockouts(on req: Request) async -> Int {
		return await req.application.authRateLimitStore.clearLocked()
	}

	/// Clears the counts and lockouts for these buckets. Used when staff unlock an account.
	static func clear(_ buckets: [Bucket], on req: Request) async {
		for bucket in buckets {
			await req.application.authRateLimitStore.clear(bucket.key)
		}
	}
}

/// Attempt counts and lockouts for `AuthRateLimiter`, kept in memory. Swiftarr runs as a single instance (`UserCache` relies
/// on this too), so there's no need to share this state through Redis. A restart clears every count and lockout.
///
/// Being an actor, each call runs to completion before the next one starts, so concurrent requests each see the count left by
/// the one before.
actor AuthRateLimitStore {
	private struct Bucket {
		/// Attempts counted in the current window. Reset when the bucket locks.
		var count = 0
		var windowEnds = Date.distantPast
		var lockedUntil = Date.distantPast
		/// Lockouts within the last day; each one lasts twice as long as the previous one.
		var strikes = 0
		var strikesExpire = Date.distantPast

		/// Resets whatever has expired. Returns false if nothing is left worth keeping.
		mutating func expire(at now: Date) -> Bool {
			if windowEnds <= now {
				count = 0
			}
			if strikesExpire <= now {
				strikes = 0
			}
			return count > 0 || strikes > 0 || lockedUntil > now
		}
	}

	static let strikeMemory: TimeInterval = 24 * 60 * 60
	static let sweepInterval: TimeInterval = 5 * 60

	private var buckets: [String: Bucket] = [:]
	private var nextSweep = Date.distantPast
	private let now: @Sendable () -> Date

	/// `now` is for tests that need to move the clock.
	init(now: @escaping @Sendable () -> Date = { Date() }) {
		self.now = now
	}

	/// Counts one attempt against `key`. Going over `limit` attempts within `window` seconds locks the bucket.
	/// Returns `wait`: 0 if the attempt may proceed, else the number of seconds the caller must wait. `lockedAtCount` is the
	/// attempt count if this attempt is the one that locked the bucket, nil otherwise (including attempts against an already
	/// locked bucket).
	func reserve(
		_ key: String,
		limit: Int,
		window: Int,
		baseLockout: Int,
		maxLockout: Int
	) -> (wait: Int, lockedAtCount: Int?) {
		let now = now()
		sweep(at: now)
		var bucket = buckets[key] ?? Bucket()
		_ = bucket.expire(at: now)
		defer { buckets[key] = bucket }
		if bucket.lockedUntil > now {
			return (Int(bucket.lockedUntil.timeIntervalSince(now).rounded(.up)), nil)
		}
		if bucket.count == 0 {
			bucket.windowEnds = now.addingTimeInterval(TimeInterval(window))
		}
		bucket.count += 1
		guard bucket.count > limit else {
			return (0, nil)
		}
		let lockedAtCount = bucket.count
		bucket.strikes += 1
		bucket.strikesExpire = now.addingTimeInterval(Self.strikeMemory)
		// Cap the exponent too, so the shift can't overflow however many strikes pile up.
		let lockout = min(baseLockout << min(bucket.strikes - 1, 30), maxLockout)
		bucket.lockedUntil = now.addingTimeInterval(TimeInterval(lockout))
		bucket.count = 0
		return (lockout, lockedAtCount)
	}

	/// Takes back one attempt counted by `reserve`, so that successful attempts don't count toward the limit.
	func refund(_ key: String) {
		guard var bucket = buckets[key] else {
			return
		}
		let now = now()
		_ = bucket.expire(at: now)
		if bucket.count > 0 {
			bucket.count -= 1
		}
		buckets[key] = bucket.expire(at: now) ? bucket : nil
	}

	/// Clears a bucket's attempt count, lockout, and lockout history.
	func clear(_ key: String) {
		buckets[key] = nil
	}

	/// Clears every bucket that is currently locked out, including its lockout history. Buckets that are counting attempts
	/// but aren't locked are left alone. Returns the number of lockouts cleared.
	func clearLocked() -> Int {
		let now = now()
		let locked = buckets.filter { $0.value.lockedUntil > now }.keys
		for key in locked {
			buckets[key] = nil
		}
		return locked.count
	}

	/// The attempts currently counted against `key`, for tests.
	func count(_ key: String) -> Int {
		guard var bucket = buckets[key] else {
			return 0
		}
		_ = bucket.expire(at: now())
		return bucket.count
	}

	/// Drops buckets with nothing left in them, every few minutes, so that guesses at many different usernames don't pile up.
	private func sweep(at now: Date) {
		guard now >= nextSweep else {
			return
		}
		nextSweep = now.addingTimeInterval(Self.sweepInterval)
		buckets = buckets.filter { _, bucket in
			var bucket = bucket
			return bucket.expire(at: now)
		}
	}
}

extension Application {
	private struct AuthRateLimitStoreKey: StorageKey, LockKey {
		typealias Value = AuthRateLimitStore
	}

	/// This app's `AuthRateLimitStore`, created on first use.
	var authRateLimitStore: AuthRateLimitStore {
		locks.lock(for: AuthRateLimitStoreKey.self).withLock {
			if let store = storage[AuthRateLimitStoreKey.self] {
				return store
			}
			let store = AuthRateLimitStore()
			storage[AuthRateLimitStoreKey.self] = store
			return store
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
