import Vapor
import Crypto
import FluentSQL
import Foundation
import gd

struct ImageController: APIRouteCollection {
	// Important that this stays a constant; changing after creation is not thread-safe.
	// Also, since this is based on DirectoryConfiguration, the value is process-wide, not Application-wide.
	let imagesDirectory: URL
	
	// TODO: Currently this creates an images directory inside of `DerivedData`, meaning all images are deleted
	// on "Clean Build Folder". This doesn't reset the database, so you end up with a DB referencing images that aren't there.
	// It would be better to put images elsewhere and tie their lifecycle to the database.
	init() {
		let dir = DirectoryConfiguration.detect().workingDirectory
		imagesDirectory = URL(fileURLWithPath: dir).appendingPathComponent("images")
	}
 
    /// Required. Registers routes to the incoming router.
    func registerRoutes(_ app: Application) throws {
        
		// convenience route group for all /api/v3/image endpoints
		let imageRoutes = app.grouped("api", "v3", "image")
		let userImageRoutes = imageRoutes.grouped(DisabledAPISectionMiddleware(feature: .images))

		// open access endpoints
		userImageRoutes.get("full", ":image_filename", use: getImage_FullHandler)
		userImageRoutes.get("thumb", ":image_filename", use: getImage_ThumbnailHandler)
		userImageRoutes.get("user", "identicon", userIDParam, use: getUserIdenticonHandler)
		userImageRoutes.get("user", "full", userIDParam, use: getUserAvatarHandler)
		userImageRoutes.get("user", "thumb", userIDParam, use: getUserAvatarHandler)

		// Moderator-only endpoints
		let requireModMiddleware = RequireModeratorMiddleware()
		let tokenAuthGroup = addTokenAuthGroup(to: imageRoutes).grouped(requireModMiddleware)
		tokenAuthGroup.get("archive", ":image_filename", use: getImage_ArchivedHandler)
	}
	
    /// `GET /api/v3/image/full/STRING`
    ///
    /// Returns a user-created image previously uploaded to the server. This includes images in Twitarr posts, ForumPosts, FezPosts, User Avatars, and Daily Theme images.
	/// Even though the path for this API call says 'full', images may be downsized when uploaded (currently, images get downsized to a max edge length of 2048).
	/// 
	/// Image filenames should have a form of: `UUIDString.typeExtension` where the UUIDString matches the output of `UUID().string` and `typeExtension`
	/// matches one of : "bmp", "gif", "jpg", "png", "tiff", "wbmp", "webp". Example: `F818D809-AAB9-4C92-8AAD-6AE483C8AB82.jpg` The `thumb` and `full`
	/// versions of this call return differently-sized versions of the same image when called with the same filename.
	/// 
	/// User Avatar Images: UserHeader.image will be nil for a user that has not set an avatar image; clients should display a default avatar image instead. Or, clients may
	/// call the `/api/v3/image/user/` endpoints instead--these endpoints return identicon images for users that have not set custom images for themselves.
	/// 
    /// - Parameter STRING: A reference to the image, returned from another API call.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: Image data
	func getImage_FullHandler(_ req: Request) throws -> Response {
		return try getUserUploadedImage(req, sizeGroup: .full)
	}
	
    /// `GET /api/v3/image/thumb/STRING`
    ///
    /// Returns a user-created image thumbnail previously uploaded to the server. This includes images in Twitarr posts, ForumPosts, 
	/// FezPosts, User Avatars, and Daily Theme images. The exact size of the thumbnail may vary based on the usage given at upload time.
	/// 
	/// Image filenames should have a form of: `UUIDString.typeExtension` where the UUIDString matches the output of `UUID().string` and `typeExtension`
	/// matches one of : "bmp", "gif", "jpg", "png", "tiff", "wbmp", "webp". Example: `F818D809-AAB9-4C92-8AAD-6AE483C8AB82.jpg`. The `thumb` and `full`
	/// versions of this call return differently-sized versions of the same image when called with the same filename.
	/// 
	/// User Avatar Images: UserHeader.image will be nil for a user that has not set an avatar image; clients should display a default avatar image instead. Or, clients may
	/// call the `/api/v3/image/user/` endpoints instead--these endpoints return identicon images for users that have not set custom images for themselves.
	/// 
    /// - Parameter STRING: A reference to the image, returned from another API call.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: Image data
	func getImage_ThumbnailHandler(_ req: Request) throws -> Response {
		return try getUserUploadedImage(req, sizeGroup: .thumbnail)
	}
	
    /// `GET /api/v3/image/archive/STRING`
    ///
    /// Returns an archived user-created image previously uploaded to the server, and then previously deleted/replaced. This includes images in Twitarr posts,
	/// ForumPosts, FezPosts, User Avatars, and Daily Theme images. Archived images are only accessible by Moderators and above.
	/// 
	/// Image filenames should have a form of: `UUIDString.typeExtension` where the UUIDString matches the output of `UUID().string` and `typeExtension`
	/// matches one of : "bmp", "gif", "jpg", "png", "tiff", "wbmp", "webp". Example: `F818D809-AAB9-4C92-8AAD-6AE483C8AB82.jpg`. The `thumb` and `full`
	/// versions of this call return differently-sized versions of the same image when called with the same filename.
	/// 
    /// - Parameter STRING: A reference to the image, returned from another API call.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: Image data
	func getImage_ArchivedHandler(_ req: Request) throws -> Response {
		return try getUserUploadedImage(req, sizeGroup: .archive)
	}
	
    /// `GET /api/v3/image/user/full/:userID`
    /// `GET /api/v3/image/user/thumb/:userID`
    ///
	///  Gets the avatar image for the given user. 
	///  If the user has a custom avatar, result is the same as if you called `/api/v3/image/<thumb|full>/<user.userImage>`
	///  If the user has no custom avatar, returns a 40x40 Identicon image specific to the given userID. 
	///  
	///  Note: This method is a convenience for clients that do their own image caching. For clients that rely on `Cache-Control` headers, it's better to call
	///  either the custom image or user identicon call instead; those calls can set a long-term cache expiry and this method cannot. Said differently,
	///  `/api/v3/image/thumb/:filename` only changes its result if the file is mod-deleted, and if that happens the user's userImage field updates.
	///  Similarly, `api/v3/image/user/identicon/:userID` will always return the same result for the same userID parameter. This method returns a different 
	///  image for the same URL whenever the user updates their profile image, therefore we can't set cache headers as aggressively.  
	///  
	///  Barring severe errors, this method will always return an image--either a user's custom avatar or their default identicon. A consequence of this is that you cannot tell
	///  whether a user has a custom avatar set or not when calling this method.
	///  
	///  This method is optional. If you don't want the server-generated identicons for your client, you can create your own and know when to use them instead of 
	///  user-created avatars, as the user's userImage will be nil if they have no custom avatar.
	///  
    /// - Parameter ID: A userID value, in the URL path.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: Image data, or `304 notModified` if client's ETag matches.
	func getUserAvatarHandler(_ req: Request) throws -> Response {
        guard let userID = req.parameters.get(userIDParam.paramString, as: UUID.self) else {
            throw Abort(.badRequest, reason: "Missing user ID parameter.")
        }
        let sizeGroup: ImageSizeGroup = req.url.path.hasPrefix("/api/v3/image/user/thumb") ? .thumbnail : .full
		guard let targetUser = req.userCache.getUser(userID) else {
			throw Abort(.badRequest, reason: "User not found")
		}
		if let filename = targetUser.userImage {
			return try getUserUploadedImage(req, sizeGroup: sizeGroup, imageFilename: filename)
		}
		var headers: HTTPHeaders = [:]

		// Check if file has been cached already and return NotModified response if the etags match
		headers.replaceOrAdd(name: .eTag, value: "W/\"1\"")
		if "W/\"1\"" == req.headers.first(name: .ifNoneMatch) {
			return Response(status: .notModified)
		}

		let imageData = try generateIdenticon(for: targetUser.userID)
		headers.contentType = HTTPMediaType.fileExtension("png")
		let body = Response.Body(data: imageData)
		return Response(status: .ok, headers: headers, body: body)
	}
	
    /// `GET /api/v3/image/user/identicon/ID`
    ///
	/// Returns a user's identicon avatar image, even if that user has a custom avatar set. Meant for use in User Profile edit flows, to show a user what
	/// their default identicon will look like even when a custom avatar is set.
	/// 
	/// Please don't use this method to show identicons for all users everywhere. Users like their custom avatars.
	/// 
    /// - Parameter ID: A userID value, in the URL path.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: Image data, or `304 notModified` if client's ETag matches.
	func getUserIdenticonHandler(_ req: Request) throws -> Response {
        guard let userID = req.parameters.get(userIDParam.paramString, as: UUID.self) else {
            throw Abort(.badRequest, reason: "Missing user ID parameter.")
        }
		guard let targetUser = req.userCache.getUser(userID) else {
			throw Abort(.badRequest, reason: "User not found")
		}
		var headers: HTTPHeaders = [:]
		// Check if file has been cached already and return NotModified response if the etags match
		headers.replaceOrAdd(name: .eTag, value: "W/\"1\"")
		if "W/\"1\"" == req.headers.first(name: .ifNoneMatch) {
			return Response(status: .notModified)
		}
		let imageData = try generateIdenticon(for: targetUser.userID)
		headers.contentType = HTTPMediaType.fileExtension("png")
		headers.cacheControl = .init(isPublic: true, maxAge: 3600 * 24)
		let body = Response.Body(data: imageData)
		return Response(status: .ok, headers: headers, body: body)
	}
	
// MARK: - Utilities
	func getUserUploadedImage(_ req: Request, sizeGroup: ImageSizeGroup, imageFilename: String? = nil) throws -> Response {
		let inputFilename = imageFilename ?? req.parameters.get("image_filename")
		guard let fileParam = inputFilename else {
			throw Abort(.badRequest, reason: "No image file specified.")
		}
		
		// Check the extension
		var fileExtension = URL(fileURLWithPath: fileParam).pathExtension
		if !["bmp", "gif", "jpg", "png", "tiff", "wbmp", "webp"].contains(fileExtension) {
			fileExtension = "jpg"
		}
		
		// Strip extension and any other gunk off the filename. Eject if two extensions detected (.php.jpg, for example).
		let noFiletype = URL(fileURLWithPath: fileParam).deletingPathExtension()
		if noFiletype.pathExtension.count > 0 {
			throw Abort(.badRequest, reason: "Malformed image filename.")
		}
		let filename = noFiletype.lastPathComponent
		// This check is important for security. Not only does it do the obvious, it protects
		// against "../../../../file_important_to_Swiftarr_operation" attacks.
		guard let fileUUID = UUID(filename) else {
			throw Abort(.badRequest, reason: "Image filename is not a valid UUID.")
		}
				
		// I don't think ~10K files in each directory is going to cause slowdowns, but if it does,
		// this will give us 128 subdirs.
		let subDirName = String(fileParam.prefix(2))
			
        let fileURL = imagesDirectory.appendingPathComponent(sizeGroup.rawValue)
        		.appendingPathComponent(subDirName)
        		.appendingPathComponent(fileUUID.uuidString + "." + fileExtension)
		let response = req.fileio.streamFile(at: fileURL.path)
		// If streamFile is returning the image file, add a cache-control header to the repsonse
		if response.status == .ok {
			response.headers.cacheControl = .init(isPublic: true, maxAge: 3600 * 24)
		}
		return response
	}
	
	/// Creates an identicon image from the given user's userID. 
	/// 
	/// Created images are 40x40 PNG palette-based images, averaging ~200 bytes in size. Random inputs into the generator come from the 
	/// Xoshiro random number generator, seeded with a (very poor) hash of the user's userID value. Because of this seeding, the algorithm repeatedly
	/// produces the same image for the same userID value.
	///
	/// From testing, this method can generate about 10000 icons / second on a single thread. This should be fast enough so that we don't need to store
	/// and retrieve generated images; we may as well just generate them on-demand.
	func generateIdenticon(for userID: UUID) throws -> Data {
		// This creates a random number generator that is seeded with a specific value based on a user's userID.
		// This generator should then create a repeatable sequence of values for each user.
		var gen = Xoshiro(seed: userID)

		guard let srcImage = GDImage(width: 5, height: 5, type: .palette) else {
			throw Abort(.internalServerError, reason: "Could not allocate image for identicon.")
		}
		let r1 = Int32.random(in: 0...127, using: &gen)
		let g1 = Int32.random(in: 0...127, using: &gen)
		let b1 = Int32.random(in: 0...127, using: &gen)
//		let color1 = gdImageColorClosest(srcImage.internalImage, r1, g1, b1)
		let color1 = gdImageColorAllocate(srcImage.internalImage, r1, g1, b1)
		var color2 = color1
		for _ in 0...10 {
			let r2 = Int32.random(in: 128...255, using: &gen)
			let g2 = Int32.random(in: 128...255, using: &gen)
			let b2 = Int32.random(in: 128...255, using: &gen)
			if abs(r1 - r2) > 20 || abs(g1 - g2) > 20 || abs(b1 - b2) > 20 {
//				color2 = gdImageColorClosest(srcImage.internalImage, r1, g2, b2)
				color2 = gdImageColorAllocate(srcImage.internalImage, r1, g2, b2)
				break
			}	
		}
		
		for x : Int32 in 0...2 {
			for y : Int32 in 0...4 {
				let pixelColor = Bool.random(using: &gen) ? color1 : color2
				gdImageSetPixel(srcImage.internalImage, x, y, pixelColor)
				if x < 2 {
					gdImageSetPixel(srcImage.internalImage, 4 - x, y, pixelColor)
				}
			}
		}
		let dstImage = srcImage.resizedTo(width: 40, height: 40, applySmoothing: false)!
		// JPEG compression was a bit faster than PNG, but produced images that were ~900 bytes,
		// as opposed to ~200 bytes for PNGs.
		// let jpegData = try dstImage.export(as: .jpg(quality: 70))
		// return jpegData
		let pngData = try dstImage.export(as: .png)
		return pngData
	}
	
}

/// Random number generator that can be initialized with a seed value.
/// Copied from https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlRandom.swift
/// 
/// The idea here is that this RNG is seeded with a user's userID, and will always produce the same sequence of numbers when building a user's identicon..
public struct Xoshiro: RandomNumberGenerator {
	public typealias StateType = (UInt64, UInt64, UInt64, UInt64)

	private var state: StateType = (0, 0, 0, 0)

	public init(seed: StateType) {
		self.state = seed
	}
	
	public init(seed: UUID) {
		let (byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7, byte8, byte9, byteA, byteB, byteC, byteD, byteE, byteF) = seed.uuid
		var high64: UInt64 = (UInt64(byte0) << 0o70) | (UInt64(byte1) << 0o60) | (UInt64(byte2) << 0o50) | (UInt64(byte3) << 0o40)
		high64 |= (UInt64(byte4) << 0o30) | (UInt64(byte5) << 0o20) | (UInt64(byte6) << 0o10) | (UInt64(byte7) << 0o00)
		var low64: UInt64 = (UInt64(byte8) << 0o70) | (UInt64(byte9) << 0o60) | (UInt64(byteA) << 0o50) | (UInt64(byteB) << 0o40)
		low64 |= (UInt64(byteC) << 0o30) | (UInt64(byteD) << 0o20) | (UInt64(byteE) << 0o10) | (UInt64(byteF) << 0o00)
		self.init(seed: (0xf4ea82acc99f4b28, 0xd72f22e359f3c6ad, high64, low64))
	}

	public mutating func next() -> UInt64 {
		// Derived from public domain implementation of xoshiro256** here:
		// http://xoshiro.di.unimi.it
		// by David Blackman and Sebastiano Vigna
		let x = state.1 &* 5
		let result = ((x &<< 7) | (x &>> 57)) &* 9
		let t = state.1 &<< 17
		state.2 ^= state.0
		state.3 ^= state.1
		state.1 ^= state.2
		state.0 ^= state.3
		state.2 ^= t
		state.3 = (state.3 &<< 45) | (state.3 &>> 19)
		return result
	}
}

