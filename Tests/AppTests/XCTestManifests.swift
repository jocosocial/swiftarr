#if !canImport(ObjectiveC)
import XCTest

extension AppTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__AppTests = [
        ("testNothing", testNothing),
    ]
}

extension BarrelTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__BarrelTests = [
        ("testAlertWordsModify", testAlertWordsModify),
        ("testBarrelCreate", testBarrelCreate),
        ("testBarrelModify", testBarrelModify),
        ("testDefaultBarrels", testDefaultBarrels),
        ("testMuteWordsModify", testMuteWordsModify),
        ("testUserBarrel", testUserBarrel),
        ("testUserBarrelDelete", testUserBarrelDelete),
        ("testUserBarrelRename", testUserBarrelRename),
        ("testUserBlock", testUserBlock),
        ("testUserFilters", testUserFilters),
        ("testUserMute", testUserMute),
        ("testUserUnblock", testUserUnblock),
        ("testUserUnmute", testUserUnmute),
    ]
}

extension ClientTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ClientTests = [
        ("testClientMigration", testClientMigration),
        ("testUserHeaders", testUserHeaders),
        ("testUsersearch", testUsersearch),
        ("testUserUpdates", testUserUpdates),
    ]
}

extension EventTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__EventTests = [
        ("testEventForums", testEventForums),
        ("testEventsAll", testEventsAll),
        ("testEventsBarrel", testEventsBarrel),
        ("testEventsMatch", testEventsMatch),
        ("testEventsMigration", testEventsMigration),
        ("testEventsNow", testEventsNow),
        ("testEventsToday", testEventsToday),
        ("testEventsUpdate", testEventsUpdate),
    ]
}

extension GroupTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__GroupTests = [
        ("testCreate", testCreate),
        ("testJoin", testJoin),
        ("testOpen", testOpen),
        ("testOwnerModify", testOwnerModify),
        ("testPosts", testPosts),
    ]
}

extension ForumTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ForumTests = [
        ("testCategoriesMigration", testCategoriesMigration),
        ("testCategoryTypes", testCategoryTypes),
        ("testContentFilter", testContentFilter),
        ("testForumBarrel", testForumBarrel),
        ("testForumCategory", testForumCategory),
        ("testForumCreate", testForumCreate),
        ("testForumModify", testForumModify),
        ("testForumOwner", testForumOwner),
        ("testForumReport", testForumReport),
        ("testForumSearch", testForumSearch),
        ("testMatchForum", testMatchForum),
        ("testPostDelete", testPostDelete),
        ("testPostForum", testPostForum),
        ("testPostImage", testPostImage),
        ("testPostReactions", testPostReactions),
        ("testPostReport", testPostReport),
        ("testPostSearch", testPostSearch),
        ("testPostUpdate", testPostUpdate),
    ]
}

extension TwitarrTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__TwitarrTests = [
        ("testBookmarks", testBookmarks),
        ("testLikes", testLikes),
        ("testMentions", testMentions),
        ("testReplyQuarantine", testReplyQuarantine),
        ("testRetrieve", testRetrieve),
        ("testTwarrtCUD", testTwarrtCUD),
        ("testUsers", testUsers),
    ]
}

extension UserTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__UserTests = [
        ("testAuthLogin", testAuthLogin),
        ("testAuthLogout", testAuthLogout),
        ("testAuthRecovery", testAuthRecovery),
        ("testRegistrationCodesMigration", testRegistrationCodesMigration),
        ("testUserAccessLevelsAreOrdered", testUserAccessLevelsAreOrdered),
        ("testUserAdd", testUserAdd),
        ("testUserCreate", testUserCreate),
        ("testUserImage", testUserImage),
        ("testUserNotes", testUserNotes),
        ("testUserPassword", testUserPassword),
        ("testUserProfile", testUserProfile),
        ("testUserUsername", testUserUsername),
        ("testUserVerify", testUserVerify),
        ("testUserWhoami", testUserWhoami),
    ]
}

extension UsersTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__UsersTests = [
        ("testMatchAllNames", testMatchAllNames),
        ("testMatchUsername", testMatchUsername),
        ("testUserReport", testUserReport),
        ("testUsersFind", testUsersFind),
        ("testUsersHeader", testUsersHeader),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AppTests.__allTests__AppTests),
        testCase(BarrelTests.__allTests__BarrelTests),
        testCase(ClientTests.__allTests__ClientTests),
        testCase(EventTests.__allTests__EventTests),
        testCase(GroupTests.__allTests__GroupTests),
        testCase(ForumTests.__allTests__ForumTests),
        testCase(TwitarrTests.__allTests__TwitarrTests),
        testCase(UserTests.__allTests__UserTests),
        testCase(UsersTests.__allTests__UsersTests),
    ]
}
#endif
