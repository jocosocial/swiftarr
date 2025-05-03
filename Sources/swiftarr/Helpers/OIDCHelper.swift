import Foundation
import ASN1Swift
import Vapor
@preconcurrency import JWT
import JOSE
import SwiftASN1

// We're using a regular actor without a global actor wrapper.

/// Actor that manages OIDC state
actor OIDCSignerActor {
	static let shared = OIDCSignerActor()
	
	// Static properties for JWKS and keys
	var jwkSet: JWKSet = JWKSet(keys: [])
	var signer: JWTSigners?
	var publicJWK: JWK?
	var rsaKey: RSAKey?
	
	// Methods to access the data
	func getJWKS() -> [String: [JWK]] {
		// Convert JOSE JWKSet to our custom JWK format
		let keys = jwkSet.keys.map { joseJWK -> JWK in
			// Extract RSA parameters if available
			let n = joseJWK.n?.base64URLEncodedString()
			let e = joseJWK.e?.base64URLEncodedString()
			
			return JWK(
				keyType: "RSA",
				use: "sig",
				keyID: joseJWK.keyID ?? "swiftarr-key-1",
				algorithm: "RS256",
				modulus: n,
				exponent: e
			)
		}
		return ["keys": keys]
	}
	
	func setJWKSet(_ newJWKSet: JWKSet) {
		jwkSet = newJWKSet
	}
	
	func setPublicJWK(_ jwk: JWK) {
		publicJWK = jwk
	}
	
	func setSigner(_ newSigner: JWTSigners) {
		signer = newSigner
	}
	
	func setRSAKey(_ key: RSAKey) {
		rsaKey = key
	}
	
	func sign<T: JWTPayload & Sendable>(_ payload: T) throws -> String {
		guard let signer = signer else {
			throw Abort(.internalServerError, reason: "JWT signer not initialized")
		}
		return try signer.sign(payload)
	}
}

/// Helper struct for OIDC operations
struct OIDCHelper {
	
	/// Generates a cryptographically secure random string using Base58 encoding
	/// This algorithm has a _slight_ bias towards the first 24 letters due to modulus, but it's well offset by the length of the string
	///
	/// - Parameter length: The desired length of the output string
	/// - Returns: A secure random string of the specified length
	static func generateSecureRandomString(length: Int) throws -> String {
		// Define the base58 alphabet
		let base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
		
		// Generate random bytes.
		var randomBytes = [UInt8](repeating: 0, count: length)
		let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
		
		guard status == errSecSuccess else {
			throw SecureRandomError.randomGenerationFailed
		}
		
		// Convert random bytes to Base58 string
		var result = ""
		for byte in randomBytes {
			let index = Int(byte) % base58Alphabet.count
			let character = base58Alphabet[base58Alphabet.index(base58Alphabet.startIndex, offsetBy: index)]
			result.append(character)
		}
		
		return result
	}
	
	/// Extract RSA modulus and exponent from a PEM-encoded public key
	/// - Parameter pemString: The PEM-encoded RSA public key
	/// - Returns: A tuple containing the modulus and exponent as Data objects
	static func extractRSAComponentsFromPEM(_ pemString: String) throws -> (modulus: Data, exponent: Data) {
		// Parse the PEM document to get DER bytes
		let pemDocument = try PEMDocument(pemString: pemString)
		let derBytes = pemDocument.derBytes
		
		let logger = Logger(label: "app.swiftarr.oidc.key")
		logger.debug("Parsing PEM-encoded public key with length \(derBytes.count) bytes")
		
		// RSA Public Key ASN.1 structure (when wrapped in PKCS#1):
		// RSAPublicKey ::= SEQUENCE {
		//    modulus           INTEGER,  -- n
		//    publicExponent    INTEGER   -- e
		// }
		
		// SubjectPublicKeyInfo ASN.1 structure (X.509 format):
		// SubjectPublicKeyInfo ::= SEQUENCE {
		//    algorithm        AlgorithmIdentifier,
		//    subjectPublicKey BIT STRING
		// }
		
		// AlgorithmIdentifier ::= SEQUENCE {
		//    algorithm        OBJECT IDENTIFIER,
		//    parameters       ANY DEFINED BY algorithm OPTIONAL
		// }
		
		// Direct manual byte-based parsing instead of using ASN1Swift's decoder
		do {
			let derData = Data(derBytes)
			var index = 0
			
			// Utility functions for ASN.1 parsing
			func readTag() throws -> UInt8 {
				guard index < derData.count else {
					throw ASN1Error.invalidASN1Structure
				}
				let tag = derData[index]
				index += 1
				return tag
			}
			
			func readLength() throws -> Int {
				guard index < derData.count else {
					throw ASN1Error.invalidASN1Structure
				}
				
				let firstByte = derData[index]
				index += 1
				
				if firstByte & 0x80 == 0 {
					// Short form
					return Int(firstByte)
				} else {
					// Long form
					let numBytes = Int(firstByte & 0x7F)
					guard index + numBytes <= derData.count, numBytes > 0 else {
						throw ASN1Error.invalidASN1Structure
					}
					
					var length = 0
					for i in 0..<numBytes {
						length = (length << 8) | Int(derData[index + i])
					}
					index += numBytes
					return length
				}
			}
			
			func skipValue(length: Int) throws {
				guard index + length <= derData.count else {
					throw ASN1Error.invalidASN1Structure
				}
				index += length
			}
			
			func readValue(length: Int) throws -> Data {
				guard index + length <= derData.count else {
					throw ASN1Error.invalidASN1Structure
				}
				let value = derData.subdata(in: index..<(index + length))
				index += length
				return value
			}
			
			// Begin parsing
			
			// Expect SEQUENCE for SubjectPublicKeyInfo
			let outerTag = try readTag()
			guard outerTag == 0x30 else { // SEQUENCE tag
				logger.error("Expected SEQUENCE tag at start of DER data, got \(outerTag)")
				throw ASN1Error.invalidASN1Structure
			}
			
			// Read sequence length
			let _ = try readLength()
			
			// Expect SEQUENCE for AlgorithmIdentifier
			let algoTag = try readTag()
			guard algoTag == 0x30 else { // SEQUENCE tag
				logger.error("Expected SEQUENCE tag for AlgorithmIdentifier, got \(algoTag)")
				throw ASN1Error.invalidASN1Structure
			}
			
			// Read algorithm identifier length and skip its contents
			let algoLength = try readLength()
			try skipValue(length: algoLength)
			
			// Expect BIT STRING for subjectPublicKey
			let keyTag = try readTag()
			guard keyTag == 0x03 else { // BIT STRING tag
				logger.error("Expected BIT STRING tag for subjectPublicKey, got \(keyTag)")
				throw ASN1Error.invalidASN1Structure
			}
			
			// Read bit string length (we don't use it but need to advance index)
			let _ = try readLength()
			
			// Skip unused bits byte (almost always 0)
			let unusedBits = try readTag()
			if unusedBits != 0 {
				logger.warning("Unexpected unused bits value: \(unusedBits)")
			}
			
			// The bit string contains the RSA key bytes
			// We need to parse another SEQUENCE within the bit string
			
			// Expect SEQUENCE for RSA key
			let rsaSequenceTag = try readTag()
			guard rsaSequenceTag == 0x30 else { // SEQUENCE tag
				logger.error("Expected SEQUENCE tag for RSA key, got \(rsaSequenceTag)")
				throw ASN1Error.invalidASN1Structure
			}
			
			// Read sequence length
			let _ = try readLength()
			
			// Read modulus INTEGER
			let modulusTag = try readTag()
			guard modulusTag == 0x02 else { // INTEGER tag
				logger.error("Expected INTEGER tag for modulus, got \(modulusTag)")
				throw ASN1Error.invalidASN1Structure
			}
			
			// Read modulus length and value
			let modulusLength = try readLength()
			var modulusData = try readValue(length: modulusLength)
			
			// Read exponent INTEGER
			let exponentTag = try readTag()
			guard exponentTag == 0x02 else { // INTEGER tag
				logger.error("Expected INTEGER tag for exponent, got \(exponentTag)")
				throw ASN1Error.invalidASN1Structure
			}
			
			// Read exponent length and value
			let exponentLength = try readLength()
			let exponentData = try readValue(length: exponentLength)
			
			// ASN.1 INTEGERs may have a leading zero byte for sign (since we know these are positive)
			if modulusData.count > 1 && modulusData[0] == 0 {
				modulusData = modulusData.dropFirst()
			}
			
			// Log the extracted values (truncated for security)
			if modulusData.count > 10 {
				let modulusPrefix = modulusData.prefix(5).hex
				let modulusSuffix = modulusData.suffix(5).hex
				logger.debug("Extracted modulus: \(modulusPrefix)...\(modulusSuffix) (\(modulusData.count) bytes)")
			}
			
			logger.debug("Extracted exponent: \(exponentData.hex) (\(exponentData.count) bytes)")
			
			return (modulusData, exponentData)
			
		} catch {
			logger.error("ASN.1 parsing error: \(error)")
			throw ASN1Error.invalidASN1Structure
		}
	}
	
	/// Access to JWKS data (via actor)
	static func getJWKS() async -> [String: [JWK]] {
		return await OIDCSignerActor.shared.getJWKS()
	}
	
	/// Initialize the OIDC helper with the RSA keys for signing JWTs
	static func initialize() async {
		// Get the key ID from environment or use default
		let keyID = Environment.get("SWIFTARR_JWT_KID") ?? "swiftarr-key-1"
		let logger = Logger(label: "app.swiftarr.oidc")
		
		// Check if private and public key file paths are provided
		guard let privateKeyPath = Environment.get("SWIFTARR_JWT_PRIVATE_KEY") else {
			logger.error("JWT private key path not provided. Set SWIFTARR_JWT_PRIVATE_KEY environment variable to the path of your RSA private key file.")
			logger.error("OIDC functionality will not work correctly without a valid signing key.")
			return
		}
		
		// Get public key path - default to private key path with ".pub" extension if not specified
		let publicKeyPath = Environment.get("SWIFTARR_JWT_PUBLIC_KEY") ?? privateKeyPath.replacingOccurrences(of: ".pem", with: ".pub.pem")
		
		logger.info("Loading JWT private key from \(privateKeyPath)")
		logger.info("Loading JWT public key from \(publicKeyPath)")
		
		// Initialize JWT signers
		let signers = JWTSigners()
		
		do {
			// Read private key from file
			guard let privateKeyData = FileManager.default.contents(atPath: privateKeyPath) else {
				logger.error("Failed to read JWT private key file at path: \(privateKeyPath)")
				logger.error("OIDC functionality will not work correctly without a valid signing key.")
				return
			}
			
			// Read public key from file
			guard let publicKeyData = FileManager.default.contents(atPath: publicKeyPath) else {
				logger.error("Failed to read JWT public key file at path: \(publicKeyPath)")
				logger.error("OIDC functionality will not work correctly without a valid public key.")
				return
			}
			
			// Parse the keys with Vapor's JWT library for signing
			let privateKey = try RSAKey.private(pem: String(decoding: privateKeyData, as: UTF8.self))
			// We don't need to parse the public key with Vapor's JWT, since we're parsing it with SwiftASN1
			
			// Register the key with the signers
			signers.use(.rs256(key: privateKey), kid: JWKIdentifier(string: keyID))
			
			// Store the RSA key in the actor
			await OIDCSignerActor.shared.setRSAKey(privateKey)
			
			// Create JWK with swift-jose library
			// Parse the public key to JOSE format
			let pemString = String(decoding: publicKeyData, as: UTF8.self)
			
			// Extract the RSA components (modulus and exponent) from the PEM-encoded public key
			logger.info("Extracting RSA components from public key")
			let (modulusData, exponentData) = try extractRSAComponentsFromPEM(pemString)
			
			// Log the extracted components (truncated for security)
			if modulusData.count > 8 {
				let truncatedModulus = modulusData.prefix(4).hex + "..." + modulusData.suffix(4).hex
				logger.debug("Extracted modulus: \(truncatedModulus) (\(modulusData.count) bytes)")
			}
			
			if exponentData.count > 0 {
				logger.debug("Extracted exponent: \(exponentData.hex) (\(exponentData.count) bytes)")
			}
			
			// Create a JOSE JWK manually with the extracted modulus and exponent
			let jwk = JOSE.JWK(
				keyType: .rsa,
				algorithm: "RS256",
				keyID: keyID,
				e: exponentData,
				n: modulusData
			)
			
			// Create a JWKSet with the RSA key
			let jwkSet = JWKSet(keys: [jwk])
			
			// Store the JWKSet in the actor
			await OIDCSignerActor.shared.setJWKSet(jwkSet)
			
			// Create our custom JWK format for backward compatibility
			let legacyJWK = JWK(
				keyType: "RSA",
				use: "sig",
				keyID: keyID,
				algorithm: "RS256",
				modulus: modulusData.base64URLEncodedString(),
				exponent: exponentData.base64URLEncodedString()
			)
			
			// Store the public key in the actor
			await OIDCSignerActor.shared.setPublicJWK(legacyJWK)
			
			// Store the signers in the actor
			await OIDCSignerActor.shared.setSigner(signers)
			
			logger.info("JWT key initialized successfully with kid: \(keyID)")
			
		} catch {
			logger.error("Failed to initialize OIDC JWT key: \(error)")
			logger.error("OIDC functionality will not work correctly without a valid signing key.")
		}
	}
	
	/// Signs a JWT token with the private key
	static func signToken<T: JWTPayload & Sendable>(_ payload: T) async throws -> String {
		let logger = Logger(label: "app.swiftarr.oidc")
		
		do {
			// Log token payload details for debugging
			let jsonEncoder = JSONEncoder()
			jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			let payloadData = try jsonEncoder.encode(payload)
			if let payloadString = String(data: payloadData, encoding: .utf8) {
				logger.debug("Signing JWT token with payload: \(payloadString)")
			}
			
			// Get key ID being used
			let keyID = Environment.get("SWIFTARR_JWT_KID") ?? "swiftarr-key-1"
			logger.debug("Using signing key with ID: \(keyID)")
			
			// Sign the token using the actor's sign method
			let token = try await OIDCSignerActor.shared.sign(payload)
			
			// Log successful signing
			logger.debug("Successfully signed JWT token with length: \(token.count) characters")
			
			// Extract and log token parts for debugging
			let parts = token.split(separator: ".")
			if parts.count == 3 {
				logger.debug("JWT token structure: header.\(parts[1].prefix(10))...\(parts[1].suffix(10)).signature")
			}
			
			return token
		} catch {
			logger.error("Error signing JWT token: \(error)")
			throw Abort(.internalServerError, reason: "JWT signing failed: \(error.localizedDescription)")
		}
	}
}

/// JWK (JSON Web Key) structure as defined in RFC 7517
struct JWK: Content, Sendable {
	let kty: String
	let use: String
	let kid: String
	let alg: String
	let n: String?
	let e: String?
	
	init(keyType: String, use: String, keyID: String, algorithm: String, modulus: String? = nil, exponent: String? = nil) {
		self.kty = keyType
		self.use = use
		self.kid = keyID
		self.alg = algorithm
		self.n = modulus
		self.e = exponent
	}
}

// Data extension for base64URLEncodedString is now in Foundation+Extensions.swift

/// Extension to Data to provide hex string representation
extension Data {
	/// Returns a hex string representation of the data
	var hex: String {
		return self.map { String(format: "%02x", $0) }.joined()
	}
}

/// Errors that can occur during ASN.1 parsing
enum ASN1Error: Error {
	case invalidPEMString
	case invalidASN1Structure
}

/// Error thrown when secure random string generation fails
enum SecureRandomError: Error {
	case randomGenerationFailed
}
