import Vapor
import Fluent


/// Every day during the cruise, there's a theme. This model lets us store the themes for each day, with a bit of text explaining the theme
/// and an image related to the theme somehow.
/// 
/// For an 8 day cruise, there shouldn't be more than ~10 of these records. Each day of the cruise tends to have an 'officall' theme day,
/// and it might be appropriate to add unofficial themes for a day or two before embarkation? 

final class DailyTheme: Model {
	static let schema = "daily_theme"
	
    // MARK: Properties
    
    /// The theme's ID.
    @ID(key: .id) var id: UUID?
    
    /// The title of the theme.
    @Field(key: "title") var title: String
    
    /// A paragraph-length description of the theme, including info on how to participate.
    @Field(key: "info") var info: String
    
	/// An image that relates to the theme.
    @Field(key: "image") var image: String?
    
    /// Day of cruise, counted from `Settings.shared.cruiseStartDate`. 0 is embarkation day. Values could be negative (e.g. Day -1 is "Anticipation Day")
    /// Values for this field are uniqued in the database, meaning switching two theme days requires extra steps.
    @Field(key: "cruise_day") var cruiseDay: Int32
    
	// MARK: Relations
	
    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new DailyTheme.
    ///
    /// - Parameters:
    ///   - title: The title for the the theme day.
    ///   - info: Extra info about the daily theme.
    ///   - image: An image relating to the theme somehow..
    ///   - day: Which day of the cruise this DailyTheme pertains to. Day 0 is embarkation day; days are midnight to midnight in the ship's time zone.
	init(title: String, info: String, image: String?, day: Int32) {
        self.title = title
        self.info = info
        self.image = image
        self.cruiseDay = day
    }
}
