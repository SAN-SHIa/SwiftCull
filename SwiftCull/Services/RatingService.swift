import Foundation

final class RatingService: @unchecked Sendable {
    static let shared = RatingService()

    private let ratingKey = "com.photofilter.rating"
    private let defaults = UserDefaults.standard

    private init() {}

    func getRating(for photoId: String) -> Int {
        defaults.integer(forKey: "\(ratingKey).\(photoId)")
    }

    func setRating(_ rating: Int, for photoId: String) {
        defaults.set(rating, forKey: "\(ratingKey).\(photoId)")
    }
}
