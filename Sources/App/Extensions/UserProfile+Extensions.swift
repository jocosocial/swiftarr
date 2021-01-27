import Vapor
import Fluent

// MARK: - Methods

extension UserProfile {
    /// Converts a `UserProfile` model to a version intended for editing by the owning
    /// user. `.username` and `.displayedName` are provided for client display convenience
    /// only and may not be edited.
    func convertToData() -> UserProfileData {
        var userProfileData = UserProfileData(
            username: self.username,
            displayedName: "",
            about: self.about ?? "",
            displayName: self.displayName ?? "",
            email: self.email ?? "",
            homeLocation: self.homeLocation ?? "",
            message: self.message ?? "",
            preferredPronoun: self.preferredPronoun ?? "",
            realName: self.realName ?? "",
            roomNumber: self.roomNumber ?? "",
            limitAccess: self.limitAccess
        )
        if userProfileData.displayName.isEmpty {
            userProfileData.displayedName = "@\(self.username)"
        } else {
            userProfileData.displayedName = userProfileData.displayName + " (@\(self.username))"
        }
        return userProfileData
    }
    
    /// Converts a `UserProfile` model to a version intended for content headers. Only the ID,
    /// generated `.displayedName` and name of the profile's user image are returned.
    func convertToHeader() throws -> UserHeader {
        let userHeader = UserHeader(
            userID: self.$user.id,
            username: username,
            displayName: displayName,
            userImage: self.userImage
        )
        return userHeader
    }
    
    /// Converts a `UserProfile` model to a version that is publicly viewable. Essentially,
    /// sensitive and unneeded data are omitted and the `.username` and `.displayName` properties
    /// are massaged into the more familiar "Display Name (@username)" or "@username" (if
    /// `.displayName` is empty) format as seen in posted content headers.
    func convertToPublic() throws -> ProfilePublicData {
        let profilePublicData = ProfilePublicData(
            profileID: try self.requireID(),
            displayedName: self.displayedName(),
            about: self.about ?? "",
            email: self.email ?? "",
            homeLocation: self.homeLocation ?? "",
            message: self.message ?? "",
            preferredPronoun: self.preferredPronoun ?? "",
            realName: self.realName ?? "",
            roomNumber: self.roomNumber ?? "",
            note: nil
        )
		return profilePublicData
    }
    
    /// Converts a `UserProfile` model to a version intended for multi-field search. Only the ID
    /// and a precomposed `.displayName` + `.username` + `.realName` string are returned.
    func convertToSearch() throws -> UserSearch {
        return UserSearch(
            userID: try self.user.requireID(),
            userSearch: self.userSearch
        )
    }
    
    func displayedName() -> String {
        let displayName = self.displayName ?? ""
        if displayName.isEmpty {
            return "@\(self.username)"
        } else {
            return displayName + " (@\(self.username))"
        }
    }
}

extension EventLoopFuture where Value: UserProfile {
    /// Converts a `EventLoopFuture<UserProfile>` to a `EventLoopFuture<UserHeader>`. This extension
    /// provides the convenience of simply using `profile.convertToHeader()` and allowing the
    /// compiler to choose the appropriate version for the context.
    func convertToHeader() throws -> EventLoopFuture<UserHeader> {
        return self.flatMapThrowing {
            (profile) in
            return try profile.convertToHeader()
        }
    }
    
    /// Converts a `EventLoopFuture<UserProfile>` to a `EventLoopFuture<UserSearch>`. This extension
    /// provides the convenience of simply using `profile.convertToSearch()` and allowing the
    /// compiler to choose the appropriate version for the context.
    func convertToSearch() throws -> EventLoopFuture<UserSearch> {
        return self.flatMapThrowing {
            (profile) in
            return try profile.convertToSearch()
        }
    }
}

