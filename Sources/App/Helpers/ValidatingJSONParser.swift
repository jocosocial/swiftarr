import Foundation
import Vapor

// Make a wrapping decoder for JSONDecoder. The decoder's container() methods return wrapping containers.
// Override the  decode<T> method so that if T is validatible we run validations on T.
// Abuse the compiler-generated init(from: decoder) method, basically.
// https://www.mikeash.com/pyblog/friday-qa-2017-07-14-swiftcodable.html


protocol RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws
}

// Describes an individual failed validation test. The whole reason I wrote this instead of using Vapor's validation suite
// is so I could get per-field validation failures reported out in a way they could get encoded in the response with
// [{ "fieldname" : "the thing wrong with this field" }] in the JSON.
struct ValidationFailure {
	let path: String
	let field: String?
	var errorString: String
}

struct ValidationError: Error {
    var status: HTTPResponseStatus = .badRequest
    var headers: HTTPHeaders = [:]
	var validationFailures: [ValidationFailure]
    
    func collectReasonString() -> String {
    	let reasons = validationFailures.map { $0.errorString }
    	let reasonString = reasons.joined(separator: "; ")
    	return reasonString
    }
    
    // Errors tagged with a field are put in the dictionary with the full path to the error.
    // Untagged errors (where field is nil) are all lumped into a "general" key.
    func collectFieldErrors() -> [String : String]? {
    	var fieldErrors: [(String, String)] = validationFailures.map {
    		var fullPath = "general"
    		if let field = $0.field { 
    			fullPath = $0.path.count > 0 ? "\($0.path).\(field)" : field
			}
			return (fullPath, $0.errorString)
		}
		// Prevent hayware error lists. Could also check for cases where multiple array elements had the same validation error.
		if fieldErrors.count > 10 {
			fieldErrors = Array(fieldErrors.prefix(10))
		}
		
		// Concatenates multiple error strings that have the same key.
		return fieldErrors.count == 0 ? nil : Dictionary(fieldErrors, uniquingKeysWith: { "\($0) and \($1)" })
    }
}


struct ValidatingKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
	let wrappedContainer: KeyedDecodingContainer<Self.Key>
	let wrappingDecoder: ValidatingDecoder
		
	var codingPath: [CodingKey] {
		return wrappedContainer.codingPath
	}
	var allKeys: [Key] {
		return wrappedContainer.allKeys
	}
	
	init(wrapping: KeyedDecodingContainer<Key>, for decoder: ValidatingDecoder) {
		wrappedContainer = wrapping
		wrappingDecoder = decoder
	}
	
	func validate(_ test: Bool, forKey: Key, or errorString: String? = nil) {
		if !test {
			let path = codingPath.map { $0.stringValue }.joined(separator: ".")
			let pathString = path == "" ? "" : "at path \(path)"
			let errorStr = errorString ?? "Field \"\(forKey.stringValue)\" \(pathString) is invalid"
			addValidationError(forKey: forKey, errorString: errorStr)
		}
	}
	
	func validateStrLenOptional(_ str: String?, nilOkay: Bool = true, min: Int = 0, max: Int = Int.max, forKey: Key, 
			fieldName: String? = nil, or errorString: String? = nil) {
		if let internalStr = str, !internalStr.isEmpty {
			validateStrLen(internalStr, min: min, max: max, forKey: forKey, fieldName: fieldName, or: errorString)
		}
		else if !nilOkay {
			var errorStr = errorString ?? ""
			if errorStr.isEmpty {
				if let field = fieldName {
					errorStr = "\(field) must have a value and cannot be nil"
				}
				else {
					let path = codingPath.map { $0.stringValue }.joined(separator: ".")
					let pathString = path == "" ? "" : "at path \(path)"
					errorStr = "\"\(forKey.stringValue)\" \(pathString) must have a value and cannot be nil"
				}
			}
			addValidationError(forKey: forKey, errorString: errorStr)
		}
	}
	
	func validateStrLen(_ str: String, min: Int = 0, max: Int = Int.max, forKey: Key, fieldName: String? = nil,
			or errorString: String? = nil) {
		let len = str.count
		if len < min || len > max {
			var errorStr = errorString ?? ""
			if errorStr.isEmpty {
				if let field = fieldName {
					errorStr = len < min ? "\(field) has a \(min) character minimum" : "\(field) has a \(max) character maximum"
				}
				else {
					let path = codingPath.map { $0.stringValue }.joined(separator: ".")
					let pathString = path == "" ? "" : "at path \(path)"
					if len < min {
						errorStr = "\"\(forKey.stringValue)\" \(pathString) has a \(min) character minimum"
					}
					else {
						errorStr = "\"\(forKey.stringValue)\" \(pathString)  has a \(max) character maximum"
					}
				}
			}
			addValidationError(forKey: forKey, errorString: errorStr)
		}
	}
	
	func addValidationError(forKey: Key?, errorString: String) {
		let path = codingPath.map { $0.stringValue }.joined(separator: ".")
		let error = ValidationFailure(path: path, field: forKey?.stringValue, errorString: errorString)
		wrappingDecoder.validationFailures.append(error)
	}

	func contains(_ key: Key) -> Bool {
		return wrappedContainer.contains(key)
	}
	
	func decode<Z: Decodable>(_ type: Z.Type, forKey key: Key) throws -> Z {
		let result = try wrappedContainer.decode(type, forKey: key) 
		if let r = result as? RCFValidatable {
			try r.runValidations(using: wrappingDecoder)
		}
		return result
	}
	
	func decodeIfPresent<Z: Decodable>(_ type: Z.Type, forKey key: Key) throws -> Z? {
		if let result = try wrappedContainer.decodeIfPresent(type, forKey: key) {
			if let r = result as? RCFValidatable {
				try r.runValidations(using: wrappingDecoder)
			}
			return result
		}
		return nil
	}
	
	func decodeNil(forKey key: Key) throws -> Bool {
		return try wrappedContainer.decodeNil(forKey: key) 
	}

	func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) 
			throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
		return try wrappedContainer.nestedContainer(keyedBy: type, forKey: key)
	}
	
	func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
		return try wrappedContainer.nestedUnkeyedContainer(forKey: key)
	}
	
	func superDecoder() throws -> Decoder {
		return try wrappedContainer.superDecoder()
	}
	
	func superDecoder(forKey key: Key) throws -> Decoder {
		return try wrappedContainer.superDecoder(forKey: key)
	}
}

final public class ValidatingDecoder: Decoder {
    let wrappedDecoder: Decoder
    var validationFailures: [ValidationFailure] = []

	public var codingPath: [CodingKey] {
		return wrappedDecoder.codingPath
	}
	public var userInfo: [CodingUserInfoKey: Any] {
		return wrappedDecoder.userInfo
	}
	
    public init(with decoder: Decoder) throws {
        wrappedDecoder = decoder
    }
	
	func validator<Key>(keyedBy type: Key.Type) throws -> ValidatingKeyedContainer<Key> where Key : CodingKey {
		let container = try wrappedDecoder.container(keyedBy: type)
		return ValidatingKeyedContainer<Key>(wrapping: container, for: self)
	}


// If necessary, the wrapped container could be keyed by ValidationKey. Our container must stay generic over Key.
	public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
		let container = try wrappedDecoder.container(keyedBy: type)
		return KeyedDecodingContainer(ValidatingKeyedContainer<Key>(wrapping: container, for: self))
	}
	public func singleValueContainer() throws -> SingleValueDecodingContainer {
		let container = try wrappedDecoder.singleValueContainer()
//		return ValidatingSingleValueContainer(wrapping: container)
		return container
	}
	public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
		let container = try wrappedDecoder.unkeyedContainer()
		return ValidatingUnkeyedContainer(wrapping: container)
	}

		
    private struct ValidatingUnkeyedContainer: UnkeyedDecodingContainer {
		var wrappedContainer: UnkeyedDecodingContainer

		var codingPath: [CodingKey] { wrappedContainer.codingPath }
		var count: Int? { wrappedContainer.count }
        var currentIndex: Int { wrappedContainer.currentIndex }
        var isAtEnd: Bool { wrappedContainer.isAtEnd }

 		init(wrapping: UnkeyedDecodingContainer) {
			wrappedContainer = wrapping
		}

      	mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
			return try wrappedContainer.decode(type) 
        }

        func decodeNil() -> Bool {
            return true
        }

        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
			return try wrappedContainer.nestedContainer(keyedBy: type) 
        }

        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
			return try wrappedContainer.nestedUnkeyedContainer() 
        }

        mutating func superDecoder() throws -> Decoder {
			return try wrappedContainer.superDecoder() 
        }
    }
    
    private struct ValidatingSingleValueContainer: SingleValueDecodingContainer {
		var wrappedContainer: SingleValueDecodingContainer

		var codingPath: [CodingKey] { wrappedContainer.codingPath }

 		init(wrapping: SingleValueDecodingContainer) {
			wrappedContainer = wrapping
		}

      	func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
			return try wrappedContainer.decode(type) 
        }

        func decodeNil() -> Bool {
            return true
        }
    }
}


final public class DecoderProxy<OutputType>: Decodable where OutputType: Decodable {
	public var result: OutputType
	var validationFailures: [ValidationFailure]

    public init(from decoder: Decoder) throws {
        let wrappingDecoder = try ValidatingDecoder(with: decoder)
        result = try OutputType(from: wrappingDecoder)
        if let v = result as? RCFValidatable {
        	try v.runValidations(using: wrappingDecoder)
        }
        self.validationFailures = wrappingDecoder.validationFailures
    }
}


// This should implement the TopLevelDecoder protocol (not actually available, as it's in Combine; Apple says they're moving it).
// TopLevelDecoder is the 'external' API for decoder objects, whereas Decoder is the 'internal' API the decoder uses to talk
// to the objects being created during decoding.
public class ValidatingJSONDecoder {
	let jsonDecoder: JSONDecoder
	
	init(_ decoder: JSONDecoder = JSONDecoder()) {
		jsonDecoder = decoder
		jsonDecoder.dateDecodingStrategy = .iso8601ms
	}
	
	// JSONDecoder.Input is the correct input type for current Mac implementations. Linux doesn't have this type
	// yet, and really, the type is just an alias for Data.
//	func decode<Output>(_ type: Output.Type, from: JSONDecoder.Input) throws -> Output where Output : Decodable {
	func decode<Output>(_ type: Output.Type, from: Data) throws -> Output where Output : Decodable {
		let wrapper = try jsonDecoder.decode(DecoderProxy<Output>.self, from: from)
		return wrapper.result
	}
	
	func decode<Output>(_ type: Output.Type, fromBodyOf req: Request) throws -> Output where Output : Decodable {
		guard let body = req.body.data else {
			req.logger.debug("Decoding streaming bodies not supported")
			throw Abort(.unprocessableEntity)
		}
		let wrapper = try jsonDecoder.decode(DecoderProxy<Output>.self, from: body)
		if wrapper.validationFailures.count > 0 {
			throw ValidationError(validationFailures: wrapper.validationFailures)
		}
		return wrapper.result
	}
	
	// This isn't just decode() without a result. Validate-only could do less by not decoding some values.
	func validate<Output: Decodable>(_ type: Output.Type, fromBodyOf req: Request) throws {
		guard let body = req.body.data else {
			req.logger.debug("Decoding streaming bodies not supported")
			throw Abort(.unprocessableEntity)
		}
		let wrapper = try jsonDecoder.decode(DecoderProxy<Output>.self, from: body)
		if wrapper.validationFailures.count > 0 {
			throw ValidationError(validationFailures: wrapper.validationFailures)
		}
	}
}


