/// Represents errors that can be thrown within the SwiftGD module.
///
/// - invalidFormat: Image raster format mismatch on import/export
/// - invalidImage: Contains the reason this error was thrown.
/// - invalidColor: Contains the reason this error was thrown.
/// - invalidMaxColors: Asserts sane values for creating indexed Images
public enum GDError: Swift.Error {
	case invalidFormat
	case invalidImage(reason: String)  // The reason this error was thrown
	case invalidColor(reason: String)  // The reason this error was thrown.
	case invalidMaxColors(reason: String)
}

/// A structure that represents a geometric angle.
public struct Angle: Sendable {
	/// The angle value in radians.
	public var radians: Double

	/// The angle value in degrees.
	public var degrees: Double {
		get { radians * (180.0 / .pi) }
		set { radians = newValue * (.pi / 180.0) }
	}

	/// Creates an angle with the specified radians.
	///
	/// - Parameter radians: The radians of the angle.
	public init(radians: Double) {
		self.radians = radians
	}

	/// Creates an angle with the specified degrees.
	///
	/// - Parameter degrees: The degrees of the angle.
	public init(degrees: Double) {
		self.init(radians: degrees * (.pi / 180.0))
	}
}

extension Angle {
	/// A zero angle.
	public static let zero = Angle(degrees: 0)

	/// An angle.
	///
	/// - Parameter radians: The radians of the angle.
	/// - Returns: A new `Angle` instance with the specified radians.
	public static func radians(_ radians: Double) -> Angle {
		return Angle(radians: radians)
	}

	/// An angle.
	///
	/// - Parameter degrees: The degrees of the angle.
	/// - Returns: A new `Angle` instance with the specified degrees.
	public static func degrees(_ degrees: Double) -> Angle {
		return Angle(degrees: degrees)
	}
}

public struct Color: Sendable {
	public var redComponent: Double
	public var greenComponent: Double
	public var blueComponent: Double
	public var alphaComponent: Double

	public init(red: Double, green: Double, blue: Double, alpha: Double) {
		redComponent = red
		greenComponent = green
		blueComponent = blue
		alphaComponent = alpha
	}
}

// MARK: Constants

extension Color {
	public static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)

	public static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)

	public static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)

	public static let black = Color(red: 0, green: 0, blue: 0, alpha: 1)

	public static let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
}

// MARK: Hexadecimal

extension Color {
	/// The maximum representable integer for each color component.
	private static let maxHex: Int = 0xff

	/// Initializes a new `Color` instance of given hexadecimal color string.
	///
	/// Given string will be stripped from a single leading "#", if applicable.
	/// Resulting string must met any of the following criteria:
	///
	/// - Is a string with 8-characters and therefore a fully fledged hexadecimal
	///   color representation **including** an alpha component. Given value will remain
	///   untouched before conversion. Example: `ffeebbaa`
	/// - Is a string with 6-characters and therefore a fully fledged hexadecimal color
	///   representation **excluding** an alpha component. Given RGB color components will
	///   remain untouched and an alpha component of `0xff` (opaque) will be extended before
	///   conversion. Example: `ffeebb` -> `ffeebbff`
	/// - Is a string with 4-characters and therefore a shortened hexadecimal color
	///   representation **including** an alpha component. Each single character will be
	///   doubled before conversion. Example: `feba` -> `ffeebbaa`
	/// - Is a string with 3-characters and therefore a shortened hexadecimal color
	///   representation **excluding** an alpha component. Given RGB color character will
	///   be doubled and an alpha of component of `0xff` (opaque) will be extended before
	///   conversion. Example: `feb` -> `ffeebbff`
	///
	/// - Parameters:
	///   - string: The hexadecimal color string.
	///   - leadingAlpha: Indicate whether given string should be treated as ARGB (`true`) or RGBA (`false`)
	/// - Throws: `.invalidColor` if given string does not match any of the above mentioned criteria or is not a valid hex color.
	public init(hex string: String, leadingAlpha: Bool = false) throws {
		let string = try Color.sanitize(hex: string, leadingAlpha: leadingAlpha)
		guard let code = Int(string, radix: 16) else {
			throw GDError.invalidColor(reason: "0x\(string) is not a valid hex color code")
		}
		self.init(hex: code, leadingAlpha: leadingAlpha)
	}

	/// Initializes a new `Color` instance of given hexadecimal color values.
	///
	/// - Parameters:
	///   - color: The hexadecimal color value, incl. red, green, blue and alpha
	///   - leadingAlpha: Indicate whether given code should be treated as ARGB (`true`) or RGBA (`false`)
	public init(hex color: Int, leadingAlpha: Bool = false) {
		let max = Double(Color.maxHex)
		let first = Double((color >> 24) & Color.maxHex) / max
		let secnd = Double((color >> 16) & Color.maxHex) / max
		let third = Double((color >> 8) & Color.maxHex) / max
		let forth = Double((color >> 0) & Color.maxHex) / max
		if leadingAlpha {
			self.init(red: secnd, green: third, blue: forth, alpha: first)  // ARGB
		}
		else {
			self.init(red: first, green: secnd, blue: third, alpha: forth)  // RGBA
		}
	}

	// MARK: Private helper

	/// Sanitizes given hexadecimal color string (strips # and forms proper length).
	///
	/// - Parameters:
	///   - string: The hexadecimal color string to sanitize
	///   - leadingAlpha: Indicate whether given and returning string should be treated as ARGB (`true`) or RGBA (`false`)
	/// - Returns: The sanitized hexadecimal color string
	/// - Throws: `.invalidColor` if given string is not of proper length
	private static func sanitize(hex string: String, leadingAlpha: Bool) throws -> String {

		// Drop leading "#" if applicable
		var string = string.hasPrefix("#") ? String(string.dropFirst(1)) : string

		// Evaluate if short code w/wo alpha (e.g. `feb` or `feb4`). Double up the characters if so.
		if string.count == 3 || string.count == 4 {
			string = string.map({ "\($0)\($0)" }).joined()
		}

		// Evaluate if fully fledged code w/wo alpha (e.g. `ffaabb` or `ffaabb44`), otherwise throw error
		switch string.count {
		case 6:  // Hex color code without alpha (e.g. ffeeaa)
			let alpha = String(Color.maxHex, radix: 16)  // 0xff (opaque)
			return leadingAlpha ? alpha + string : string + alpha
		case 8:  // Fully fledged hex color including alpha (e.g. eebbaa44)
			return string
		default:
			throw GDError.invalidColor(reason: "0x\(string) has invalid hex color string length")
		}
	}
}

/// A structure that contains a point in a two-dimensional coordinate system.
public struct Point: Sendable {
	/// The x-coordinate of the point.
	public var x: Int

	/// The y-coordinate of the point.
	public var y: Int

	/// Creates a point with specified coordinates.
	///
	/// - Parameters:
	///   - x: The x-coordinate of the point
	///   - y: The y-coordinate of the point
	public init(x: Int, y: Int) {
		self.x = x
		self.y = y
	}
}

extension Point {
	/// The point at the origin (0,0).
	public static let zero = Point(x: 0, y: 0)

	/// Creates a point with specified coordinates.
	///
	/// - Parameters:
	///   - x: The x-coordinate of the point
	///   - y: The y-coordinate of the point
	public init(x: Int32, y: Int32) {
		self.init(x: Int(x), y: Int(y))
	}
}

extension Point: Equatable {
	/// Returns a Boolean value indicating whether two values are equal.
	///
	/// Equality is the inverse of inequality. For any values `a` and `b`,
	/// `a == b` implies that `a != b` is `false`.
	///
	/// - Parameters:
	///   - lhs: A value to compare.
	///   - rhs: Another value to compare.
	public static func == (lhs: Point, rhs: Point) -> Bool {
		return lhs.x == rhs.x && lhs.y == rhs.y
	}
}

/// A structure that represents a rectangle.
public struct Rectangle: Sendable {
	/// The origin of the rectangle.
	public var point: Point

	/// The size of the rectangle.
	public var size: Size

	/// Creates a rectangle at specified point and given size.
	///
	/// - Parameters:
	///   - point: The origin of the rectangle
	///   - height: The size of the rectangle
	public init(point: Point, size: Size) {
		self.point = point
		self.size = size
	}
}

extension Rectangle {
	/// Rectangle at the origin whose width and height are both zero.
	public static let zero = Rectangle(point: .zero, size: .zero)

	/// Creates a rectangle at specified point and given size.
	///
	/// - Parameters:
	///   - x: The x-coordinate of the point
	///   - y: The y-coordinate of the point
	///   - width: The width value of the size
	///   - height: The height value of the size
	public init(x: Int, y: Int, width: Int, height: Int) {
		self.init(point: Point(x: x, y: y), size: Size(width: width, height: height))
	}

	/// Creates a rectangle at specified point and given size.
	///
	/// - Parameters:
	///   - x: The x-coordinate of the point
	///   - y: The y-coordinate of the point
	///   - width: The width value of the size
	///   - height: The height value of the size
	public init(x: Int32, y: Int32, width: Int32, height: Int32) {
		self.init(x: Int(x), y: Int(y), width: Int(width), height: Int(height))
	}
}

extension Rectangle: Equatable {
	/// Returns a Boolean value indicating whether two values are equal.
	///
	/// Equality is the inverse of inequality. For any values `a` and `b`,
	/// `a == b` implies that `a != b` is `false`.
	///
	/// - Parameters:
	///   - lhs: A value to compare.
	///   - rhs: Another value to compare.
	public static func == (lhs: Rectangle, rhs: Rectangle) -> Bool {
		return lhs.point == rhs.point && lhs.size == rhs.size
	}
}

/// A structure that represents a two-dimensional size.
public struct Size: Sendable {
	/// The width value of the size.
	public var width: Int

	/// The height value of the size.
	public var height: Int

	/// Creates a size with specified dimensions.
	///
	/// - Parameters:
	///   - width: The width value of the size
	///   - height: The height value of the size
	public init(width: Int, height: Int) {
		self.width = width
		self.height = height
	}
}

extension Size {
	/// Size whose width and height are both zero.
	public static let zero = Size(width: 0, height: 0)

	/// Creates a size with specified dimensions.
	///
	/// - Parameters:
	///   - width: The width value of the size
	///   - height: The height value of the size
	public init(width: Int32, height: Int32) {
		self.init(width: Int(width), height: Int(height))
	}
}

extension Size: Comparable {
	/// Returns a Boolean value indicating whether the value of the first
	/// argument is less than that of the second argument.
	///
	/// This function is the only requirement of the `Comparable` protocol. The
	/// remainder of the relational operator functions are implemented by the
	/// standard library for any type that conforms to `Comparable`.
	///
	/// - Parameters:
	///   - lhs: A value to compare.
	///   - rhs: Another value to compare.
	public static func < (lhs: Size, rhs: Size) -> Bool {
		return lhs.width < rhs.width && lhs.height < rhs.height
	}

	/// Returns a Boolean value indicating whether two values are equal.
	///
	/// Equality is the inverse of inequality. For any values `a` and `b`,
	/// `a == b` implies that `a != b` is `false`.
	///
	/// - Parameters:
	///   - lhs: A value to compare.
	///   - rhs: Another value to compare.
	public static func == (lhs: Size, rhs: Size) -> Bool {
		return lhs.width == rhs.width && lhs.height == rhs.height
	}
}
